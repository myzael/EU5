Includes = {
	"cw/pdxgui.fxh"
}

VertexStruct VS_PDXGUI_LINE_INPUT
{
    float2 LocalPosition	: POSITION;
    float2 Normal			: NORMAL;
	float2 UV				: TEXCOORD0;
	float Size				: TEXCOORD1;
	uint VertexID			: PDX_VertexID;
};

VertexStruct VS_PDXGUI_LINE_OUTPUT
{
	float4 Position	: PDX_POSITION;
	float2 UV0To1			: TEXCOORD0;
	float2 UV				: TEXCOORD1;
	float2 MaskUV			: TEXCOORD2;
	float2 WidgetLocalPos 	: TEXCOORD3;
};

ConstantBuffer( PdxConstantBuffer0 )
{
	float4		Color;
	float2		UVScale;
	float2		UVAnimationSpeed;
	float2		MaskUVScale;
	float2		ScreenPosition;
	float		Scale;
	float		LineLength;
	float		HalfWidth;
	float       FeatherDistance;
};

VertexShader =
{
	Code
	[[
		VS_PDXGUI_LINE_OUTPUT PdxGuiLineVertexShader( VS_PDXGUI_LINE_INPUT Input )
		{
			VS_PDXGUI_LINE_OUTPUT Out;
			
			float2 OffsetDir = Input.Normal * (((Input.VertexID % 2) == 0) ? 1.0 : -1.0);

			Out.WidgetLocalPos = Input.LocalPosition + OffsetDir * HalfWidth * Input.Size;
			float2 PixelLocalPos = ScreenPosition + Out.WidgetLocalPos * Scale;
			
			Out.Position = PixelToScreenSpace( PixelLocalPos );
			Out.UV0To1 = Input.UV;
			
			float2 UV = Input.UV;
			UV.x *= LineLength;
			
			Out.UV = UV * UVScale;
			Out.UV -= UVAnimationSpeed * GuiTime;
			
			Out.MaskUV = UV * MaskUVScale;
			
			return Out;
		}
	]]
	
	MainCode VS_PdxGuiLine
	{
		Input = "VS_PDXGUI_LINE_INPUT"
		Output = "VS_PDXGUI_LINE_OUTPUT"
		Code
		[[
			PDX_MAIN
			{
				return PdxGuiLineVertexShader( Input );
			}
		]]
	}
}

PixelShader
{
	Code
	[[
		float CalcAlpha( VS_PDXGUI_LINE_OUTPUT Input, float FeatherDistance )
		{
			float DistanceFromEdge = (1.0 - abs( 0.5 - Input.UV0To1.y ) * 2.0) * HalfWidth;
			return saturate( DistanceFromEdge / FeatherDistance );
		}

		float4 SampleMask( float2 MaskUV, in PdxTextureSampler2D Texture )
		{			
			float2 DDX = ddx( MaskUV );
			float2 DDY = ddy( MaskUV );
			
			// This part tiles the texture from U 0.25 -> 0.75
			float MaxU = MaskUVScale.x * LineLength;
			if ( MaxU < 1.0 ) // If we are smaller than 1 tile, sample from the tip of the texture
			{
				MaskUV.x += 1.0 - MaxU;
			}
			else if ( MaskUV.x > (MaxU - 0.25) ) // Should we sample the "tip" of the texture
			{
				MaskUV.x -= MaxU - 1.0;
			}
			else if ( MaskUV.x > 0.25 ) // In the middle we repeat the texture
			{
				MaskUV.x = mod( MaskUV.x - 0.25, 0.5 ) + 0.25;
			}
		
			return PdxTex2DGrad( Texture, MaskUV, DDX, DDY );
		}
	]]
}