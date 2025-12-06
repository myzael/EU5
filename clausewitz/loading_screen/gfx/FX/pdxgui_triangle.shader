Includes = {
	"cw/pdxgui_triangle.fxh"
}

PixelShader =
{
	MainCode PS_PdxGuiTriangleOnlyColor
	{
		Input = "VS_PDXGUI_TRIANGLE_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{				
				return Color;
			}
		]]
	}	
}


BlendState BlendState
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
}

DepthStencilState DepthStencilState
{
	DepthEnable = no
}

Effect PdxGuiTriangleOnlyColor
{
	VertexShader = "VS_PdxGuiTriangle"
	PixelShader = "PS_PdxGuiTriangleOnlyColor"
}