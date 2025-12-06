Includes = {
	"cw/mesh2/pdx_mesh2_geometry.fxh"
}

BufferTexture SkinningTransformsBuffer
{
	Ref = PdxMesh2SkinningTransformsBuffer
	type = uint
}

BufferTexture PreviousSkinningTransformsBuffer
{
	Ref = PdxMesh2PreviousSkinningTransformsBuffer
	type = uint
}

Code
[[
	struct SSkinningData
	{
		uint _NumBones;
		
		// In this mode just store the data read from the "vertex stream"
	#ifdef PDX_MESH2_SKIN_RGBA_UINT16_RGB_FLOAT
		uint4 _BoneIndices;
		float4 _BoneWeights;
	#else
		uint _BoneDataOffset;
	#endif
	};

#if defined( PDX_MESH2_SKIN	) && defined( PDX_MESH2_SKIN_EXTERNAL )
	SSkinningData UnpackSkinningData( STypeData TypeData, uint Packed )
	{
		uint2 Unpacked = UnpackUint6_Uint26( Packed );
		
		SSkinningData SkinningData;
		SkinningData._NumBones = Unpacked.x;
		#if defined( PDX_MESH2_SKIN_EXTERNAL_8_UINT_24_UNORM ) || defined ( PDX_MESH2_SKIN_EXTERNAL_16_UINT_16_UNORM )
			SkinningData._BoneDataOffset = TypeData._SkinExternalDataOffset + Unpacked.y;
		#else
			// Uncompressed each bone influence stores 1 uint32 and one float, see SMesh2BoneInfluence
			SkinningData._BoneDataOffset = TypeData._SkinExternalDataOffset + Unpacked.y * 2;
		#endif
		return SkinningData;
	}
#endif
	
	SSkinningData GetSkinningDataForType( STypeData TypeData, uint VertexID )
	{
		HandleIndexBuffer( TypeData, VertexID );
		
		SSkinningData SkinningData;
	#ifdef PDX_MESH2_SKIN
		#ifdef PDX_MESH2_SKIN_RGBA_UINT16_RGB_FLOAT
		
			uint DataBufferOffset = TypeData._SkinVertexDataOffset + VertexID * 5;
			uint2 Data = Read2( Mesh2GeometryDataBuffer, DataBufferOffset );
			DataBufferOffset += 2;
			float3 BoneWeights = Read3Float( Mesh2GeometryDataBuffer, DataBufferOffset );
			
			SkinningData._NumBones = 4;
			SkinningData._BoneIndices.xy = UnpackUint16_x2( Data.x );
			SkinningData._BoneIndices.zw = UnpackUint16_x2( Data.y );
			SkinningData._BoneWeights = float4( BoneWeights, 1.0 - BoneWeights.x - BoneWeights.y - BoneWeights.z );
		
		#else

			uint DataBufferOffset = TypeData._SkinVertexDataOffset + VertexID;
			uint Data = Mesh2GeometryDataBuffer[DataBufferOffset];
			SkinningData = UnpackSkinningData( TypeData, Data );
			
		#endif
	#else
		SkinningData._NumBones = 0;
	#endif
	
		return SkinningData;
	}
	
	void GetBoneIndexAndWeightForType( SSkinningData SkinningData, uint Index, out uint BoneIndexOut, out float BoneWeightOut )
	{
	#ifdef PDX_MESH2_SKIN		
		#ifdef PDX_MESH2_SKIN_RGBA_UINT16_RGB_FLOAT
			BoneIndexOut = SkinningData._BoneIndices[Index];
			BoneWeightOut = SkinningData._BoneWeights[Index];
		#else
			
			#if defined( PDX_MESH2_SKIN_EXTERNAL_8_UINT_24_UNORM ) || defined ( PDX_MESH2_SKIN_EXTERNAL_16_UINT_16_UNORM )
				uint DataBufferOffset = SkinningData._BoneDataOffset + Index;
				uint CompressedBoneInfluence = Mesh2GeometryDataBuffer[DataBufferOffset];
				#ifdef PDX_MESH2_SKIN_EXTERNAL_8_UINT_24_UNORM
					UnpackUint8_Unorm24( CompressedBoneInfluence, BoneIndexOut, BoneWeightOut );
				#endif
				#ifdef PDX_MESH2_SKIN_EXTERNAL_16_UINT_16_UNORM
					UnpackUint16_Unorm16( CompressedBoneInfluence, BoneIndexOut, BoneWeightOut );
				#endif
			#else
				uint DataBufferOffset = SkinningData._BoneDataOffset + Index * 2; // Uncompressed each bone influence stores 1 uint32 and one float, see SMesh2BoneInfluence
				BoneIndexOut = Mesh2GeometryDataBuffer[DataBufferOffset];
				BoneWeightOut = asfloat( Mesh2GeometryDataBuffer[DataBufferOffset + 1] );
			#endif
	
		#endif
	#else
		BoneIndexOut = 0;
		BoneWeightOut = 0.0;
	#endif
	}
	
	void ProcessSkinning( uint SkinningTransformsOffset, 
						  uint BoneIndex, float BoneWeight, 
						  float3 Position, float3 Normal, float3 Tangent, 
						  inout float3 SkinnedPosition, inout float3 PreviousSkinnedPosition, inout float3 SkinnedNormal, inout float3 SkinnedTangent )
	{
		float4x4 VertexMatrix = ReadMatrix34( SkinningTransformsBuffer, ( SkinningTransformsOffset + BoneIndex ) * PDX_MESH2_MATRIX34_DATA_STRIDE );
		SkinnedPosition += mul( VertexMatrix, float4( Position, 1.0 ) ).xyz * BoneWeight;
		
	#ifdef PDX_MESH2_MOTION_VECTORS
		float4x4 PreviousVertexMatrix = ReadMatrix34( PreviousSkinningTransformsBuffer, ( SkinningTransformsOffset + BoneIndex ) * PDX_MESH2_MATRIX34_DATA_STRIDE );
		PreviousSkinnedPosition += mul( PreviousVertexMatrix, float4( Position, 1.0 ) ).xyz * BoneWeight;
	#endif
		
		float3 XAxis = float3( GetMatrixData( VertexMatrix, 0, 0 ), GetMatrixData( VertexMatrix, 0, 1 ), GetMatrixData( VertexMatrix, 0, 2 ) );
		float3 YAxis = float3( GetMatrixData( VertexMatrix, 1, 0 ), GetMatrixData( VertexMatrix, 1, 1 ), GetMatrixData( VertexMatrix, 1, 2 ) );
		float3 ZAxis = float3( GetMatrixData( VertexMatrix, 2, 0 ), GetMatrixData( VertexMatrix, 2, 1 ), GetMatrixData( VertexMatrix, 2, 2 ) );

		float XSqMagnitude = dot( XAxis, XAxis );
		float YSqMagnitude = dot( YAxis, YAxis );
		float ZSqMagnitude = dot( ZAxis, ZAxis );
		float3 SqScale = float3( XSqMagnitude, YSqMagnitude, ZSqMagnitude );
		float3 SqScaleReciprocal = vec3( 1.0 ) / SqScale;

		float3 ScaledNormal = Normal * SqScaleReciprocal;
		float3 ScaledTangent = Tangent * SqScaleReciprocal;

		float3x3 VertexRotationMatrix = CastTo3x3( VertexMatrix );
		float3 RotatedNormal =  mul( VertexRotationMatrix, ScaledNormal );
		float3 RotatedTangent = mul( VertexRotationMatrix, ScaledTangent );
		RotatedNormal = normalize( RotatedNormal );
		RotatedTangent = normalize( RotatedTangent );

		SkinnedNormal += RotatedNormal * BoneWeight;
		SkinnedTangent += RotatedTangent * BoneWeight;
	}
]]