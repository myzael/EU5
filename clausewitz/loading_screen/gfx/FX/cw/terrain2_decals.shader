Includes = {
	"cw/terrain2_heightmap.fxh"
	"cw/terrain2_materials.fxh"
	"cw/terrain2_utils.fxh"
}

# See ReadDecal() for structure
BufferTexture DecalBuffer
{
	Ref = PdxDecalBuffer
	type = float4
}

BufferTexture DecalIndexBuffer
{
	Ref = PdxDecalIndexBuffer
	type = uint
}

BufferTexture DecalOffsetBuffer
{
	Ref = PdxDecalOffsetBuffer
	type = uint
}

Sampler DecalSampler
{
	MagFilter = "Linear"
	MinFilter = "Linear"
	MipFilter = "Linear"
	SampleModeU = "Clamp"
	SampleModeV = "Clamp"
}

Sampler DecalMaterialSampler
{
	MagFilter = "Point"
	MinFilter = "Point"
	MipFilter = "Point"
	SampleModeU = "Clamp"
	SampleModeV = "Clamp"
}

ConstantBuffer( PdxTerrain2DecalConstants )
{
	float2 _GridCellSize;
	uint _GridCellCount;
	float _Padding;
}

Code
[[
	// Intersection test in decal space
	bool Intersection( float2 Position, uint4 DecalRect )
	{
		if ( Position.x < 0 )
			return false;
		if ( Position.x >= (int)DecalRect.z )
			return false;
		if ( Position.y < 0 )
			return false;
		if ( Position.y >= (int)DecalRect.w )
			return false;

		return true;
	}

	enum class EDecalHeightBlendMode : int
	{
		Add = 0,
		Subtract,
		Multiply,
		Min,
		Max,
		Override,
	};

	struct SDecal
	{
		int4 _Rect;

		float2x2 _InvXform;

		int _TextureIdx;
		float _Strength;
		float _GroundLevel;
		float _FadeMargin;

		EDecalHeightBlendMode _HeightBlendMode;
		float _CurvatureStrength;
		float2 _Padding;

		float _MaterialCutOffDistance[ 16 ];
	};

	uint2 GetGridCellDecalRange( int2 HeightmapPos )
	{
		// PSGE-7288
		uint IndexX = clamp( HeightmapPos.x / _GridCellSize.x, 0, _GridCellCount - 1 );
		uint IndexY = clamp( HeightmapPos.y / _GridCellSize.y, 0, _GridCellCount - 1 );
		uint Pos = IndexX * _GridCellCount + IndexY;
		uint DecalIndexStart = Pos > 0 ? PdxReadBuffer( DecalOffsetBuffer, Pos - 1 ) : 0;
		uint DecalIndexEnd = PdxReadBuffer( DecalOffsetBuffer, Pos );
		return uint2( DecalIndexStart, DecalIndexEnd );
	}

	SDecal ReadDecal( int DecalIdx )
	{
		const int VectorsPerDecal = 8;
		const int BufferOffset = DecalIdx * VectorsPerDecal;

		SDecal Decal;

		Decal._Rect              = asint( PdxReadBuffer4( DecalBuffer, BufferOffset + 0 ) );
		Decal._InvXform       = float2x2( PdxReadBuffer4( DecalBuffer, BufferOffset + 1 ) );
		float4 DecalProperties1 = float4( PdxReadBuffer4( DecalBuffer, BufferOffset + 2 ) );
		float4 DecalProperties2 = float4( PdxReadBuffer4( DecalBuffer, BufferOffset + 3 ) );

		Decal._TextureIdx        = (int)DecalProperties1.x;
		Decal._Strength          = DecalProperties1.y;
		Decal._GroundLevel       = DecalProperties1.z;
		Decal._FadeMargin        = DecalProperties1.w;
		Decal._HeightBlendMode   = (EDecalHeightBlendMode)DecalProperties2.x;
		Decal._CurvatureStrength = DecalProperties2.y;

		for ( uint i = 0; i < 4; ++i )
		{
			float4 CutoffDistances = float4( PdxReadBuffer4( DecalBuffer, BufferOffset + 4 + i ) );
			for ( uint j = 0; j < 4; ++j )
			{
				Decal._MaterialCutOffDistance[ i * 4 + j ] = CutoffDistances[ j ];
			}
		}

		return Decal;
	}

	// FadeMargin is a normalized float describing how far into the
	// decal we fade the height value. FadeMargin == 0 = no fade
	// (fade ends at border of the decal), 1 = fade is applied to whole decal.
	float CalcFadeFactor( float2 Uv, float FadeMargin )
	{
		if ( FadeMargin == 0.0f )
		{
			return 1.0f;
		}

		// Scale + translate the UV such that the origin is at the <.5, .5> point of the decal
		float2 Uv2 = Uv * 2.0f - 1.0f;

		// Find the distance from the current UV coordinates to the closest edge of the rounded rectangle.
		// See "Rounded Box" formula in https://iquilezles.org/articles/distfunctions2d/
		float2 UvAbs = abs( Uv2 ); // Fold into positive quadrant
		float2 FadeMarginPoint = ( float2( 1, 1 ) - FadeMargin );
		float2 ToUvAbs = UvAbs - FadeMarginPoint;
		float2 NegativeClamped = max( ToUvAbs, 0.0f );
		float DistFromFadeEdge = length( NegativeClamped );

		return smoothstep( 0.0f, FadeMargin, FadeMargin - DistFromFadeEdge );
	}

	// Transforms local decal height value into a global heightmap space
	float TransformDecalHeight( float DecalHeight, float HeightScale, float LocalOffset, float GlobalOffset )
	{
		DecalHeight = saturate( DecalHeight + LocalOffset );
		DecalHeight *= HeightScale;
		DecalHeight = saturate( DecalHeight + GlobalOffset );

		return DecalHeight;
	}

	float BlendDecalHeights( float DecalHeight, float BaseHeight, EDecalHeightBlendMode HeightBlendMode, float GroundLevel, float Strength )
	{
		switch ( HeightBlendMode )
		{
			case EDecalHeightBlendMode::Add:
				{
					// With "Add" and "Subtract" blend modes GroundLevel value is interpreted as a negative height offset in local decal space
					const float LocalOffset = -GroundLevel;
					const float HeightScale = Strength;
					const float GlobalOffset = 0.0f;

					const float TransformedDecalHeight = TransformDecalHeight( DecalHeight, HeightScale, LocalOffset, GlobalOffset );
					return saturate( BaseHeight + TransformedDecalHeight );
				}
			case EDecalHeightBlendMode::Subtract:
				{
					const float LocalOffset = -GroundLevel;
					const float HeightScale = Strength;
					const float GlobalOffset = 0.0f;

					const float TransformedDecalHeight = TransformDecalHeight( DecalHeight, HeightScale, LocalOffset, GlobalOffset );

					return saturate( BaseHeight - TransformedDecalHeight );
				}
			case EDecalHeightBlendMode::Multiply:
				{
					const float LocalOffset = 0.0f;
					const float HeightScale = Strength;
					// With "Multiply" and "Min" blend modes GroundLevel value is interpreted as the global height offset
					// from the top of the heightmap (1.0f) to the top of the transformed decal.
					// Note that GlobalOffset represents an offset of the bottom of the transformed decal from the bottom of the heightmap (0.0f)
					// therefore we also need to subtract the full decal height scale (Strength).
					const float GlobalOffset = 1.0f - GroundLevel - Strength;

					const float TransformedDecalHeight = TransformDecalHeight( DecalHeight, HeightScale, LocalOffset, GlobalOffset );

					return BaseHeight * TransformedDecalHeight;
				}
			case EDecalHeightBlendMode::Min:
				{
					const float LocalOffset = 0.0f;
					const float HeightScale = Strength;
					const float GlobalOffset = 1.0f - GroundLevel - Strength;

					const float TransformedDecalHeight = TransformDecalHeight( DecalHeight, HeightScale, LocalOffset, GlobalOffset );

					return min( BaseHeight, TransformedDecalHeight );
				}
			case EDecalHeightBlendMode::Max:
				{
					const float LocalOffset = 0.0f;
					const float HeightScale = Strength;
					// With "Max" and "Override" blend modes GroundLevel is interpreted as an offset
					// of the bottom of the transformed decal from the bottom of the heightmap (0.0f).
					const float GlobalOffset = GroundLevel;

					const float TransformedDecalHeight = TransformDecalHeight( DecalHeight, HeightScale, LocalOffset, GlobalOffset );

					return max( BaseHeight, TransformedDecalHeight );
				}
			case EDecalHeightBlendMode::Override:
				{
					const float LocalOffset = 0.0f;
					const float HeightScale = Strength;
					const float GlobalOffset = GroundLevel;

					const float TransformedDecalHeight = TransformDecalHeight( DecalHeight, HeightScale, LocalOffset, GlobalOffset );

					return TransformedDecalHeight;
				}
			default: return 0.0f;
		}
	}

#if defined( HEIGHTMAP )
	void ApplyDecalsHeight( float2 HeightmapPos, inout float Height )
	{
		uint2 DecalRange = GetGridCellDecalRange( int2( HeightmapPos ) );
		for ( int Offset = DecalRange.x; Offset < DecalRange.y; Offset++ )
		{
			uint DecalIdx = PdxReadBuffer( DecalIndexBuffer, Offset );
			SDecal Decal = ReadDecal( DecalIdx );

			// Translate & rotate the world space vector to properly orient in decal space
			float2 DecalSpacePosition = mul( HeightmapPos - Decal._Rect.xy, Decal._InvXform );

			// Is the transformed heightmap position within the decal bounds?
			if ( Intersection( DecalSpacePosition, Decal._Rect ) )
			{
				// Divide by decal width & height to derive normalized UV coordinate
				float2 UvPosition = DecalSpacePosition / Decal._Rect.zw;
				float FadeFactor = CalcFadeFactor( UvPosition, Decal._FadeMargin );

				float HighResDecalSample = PdxSampleTex2DLod( VirtualHeightmapDecalTextures[ NonUniformResourceIndex( Decal._TextureIdx ) ], DecalSampler, UvPosition, 0 ).r;
				float BlendedHeight = BlendDecalHeights( HighResDecalSample, Height, Decal._HeightBlendMode, Decal._GroundLevel, Decal._Strength );

				Height = lerp( Height, BlendedHeight, FadeFactor );
			}
		}
	}
#endif // defined( HEIGHTMAP )

#if defined( MATERIALS )
	void ApplyDecalsMaterial( float2 HeightmapPos, inout uint Material )
	{
		uint2 DecalRange = GetGridCellDecalRange( int2( HeightmapPos ) );
		for ( int Offset = DecalRange.x; Offset < DecalRange.y; Offset++ )
		{
			uint DecalIdx = PdxReadBuffer( DecalIndexBuffer, Offset );
			SDecal Decal = ReadDecal( DecalIdx );

			// Translate & rotate the world space vector to properly orient in decal space
			float2 DecalSpacePosition = mul( HeightmapPos - Decal._Rect.xy, Decal._InvXform );

			// Is the transformed heightmap position within the decal bounds?
			if ( Intersection( DecalSpacePosition, Decal._Rect ) )
			{
				// Divide by decal width & height to derive normalized UV coordinate
				float2 UvPosition = DecalSpacePosition / Decal._Rect.zw;

				float2 TextureSize;
				PdxTexture2DSize( VirtualMaterialsDecalTextures[ NonUniformResourceIndex( Decal._TextureIdx ) ], TextureSize );
				uint2 Position = (uint2)( UvPosition * TextureSize );

				uint DecalMaterialSample = asuint( PdxTexture2DLoad0( VirtualMaterialsDecalTextures[ NonUniformResourceIndex( Decal._TextureIdx ) ], Position ).r );

				uint ActiveMaterialMask = 0;
				for ( uint MaterialIdx = 0; MaterialIdx < 16; MaterialIdx++ )
				{
					//TODO[DvdB]: have separate distances values for x and y axis.
					const float2 CutoffDistance = float2( Decal._MaterialCutOffDistance[ MaterialIdx ], Decal._MaterialCutOffDistance[ MaterialIdx ] );
					const uint XFactor = (uint)( UvPosition.x > CutoffDistance.x && 1.0f - UvPosition.x > CutoffDistance.x );
					const uint YFactor = (uint)( UvPosition.y > CutoffDistance.y && 1.0f - UvPosition.y > CutoffDistance.y );

					ActiveMaterialMask |= DecalMaterialSample & ( ( 1u << MaterialIdx ) * ( XFactor * YFactor ) );
				}

				Material |= ActiveMaterialMask;
			}
		}
	}
#endif // defined( MATERIALS )

#if defined( CURVATURE )
	void ApplyDecalsCurvature( float2 HeightmapPos, inout float Curvature )
	{
		uint2 DecalRange = GetGridCellDecalRange( int2( HeightmapPos ) );
		for ( int Offset = DecalRange.x; Offset < DecalRange.y; Offset++ )
		{
			uint DecalIdx = PdxReadBuffer( DecalIndexBuffer, Offset );
			SDecal Decal = ReadDecal( DecalIdx );

			// Translate & rotate the world space vector to properly orient in decal space
			float2 DecalSpacePosition = mul( HeightmapPos - Decal._Rect.xy, Decal._InvXform );

			// Is the transformed heightmap position within the decal bounds?
			if ( Intersection( DecalSpacePosition, Decal._Rect ) )
			{
				// Divide by decal width & height to derive normalized UV coordinate
				float2 UvPosition = DecalSpacePosition / Decal._Rect.zw;
				float FadeFactor = CalcFadeFactor( UvPosition, Decal._FadeMargin );

				float HighResDecalSample = PdxSampleTex2DLod( VirtualCurvatureDecalTextures[ NonUniformResourceIndex( Decal._TextureIdx ) ], DecalSampler, UvPosition, 0 ).r;

				// Into [-1,1]
				HighResDecalSample = ( HighResDecalSample * 2.0f ) - 1.0f;

				HighResDecalSample *= Decal._CurvatureStrength;
				// HighResDecalSample *= 100.0f;

				// Into [0,1]
				HighResDecalSample = saturate( ( HighResDecalSample + 1.0f ) * 0.5f );

				if ( HighResDecalSample != 0.0 )
				{
					Curvature = BlendAddSub( Curvature, HighResDecalSample );
				}
			}
		}
	}
#endif // defined( CURVATURE )
]]

