Includes = {
	"cw/mesh2/pdx_mesh2_utils.fxh"
}

BufferTexture Mesh2GeometryDataBuffer
{
	Ref = PdxMesh2GeometryDataBuffer
	type = uint
}

Code
[[
	struct STypeData
	{
		float3 _BoundingSphereCenter;
		float _BoundingSphereRadius;
		
		float3 _BoundingBoxMin;
		float3 _BoundingBoxMax;
		
		uint _Numindices;
		uint _IndexDataOffset;
		
		uint _PositionDataOffset;
		
		// TODO - PSGE-6681 - Shader Defines, how do we want to deal with this, separate formats might complicate shared compute shader code
	#ifdef PDX_MESH2_QTANGENT
		uint _QTangentDataOffset;
	#endif
	
	#ifdef PDX_MESH2_NORMAL
		uint _NormalDataOffset;
	#endif
	#ifdef PDX_MESH2_TANGENT
		uint _TangentDataOffset;
	#endif
	
	#ifdef PDX_MESH2_UV0
		uint _Uv0DataOffset;
	#endif
	#ifdef PDX_MESH2_UV1
		uint _Uv1DataOffset;
	#endif
	#ifdef PDX_MESH2_UV2
		uint _Uv2DataOffset;
	#endif
	#ifdef PDX_MESH2_UV3
		uint _Uv3DataOffset;
	#endif
	
	#ifdef PDX_MESH2_COLOR0
		uint _Color0DataOffset;
	#endif
	#ifdef PDX_MESH2_COLOR1
		uint _Color1DataOffset;
	#endif
	
	#ifdef PDX_MESH2_SKIN
		uint _SkinVertexDataOffset;
		
		#ifdef PDX_MESH2_SKIN_EXTERNAL
			uint _SkinExternalDataOffset; // For versions that stores count/offset in vertex stream and actual skinning data separately
		#endif
	#endif
	
	#ifdef PDX_MESH2_BLENDSHAPES
		uint _BlendShapeTypeDataOffset;
	#endif
	};
	
	// Note that offsets are known at compile time so even tho it looks like we always load all this data the compiler should throw away all fields that are unused
	STypeData LoadTypeData( uint TypeDataOffset )
	{
		STypeData TypeData;
		
		TypeData._BoundingSphereCenter = Read3Float( Mesh2GeometryDataBuffer, TypeDataOffset );
		TypeDataOffset += 3;
		TypeData._BoundingSphereRadius = asfloat( Mesh2GeometryDataBuffer[TypeDataOffset++] );
		
		TypeData._BoundingBoxMin = Read3Float( Mesh2GeometryDataBuffer, TypeDataOffset );
		TypeDataOffset += 3;
		TypeData._BoundingBoxMax = Read3Float( Mesh2GeometryDataBuffer, TypeDataOffset );
		TypeDataOffset += 3;
		
		TypeData._Numindices = Mesh2GeometryDataBuffer[TypeDataOffset++];
		TypeData._IndexDataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
		
		TypeData._PositionDataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
		
	#ifdef PDX_MESH2_QTANGENT
		TypeData._QTangentDataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
	#endif
	
	#ifdef PDX_MESH2_NORMAL
		TypeData._NormalDataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
	#endif
	#ifdef PDX_MESH2_TANGENT
		TypeData._TangentDataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
	#endif
		
	#ifdef PDX_MESH2_UV0
		TypeData._Uv0DataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
	#endif
	#ifdef PDX_MESH2_UV1
		TypeData._Uv1DataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
	#endif
	#ifdef PDX_MESH2_UV2
		TypeData._Uv2DataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
	#endif
	#ifdef PDX_MESH2_UV3
		TypeData._Uv3DataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
	#endif
	
	#ifdef PDX_MESH2_COLOR0
		TypeData._Color0DataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
	#endif
	#ifdef PDX_MESH2_COLOR1
		TypeData._Color1DataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
	#endif
	
	#ifdef PDX_MESH2_SKIN
		TypeData._SkinVertexDataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
		
		#ifdef PDX_MESH2_SKIN_EXTERNAL
			TypeData._SkinExternalDataOffset = Mesh2GeometryDataBuffer[TypeDataOffset++];
		#endif
	#endif
	
	#ifdef PDX_MESH2_BLENDSHAPES
		TypeData._BlendShapeTypeDataOffset = TypeDataOffset;
	#endif
	
		return TypeData;
	}
	
	
	float2 ReadPackedFloat2( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID * 2;
		return Read2Float( Mesh2GeometryDataBuffer, DataBufferOffset );
	}
	float3 ReadPackedFloat3( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID * 3;
		return Read3Float( Mesh2GeometryDataBuffer, DataBufferOffset );
	}
	float4 ReadPackedFloat4( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID * 4;
		return Read4Float( Mesh2GeometryDataBuffer, DataBufferOffset );
	}

	
	// Reads 4 snorm16 compressed values and convert to float4 (better naming is welcomed)
	float4 ReadPackedFloat4_Snorm16( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID * 2; // 2 snorm16 values in each uint, so 2 uint for 4 values
		int2 Data = asint( Read2( Mesh2GeometryDataBuffer, DataBufferOffset ) );
		return float4( UnpackSnorm16_x2( Data.x ), UnpackSnorm16_x2( Data.y ) );
	}
	
	// Reads 2 unorm16 compressed values and convert to float2
	float2 ReadPackedFloat2_Unorm16( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID; // 2 unorm16 values in each uint
		uint Data = Mesh2GeometryDataBuffer[DataBufferOffset];
		return UnpackUnorm16_x2( Data );
	}
	
	// Reads 4 unorm16 compressed values and convert to float4
	float4 ReadPackedFloat4_Unorm16( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID * 2; // 2 unorm16 values in each uint, so 2 uint for 4 values
		uint2 Data = Read2( Mesh2GeometryDataBuffer, DataBufferOffset );
		return float4( UnpackUnorm16_x2( Data.x ), UnpackUnorm16_x2( Data.y ) );
	}
	
	// Reads 4 unorm8 compressed values and convert to float4
	float4 ReadPackedFloat4_Unorm8( uint BaseOffset, uint VertexID )
	{
		uint DataBufferOffset = BaseOffset + VertexID; // 4 unorm8 values in each uint
		uint Data = Mesh2GeometryDataBuffer[DataBufferOffset];
		return UnpackUnorm8_x4( Data );
	}
	
	
	void HandleIndexBuffer( STypeData TypeData, inout uint VertexID )
	{
	#ifndef USE_IB
		#ifdef PDX_MESH2_INDEX_UINT_16
			uint DataBufferOffset = TypeData._IndexDataOffset + VertexID / 2;
			uint PackedIndex = Mesh2GeometryDataBuffer[DataBufferOffset];
			uint2 IndexUint16 = UnpackUint16_x2( PackedIndex );
			VertexID = IndexUint16[ mod(VertexID, 2) ];
		#else
			uint DataBufferOffset = TypeData._IndexDataOffset + VertexID;
			VertexID = Mesh2GeometryDataBuffer[DataBufferOffset];
		#endif
	#endif
	}
	
	
	float3 DecompressPosition( STypeData TypeData, float3 CompressedPosition )
	{
		return lerp( TypeData._BoundingBoxMin, TypeData._BoundingBoxMax, CompressedPosition.xyz );
	}

	float3 GetPositionForType( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
	
	#ifdef PDX_MESH2_POSITION_COMPRESSED
		float4 CompressedPosition = ReadPackedFloat4_Unorm16( TypeData._PositionDataOffset, VertexID );
		return DecompressPosition( TypeData, CompressedPosition.xyz );
	#else
		return ReadPackedFloat3( TypeData._PositionDataOffset, VertexID );
	#endif
	}
	
	void GetNormalAndTangentForType( STypeData TypeData, uint VertexID, out float3 Normal, out float3 Tangent, out float BitangentDir )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
	#ifdef PDX_MESH2_QTANGENT
		float4 QTangent = normalize( ReadPackedFloat4_Snorm16( TypeData._QTangentDataOffset, VertexID ) );
		// Extract "rotation matrix x-axis" from quaternion
		Normal = float3( 1, 0, 0 ) + float3( -2, 2, -2 ) * QTangent.y * QTangent.yxw + float3( -2, 2, 2 ) * QTangent.z * QTangent.zwx;
		// Extract y-axis
		Tangent = float3( 0, 1, 0 ) + float3( 2, -2, 2 ) * QTangent.x * QTangent.yxw + float3( -2, -2, 2 ) * QTangent.z * QTangent.wzy;
		BitangentDir = sign( QTangent.w );
	#else
		#ifdef PDX_MESH2_NORMAL
			#ifdef PDX_MESH2_NORMAL_COMPRESSED
				Normal = normalize( ReadPackedFloat4_Snorm16( TypeData._NormalDataOffset, VertexID ).xyz );
			#else
				Normal = ReadPackedFloat3( TypeData._NormalDataOffset, VertexID );
			#endif
		#else
			Normal = float3( 0.0, 0.0, 0.0 );
		#endif
		
		#ifdef PDX_MESH2_TANGENT
			#ifdef PDX_MESH2_TANGENT_COMPRESSED
				float4 TangentData = ReadPackedFloat4_Snorm16( TypeData._TangentDataOffset, VertexID );
				TangentData.xyz = normalize( TangentData.xyz );
			#else
				float4 TangentData = ReadPackedFloat4( TypeData._TangentDataOffset, VertexID );
			#endif
			Tangent = TangentData.xyz;
			BitangentDir = TangentData.w;
		#else
			Tangent = float3( 0.0, 0.0, 0.0 );
			BitangentDir = 0.0;
		#endif
	#endif
	}
	
	// Templates please
	// (maybe also this should be more "dynamic", all the defines could be problematic for generic compute/ray tracing shaders)
	float2 GetUv0( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
	#ifdef PDX_MESH2_UV0
		#ifdef PDX_MESH2_UV0_COMPRESSED
			return ReadPackedFloat2_Unorm16( TypeData._Uv0DataOffset, VertexID );
		#else
			return ReadPackedFloat2( TypeData._Uv0DataOffset, VertexID );
		#endif
	#else
		return float2( 0.0, 0.0 );
	#endif
	}	
	
	float2 GetUv1( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
	#ifdef PDX_MESH2_UV1
		#ifdef PDX_MESH2_UV1_COMPRESSED
			return ReadPackedFloat2_Unorm16( TypeData._Uv1DataOffset, VertexID );
		#else
			return ReadPackedFloat2( TypeData._Uv1DataOffset, VertexID );
		#endif
	#else
		return float2( 0.0, 0.0 );
	#endif
	}
	
	float2 GetUv2( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
	#ifdef PDX_MESH2_UV2
		#ifdef PDX_MESH2_UV2_COMPRESSED
			return ReadPackedFloat2_Unorm16( TypeData._Uv2DataOffset, VertexID );
		#else
			return ReadPackedFloat2( TypeData._Uv2DataOffset, VertexID );
		#endif
	#else
		return float2( 0.0, 0.0 );
	#endif
	}
	
	float2 GetUv3( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
	#ifdef PDX_MESH2_UV3
		#ifdef PDX_MESH2_UV3_COMPRESSED
			return ReadPackedFloat2_Unorm16( TypeData._Uv3DataOffset, VertexID );
		#else
			return ReadPackedFloat2( TypeData._Uv3DataOffset, VertexID );
		#endif
	#else
		return float2( 0.0, 0.0 );
	#endif
	}
	
	float4 GetColor0( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
	#ifdef PDX_MESH2_COLOR0
		#ifdef PDX_MESH2_COLOR0_COMPRESSED
			return ReadPackedFloat4_Unorm8( TypeData._Color0DataOffset, VertexID );
		#else
			return ReadPackedFloat4( TypeData._Color0DataOffset, VertexID );
		#endif
	#else
		return float4( 0.0, 0.0, 0.0, 0.0 );
	#endif
	}
	
	float4 GetColor1( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
	#ifdef PDX_MESH2_COLOR1
		#ifdef PDX_MESH2_COLOR1_COMPRESSED
			return ReadPackedFloat4_Unorm8( TypeData._Color1DataOffset, VertexID );
		#else
			return ReadPackedFloat4( TypeData._Color1DataOffset, VertexID );
		#endif
	#else
		return float4( 0.0, 0.0, 0.0, 0.0 );
	#endif
	}
]]


