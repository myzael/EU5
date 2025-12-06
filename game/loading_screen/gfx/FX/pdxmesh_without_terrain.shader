Includes = {
	"pdxmesh_base.fxh"
}

Effect standard_alpha_blend
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
	BlendState = "alpha_blend"
	DepthStencilState = "depth_no_write"
}
Effect standard_alpha_blendShadow
{
	VertexShader = "VS_standard_shadow"
	PixelShader = "PixelPdxMeshAlphaBlendShadow"
	
	RasterizerState = ShadowRasterizerState
}
Effect standard_alpha_blend_two_sided
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
	BlendState = "alpha_blend"
	DepthStencilState = "depth_no_write"
	RasterizerState = RasterizerState_two_sided
}
Effect standard_alpha_blend_two_sidedShadow
{
	VertexShader = "VS_standard_shadow"
	PixelShader = "PixelPdxMeshAlphaBlendShadow"
	
	RasterizerState = ShadowRasterizerState_two_sided
}

Effect standard_alpha_to_coverage
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
	BlendState = "alpha_to_coverage"
}
Effect standard_alpha_to_coverage_two_sided
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
	BlendState = "alpha_to_coverage"
	RasterizerState = RasterizerState_two_sided	
}


Effect standard_added_alphas
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
	BlendState = "added_alphas"
}

Effect standard_animate_uv
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
	Defines = { "ANIMATE_UV" }
}
Effect standard_animate_uv_two_sided
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
	Defines = { "ANIMATE_UV" }
	RasterizerState = RasterizerState_two_sided	
}

Effect standard_animate_uv_alpha_blend
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
	BlendState = "alpha_blend"
	DepthStencilState = "depth_no_write"
	Defines = { "ANIMATE_UV" }
}
Effect standard_animate_uv_alpha_blend_two_sided
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
	BlendState = "alpha_blend"
	DepthStencilState = "depth_no_write"
	Defines = { "ANIMATE_UV" }
	RasterizerState = RasterizerState_two_sided	
}

Effect standard_animate_uv_alpha_additive
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
	BlendState = "alpha_additive"
	DepthStencilState = "depth_no_write"
	Defines = { "ANIMATE_UV" }
}
Effect standard_animate_uv_alpha_additive_two_sided
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
	BlendState = "alpha_additive"
	DepthStencilState = "depth_no_write"
	Defines = { "ANIMATE_UV" }
	RasterizerState = RasterizerState_two_sided	
}

Effect standard_no_terrain
{
	VertexShader = "VS_standard"
	PixelShader = "PS_standard"
}
Effect standard_no_terrainShadow
{
	VertexShader = "VS_standard_shadow"
	PixelShader = "PixelPdxMeshStandardShadow"	
	
	RasterizerState = ShadowRasterizerState
}

Effect standard_alpha_to_coverageShadow
{
	VertexShader = "VS_standard_shadow"
	PixelShader = "PixelPdxMeshAlphaBlendShadow"
	BlendState = "alpha_to_coverage"
}
Effect standard_alpha_to_coverage_two_sidedShadow
{
	VertexShader = "VS_standard_shadow"
	PixelShader = "PixelPdxMeshAlphaBlendShadow"
	BlendState = "alpha_to_coverage"
	RasterizerState = RasterizerState_two_sided	
}