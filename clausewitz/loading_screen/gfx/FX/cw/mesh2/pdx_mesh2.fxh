Includes = {
	"cw/mesh2/pdx_mesh2_geometry.fxh"
	"cw/mesh2/pdx_mesh2_skinning.fxh"
	"cw/mesh2/pdx_mesh2_blend_shape.fxh"
	"cw/mesh2/pdx_mesh2_vertex_cache.fxh"
}

BufferTexture Mesh2InstanceDataBuffer
{
	Ref = PdxMesh2InstanceDataBuffer
	type = uint
}

BufferTexture Mesh2TransformsBuffer
{
	Ref = PdxMesh2TransformsBuffer
	type = uint
}

BufferTexture Mesh2PreviousTransformsBuffer
{
	Ref = PdxMesh2PreviousTransformsBuffer
	type = uint
}

BufferTexture Mesh2ShaderDataBuffer
{
	Ref = PdxMesh2ShaderDataBuffer
	type = uint
}

ConstantBuffer( PdxMesh2BatchConstants )
{
	uint _GeometryTypeDataOffset;
};
	
ConstantBuffer( PdxMesh2InstanceConstants )
{
	uint _InstanceDataOffset;
	uint _InstanceDataStride;
};

ConstantBuffer( PdxMesh2VertexCacheConstants )
{
	uint _VertexCacheOffset;
	uint _VertexCacheNumVertices;
	uint _VertexCacheNumInstances;
};

