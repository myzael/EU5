Includes = {
	"cw/mesh2/pdx_mesh2.fxh"
}

BufferTexture Mesh2MeshStatesBuffer
{
	Ref = PdxMesh2MeshStatesBuffer
	type = uint
}

BufferTexture Mesh2CompactedInstancesBuffer
{
	Ref = PdxMesh2CompactedInstancesBuffer
	type = uint
}


Code
[[
	struct SLodResult
	{
		static const uint NoLod = UINT32_MAX;

		uint _BaseLod;
		uint _NextLod;
		float _BlendValue;
	};
	SLodResult CreateLodResult( uint BaseLod )
	{
		SLodResult Result;
		Result._BaseLod = BaseLod;
		Result._NextLod = SLodResult::NoLod;
		Result._BlendValue = 0.0;
		return Result;
	}


	struct SMeshStateData
	{
		float3 _BoundingSphereCenter;
		float _BoundingSphereRadius;
		uint _NumLods;
	};
	#define PDX_MESH2_MESH_STATE_DATA_STRIDE ( 128 / 4 ) // CWorldBucketGpu::UpdateMeshStateBuffer()
	#define PDX_MESH2_MESH_STATE_DATA_DYNAMIC_DATA_OFFSET 5 // 5 to jump over bounding sphere and num lods, see CWorldBucketGpu::UpdateMeshStateBuffer()/SMeshStateGpuData for how this data is laid out
	
	struct SMeshInstanceData
	{
		uint _TransformIndex;
		uint _MeshStateIndex;
	};
	#define PDX_MESH2_MESH_INSTANCE_DATA_STRIDE 2
	
	
	SMeshStateData LoadMeshStateData( uint MeshStateIndex )
	{
		uint DataOffset = MeshStateIndex * PDX_MESH2_MESH_STATE_DATA_STRIDE;
		
		SMeshStateData MeshStateData;
		MeshStateData._BoundingSphereCenter = asfloat( Read3( Mesh2MeshStatesBuffer, DataOffset ) );
		DataOffset += 3;
		MeshStateData._BoundingSphereRadius = asfloat( Mesh2MeshStatesBuffer[DataOffset++] );
		MeshStateData._NumLods = Mesh2MeshStatesBuffer[DataOffset++];
		
		return MeshStateData;
	}

	// See CWorldBucketGpu::UpdateMeshStateBuffer()/SMeshStateGpuData for how this data is laid out
	uint LoadMeshStateLodIndex( uint MeshStateIndex, uint LodIndex )
	{
		uint MeshStateLodIndexDataOffset = ( MeshStateIndex * PDX_MESH2_MESH_STATE_DATA_STRIDE ) + PDX_MESH2_MESH_STATE_DATA_DYNAMIC_DATA_OFFSET;
		return Mesh2MeshStatesBuffer[ MeshStateLodIndexDataOffset + LodIndex ];
	}
	

	SMeshInstanceData LoadMeshInstanceData( uint DataOffset )
	{
		SMeshInstanceData Data;
		Data._TransformIndex = Mesh2CompactedInstancesBuffer[DataOffset++];
		Data._MeshStateIndex = Mesh2CompactedInstancesBuffer[DataOffset++];
		return Data;
	}
	
	SMeshInstanceData LoadMeshInstanceDataForIndex( uint Index )
	{
		return LoadMeshInstanceData( Index * PDX_MESH2_MESH_INSTANCE_DATA_STRIDE );
	}
	
	
	float CalcDistanceFromPlane( float3 Point, float4 Plane )
	{
		return dot( Plane.xyz, Point ) + Plane.w;
	}
	
	bool SphereIntersectsFrustum( float3 Center, float Radius, float4 FrustumPlanes[6] )
	{		
		for ( int i = 0; i < 6; ++i )
		{
			float DistanceFromPlane = CalcDistanceFromPlane( Center, FrustumPlanes[i] );
			if ( DistanceFromPlane > Radius )
			{
				return false;
			}
		}
		
		return true;
	}

	float CalcLengthSquared( float3 Vec )
	{
		return dot( Vec, Vec );
	}
	
	// From https://zeux.io/2023/01/12/approximate-projected-bounds/
	bool ProjectSphere( float3 c, float r, float znear, float P00, float P11, out float4 Aabb )
	{
		if (c.z < r + znear)
		{
			return false;
		}

		float3 cr = c * r;
		float czr2 = c.z * c.z - r * r;

		float vx = sqrt(c.x * c.x + czr2);
		float minx = (vx * c.x - cr.z) / (vx * c.z + cr.x);
		float maxx = (vx * c.x + cr.z) / (vx * c.z - cr.x);

		float vy = sqrt(c.y * c.y + czr2);
		float miny = (vy * c.y - cr.z) / (vy * c.z + cr.y);
		float maxy = (vy * c.y + cr.z) / (vy * c.z - cr.y);

		Aabb = float4( minx * P00, miny * P11, maxx * P00, maxy * P11 );
		// clip space -> uv space
		Aabb = Aabb.xwzy * float4( 0.5, -0.5, 0.5, -0.5 ) + vec4( 0.5 );

		return true;
	}

	void CalculateTransformedBoundingSphere( SMeshInstanceData MeshInstanceData, out float4 BoundingSphereOut )
	{
		SMeshStateData MeshStateData = LoadMeshStateData( MeshInstanceData._MeshStateIndex );
	
		float4x4 InstanceTransform = LoadInstanceTransform( MeshInstanceData._TransformIndex );
		BoundingSphereOut.xyz = mul( InstanceTransform, float4( MeshStateData._BoundingSphereCenter, 1.0 ) ).xyz;
	
		float4x4 TransposedTransform = transpose( InstanceTransform );
		float MaxScaling = sqrt( max( max( CalcLengthSquared( TransposedTransform[0].xyz ), CalcLengthSquared( TransposedTransform[1].xyz ) ), CalcLengthSquared( TransposedTransform[2].xyz ) ) );
		BoundingSphereOut.w = MeshStateData._BoundingSphereRadius * MaxScaling;
	}
	
	bool CalculateOcclusionSettings( float4 BoundingSphere, float ZNear, float4x4 ViewMatrix, float4x4 ProjectionMatrix, uint2 DepthPyramidSize, uint DepthPyramidMaxMipLevel, 
									 out float4 DepthPyramidUvRectOut, out float DepthPyramidLevelOut, out float SphereDepthOut )
	{
		float3 ViewSpaceSphereCenter = mul( ViewMatrix, float4( BoundingSphere.xyz, 1 ) ).xyz;
		if ( !ProjectSphere( ViewSpaceSphereCenter, BoundingSphere.w, ZNear, ProjectionMatrix[0][0], ProjectionMatrix[1][1], DepthPyramidUvRectOut ) )
		{
			return false;
		}
		
		float2 AabbSize = ( DepthPyramidUvRectOut.zw - DepthPyramidUvRectOut.xy ) * DepthPyramidSize;
		DepthPyramidLevelOut = ceil( log2( max( AabbSize.x, AabbSize.y ) ) );
		DepthPyramidLevelOut = clamp( DepthPyramidLevelOut, 0, DepthPyramidMaxMipLevel );
		
		// Since this can be quite conservative check if next lower level mip only touches a 2x2 region, if so use it
		float NextMipLevel = max( DepthPyramidLevelOut - 1, 0 );
		uint2 NextMipLevelSize = DepthPyramidSize >> uint( NextMipLevel );
		uint2 MinTexel = DepthPyramidUvRectOut.xy * NextMipLevelSize;
		uint2 MaxTexel = DepthPyramidUvRectOut.zw * NextMipLevelSize;
		uint2 RegionSize = MaxTexel - MinTexel;		
		if ( RegionSize.x <= 1 && RegionSize.y <= 1 )
		{
			DepthPyramidLevelOut = NextMipLevel;
		}
		
		SphereDepthOut = ( ViewSpaceSphereCenter.z - BoundingSphere.w );
		
		return true;
	}

	float CalculateScreenSize( float3 CameraPos, float3 ObjectPos, float ObjectRadius, float LodScale )
	{
		const float Epsilon = 0.00001;
		float DistanceToObject = length( ObjectPos - CameraPos );
		return ( LodScale * ObjectRadius ) / max( DistanceToObject, Epsilon );
	}

	SLodResult CalculateLod( SMeshStateData MeshStateData, SMeshInstanceData MeshInstanceData, float4 BoundingSphere, float3 LodCameraPosition, float LodScale, float LodFadeRange, uint LodFadeEnabled )
	{
		// See CWorldBucketGpu::UpdateMeshStateBuffer()/SMeshStateGpuData for how this data is laid out
		uint ScreenPercentageDataOffset = ( MeshInstanceData._MeshStateIndex * PDX_MESH2_MESH_STATE_DATA_STRIDE ) + PDX_MESH2_MESH_STATE_DATA_DYNAMIC_DATA_OFFSET + MeshStateData._NumLods;
		float InstanceScreenSize = CalculateScreenSize( LodCameraPosition, BoundingSphere.xyz, BoundingSphere.w, LodScale );

		uint PrevLodIndex = SLodResult::NoLod;
		for ( int i =  MeshStateData._NumLods - 1; i >= 0; --i )
		{
			const uint LodIndex = uint( i );
			const float LodFadeStart = asfloat( Mesh2MeshStatesBuffer[ ScreenPercentageDataOffset + LodIndex ] );
			// If we are not large enough for this lod we should use previous lod (or NoLod/Cull if this is the last lod)
			if ( InstanceScreenSize < LodFadeStart )
			{
				return CreateLodResult( PrevLodIndex );
			}
	
			const float PrevLodFadeStart = ( LodIndex == 0 ) ? 1.0 : asfloat( Mesh2MeshStatesBuffer[ ScreenPercentageDataOffset + LodIndex - 1 ] );
			// Multiplying with ( 1.0f + LodFadeRange ) instead of adding LodFadeRange causes quicker transitions when the percentage is low.
			const float LodFadeEnd = min( LodFadeStart * ( 1.0f + LodFadeRange ), PrevLodFadeStart );
	
			// If we are larger than the fade end, we should try the next lod
			if ( InstanceScreenSize > LodFadeEnd )
			{
				PrevLodIndex = LodIndex;
				continue;
			}
	
			// If we reach here it means we are in the fade range
			SLodResult LodResult = CreateLodResult( LodIndex );
			if ( LodFadeEnabled == 1 )
			{
				// Find the t value of `InstanceScreenSizeLodBiased` between `LodFadeStart` and `LodFadeEnd`
				LodResult._BlendValue = 1.0 - saturate( ( LodFadeEnd - InstanceScreenSize ) / max( 0.0001, LodFadeEnd - LodFadeStart ) );
				LodResult._NextLod = PrevLodIndex;
			}
			return LodResult;
		}
	
		return CreateLodResult( PrevLodIndex );
	}
]]