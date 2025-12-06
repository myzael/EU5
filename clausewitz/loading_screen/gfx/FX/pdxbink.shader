Includes = {
	"cw/pdxgui.fxh"
}

VertexStruct VS_OUTPUT_BINK
{
    float4 Position : PDX_POSITION;
    float4 UV       : TEXCOORD0;
};

VertexShader =
{
    ConstantBuffer( PdxConstantBuffer0 )
    {
        float4 CoordMat;
        float4 CoordTrans;
        float4 ConstUV_X;
        float4 ConstUV_Y;
        float4 ConstUV_W;
    }
	
	VertexStruct VS_INPUT_BINK
	{
		int2 position	: POSITION;
	};

    MainCode VertexShaderBink
    {
		Input = "VS_INPUT_BINK"
		Output = "VS_OUTPUT_BINK"
		Code 
		[[
			PDX_MAIN
			{
                VS_OUTPUT_BINK o;
                o.Position = float4( Input.position, 0.0, 1.0 );
				float2 UV = Input.position.xy * 0.5 + 0.5;
				UV.y = 1.0 - UV.y;
                o.UV = ( UV.x * ConstUV_X ) + ( UV.y * ConstUV_Y ) + ConstUV_W;
                return o;
			}
		]]
    }
}



PixelShader =
{
    ConstantBuffer( PdxConstantBuffer1 )
    {
        float4 consta;
        float4 crc;
        float4 cbc;
        float4 adj;
        float4 yscale;
    }

    MainCode PixelShaderBink
    {
        TextureSampler YTexture
        {
            Ref = PdxTexture0
            MinFilter = "Point"
            MagFilter = "Point"
            MipFilter = "Point"
            SampleModeU = "Clamp"
            SampleModeV = "Clamp"
        }

        TextureSampler CRTexture
        {
            Ref = PdxTexture1
            MinFilter = "Point"
            MagFilter = "Point"
            MipFilter = "Point"
            SampleModeU = "Clamp"
            SampleModeV = "Clamp"
        }

        TextureSampler CBTexture
        {
            Ref = PdxTexture2
            MinFilter = "Point"
            MagFilter = "Point"
            MipFilter = "Point"
            SampleModeU = "Clamp"
            SampleModeV = "Clamp"
        }

        TextureSampler ATexture
        {
            Ref = PdxTexture3
            MinFilter = "Point"
            MagFilter = "Point"
            MipFilter = "Point"
            SampleModeU = "Clamp"
            SampleModeV = "Clamp"
        }

        Input = "VS_OUTPUT_BINK"
        Output = "PDX_COLOR"
        Code
        [[
            PDX_MAIN
            {
                float4 FinalColor;

				// Formula for YCrCb space to rgb and then to srgb copied from bink example shader code
				// from binktex_d3d11_shaders
                float y = PdxTex2D(YTexture,   Input.UV.xy).r;
                float cr = PdxTex2D(CRTexture, Input.UV.zw).r;
                float cb = PdxTex2D(CBTexture, Input.UV.zw).r;
				
                FinalColor = ( y * yscale ) + ( cr * crc ) + ( cb * cbc ) + adj;

				#ifdef ALPHA
                FinalColor.a = PdxTex2D(ATexture, Input.UV.xy).r;
                #endif

                FinalColor *= consta;

                #ifdef SRGB				
                FinalColor.xyz = FinalColor.xyz * ( FinalColor.xyz * ( ( FinalColor.xyz * 0.305306011 ) + 0.682171111 ) + 0.012522878 );				
				#endif
			
				FinalColor = FinalColor.SWIZZLE;
				
				#ifdef ALPHA_ONE
				FinalColor.a = 1.0f;
				#endif
				
				return FinalColor;
            }
        ]]
    }
}

BlendState BinkBlendState
{
	BlendEnable = yes
	SourceBlend = "src_alpha"
	DestBlend = "inv_src_alpha"    
}

DepthStencilState DepthStencilState
{
	DepthEnable = no
}

Effect PdxBinkYCrCb_NoAlpha_NoSRGB
{
	VertexShader = "VertexShaderBink"
	PixelShader = "PixelShaderBink"
    BlendState = BinkBlendState
}

Effect PdxBinkYCrCb_Alpha_NoSRGB
{
	VertexShader = "VertexShaderBink"
	PixelShader = "PixelShaderBink"
	
	Defines = 
	{ 
		"ALPHA"
	}
    BlendState = BinkBlendState
}

Effect PdxBinkYCrCb_NoAlpha_SRGB
{
	VertexShader = "VertexShaderBink"
	PixelShader = "PixelShaderBink"
	
	Defines = 
	{ 
		"SRGB"
	}
    BlendState = BinkBlendState
}

Effect PdxBinkYCrCb_Alpha_SRGB
{
	VertexShader = "VertexShaderBink"
	PixelShader = "PixelShaderBink"
	
	Defines = 
	{ 
		"ALPHA"
		"SRGB"
	}
    BlendState = BinkBlendState
}