Code
[[
	struct PDXMESH2_VERTEX_INPUT
	{
		float3 _Position;
		float3 _Normal;
		float3 _Tangent;
		float _BitangentDir;
		
		float2 _Uv0;
		float2 _Uv1;
		float2 _Uv2;
		float2 _Uv3;
		
		float4 _Color0;
		float4 _Color1;
		
	#ifdef PDX_MESH2_SKIN
		SSkinningData _SkinningData;
	#endif
	};
	
	struct PDXMESH2_INSTANCE_INPUT
	{
		float4x4 _WorldMatrix;
	#ifdef PDX_MESH2_MOTION_VECTORS
		float4x4 _PreviousWorldMatrix;
	#endif
	
		float _BlendValue;
		
	#ifdef PDX_MESH2_SKIN_INSTANCE_INPUT
		uint _SkinningTransformsOffset;
	#endif

	#ifdef PDX_MESH2_BLENDSHAPES_INSTANCE_INPUT
		uint _BlendShapeDataOffset;
	#endif
	
	#ifdef PDX_MESH2_VERTEX_CACHE_INSTANCE_INPUT
		uint _CachedVertexDataOffset;
	#endif
	
	#ifdef PDX_MESH2_SHADER_DATA_INSTANCE_INPUT
		uint _ShaderDataOffset;
	#endif
	};

	struct PDXMESH2_OUTPUT
	{
		float4 _Position;
		float3 _WorldSpacePosition;
	#ifdef PDX_MESH2_MOTION_VECTORS
		float3 _PreviousWorldSpacePosition;
	#endif
	
		float _BlendValue;
		
		float3 _Normal;
		float3 _Tangent;
		float3 _Bitangent;
		
		float2 _Uv0;
		float2 _Uv1;
		float2 _Uv2;
		float2 _Uv3;
		
		float4 _Color0;
		float4 _Color1;
	};
	
	
	float4x4 LoadInstanceTransform( uint TransformIndex )
	{
		uint Offset = TransformIndex * PDX_MESH2_MATRIX34_DATA_STRIDE;
		return ReadMatrix34( Mesh2TransformsBuffer, Offset );
	}
	
	float4x4 LoadPreviousInstanceTransform( uint TransformIndex )
	{
		uint Offset = TransformIndex * PDX_MESH2_MATRIX34_DATA_STRIDE;
		return ReadMatrix34( Mesh2PreviousTransformsBuffer, Offset );
	}
	
	void BuildTangentFrame( float3x3 Transform, float3 Normal, float3 Tangent, float BitangentDir, out float3 NormalOut, out float3 TangentOut, out float3 BitangentOut )
	{
		NormalOut = normalize( mul( Transform, Normal ) );
		TangentOut = normalize( mul( Transform, Tangent ) );
		BitangentOut = normalize( cross( NormalOut, TangentOut ) * BitangentDir );
	}

	
	PDXMESH2_VERTEX_INPUT PdxMesh2VertexInputFromGeometryBuffer( STypeData TypeData, uint VertexID )
	{
		PDXMESH2_VERTEX_INPUT Out;
		
		Out._Position = GetPositionForType( TypeData, VertexID );
		GetNormalAndTangentForType( TypeData, VertexID, Out._Normal, Out._Tangent, Out._BitangentDir );

		Out._Uv0 = GetUv0( TypeData, VertexID );
		Out._Uv1 = GetUv1( TypeData, VertexID );
		Out._Uv2 = GetUv2( TypeData, VertexID );
		Out._Uv3 = GetUv3( TypeData, VertexID );
		
		Out._Color0 = GetColor0( TypeData, VertexID );
		Out._Color1 = GetColor1( TypeData, VertexID );
		
	#ifdef PDX_MESH2_SKIN
		Out._SkinningData = GetSkinningDataForType( TypeData, VertexID );
	#endif

		return Out;
	}
	
	void PdxMesh2ReadOptionalInstanceInput( uint InstanceDataIndex, inout PDXMESH2_INSTANCE_INPUT InstanceInput )
	{
	#ifdef PDX_MESH2_SKIN_INSTANCE_INPUT
		InstanceInput._SkinningTransformsOffset = Mesh2InstanceDataBuffer[ InstanceDataIndex++ ];
	#endif
	
	#ifdef PDX_MESH2_BLENDSHAPES_INSTANCE_INPUT
		InstanceInput._BlendShapeDataOffset = Mesh2InstanceDataBuffer[ InstanceDataIndex++ ];
	#endif
	
	#ifdef PDX_MESH2_VERTEX_CACHE_INSTANCE_INPUT
		InstanceInput._CachedVertexDataOffset = Mesh2InstanceDataBuffer[ InstanceDataIndex++ ];
	#endif
	
	#ifdef PDX_MESH2_SHADER_DATA_INSTANCE_INPUT
		InstanceInput._ShaderDataOffset =  Mesh2InstanceDataBuffer[ InstanceDataIndex++ ];
	#endif
	}
	
	PDXMESH2_INSTANCE_INPUT PdxMesh2InstanceInputFromInstanceID( uint InstanceID, uint InstanceDataOffset, uint InstanceDataStride )
	{
		PDXMESH2_INSTANCE_INPUT Out;
		
		uint InstanceDataIndex = InstanceDataOffset + InstanceID * InstanceDataStride;

		uint TransformIndex = Mesh2InstanceDataBuffer[ InstanceDataIndex++ ];
		Out._WorldMatrix = LoadInstanceTransform( TransformIndex );
	#ifdef PDX_MESH2_MOTION_VECTORS
		Out._PreviousWorldMatrix = LoadPreviousInstanceTransform( TransformIndex );
	#endif
	
		Out._BlendValue = asfloat( Mesh2InstanceDataBuffer[ InstanceDataIndex++ ] );
	
		PdxMesh2ReadOptionalInstanceInput( InstanceDataIndex, Out );

		return Out;
	}
	
	PDXMESH2_OUTPUT PdxMesh2VertexShader( STypeData TypeData, uint VertexID, PDXMESH2_VERTEX_INPUT VertexInput, PDXMESH2_INSTANCE_INPUT InstanceInput )
	{
		PDXMESH2_OUTPUT Out;

	#ifdef PDX_MESH2_BLENDSHAPES
		// Apply blendshapes to data in VertexInput
		PdxMesh2ApplyBlendShapes( TypeData, VertexID, InstanceInput._BlendShapeDataOffset, VertexInput._Position, VertexInput._Normal, VertexInput._Tangent );
	#endif
	
	#ifdef PDX_MESH2_VERTEX_CACHE
		// Overwrite data in VertexInput (position/normal/tangent) with data read from vertex cache (we currently rely on compiler to optimize away potentially enabled PdxMesh2ApplyBlendShapes)
		PdxMesh2VertexInputFromVertexCache( VertexID, InstanceInput._CachedVertexDataOffset + _VertexCacheOffset, _VertexCacheNumVertices, VertexInput._Position, VertexInput._Normal, VertexInput._Tangent );
	#endif
	
		float3 Position = VertexInput._Position;
		float3 PreviousPosition = Position;

		float3 Normal = VertexInput._Normal;
		float3 Tangent = VertexInput._Tangent;
		float BitangentDir = VertexInput._BitangentDir;

	#ifdef PDX_MESH2_SKIN
	
		float3 SkinnedPosition = vec3( 0.0 );
		float3 PreviousSkinnedPosition = vec3( 0.0 );
		float3 SkinnedNormal = vec3( 0.0 );
		float3 SkinnedTangent = vec3( 0.0 );
		for( uint i = 0; i < VertexInput._SkinningData._NumBones; ++i )
		{
			uint BoneIndex;
			float BoneWeight;
			GetBoneIndexAndWeightForType( VertexInput._SkinningData, i, BoneIndex, BoneWeight );
	
			ProcessSkinning( InstanceInput._SkinningTransformsOffset, BoneIndex, BoneWeight, Position, Normal, Tangent, SkinnedPosition, PreviousSkinnedPosition, SkinnedNormal, SkinnedTangent );
		}
		
		Position = SkinnedPosition;
		PreviousPosition = PreviousSkinnedPosition;
		Normal = SkinnedNormal;
		Tangent = SkinnedTangent;

	#endif

		float4 TransformedPosition = mul( InstanceInput._WorldMatrix, float4( Position, 1.0 ) );
		Out._Position = FixProjectionAndMul( ViewProjectionMatrix, TransformedPosition );
		Out._WorldSpacePosition = TransformedPosition.xyz;
	#ifdef PDX_MESH2_MOTION_VECTORS
		Out._PreviousWorldSpacePosition = mul( InstanceInput._PreviousWorldMatrix, float4( PreviousPosition, 1.0 ) );
	#endif
		
		BuildTangentFrame( CastTo3x3( InstanceInput._WorldMatrix ), Normal, Tangent, BitangentDir, Out._Normal, Out._Tangent, Out._Bitangent );
		
		Out._BlendValue = InstanceInput._BlendValue;
		
		Out._Uv0 = VertexInput._Uv0;
		Out._Uv1 = VertexInput._Uv1;
		Out._Uv2 = VertexInput._Uv2;
		Out._Uv3 = VertexInput._Uv3;
		
		Out._Color0 = VertexInput._Color0;
		Out._Color1 = VertexInput._Color1;
		
		return Out;
	}
]]


