Includes = {
	"cw/pdxgui.fxh"
	"cw/pdxgui_sprite.fxh"
}

ConstantBuffer( PdxConstantBuffer2 )
{
	float3 HighlightColor;
};

VertexShader =
{
	MainCode VertexShader
	{
		Input = "VS_INPUT_PDX_GUI"
		Output = "VS_OUTPUT_PDX_GUI"
		Code
		[[
			PDX_MAIN
			{
				return PdxGuiDefaultVertexShader( Input );
			}
		]]
	}
}

PixelShader =
{
	Code
	[[
		float3 HandleDisable( float3 Color  )
		{
			#ifdef DISABLED
				return DisableColor( Color );
			#else
				return Color;
			#endif
		}
	]]
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
