Includes = {
	"cw/camera.fxh"
	"cw/mesh2/pdx_mesh2_culling.fxh"
}

ComputeShader =
{
	VertexStruct CS_INPUT
	{
		uint3 GlobalId : PDX_DispatchThreadID
	};

	MainCode ComputeShader_ClearInstanceCountBuffer
	{
		RWBufferTexture Mesh2MeshStateLodInstanceCountRwBuffer
		{
			Ref = PdxRWBufferTexture0
			type = uint
		}
		
		ConstantBuffer( PdxConstantBuffer0 )
		{
			uint _NumMeshStateLods;
		};
		
		Input = "CS_INPUT"
		NumThreads = { 128 1 1 }
		Code 
		[[
			PDX_MAIN
			{
				uint Index = min( Input.GlobalId.x, _NumMeshStateLods );				
				Mesh2MeshStateLodInstanceCountRwBuffer[Index] = 0;
			}
		]]
	}
	
	MainCode ComputeShader_DrawCallUpdate
	{
		BufferTexture Mesh2DrawCallMeshLodIndexBuffer
		{
			Ref = PdxBufferTexture0
			type = uint
		}
		
		BufferTexture Mesh2DrawCallIndexCountPerInstanceBuffer
		{
			Ref = PdxBufferTexture1
			type = uint
		}
		
		BufferTexture Mesh2MeshStateLodInstanceCountBuffer
		{
			Ref = PdxBufferTexture2
			type = uint
		}
		
		RWBufferTexture Mesh2DrawCallRwBuffer
		{
			Ref = PdxRWBufferTexture0
			type = uint
		}
		
		ConstantBuffer( PdxConstantBuffer0 )
		{
			uint _NumDrawCalls;
		};
		
		Input = "CS_INPUT"
		NumThreads = { 128 1 1 }
		Code 
		[[
			PDX_MAIN
			{
				uint DrawCallIndex = min( Input.GlobalId.x, _NumDrawCalls );
				uint MeshStateLodIndex = Mesh2DrawCallMeshLodIndexBuffer[DrawCallIndex];
				uint IndexCountPerInstance = Mesh2DrawCallIndexCountPerInstanceBuffer[DrawCallIndex];
				uint InstanceCount = Mesh2MeshStateLodInstanceCountBuffer[MeshStateLodIndex];
				
				uint DrawcallBufferIndex = DrawCallIndex * 5; // Each drawcall argument is 5 32 bit values
				Mesh2DrawCallRwBuffer[DrawcallBufferIndex] = IndexCountPerInstance; // First value is "_IndexCountPerInstance", see SGfxDrawIndexedInstancedIndirectArgs
				Mesh2DrawCallRwBuffer[DrawcallBufferIndex + 1] = InstanceCount; // Second value is "_InstanceCount", see SGfxDrawIndexedInstancedIndirectArgs
				
				// Clear _StartIndexLocation, _BaseVertexLocation, _StartInstanceLocation
				Mesh2DrawCallRwBuffer[DrawcallBufferIndex + 2] = 0;
				Mesh2DrawCallRwBuffer[DrawcallBufferIndex + 3] = 0;
				Mesh2DrawCallRwBuffer[DrawcallBufferIndex + 4] = 0;
			}
		]]
	}
	
	MainCode ComputeShader_DoCulling
	{
		BufferTexture Mesh2MeshStateLodOffsetsBuffer
		{
			Ref = PdxBufferTexture0
			type = uint
		}
		
		RWBufferTexture Mesh2MeshStateLodInstanceCountRwBuffer
		{
			Ref = PdxRWBufferTexture0
			type = uint
		}
		
		RWBufferTexture Mesh2InstanceDataRwBuffer
		{
			Ref = PdxRWBufferTexture1
			type = uint
		}
		
		Texture DepthPyramid
		{
			Ref = PdxTexture0
			format = float
		}
		Sampler DepthPyramidSampler
		{
			MagFilter = "Point"
			MinFilter = "Point"
			MipFilter = "Point"
			SampleModeU = "Clamp"
			SampleModeV = "Clamp"
		}

		ConstantBuffer( PdxConstantBuffer0 )
		{
			uint2 _DepthPyramidSize;
			uint _DepthPyramidMaxMipLevel;
			uint _NumInstances;
			float3 _LodCameraPosition;
			float _LodScale;
			float _LodFadeRange;
			uint _LodFadeEnabled;
		};
		
		ConstantBuffer( PdxConstantBuffer1 )
		{
			float4 _FrustumPlanes[6];
		};
		
		Input = "CS_INPUT"
		NumThreads = { 128 1 1 }
		Code 
		[[
			void WriteInstance( SMeshInstanceData MeshInstanceData, uint LodIndex, float BlendValue )
			{
				uint MeshStateLodIndex = LoadMeshStateLodIndex( MeshInstanceData._MeshStateIndex, LodIndex );
				uint InstanceOffset = Mesh2MeshStateLodOffsetsBuffer[MeshStateLodIndex];
				
				uint IndexToWrite = 0;
				InterlockedAdd( Mesh2MeshStateLodInstanceCountRwBuffer[MeshStateLodIndex], 1, IndexToWrite ); // Increment "_InstanceCount", we also use the returned value as the position we should write into
				
				uint InstanceDataOffset = 2 * ( InstanceOffset + IndexToWrite );
				Mesh2InstanceDataRwBuffer[InstanceDataOffset] = MeshInstanceData._TransformIndex;
				Mesh2InstanceDataRwBuffer[InstanceDataOffset + 1] = asuint( BlendValue );
			}

			void WriteInstance( SMeshInstanceData MeshInstanceData, SLodResult LodResult )
			{
				if ( LodResult._BaseLod == SLodResult::NoLod )
				{
					return;
				}
				
				WriteInstance( MeshInstanceData, LodResult._BaseLod, LodResult._BlendValue );
				
				if ( LodResult._NextLod != SLodResult::NoLod )
				{
					WriteInstance( MeshInstanceData, LodResult._NextLod, -LodResult._BlendValue );
				}
			}

			PDX_MAIN
			{
				if ( Input.GlobalId.x < _NumInstances )
				{
					SMeshInstanceData MeshInstanceData = LoadMeshInstanceDataForIndex( Input.GlobalId.x );

					float4 BoundingSphere;
					CalculateTransformedBoundingSphere( MeshInstanceData, BoundingSphere );
					
				#ifdef PDX_MESH2_ENABLE_FRUSTUM_CULLING
					if ( !SphereIntersectsFrustum( BoundingSphere.xyz, BoundingSphere.w, _FrustumPlanes ) )
					{
						return;
					}
				#endif
					
				#ifdef PDX_MESH2_ENABLE_OCCLUSION_CULLING
					float4 DepthPyramidUvRect;
					float DepthPyramidLevel;
					float SphereDepth;
					if ( CalculateOcclusionSettings( BoundingSphere, ZNear, ViewMatrix, ProjectionMatrix, _DepthPyramidSize, _DepthPyramidMaxMipLevel, DepthPyramidUvRect, DepthPyramidLevel, SphereDepth ) )
					{
						float4 DepthPyramidDepths = float4(
							PdxSampleTex2DLod( DepthPyramid, DepthPyramidSampler, DepthPyramidUvRect.xy, DepthPyramidLevel ).x,
							PdxSampleTex2DLod( DepthPyramid, DepthPyramidSampler, DepthPyramidUvRect.zy, DepthPyramidLevel ).x,
							PdxSampleTex2DLod( DepthPyramid, DepthPyramidSampler, DepthPyramidUvRect.xw, DepthPyramidLevel ).x,
							PdxSampleTex2DLod( DepthPyramid, DepthPyramidSampler, DepthPyramidUvRect.zw, DepthPyramidLevel ).x
						);
						float DepthPyramidDepth = max( max( DepthPyramidDepths[0], DepthPyramidDepths[1] ), max( DepthPyramidDepths[2], DepthPyramidDepths[3] ) );			
						
						if ( SphereDepth > DepthPyramidDepth )
						{
							return;
						}
					}
				#endif
			
					// If we reach here we are visible
					SMeshStateData MeshStateData = LoadMeshStateData( MeshInstanceData._MeshStateIndex );
					
					SLodResult LodResult = CalculateLod( MeshStateData, MeshInstanceData, BoundingSphere, _LodCameraPosition, _LodScale, _LodFadeRange, _LodFadeEnabled );
					WriteInstance( MeshInstanceData, LodResult );
				}
			}
		]]
	}
}

Effect ClearInstanceCountBuffer
{
	ComputeShader = "ComputeShader_ClearInstanceCountBuffer"
}

Effect DoCulling
{
	ComputeShader = "ComputeShader_DoCulling"
}

Effect DrawCallUpdate
{
	ComputeShader = "ComputeShader_DrawCallUpdate"
}