VertexShader =
{
	Code
	[[
	#ifdef USE_VB
		PDXMESH2_VERTEX_INPUT PdxMesh2VertexInputFromVertexBuffer( VS_INPUT_PDXMESH2 Input, STypeData TypeData )
		{
			PDXMESH2_VERTEX_INPUT Out;
			
			Out._Position = GetPosition( Input, TypeData );
			GetNormalAndTangent( Input, Out._Normal, Out._Tangent, Out._BitangentDir );

			Out._Uv0 = GetUv0( Input );
			Out._Uv1 = GetUv1( Input );
			Out._Uv2 = GetUv2( Input );
			Out._Uv3 = GetUv3( Input );
			
			Out._Color0 = GetColor0( Input );
			Out._Color1 = GetColor1( Input );
			
		#ifdef PDX_MESH2_SKIN

			#if defined( PDX_MESH2_SKIN_RGBA_UINT16_RGB_FLOAT )
				Out._SkinningData._NumBones = 4;
				Out._SkinningData._BoneIndices = Input.BoneIndex;
				Out._SkinningData._BoneWeights = float4( Input.BoneWeight.xyz, 1.0 - Input.BoneWeight.x - Input.BoneWeight.y - Input.BoneWeight.z );
			#else
				Out._SkinningData = UnpackSkinningData( TypeData, Input.SkinData );
			#endif
			
		#endif

			return Out;
		}
	#endif
	
		PDXMESH2_VERTEX_INPUT PdxMesh2LoadVertexInput( STypeData TypeData, VS_INPUT_PDXMESH2 Input )
		{
			PDXMESH2_VERTEX_INPUT Out;
			
			#ifdef USE_VB
				Out = PdxMesh2VertexInputFromVertexBuffer( Input, TypeData );
			#else
				Out = PdxMesh2VertexInputFromGeometryBuffer( TypeData, Input.VertexID );
			#endif
			
			return Out;
		}
		
		PDXMESH2_INSTANCE_INPUT PdxMesh2LoadInstanceInput( VS_INPUT_PDXMESH2 Input )
		{
			return PdxMesh2InstanceInputFromInstanceID( Input.InstanceID, _InstanceDataOffset, _InstanceDataStride );
		}
		
		PDXMESH2_OUTPUT PdxMesh2VertexShader( VS_INPUT_PDXMESH2 Input )
		{
			STypeData TypeData = LoadTypeData( _GeometryTypeDataOffset );
			
			PDXMESH2_VERTEX_INPUT VertexInput = PdxMesh2LoadVertexInput( TypeData, Input );
			PDXMESH2_INSTANCE_INPUT InstanceInput = PdxMesh2LoadInstanceInput( Input );

			PDXMESH2_OUTPUT Mesh2Output = PdxMesh2VertexShader( TypeData, Input.VertexID, VertexInput, InstanceInput );
			return Mesh2Output;
		}
	]]
}
