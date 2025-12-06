Includes = {
	"cw/pdx_lights.fxh"
	"cw/camera.fxh"
}	

ComputeShader =
{
	ConstantBuffer( PdxConstantBuffer0 )
	{
		float4x4 _InvProjectionMatrix;
		float4x4 _ViewMatrix;
		int2 _Resolution;
		uint2 _NumTilesCompute;
		uint2 _TileSizeCompute;
		uint _MaxLightsPerTileListEntries;
	};

	RWBufferTexture RwLightsPerTileList
	{
		Ref = PdxRWBufferTexture0
		type = uint
	}
	RWBufferTexture RwScreenTileToLightsPerTileList
	{
		Ref = PdxRWBufferTexture1
		type = uint
	}
	
	# TODO:[PSGE-4056] This is work in progress, using last frames depth buffer, also precision is becoming an issue, should investigate reverse depth buffer
	TextureSampler DepthBuffer
	{
		Ref = JominiDepthBuffer
		MagFilter = "Point"
		MinFilter = "Point"
		MipFilter = "Point"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}

	MainCode TiledCulling
	{
		VertexStruct CS_INPUT
		{
			uint3 GlobalId : PDX_DispatchThreadID	# "Global" id for whole dispatch, 0,0 -> NumTiles.x/y * NUM_THREADS_X/NUM_THREADS_Y
			uint3 LocalId : PDX_GroupThreadID 		# "Local" id within threadgroup, 0,0 -> NUM_THREADS_X/NUM_THREADS_Y
			uint3 GroupId : PDX_GroupID				# "Group" id, 0,0 -> NumTiles.x/y
			uint LocalIndex : PDX_GroupIndex		# "Flattened local" index within threadgroup, 0 -> NUM_THREADS_X * NUM_THREADS_Y
		};
	
		Input = "CS_INPUT"
		NumThreads = { NUM_THREADS_X NUM_THREADS_Y 1 }
		Code 
		[[
			#define DO_AABB_TEST
			#define DO_TILE_FRUSTUM_TEST
			//#define DO_TILE_FRUSTUM_DEPTH_TEST
			
			#define MAX_NUM_LIGHTS_PER_TILE 256
			
			groupshared uint DepthMinAsUint; // Min depth of the tile (uint so we can do atomics)
			groupshared uint DepthMaxAsUint; // Max depth of the tile (uint so we can do atomics)
			groupshared float3 FrustumPlanes[4]; // The 4 side frustum planes of the tile, these are in viewspace and origin is intersecting the plane, hence we only need to store the normal (distance = 0)
			groupshared uint NumTotalLightsWritten; // The number of lights written for this tile (threads atomic increments this one)
			groupshared uint NumPointLightsWritten; // The number of point lights written for this tile (threads atomic increments this one)
			groupshared uint NumSpotLightsWritten; // The number of spot lights written for this tile (threads atomic increments this one)
			groupshared uint LightDataIndices[MAX_NUM_LIGHTS_PER_TILE]; // Light data index for "tile light [i]"
			groupshared uint WriteIndex; // Index into the global LightsPerTileList where we should write data for this tile
			
			// Creates a plane from view space points P1, P2 and the implicit origin, hence we do not need to save distance
			float3 CreatePlane( float3 P1, float3 P2 )
			{
				float3 Normal = normalize( cross( P1, P2 ) );
				return float3( Normal );
			}

			float CalcDistanceFromPlane( float3 P, float3 Plane )
			{
			 	return dot( Plane.xyz, P );
			}
			
			// From https://simoncoenen.com/blog/programming/graphics/SpotlightCulling
			bool IsPointBehindPlane( float3 P, float3 Plane )
			{
			  	return CalcDistanceFromPlane( P, Plane ) < 0.0;
			}

			bool IsConeBehindPlane( float3 ConeTip, float3 ConeDirection, float ConeHeight, float ConeRadius, float3 Plane )
			{
				float3 FurthestPointDirection = normalize( cross( cross( Plane, ConeDirection ), ConeDirection ) );
				float3 FurthestPointOnCircle = ConeTip + ConeDirection * ConeHeight - FurthestPointDirection * ConeRadius;
				return IsPointBehindPlane( ConeTip, Plane ) && IsPointBehindPlane( FurthestPointOnCircle, Plane );
			}
			
			float3 CalcViewSpacePos( float3 ClipSpacePos )
			{
				float4 Unprojected = mul( _InvProjectionMatrix, float4( ClipSpacePos, 1.0 ) );
				return Unprojected.xyz / Unprojected.w;
			}
			float3 CalcViewSpacePos( int PixelPosX, int PixelPosY )
			{
				float3 ClipSpacePos = float3( ( float2( PixelPosX, _Resolution.y - PixelPosY ) / float2( _Resolution ) ) * 2.0 - 1.0, 1.0 );
				return CalcViewSpacePos( ClipSpacePos );
			}
			
			float ComputeSquaredDistanceToAABB( float3 Pos, float3 AABBCenter, float3 AABBHalfSize )
			{
				float3 Delta = max( vec3( 0.0 ), abs( AABBCenter - Pos ) - AABBHalfSize );
				return dot( Delta, Delta );
			}
			bool TestSphereVsAABB( float3 SphereCenter, float SphereRadius, float3 AABBCenter, float3 AABBHalfSize )
			{
				float DistanceSq = ComputeSquaredDistanceToAABB( SphereCenter, AABBCenter, AABBHalfSize );
				return DistanceSq <= SphereRadius * SphereRadius;
			}
			
			// From https://bartwronski.com/2017/04/13/cull-that-cone/ and https://www.cbloom.com/3d/techdocs/culling.txt
			// Kept the variable names from those articles for easier mapping
			bool TestConeVsAABB( float3 ConeTip, float3 ConeDirection, float CosHalfAngle, float3 AABBCenter, float3 AABBHalfSize )
			{
				float SphereRadius = sqrt( dot( AABBHalfSize, AABBHalfSize ) );
				float3 V = AABBCenter - ConeTip;
				float VLengthSq = dot( V, V );
				float V1Length = dot( V, ConeDirection );
				float E = CosHalfAngle * sqrt( VLengthSq - V1Length * V1Length ) - V1Length * sin( acos( CosHalfAngle ) ); // Can we avoid the trig somehow?
				bool AngleCull = E > SphereRadius;
				bool BackCull = V1Length < -SphereRadius;
				
				// We do not use the FrontCull since we are doing TestSphereVsAABB() anyway and it catches those
				
				return !AngleCull && !BackCull;
			}
			
			
			// Test pointlight against tile AABB
			bool IntersectsTileAABB( SPointLight PointLight, float3 AABBCenter, float3 AABBHalfSize )
			{
				float3 ViewSpaceLightPos = mul( _ViewMatrix, float4( PointLight._Position, 1.0 ) ).xyz;
				
				return TestSphereVsAABB( ViewSpaceLightPos, PointLight._Radius, AABBCenter, AABBHalfSize );
			}
			
			// Test spotlight against tile AABB
			bool IntersectsTileAABB( SSpotLight Spot, float3 AABBCenter, float3 AABBHalfSize )
			{
				float3 ViewSpaceLightPos = mul( _ViewMatrix, float4( Spot._PointLight._Position, 1.0 ) ).xyz;
				float3 ViewSpaceConeDirection = mul( _ViewMatrix, float4( Spot._ConeDirection, 0.0 ) ).xyz;
				
				return TestSphereVsAABB( ViewSpaceLightPos, Spot._PointLight._Radius, AABBCenter, AABBHalfSize ) && TestConeVsAABB( ViewSpaceLightPos, ViewSpaceConeDirection, Spot._CosOuterConeHalfAngle, AABBCenter, AABBHalfSize );
			}
			
			
			// Test pointlight against tile frustum
			bool IntersectsTileFrustum( SPointLight PointLight, float DepthMin, float DepthMax, float3 FrustumPlanes[4] )
			{
				float3 ViewSpaceLightPos = mul( _ViewMatrix, float4( PointLight._Position, 1.0 ) ).xyz;
				
				if ( 
				#ifdef DO_TILE_FRUSTUM_DEPTH_TEST
					( ViewSpaceLightPos.z - PointLight._Radius < DepthMax ) && 
					( ViewSpaceLightPos.z + PointLight._Radius > DepthMin ) &&
				#endif
					( CalcDistanceFromPlane( ViewSpaceLightPos, FrustumPlanes[0] ) < PointLight._Radius ) &&
					( CalcDistanceFromPlane( ViewSpaceLightPos, FrustumPlanes[1] ) < PointLight._Radius ) &&
					( CalcDistanceFromPlane( ViewSpaceLightPos, FrustumPlanes[2] ) < PointLight._Radius ) &&
					( CalcDistanceFromPlane( ViewSpaceLightPos, FrustumPlanes[3] ) < PointLight._Radius ) )
				{
					return true;
				}

				return false;
			}

			// Test spotlight against tile frustum
			bool IntersectsTileFrustum( SSpotLight Spot, float DepthMin, float DepthMax, float3 FrustumPlanes[4] )
			{
				float3 ViewSpaceLightPos = mul( _ViewMatrix, float4( Spot._PointLight._Position, 1.0 ) ).xyz;
				float3 ViewSpaceConeDirection = mul( _ViewMatrix, float4( Spot._ConeDirection, 0.0 ) ).xyz;
				float ConeRadius = tan( acos( Spot._CosOuterConeHalfAngle ) ) * Spot._PointLight._Radius; // Can we avoid the trig somehow?
				
				if ( !IsConeBehindPlane( ViewSpaceLightPos, ViewSpaceConeDirection, Spot._PointLight._Radius, ConeRadius, -FrustumPlanes[0] ) &&
					 !IsConeBehindPlane( ViewSpaceLightPos, ViewSpaceConeDirection, Spot._PointLight._Radius, ConeRadius, -FrustumPlanes[1] ) &&
					 !IsConeBehindPlane( ViewSpaceLightPos, ViewSpaceConeDirection, Spot._PointLight._Radius, ConeRadius, -FrustumPlanes[2] ) &&
					 !IsConeBehindPlane( ViewSpaceLightPos, ViewSpaceConeDirection, Spot._PointLight._Radius, ConeRadius, -FrustumPlanes[3] ) )
				{
					return true;
				}
				
				return false;
			}
			

			// Does the enabled tile/light intersections and updates the shared variables (NumTotalLightsWritten/NumPointLightsWritten/LightDataIndices)
			// Returns false when shared list is full
			bool HandlePointLightIntersection( uint LightDataIndex, float3 AABBCenter, float3 AABBHalfSize, float DepthMin, float DepthMax, float3 FrustumPlanes[4] )
			{
				SPointLight pointlight = GetPointLight( LightDataIndex );
			#ifdef DO_AABB_TEST
				bool IsIntersectingAABB = IntersectsTileAABB( pointlight, AABBCenter, AABBHalfSize );
			#else
				bool IsIntersectingAABB = true;
			#endif
			
			#ifdef DO_TILE_FRUSTUM_TEST
				bool IsIntersectingTile = IntersectsTileFrustum( pointlight, DepthMin, DepthMax, FrustumPlanes );
			#else
				bool IsIntersectingTile = true;
			#endif
			
				if ( IsIntersectingAABB && IsIntersectingTile )
				{
					uint LocalLightIndex = 0;
					InterlockedAdd( NumTotalLightsWritten, 1, LocalLightIndex ); // Check which position we should write into
					InterlockedAdd( NumPointLightsWritten, 1 );
					if ( LocalLightIndex < MAX_NUM_LIGHTS_PER_TILE ) // Check that we have not exceeded max num lights
					{
						LightDataIndices[LocalLightIndex] = LightDataIndex;
					}
					else
					{
						return false;
					}
				}
				
				return true;
			}
			
			
			// Does the enabled tile/light intersections and updates the shared variables (NumTotalLightsWritten/NumSpotLightsWritten/LightDataIndices)
			// Returns false when shared list is full
			bool HandleSpotLightIntersection( uint LightDataIndex, float3 AABBCenter, float3 AABBHalfSize, float DepthMin, float DepthMax, float3 FrustumPlanes[4] )
			{
				SSpotLight Spot = GetSpotLight( LightDataIndex );
			#ifdef DO_AABB_TEST
				bool IsIntersectingAABB = IntersectsTileAABB( Spot, AABBCenter, AABBHalfSize );
			#else
				bool IsIntersectingAABB = true;
			#endif
			
			#ifdef DO_TILE_FRUSTUM_TEST
				bool IsIntersectingTile = IntersectsTileFrustum( Spot, DepthMin, DepthMax, FrustumPlanes );
			#else
				bool IsIntersectingTile = true;
			#endif
			
				if ( IsIntersectingAABB && IsIntersectingTile )
				{
					uint LocalLightIndex = 0;
					InterlockedAdd( NumTotalLightsWritten, 1, LocalLightIndex ); // Check which position we should write into
					InterlockedAdd( NumSpotLightsWritten, 1 );
					if ( LocalLightIndex < MAX_NUM_LIGHTS_PER_TILE ) // Check that we have not exceeded max num lights
					{
						LightDataIndices[LocalLightIndex] = LightDataIndex;
					}
					else
					{
						return false;
					}
				}
				
				return true;
			}
			
			
			PDX_MAIN
			{
				// Init the global variables
				if( Input.LocalIndex == 0 )
				{
					DepthMinAsUint = asuint( ZFar );
					DepthMaxAsUint = 0;
					NumTotalLightsWritten = 0;
					NumPointLightsWritten = 0;
					NumSpotLightsWritten = 0;
				}
				
				// Calculate pixel position clamped to resolution (note that last tile can extend outside of resolution)
				uint2 MaxPixelPos =  uint2( _Resolution - 1.0 );
				uint2 PixelPos = min( Input.GlobalId.xy, MaxPixelPos );
				
				// Sample depth buffer and calculate view space depth
				float Depth = PdxTex2DLoad0( DepthBuffer, PixelPos ).x;
				Depth = CalcViewSpaceDepth( Depth );
				
				// Convert depth to uint because atomic operations are on integers only
				// for our case this conversion should be safe since float depth is always positive and the int representaion behaves the same in regards to Min/Max
				uint DepthAsUint = asuint( Depth );
			
				// This it to sync the initing of global variables (DepthMinAsUint/DepthMaxAsUint) before we start overwriting them
				GroupMemoryBarrierWithGroupSync();
				
				// Figure out tiles min/max depth
				InterlockedMin( DepthMinAsUint, DepthAsUint );
				InterlockedMax( DepthMaxAsUint, DepthAsUint );
				// Sync min/max calculation
				GroupMemoryBarrierWithGroupSync();
				
				// Convert min/max depth back to float
				float DepthMin = asfloat( DepthMinAsUint );
				float DepthMax = asfloat( DepthMaxAsUint );
				
				// Calculate tile information
				uint2 TileSize = uint2( NUM_THREADS_X, NUM_THREADS_Y );
				uint2 TileMin = TileSize * Input.GroupId.xy;
				// Last tile can go outside resolution, hence the min()
				uint2 TileMax = min( TileMin + TileSize, MaxPixelPos );
				

				// Calculate corners of the tile at far plane
				float3 Corners[4];
				Corners[0] = CalcViewSpacePos( TileMin.x, TileMin.y );
				Corners[1] = CalcViewSpacePos( TileMax.x, TileMin.y );
				Corners[2] = CalcViewSpacePos( TileMax.x, TileMax.y );
				Corners[3] = CalcViewSpacePos( TileMin.x, TileMax.y );
				
				// Create frustum planes for the tile (going through Corners and origin (camera position in view space))
				float3 FrustumPlanes[4];
				FrustumPlanes[0] = CreatePlane( Corners[0], Corners[1] );
				FrustumPlanes[1] = CreatePlane( Corners[1], Corners[2] );
				FrustumPlanes[2] = CreatePlane( Corners[2], Corners[3] );
				FrustumPlanes[3] = CreatePlane( Corners[3], Corners[0] );

			
				// Two opposite corners of the tile, top-left and bottom-right, at the far plane
				float3 FrustumTL = Corners[0]; //CalcViewSpacePos( TileMin.x, TileMin.y );
				float3 FrustumBR = Corners[2]; //CalcViewSpacePos( TileMax.x, TileMax.y );
			
				// Calculate frustum x/y extents at min/max depth
				float2 FrustumTLAtBack = vec2( DepthMax / FrustumTL.z ) * FrustumTL.xy;
				float2 FrustumBRAtBack = vec2( DepthMax / FrustumBR.z ) * FrustumBR.xy;
				float2 FrustumTLAtFront = vec2( DepthMin / FrustumTL.z ) * FrustumTL.xy;
				float2 FrustumBRAtFront = vec2( DepthMin / FrustumBR.z ) * FrustumBR.xy;
			
				// Calculate frustum min/max x/y extents
				float2 FrustumMinXY = min( min( FrustumTLAtBack, FrustumBRAtBack ), min( FrustumTLAtFront, FrustumBRAtFront ) );
				float2 FrustumMaxXY = max( max( FrustumTLAtBack, FrustumBRAtBack ), max( FrustumTLAtFront, FrustumBRAtFront ) );
			
				// Final AABB
				float3 FrustumAABBMin = float3( FrustumMinXY, DepthMin );
				float3 FrustumAABBMax = float3( FrustumMaxXY, DepthMax);
			
				float3 FrustumAABBCenter = ( FrustumAABBMin + FrustumAABBMax ) * 0.5;
				float3 FrustumAABBHalfSize = ( FrustumAABBMax - FrustumAABBMin ) * 0.5;

				
				// We process NUM_THREADS lights in "parallell"
				#define NUM_THREADS ( NUM_THREADS_X * NUM_THREADS_Y )

				// In ECullingMode_CpuGpuTiled mode we have prepared a coarse tile grid on the CPU, fetch information from that one and refine with smaller GPU tiles and depth information
#ifdef DYNAMIC_CULLING_MODE
				if ( _CullingMode == ECullingMode_CpuGpuTiled )
#endif
#if defined( DYNAMIC_CULLING_MODE ) || defined ( CULLING_MODE_TILED )
				{
					uint LightsPerTileListIndex = CalculateLightsPerTileListIndexForTile( PixelPos );
					
					uint NumPointLights = PdxReadBuffer( LightsPerTileList, LightsPerTileListIndex );
					uint NumSpotLights = PdxReadBuffer( LightsPerTileList, LightsPerTileListIndex + 1 );
					uint Offset = LightsPerTileListIndex + 2;  // +2 to jump over the "NumPointLights/NumSpotLights"
					for ( uint i = Input.LocalIndex; i < NumPointLights; i += NUM_THREADS )
					{
						uint LightDataIndex = PdxReadBuffer( LightsPerTileList, Offset + i );
						if ( !HandlePointLightIntersection( LightDataIndex, FrustumAABBCenter, FrustumAABBHalfSize, DepthMin, DepthMax, FrustumPlanes ) )
						{
							break;
						}
					}
					
					// We want to finish writing all pointlights first
					GroupMemoryBarrierWithGroupSync();
					
					Offset += NumPointLights; // Jump over point lights
					for ( uint i = Input.LocalIndex; i < NumSpotLights; i += NUM_THREADS )
					{
						uint LightDataIndex = PdxReadBuffer( LightsPerTileList, Offset + i );
						if ( !HandleSpotLightIntersection( LightDataIndex, FrustumAABBCenter, FrustumAABBHalfSize, DepthMin, DepthMax, FrustumPlanes ) )
						{
							break;
						}
					}
				}
#endif // defined( DYNAMIC_CULLING_MODE ) || defined ( CULLING_MODE_TILED )

				// In this case we loop through whole global (visible) light list
#ifdef DYNAMIC_CULLING_MODE
				else
#endif
#if defined( DYNAMIC_CULLING_MODE ) || defined ( CULLING_MODE_NONE )
				{
					uint LightDataIndexOffset = _NumDirectionalLights * NUM_VECTORS_FOR_DIRECTIONALLIGHT; // Ignore directional lights
					for ( uint LightIndex = Input.LocalIndex; LightIndex < _NumPointLights; LightIndex += NUM_THREADS )
					{
						uint LightDataIndex = LightDataIndexOffset + LightIndex * NUM_VECTORS_FOR_POINTLIGHT; // Each pointlight takes NUM_VECTORS_FOR_POINTLIGHT entries
						if ( !HandlePointLightIntersection( LightDataIndex, FrustumAABBCenter, FrustumAABBHalfSize, DepthMin, DepthMax, FrustumPlanes ) )
						{
							break;
						}
					}
					
					// We want to finish writing all pointlights first
					GroupMemoryBarrierWithGroupSync();
					
					LightDataIndexOffset += _NumPointLights * NUM_VECTORS_FOR_POINTLIGHT; // Spot lights comes after point lights
					for ( uint LightIndex = Input.LocalIndex; LightIndex < _NumSpotLights; LightIndex += NUM_THREADS )
					{
						uint LightDataIndex = LightDataIndexOffset + LightIndex * NUM_VECTORS_FOR_SPOTLIGHT; // Each spotlight takes NUM_VECTORS_FOR_SPOTLIGHT entries
						if ( !HandleSpotLightIntersection( LightDataIndex, FrustumAABBCenter, FrustumAABBHalfSize, DepthMin, DepthMax, FrustumPlanes ) )
						{
							break;
						}
					}
				}
#elif !defined( CULLING_MODE_TILED )
				LightDataIndices[0] = 0; // If we do not do this compiler complains about potentially reading uninitialized variable, note that there should be no reading since NumTotalLightsWritten remains 0 in this case
#endif // defined( DYNAMIC_CULLING_MODE ) || defined ( CULLING_MODE_NONE )

				// Sync light culling, it writes to shared variables NumTotalLightsWritten/NumPointLightsWritten/NumSpotLightsWritten/LightDataIndices
				GroupMemoryBarrierWithGroupSync();
				
				// First thread responsible for writing tile information
				if( Input.LocalIndex == 0 )
				{
					// Last entry in RwScreenTileToLightsPerTileList is allocated for atomic counter
					uint AtomicIndex = _NumTilesCompute.x * _NumTilesCompute.y;
					WriteIndex = 0;
					if ( NumTotalLightsWritten > 0 )
					{
						uint NumEntriesToWrite = NumTotalLightsWritten + 2; // +2 since we also store "NumPointLights/NumSpotLights" per tile
						InterlockedAdd( RwScreenTileToLightsPerTileList[AtomicIndex], NumEntriesToWrite, WriteIndex );
						
						// If the buffer would overflow we do not write any lights for this tile
						if ( WriteIndex + NumEntriesToWrite >= _MaxLightsPerTileListEntries )
						{
							WriteIndex = 0;
							NumTotalLightsWritten = 0;
							NumPointLightsWritten = 0;
							NumSpotLightsWritten = 0;
						}
					}
					
					// Write the tile -> lights per tile list mapping
					RwScreenTileToLightsPerTileList[ CalculateOffsetForTile( Input.GroupId.xy, _NumTilesCompute ) ] = WriteIndex;
					// Write number of lights for this tile (first entries in lights per tile list)
					RwLightsPerTileList[ WriteIndex++ ] = NumPointLightsWritten;
					RwLightsPerTileList[ WriteIndex++ ] = NumSpotLightsWritten;
				}
				// Sync WriteIndex/NumTotalLightsWritten
				GroupMemoryBarrierWithGroupSync();

				for ( uint LightIndex = Input.LocalIndex; LightIndex < NumTotalLightsWritten; LightIndex += NUM_THREADS )
				{
					RwLightsPerTileList[ WriteIndex + LightIndex ] = LightDataIndices[ LightIndex ];
				}
			}
		]]
	}
}

# User needs to supply 2 defines NUM_THREADS_X/NUM_THREADS_Y specifying the threadcount
Effect TiledCulling
{
	ComputeShader = "TiledCulling"
}
