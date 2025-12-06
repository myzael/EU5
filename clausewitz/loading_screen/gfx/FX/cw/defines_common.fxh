#define UINT8_MAX 0xff
#define UINT16_MAX 0xffff
#define UINT32_MAX 0xffffffff
#define PI 3.14159265359

float2x2 Create2x2( float a, float b, float c, float d ) { return Create2x2( float2( a, b ), float2( c, d ) ); }

#define PdxSampleTex2DLod0(tex,samp,uv) PdxSampleTex2DLod( (tex), (samp), (uv), 0 )

#define PdxTexture2DLoad0(tex,uv) PdxTexture2DLoad( (tex), (uv), 0 )

#define PdxTexture2DArrayLoad0(tex,uv,arrayindex) PdxTexture2DArrayLoad( (tex), (uv), (arrayindex), 0)

#define PdxTex2DProj(samp,uv_proj) PdxTex2DLod0( (samp), (uv_proj).xy / (uv_proj).w )
#define PdxTex2DLod0(samp,uv) PdxTex2DLod( (samp), (uv), 0 )
#define PdxTex2DLod0Offset(samp,uv,offset) PdxTex2DLodOffset( (samp), (uv), 0, (offset) )
#define PdxTex2DLoad0(samp,uv) PdxTex2DLoad( (samp), (uv), 0 )

#define PdxTex3DLod0(samp,uv) PdxTex3DLod( (samp), (uv), 0 )
#define PdxTex3DLoad0(samp,uv) PdxTex3DLoad( (samp), (uv), 0 )

#ifdef PDX_USE_MIPLEVELTOOL
#define PdxTex2DLod0MipTool(samp,uv) PdxTex2DLodMipTool( (samp), (uv), 0 )
#define PdxTex2DLoad0MipTool(samp,uv) PdxTex2DLoadMipTool( (samp), (uv), 0 )
#endif // PDX_USE_MIPLEVELTOOL

float4 FixProjectionAndMul( float4x4 ProjectionMatrix, float4 Vector )
{
	return mul( FixProjection( ProjectionMatrix ), Vector );
}
