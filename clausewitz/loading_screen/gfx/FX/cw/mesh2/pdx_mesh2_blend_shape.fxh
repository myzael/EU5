Includes = {
	"cw/mesh2/pdx_mesh2_geometry.fxh"
}

BufferTexture Mesh2BlendShapeDataBuffer
{
	Ref = PdxMesh2BlendShapeDataBuffer
	type = uint
}

Code
[[
#ifdef PDX_MESH2_BLENDSHAPES

	#ifndef USE_IB
		#error Blend shaped meshes currently does not support non index buffer mode
	#endif

	void PdxMesh2ApplyBlendShapes( STypeData TypeData, uint VertexID, uint BlendShapeDataOffset, inout float3 Position, inout float3 Normal, inout float3 Tangent )
	{
		uint MaxNumBlendShapes = Mesh2GeometryDataBuffer[TypeData._BlendShapeTypeDataOffset]; // Only really used for error checking
		uint NumBlendShapes = Mesh2BlendShapeDataBuffer[ BlendShapeDataOffset ];

		float3 BasePosition = Position;
		float3 BaseNormal = Normal;
		float3 BaseTangent = Tangent;
		
		uint BlendShapeTypeDataBaseOffset = TypeData._BlendShapeTypeDataOffset + 1;
		uint CurrentBlendShapeDataOffset = BlendShapeDataOffset + 1;
		for ( uint i = 0; i < NumBlendShapes; ++i )
		{
			uint BlendShapeIndex = Mesh2BlendShapeDataBuffer[ CurrentBlendShapeDataOffset++ ];
			float Weight = asfloat( Mesh2BlendShapeDataBuffer[ CurrentBlendShapeDataOffset++ ] );
			
			ASSERT_FORMAT( BlendShapeIndex < MaxNumBlendShapes, "Blend shape index out of range, %d vs %d", BlendShapeIndex, MaxNumBlendShapes );
			uint BlendShapeTypeOffset = Mesh2GeometryDataBuffer[BlendShapeTypeDataBaseOffset + BlendShapeIndex];
			
			// Might want to make blend shape types its own thing since now there is an entanglement of defines between base mesh data and blend shape mesh data
			// (also some data is not needed for blend shapes)
			STypeData BlendShapeTypeData = LoadTypeData( BlendShapeTypeOffset );
			float3 BlendShapePosition = GetPositionForType( BlendShapeTypeData, VertexID );
			float3 BlendShapeNormal;
			float3 BlendShapeTangent;
			float BlendShapeBitangentDir; // This is not used, we use the one from base mesh
			GetNormalAndTangentForType( BlendShapeTypeData, VertexID, BlendShapeNormal, BlendShapeTangent, BlendShapeBitangentDir );

			Position += ( BlendShapePosition - BasePosition ) * Weight;
			Normal += ( BlendShapeNormal - BaseNormal ) * Weight;
			Tangent += ( BlendShapeTangent - BaseTangent ) * Weight;
		}
		
		Normal = normalize( Normal );
		Tangent = normalize( Tangent );
	}
#endif
]]
