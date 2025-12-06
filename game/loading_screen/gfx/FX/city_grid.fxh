Includes = {

}

VertexShader = {
	Code [[		
#ifdef CITY_GRID_SQUISH
		void ApplyCitySquish( inout float3 OutPosition, in float3 Position, int ObjectInstanceIndex )
		{
			float4 UserDataRaw0 = Data[ObjectInstanceIndex + PDXMESH_USER_DATA_OFFSET + 0];
			SCityGfxConstants CityGfxConstants;
			CityGfxConstants._CountryOwner = UserDataRaw0.x;
			CityGfxConstants._SquishToCell_Scale = UserDataRaw0.y;
			if( CityGfxConstants._SquishToCell_Scale > 0.0f )
			{
				float4 UserDataRaw1 = Data[ObjectInstanceIndex + PDXMESH_USER_DATA_OFFSET + 1];
				float4 UserDataRaw2 = Data[ObjectInstanceIndex + PDXMESH_USER_DATA_OFFSET + 2];
				CityGfxConstants._CellCorner0 = UserDataRaw1.xy;
				CityGfxConstants._CellCorner1 = UserDataRaw1.zw;
				CityGfxConstants._CellCorner2 = UserDataRaw2.xy;
				CityGfxConstants._CellCorner3 = UserDataRaw2.zw;
				float2 BR = CityGfxConstants._CellCorner0;
				float2 BL = CityGfxConstants._CellCorner1;
				float2 TL = CityGfxConstants._CellCorner2;
				float2 TR = CityGfxConstants._CellCorner3;
				float2 X1 = lerp( BL, BR, Position.x * ( 0.5f ) + 0.5f );
				float2 X2 = lerp( TL, TR, Position.x * ( 0.5f ) + 0.5f );
				float2 Y1 = lerp( X1, X2, Position.z * ( 0.5f ) + 0.5f );
				OutPosition.xz = Y1;
//TODO: Apply scaling on Y		
//TODO: what do we do with animated meshes?
			}
		}
#endif
	]]
}