ComputeShader =
{
	MainCode ComputeShaderDecalUpdate
	{
		VertexStruct CS_INPUT
		{
			# x = decal x coord, spanning multiple decal rects
			# y = decal y coord
			# z = unused
			uint3 DispatchThreadID : PDX_DispatchThreadID
		};

		RWTexture PhysicalTexture
		{
			Ref = PdxRWTexture0
			format = uint
		}

		# TODO[TS]: Name these guys!
		# TODO[TS]: Most of these can be grabbed from VirtualLayerConstants
		ConstantBuffer( PdxConstantBuffer2 )
		{
			uint _PhysicalPageWidth;
			uint _DispatchCount;
			uint _VirtualPageBorder;
			float _InvVirtualPageSize;
			bool _IgnorePreviousData;
		};

		ConstantBuffer( PdxConstantBuffer3 )
		{
			int4 _PageRects[4096];
		};

		ConstantBuffer( PdxConstantBuffer4 )
		{
			# Each data uses 1 vector:
			# float[0] = { _NodeOffset(float2), NodeScale(float), 0 }
			float4 _OffsetAndScale[4096];
		};

		Input = "CS_INPUT"
		NumThreads = { 16 4 1 }
		Code
		[[
			PDX_MAIN
			{
				if ( Input.DispatchThreadID.x >= _DispatchCount )
				{
					return;
				}
				uint RectIndex = Input.DispatchThreadID.x / _PhysicalPageWidth;

				int2 WithinRectCoord = int2( Input.DispatchThreadID.x - RectIndex * _PhysicalPageWidth, Input.DispatchThreadID.y );

				// PhysicalTexturePos represents the (global) position of the decal in the physical texture
				int2 PhysicalTexturePos = _PageRects[ RectIndex ].xy;
				float2 NodeOffset = _OffsetAndScale[ RectIndex ].xy;
				float NodeScale = _OffsetAndScale[ RectIndex ].z;

				// Calculate the GridPosition0To1 equivalent, note that this might actually be outside the [0,1] range since we also include a border for physical pages
				int2 GridPosition = WithinRectCoord - _VirtualPageBorder;
				float2 GridPosition0To1 = GridPosition * _InvVirtualPageSize;

				// 0-1 position within virtual texture
				float2 VirtualTextureUV = GridPosition0To1 * NodeScale + NodeOffset;

				// NOTE: The decals are stored in heightmap space. This means that even for the non-heightmap layers, we need to
				// calculate this position in that space.
				float2 HeightmapPos = VirtualTextureUV * _VirtualHeightmapConstants._ClipmapConstants._VirtualTextureSize;
				int2 PhysicalTextureCoord = PhysicalTexturePos + WithinRectCoord;

#if defined( HEIGHTMAP )
				float Height = _IgnorePreviousData ? 0.0f : float( PhysicalTexture[ PhysicalTextureCoord ] ) / UINT16_MAX;

				ApplyDecalsHeight( HeightmapPos, Height );

				PhysicalTexture[ PhysicalTextureCoord ] = saturate( Height ) * UINT16_MAX;
#elif defined( MATERIALS )
				uint Material = _IgnorePreviousData ? 0u : PhysicalTexture[ PhysicalTextureCoord ];

				ApplyDecalsMaterial( HeightmapPos, Material );

				PhysicalTexture[ PhysicalTextureCoord ] = Material;
#elif defined( CURVATURE )
				float Curvature = _IgnorePreviousData ? 0.5f : float( PhysicalTexture[ PhysicalTextureCoord ] ) / UINT16_MAX;

				ApplyDecalsCurvature( HeightmapPos, Curvature );

				PhysicalTexture[ PhysicalTextureCoord ] = saturate( Curvature ) * UINT16_MAX;
#else
				#error "No virtual layer type defined"
#endif
			}
		]]
	}
}

Effect TerrainDecalUpdateCompute
{
	ComputeShader = "ComputeShaderDecalUpdate"
	Defines = { "HEIGHTMAP" }
}

Effect TerrainDecalMaterialsUpdateCompute
{
	ComputeShader = "ComputeShaderDecalUpdate"
	Defines = { "MATERIALS" }
}

Effect TerrainDecalCurvatureUpdateCompute
{
	ComputeShader = "ComputeShaderDecalUpdate"
	Defines = { "CURVATURE" }
}
