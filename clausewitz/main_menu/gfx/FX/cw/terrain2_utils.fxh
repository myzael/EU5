VertexStruct STerrain2VertexInput
{
	uint4 NodeOffset_Scale_Lerp			: TEXCOORD0;
	uint2 PhysicalPageDataIndex_LodDiff	: TEXCOORD1;
	uint VertexID 						: PDX_VertexID;
};

VertexStruct STerrain2VertexOutput
{
	float4 Position 			: PDX_POSITION;
	float3 WorldSpacePosition	: TEXCOORD0;
	float4 ShadowProj			: TEXCOORD1;
};

Code
[[
	struct STerrain2NodeData
	{
		float2 _Offset;
		float _Scale;
		float _LodLerpFactor;
		uint _PhysicalPageDataIndex;
		uint _LodDiff;
	};

	// See NTerrain2::PackInstanceData()
	STerrain2NodeData Terrain2_UnpackNodeData( uint4 NodeOffset_Scale_Lerp, uint2 PhysicalPageDataIndex_LodDiff )
	{
		STerrain2NodeData Out;

		Out._Scale = 1.0 / NodeOffset_Scale_Lerp.z;
		Out._Offset = NodeOffset_Scale_Lerp.xy * Out._Scale;
		Out._LodLerpFactor = float( NodeOffset_Scale_Lerp.w ) / UINT16_MAX;
		Out._PhysicalPageDataIndex = PhysicalPageDataIndex_LodDiff.x;
		Out._LodDiff = PhysicalPageDataIndex_LodDiff.y;

		return Out;
	}

	STerrain2NodeData Terrain2_UnpackNodeDataFromVertex( STerrain2VertexInput Input )
	{
		return Terrain2_UnpackNodeData( Input.NodeOffset_Scale_Lerp, Input.PhysicalPageDataIndex_LodDiff );
	}

	float2 Terrain2_CalcGridPosition01( uint VertexID, STerrain2NodeData NodeData )
	{
		// GridPosition is 0 -> 1 within the grid
		uint2 GridPositionUint = uint2( mod( VertexID, _GridSize ), VertexID / _GridSize );

		float2 GridPositionToUse = GridPositionUint;

		// This part makes sure edges matches when lod differs and also does the "lod lerp" when changing between lods
		uint NextLevelLodDiff = 2; // Lod lerping always lerps to next level lod, i.e. LodDiff = 2

		// This unpacking logic needs to match the logic on the c++ side (NTerrain2::PackBorderLodDiff)
		// For the borders we make sure the vertices matches neighboring nodes
		if ( GridPositionUint.y == 0 )
		{
			uint LodDiff = 1u << ( NodeData._LodDiff & 0x000F );
			GridPositionToUse.x = mod( ( VertexID / LodDiff ), _GridSize ) * LodDiff;
		}
		else if ( GridPositionUint.y == ( _GridSize - 1 ) )
		{
			uint LodDiff = 1u << ( ( NodeData._LodDiff & 0x00F0 ) >> 4u );
			GridPositionToUse.x = mod( ( VertexID / LodDiff ), _GridSize ) * LodDiff;
		}
		else // In the "center" we lerp to next level lod depending on _LodLerpFactor
		{
			// Calculate vertex gridposition for next level lod
			uint ModVertexID = mod( VertexID, _GridSize );
			uint NextLevelVertexID = ModVertexID / NextLevelLodDiff;
			NextLevelVertexID += mod( ModVertexID, 2 ) * mod( NextLevelVertexID, 2 );
			uint NextLevelGridPosition = mod( NextLevelVertexID, _GridSize ) * NextLevelLodDiff;

			// Lerp between current lod and next level lod position depending on _LodLerpFactor
			GridPositionToUse.x = lerp( GridPositionUint.x, NextLevelGridPosition, NodeData._LodLerpFactor );
		}

		if ( GridPositionUint.x == 0 )
		{
			uint LodDiff = 1u << ( ( NodeData._LodDiff & 0x0F00 ) >> 8u );
			GridPositionToUse.y = ( ( VertexID / LodDiff ) / _GridSize ) * LodDiff;
		}
		else if ( GridPositionUint.x == ( _GridSize - 1 ) )
		{
			uint LodDiff = 1u << ( ( NodeData._LodDiff & 0xF000 ) >> 12u );
			GridPositionToUse.y = ( ( VertexID / LodDiff ) / _GridSize ) * LodDiff;
		}
		else
		{
			uint NextLevelVertexID = VertexID / NextLevelLodDiff;
			NextLevelVertexID += mod( VertexID / _GridSize, 2 ) * mod( NextLevelVertexID / _GridSize, 2 ) * _GridSize;
			uint NextLevelGridPosition = ( NextLevelVertexID / _GridSize ) * NextLevelLodDiff;

			GridPositionToUse.y = lerp( GridPositionUint.y, NextLevelGridPosition, NodeData._LodLerpFactor );
		}

		return GridPositionToUse * _InvGridSizeMinusOne;
	}
]]