VertexShader =
{
	VertexStruct VS_INPUT_PDXMESH2
	{
	@ifdef USE_VB
			float3 Position			: POSITION;
			
		@ifdef PDX_MESH2_NORMAL
			float3 Normal      		: NORMAL;
		@endif

		@ifdef PDX_MESH2_TANGENT
			float4 Tangent			: TANGENT;
		@endif
		@ifdef PDX_MESH2_QTANGENT
			float4 QTangent			: TANGENT;
		@endif
			
		@ifdef PDX_MESH2_UV0
			float2 Uv0				: TEXCOORD0;
		@endif
		@ifdef PDX_MESH2_UV1
			float2 Uv1				: TEXCOORD1;
		@endif
		@ifdef PDX_MESH2_UV2
			float2 Uv2				: TEXCOORD2;
		@endif
		@ifdef PDX_MESH2_UV3
			float2 Uv3				: TEXCOORD3;
		@endif

		@ifdef PDX_MESH2_COLOR0
			float4 Color0			: COLOR0;
		@endif
		@ifdef PDX_MESH2_COLOR1
			float4 Color1			: COLOR1;
		@endif
		
		@ifdef PDX_MESH2_SKIN
			@ifdef PDX_MESH2_SKIN_RGBA_UINT16_RGB_FLOAT
				uint4 BoneIndex 		: SKIN0;
				float3 BoneWeight		: SKIN1;
			@else
				uint SkinData 			: SKIN;
			@endif
		@endif
	@endif

		uint VertexID 			: PDX_VertexID;
		uint InstanceID			: PDX_InstanceID;
	};
	
	Code
	[[
	#ifdef USE_VB
		float3 GetPosition( VS_INPUT_PDXMESH2 Input, STypeData TypeData )
		{
			#ifdef PDX_MESH2_POSITION_COMPRESSED
				return DecompressPosition( TypeData, Input.Position );
			#else
				return Input.Position;
			#endif
		}
		
		void GetNormalAndTangent( VS_INPUT_PDXMESH2 Input, out float3 Normal, out float3 Tangent, out float BitangentDir )
		{
			#ifdef PDX_MESH2_QTANGENT
				float4 QTangent = normalize( Input.QTangent );
				// Extract "rotation matrix x-axis" from quaternion
				Normal = float3( 1, 0, 0 ) + float3( -2, 2, -2 ) * QTangent.y * QTangent.yxw + float3( -2, 2, 2 ) * QTangent.z * QTangent.zwx;
				// Extract y-axis
				Tangent = float3( 0, 1, 0 ) + float3( 2, -2, 2 ) * QTangent.x * QTangent.yxw + float3( -2, -2, 2 ) * QTangent.z * QTangent.wzy;
				BitangentDir = sign( QTangent.w );
			#else
				#ifdef PDX_MESH2_NORMAL
					Normal = Input.Normal;
				#else
					Normal = float3( 0.0, 0.0, 0.0 );
				#endif
				
				#ifdef PDX_MESH2_TANGENT
					Tangent = Input.Tangent.xyz;
					BitangentDir = Input.Tangent.w;
				#else
					Tangent = float3( 0.0, 0.0, 0.0 );
					BitangentDir = 0.0;
				#endif
			#endif
		}
		
		float2 GetUv0( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_UV0
				return Input.Uv0;
			#else
				return float2( 0.0, 0.0 );
			#endif
		}
		float2 GetUv1( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_UV1
				return Input.Uv1;
			#else
				return float2( 0.0, 0.0 );
			#endif
		}
		float2 GetUv2( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_UV2
				return Input.Uv2;
			#else
				return float2( 0.0, 0.0 );
			#endif
		}
		float2 GetUv3( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_UV3
				return Input.Uv3;
			#else
				return float2( 0.0, 0.0 );
			#endif
		}
		
		float4 GetColor0( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_COLOR0
				return Input.Color0;
			#else
				return float4( 0.0, 0.0, 0.0, 0.0 );
			#endif
		}
		float4 GetColor1( VS_INPUT_PDXMESH2 Input )
		{
			#ifdef PDX_MESH2_COLOR1
				return Input.Color1;
			#else
				return float4( 0.0, 0.0, 0.0, 0.0 );
			#endif
		}
	#endif
	]]
}
