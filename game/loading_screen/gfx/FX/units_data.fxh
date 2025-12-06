
TextureSampler CoaAtlas
{
	Ref = PdxMeshCustomTexture1
	MagFilter = "Linear"
	MinFilter = "Linear"
	MipFilter = "Linear"
	SampleModeU = "Clamp"
	SampleModeV = "Clamp"
}

ConstantBuffer(  UnitConstantBuffers0 )
{
	int CoaEmblemColorIndex;
	int SkinColorIndex;
	int EyeColorIndex;
	int HairColorIndex;
	int ScriptedColorOffset;
    float ShipRepaintOpacityUnitColorPrimary;
    float ShipRepaintOpacityUnitColorSecondary;
    float ShipRepaintOpacityUnitColorTerciary;
	
	float4 SelectionMarkerScaleValues;
	float4 SelectionMarkerOpacityValues;
	float4 SelectionSchwingColor;
	float4 SelectionSchwingOpacityValues;
	float2 SelectionSchwingTimestamps;
	float SelectionSchwingThickness;
	float SelectionSchwingHeight;

	float SelectionMarkerUvRotationSpeed; #radians per second
}

ConstantBuffer( UnitConstantBuffers1 )
{
	float4 CoaOffsetAndScale[32]; #Intentional overflow due to the same reason as the Data buffer for PdxMesh. Large arrays makes the hlsl compiler take a very long time but there does not seem to be any difference between Data[2] and Data[4096] in compiled code

}

ConstantBuffer( UnitViewerDebugBuffer )
{
	int EnableDebug;
	int MaterialSelection;
	int UseMaskColor;
	int EnableDebugMask;
	
	int DissableDiffuse;
	float DebugMaskTolerance;
	float DebugMaskHardness;
	float DebugMaskOutput;

	float3 DebugMaskColor;
}

BufferTexture MaterialDataSubindex
{
	Ref = UnitMaterialData0
	type = float4 
}

BufferTexture RepaintDataSubindex
{
	Ref = UnitMaterialData1
	type = float4
}


Code [[
	struct SUnitUserData
	{
		int _CountryIndex;
		int _MaterialDataBegin;
		int _MaterialDataEnd;
		float _Selection;

		float2 _SkinColorUV;
		float2 _EyeColorUV;
		float2 _HairColorUV;
	};

	// Enum values from CUnitGfxMaterial::EBlendMode
	static const int BlendModeMultiply = 0;
	static const int BlendModeOverlay = 1;

	struct SUnitMaterialData
	{
		float3	_MaterialMaskColor;
		float	_MaterialMaskTolerance;
		float	_MaterialMaskHardness;
		float	_MaterialMaskOutput;
		
		int	_DiffuseIndex;
		int	_NormalIndex;
		int	_PropertyIndex;
		int	_RepaintMaskIndex;

		int _BlendMode;

		int _RepaintBegin;
		int _RepaintCount;
	};

	struct SMaterialRepaintData
	{	
		float3	_MaskColor;
		float	_MaskTolerance;
		float	_MaskHardness;
		float	_MaskOutput;

		int _ColorIndex;
	};

	SUnitUserData GetUnitUserData( uint InstanceIndex )
	{
		SUnitUserData Ret;
		#if defined(ENABLE_UNIT_SHADER)
			float4 Raw0 = Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 0 ];
			float4 Raw1 = Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 1 ];
			float4 Raw2 = Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 2 ];


			Ret._CountryIndex = int( Raw0.x );
			Ret._MaterialDataBegin = int( Raw0.y );
			Ret._MaterialDataEnd = int( Raw0.z );
			Ret._Selection = Raw0.w;
			Ret._SkinColorUV = Raw1.xy;
			Ret._EyeColorUV = Raw1.zw;
			Ret._HairColorUV = Raw2.xy;
		#endif
		return Ret;
	};

	SUnitMaterialData GetMaterialData( uint Index )
	{
		SUnitMaterialData Ret;
		#if defined(ENABLE_UNIT_SHADER)
			const uint NUM_FLOAT4_PER_MATERIAL = 4;
			
			float4 Raw0 = PdxReadBuffer4( MaterialDataSubindex, Index * NUM_FLOAT4_PER_MATERIAL + 0 );
			float4 Raw1 = PdxReadBuffer4( MaterialDataSubindex, Index * NUM_FLOAT4_PER_MATERIAL + 1 );
			float4 Raw2 = PdxReadBuffer4( MaterialDataSubindex, Index * NUM_FLOAT4_PER_MATERIAL + 2 );
			float4 Raw3 = PdxReadBuffer4( MaterialDataSubindex, Index * NUM_FLOAT4_PER_MATERIAL + 3 );


			Ret._MaterialMaskColor		= Raw0.xyz;
			Ret._MaterialMaskTolerance	= Raw0.w;
			Ret._MaterialMaskHardness	= Raw1.x;
			Ret._MaterialMaskOutput		= Raw1.y;
			
			Ret._DiffuseIndex		= int( Raw1.z );
			Ret._NormalIndex		= int( Raw1.w );
			Ret._PropertyIndex		= int( Raw2.x );
			Ret._RepaintMaskIndex	= int( Raw2.y );
			Ret._BlendMode			= int( Raw2.z );

			Ret._RepaintBegin		= int( Raw2.w );
			Ret._RepaintCount			= int( Raw3.x );
		#endif
		return Ret;
	};

	SMaterialRepaintData GetRepaintData( uint Index )
	{
				SMaterialRepaintData Ret;
		#if defined(ENABLE_UNIT_SHADER)
			const uint NUM_FLOAT4_PER_REPAINT = 2;

			float4 Raw0 = PdxReadBuffer4( RepaintDataSubindex, Index * NUM_FLOAT4_PER_REPAINT + 0 );
			float4 Raw1 = PdxReadBuffer4( RepaintDataSubindex, Index * NUM_FLOAT4_PER_REPAINT + 1 );
			

			Ret._MaskColor.rgb	= Raw0.xyz;
			Ret._MaskTolerance	= Raw0.w;
			Ret._MaskHardness	= Raw1.x;
			Ret._MaskOutput		= Raw1.y;
			Ret._ColorIndex		= int( Raw1.z );
			//unused Raw1.w
		#endif
		return Ret;


	
	};

	int GetUnitCountryIndex( uint InstanceIndex)
	{
		float4 Raw0 = Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 0 ];
		return  int( Raw0.x );
	};
]]

PixelShader =
{

	TextureSampler CountryColorMatrix
	{
		Ref = UnitGfxColors
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}

    Code
    [[
        float3 SampleCountryColor( in int CountryIndex, in int ColorIndex)
        {
			#ifdef  ENABLE_UNIT_SHADER
            	float4 Color = PdxTex2DLoad0(CountryColorMatrix, int2(ColorIndex, CountryIndex));		
			#else
				float4 Color = vec4(0.0);
			#endif
			return ToLinear( Color.rgb );
        }

		float3 SampleCountryColor( in SUnitUserData UserData, in int ColorIndex)
		{
            return SampleCountryColor(UserData._CountryIndex, ColorIndex);
		}
    ]]
}