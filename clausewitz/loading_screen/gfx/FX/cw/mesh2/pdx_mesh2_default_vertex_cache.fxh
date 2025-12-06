Includes = {
	"cw/mesh2/pdx_mesh2.fxh"
}

ComputeShader =
{
	VertexStruct CS_INPUT_PDXMESH2
	{
		uint3 DispatchThreadID : PDX_DispatchThreadID
	};

	Code 
	[[
	#ifdef PDX_MESH2_VERTEX_CACHE

		void PdxMesh2DefaultVertexCacheWriter( uint InstanceID, uint VertexID )
		{				
			STypeData TypeData = LoadTypeData( _GeometryTypeDataOffset );
			PDXMESH2_VERTEX_INPUT VertexInput = PdxMesh2VertexInputFromGeometryBuffer( TypeData, VertexID );
			
			uint InstanceDataIndex = _InstanceDataOffset + InstanceID * _InstanceDataStride;
		
			PDXMESH2_INSTANCE_INPUT InstanceInput;
			PdxMesh2ReadOptionalInstanceInput( InstanceDataIndex, InstanceInput );
		
		#ifdef PDX_MESH2_BLENDSHAPES
			// Apply blendshapes to data in VertexInput
			PdxMesh2ApplyBlendShapes( TypeData, VertexID, InstanceInput._BlendShapeDataOffset, VertexInput._Position, VertexInput._Normal, VertexInput._Tangent );
		#endif
		
			PdxMesh2WriteVertexCache( VertexID, InstanceInput._CachedVertexDataOffset + _VertexCacheOffset, _VertexCacheNumVertices, VertexInput._Position, VertexInput._Normal, VertexInput._Tangent );
		}
		
	#endif
	]]

	MainCode CS_PdxMesh2DefaultVertexCache
	{
		Input = "CS_INPUT_PDXMESH2"
		NumThreads = { PDX_MESH2_VERTEX_CACHE_NUM_THREADS 1 1 }
		Code 
		[[
			PDX_MAIN
			{
			#ifdef PDX_MESH2_VERTEX_CACHE
				uint InstanceID = min( Input.DispatchThreadID.x / _VertexCacheNumVertices, _VertexCacheNumInstances - 1 );
				uint VertexID = Input.DispatchThreadID.x % _VertexCacheNumVertices;

				PdxMesh2DefaultVertexCacheWriter( InstanceID, VertexID );
			#endif
			}
		]]
	}
}
