
VertexStruct VS_INPUT
{
    float3 vPosition  : POSITION;
@ifdef DEBUG_DRAW_TEXTURED
	float2 UV0        : TEXCOORD0;
@endif
};

VertexStruct VS_OUTPUT
{
    float4 vPosition  : PDX_POSITION;
 	float4 vColor     : TEXCOORD1;
@ifdef DEBUG_DRAW_TEXTURED
	float2 UV0        : TEXCOORD0;
@endif
};


ConstantBuffer( PdxConstantBuffer0 )
{
	float4x4 Transform;
	float4 Color;
};


VertexShader =
{
	MainCode VertexShader
	{
		Input = "VS_INPUT"
		Output = "VS_OUTPUT"
		Code	
		[[
			PDX_MAIN
			{
			    VS_OUTPUT Out;
				
				float3 Position = Input.vPosition.xyz;
				
			    Out.vPosition = FixProjectionAndMul( Transform, float4( Position, 1.0 ) );	
				Out.vColor = Color;
				#ifdef DEBUG_DRAW_TEXTURED
					Out.UV0 = Input.UV0;
				#endif
			    return Out;
			}
		]]
	}
	
}

PixelShader =
{
	TextureSampler DiffuseMap
	{
		Ref = DebugDrawShapeDiffuse
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}

	MainCode PixelShader
	{	
		Input = "VS_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
			  	float4 OutColor = Input.vColor;
				#ifdef DEBUG_DRAW_TEXTURED
					OutColor *= PdxTex2D( DiffuseMap, Input.UV0 );
			    #endif
				return OutColor;
			}
		]]
	}
}

RasterizerState rasterizer_no_culling
{
	CullMode = "none"
}

BlendState DebugDrawTexturedBlendState
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "inv_src_alpha"
	WriteMask = "RED|GREEN|BLUE|ALPHA"
}

Effect DebugDraw
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	RasterizerState = "rasterizer_no_culling"
}

Effect DebugDrawTextured
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	RasterizerState = "rasterizer_no_culling"
	BlendState = "DebugDrawTexturedBlendState"
	Defines = { "DEBUG_DRAW_TEXTURED" }
}

