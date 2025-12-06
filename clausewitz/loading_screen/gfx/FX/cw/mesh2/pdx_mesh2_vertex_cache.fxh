Includes = {
	"cw/mesh2/pdx_mesh2_utils.fxh"
}

BufferTexture Mesh2CachedVertexDataBuffer
{
	Ref = PdxMesh2CachedVertexDataBuffer
	type = uint
}

Code
[[
#ifdef PDX_MESH2_VERTEX_CACHE

	void PdxMesh2VertexInputFromVertexCache( uint VertexID, uint CachedVertexDataOffset, uint NumVertices, out float3 Position, out float3 Normal, out float3 Tangent )
	{
		uint PositionOffset = CachedVertexDataOffset + VertexID * 3;
		Position = Read3Float( Mesh2CachedVertexDataBuffer, PositionOffset );
		
		uint NormalOffset = PositionOffset + NumVertices * 3; // jump over position data
		Normal = Read3Float( Mesh2CachedVertexDataBuffer, NormalOffset );
		
		uint TangentOffset = NormalOffset + NumVertices * 3; // Jump over normal data
		Tangent = Read3Float( Mesh2CachedVertexDataBuffer, TangentOffset );
	}

#endif
]]

ComputeShader =
{
	RwBufferTexture Mesh2CachedVertexDataRwBuffer
	{
		Ref = PdxMesh2CachedVertexDataRwBuffer
		type = uint
	}

	Code
	[[
	#ifdef PDX_MESH2_VERTEX_CACHE
	
		void PdxMesh2WriteVertexCache( uint VertexID, uint CachedVertexDataOffset, uint NumVertices, float3 Position, float3 Normal, float3 Tangent )
		{
			uint PositionOffset = CachedVertexDataOffset + VertexID * 3;
			Mesh2CachedVertexDataRwBuffer[ PositionOffset ] = asuint( Position[0] );
			Mesh2CachedVertexDataRwBuffer[ PositionOffset + 1 ] = asuint( Position[1] );
			Mesh2CachedVertexDataRwBuffer[ PositionOffset + 2 ] = asuint( Position[2] );
			
			uint NormalOffset = PositionOffset + NumVertices * 3; // jump over position data
			Mesh2CachedVertexDataRwBuffer[ NormalOffset ] = asuint( Normal[0] );
			Mesh2CachedVertexDataRwBuffer[ NormalOffset + 1 ] = asuint( Normal[1] );
			Mesh2CachedVertexDataRwBuffer[ NormalOffset + 2 ] = asuint( Normal[2] );
			
			uint TangentOffset = NormalOffset + NumVertices * 3; // Jump over normal data
			Mesh2CachedVertexDataRwBuffer[ TangentOffset ] = asuint( Tangent[0] );
			Mesh2CachedVertexDataRwBuffer[ TangentOffset + 1 ] = asuint( Tangent[1] );
			Mesh2CachedVertexDataRwBuffer[ TangentOffset + 2 ] = asuint( Tangent[2] );
		}
	
	#endif
	]]
}
