Includes = {
	"cw/pdxgui.fxh"
}

VertexStruct VS_PDXGUI_TRIANGLE_INPUT
{
    float2 Position			: POSITION;
    float4 Color			: COLOR;
	float2 UV				: TEXCOORD0;
	
};

VertexStruct VS_PDXGUI_TRIANGLE_OUTPUT
{
	float4 Position			: PDX_POSITION;	
	float4 Color            : COLOR
	float2 UV               : TEXCOORD0
};

ConstantBuffer( PdxConstantBuffer0 )
{
	float4		Color;	
	float2		ScreenPosition;
	float		Scale;	
};

VertexShader =
{
	Code
	[[
		VS_PDXGUI_TRIANGLE_OUTPUT PdxGuiTriangleVertexShader( VS_PDXGUI_TRIANGLE_INPUT Input )
		{
			VS_PDXGUI_TRIANGLE_OUTPUT Out;		
			
			float2 PixelPos = ScreenPosition + Input.Position * Scale;
			
			Out.Color = Input.Color;
			Out.Position = PixelToScreenSpace( PixelPos );					
			Out.UV = Input.UV;
			
			return Out;
		}
	]]
	
	MainCode VS_PdxGuiTriangle
	{
		Input = "VS_PDXGUI_TRIANGLE_INPUT"
		Output = "VS_PDXGUI_TRIANGLE_OUTPUT"
		Code
		[[
			PDX_MAIN
			{
				return PdxGuiTriangleVertexShader( Input );
			}
		]]
	}
}
