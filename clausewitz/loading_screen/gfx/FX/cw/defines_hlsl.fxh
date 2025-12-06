#ifndef PDX_DIRECTX_11
#define printf( ... )
#define SetPrintfEnabled( ... )
#define ASSERT_FORMAT( ... )
#define ASSERT_FAIL( ... )
#define SetAssertEnabled( ... )
#endif

#define PDX_POSITION SV_Position
#define PDX_COLOR SV_Target
#define PDX_COLOR0 SV_Target0
#define PDX_COLOR0_SRC1 SV_Target1 // Use this when doing dual source blending, currently only supports that for render target #0
#define PDX_COLOR1 SV_Target1
#define PDX_COLOR2 SV_Target2
#define PDX_COLOR3 SV_Target3
#define PDX_COLOR4 SV_Target4
#define PDX_COLOR5 SV_Target5
#define PDX_COLOR6 SV_Target6
#define PDX_COLOR7 SV_Target7
#define PDX_VertexID SV_VertexID
#define PDX_InstanceID SV_InstanceID
#define PDX_DispatchThreadID SV_DispatchThreadID
#define PDX_GroupThreadID SV_GroupThreadID
#define PDX_GroupID SV_GroupID
#define PDX_GroupIndex SV_GroupIndex
#define PDX_TessFactor SV_TessFactor
#define PDX_InsideTessFactor SV_InsideTessFactor
#define PDX_OutputControlPointID SV_OutputControlPointID
#define PDX_DomainLocation SV_DomainLocation
#define PDX_RenderTargetArrayIndex SV_RenderTargetArrayIndex
#define PDX_ViewportArrayIndex SV_ViewportArrayIndex
#define PDX_Depth SV_Depth

#define PdxDomainTypeTriangle "tri"
#define PdxDomainTypeQuad "quad"
#define PdxDomainTypeIsoline "isoline"

#define PdxPartitioningModeInteger "integer"
#define PdxPartitioningModeFractionalEven "fractional_even"
#define PdxPartitioningModeFractionalOdd "fractional_odd"

#define PdxPrimitiveTypePoint point
#define PdxPrimitiveTypeLine line
#define PdxPrimitiveTypeTriangle triangle
#define PdxPrimitiveTypeLineAdjacency lineadj
#define PdxPrimitiveTypeTriangleAdjacency triangleadj

#define PdxTessellatorOutputTopologyPoint "point"
#define PdxTessellatorOutputTopologyLine "line"
#define PdxTessellatorOutputTopologyTriangleCw "triangle_cw"
#define PdxTessellatorOutputTopologyTriangleCcw "triangle_ccw"

#define PdxMeshShaderOutputTopologyLine "line"
#define PdxMeshShaderOutputTopologyTriangle "triangle"

#define mod( X, Y ) ( (X) % (Y) )

float2x2 Create2x2( in float2 x, in float2 y )
{
	return transpose( float2x2( x, y ) );
}
// TODO, Create3x3 should be transposed in hlsl, and not in glsl, and then the mul() arguments should be reversed
#define Create3x3 float3x3
float4x4 Create4x4( in float4 x, in float4 y, in float4 z, in float4 w )
{
	return transpose( float4x4( x, y, z, w ) );
}

#define GetMatrixData( Matrix, row, col ) ( Matrix [ row ] [ col ] )

float3x3 CastTo3x3( in float4x4 M )
{
	return (float3x3)M;
}

#define lessThan( a, b ) ( (a) < (b) )

float2 vec2(float vValue) { return float2(vValue, vValue); }
float3 vec3(float vValue) { return float3(vValue, vValue, vValue); }
float4 vec4(float vValue) { return float4(vValue, vValue, vValue, vValue); }


struct PdxTextureSampler2D
{
    Texture2D 		_Texture;
    SamplerState 	_Sampler;
};
struct PdxTextureSampler2DMS
{
    Texture2DMS<float4>		_Texture;
};

struct PdxTextureSampler2DArray
{
    Texture2DArray	_Texture;
    SamplerState 	_Sampler;
};

struct PdxTextureSampler3D
{
    Texture3D 		_Texture;
    SamplerState 	_Sampler;
};

struct PdxTextureSamplerCube
{
    TextureCube 	_Texture;
    SamplerState 	_Sampler;
};

struct PdxTextureSampler2DCmp
{
    Texture2D 				_Texture;
    SamplerComparisonState 	_Sampler;
};

// These are for separate Texture/Sampler objects
#define PdxSampleTex2D(tex,samp,uv) (tex).Sample( (samp), (uv) )
#define PdxSampleTex2DBias(tex,samp,uv,bias) (tex).SampleBias( (samp), (uv), (bias) )
#define PdxSampleTex2DLod(tex,samp,uv,lod) (tex).SampleLevel( (samp), (uv), (lod) )
#define PdxSampleTex2DGrad(tex,samp,uv,ddx,ddy) (tex).SampleGrad( (samp), (uv), (ddx), (ddy) )
#define PdxSampleTex2DGather(tex,samp,uv) (tex).Gather( (samp), (uv) )

#define PdxSampleTex3D(tex,samp,uv) (tex).Sample( (samp), (uv) )
#define PdxSampleTex3DLod(tex,samp,uv,lod) (tex).SampleLevel( (samp), (uv), (lod) )

#define PdxTexture2DSize(tex,size) (tex).GetDimensions( (size).x, (size).y )
#define PdxTexture2DLoad(tex,uv,lod) (tex).Load( int3((uv), (lod)) )

#define PdxTexture2DArraySize(tex,size,elements) (tex).GetDimensions( (size).x, (size).y, elements )
#define PdxTexture2DArrayLoad(tex,uv,arrayindex,lod) (tex).Load( int4((uv), (arrayindex), (lod)) )

#define PdxTexture3DSize(tex,size) (tex).GetDimensions( (size).x, (size).y, (size).z )
#define PdxTexture3DLoad(tex,uv,lod) (tex).Load( int4((uv), (lod)) )

// These are for the combined TextureSampler objects
#define PdxTex2DSize(samp,size) PdxTexture2DSize( (samp)._Texture, (size) )
#define PdxTex2D(samp,uv) PdxSampleTex2D( (samp)._Texture, (samp)._Sampler, (uv) )
#define PdxTex2DLod(samp,uv,lod) PdxSampleTex2DLod( (samp)._Texture, (samp)._Sampler, (uv), (lod) )
#define PdxTex2DLodOffset(samp,uv,lod,offset) (samp)._Texture.SampleLevel( (samp)._Sampler, (uv), (lod), (offset) )
#define PdxTex2DBias(samp,uv,bias) PdxSampleTex2DBias( (samp)._Texture, (samp)._Sampler, (uv), (bias) )
#define PdxTex2DGrad(samp,uv,ddx,ddy) PdxSampleTex2DGrad( (samp)._Texture, (samp)._Sampler, (uv), (ddx), (ddy) )
#define PdxTex2DGather(samp,uv) PdxSampleTex2DGather( (samp)._Texture, (samp)._Sampler, (uv) )
#define PdxTex2DLoad(samp,uv,lod) PdxTexture2DLoad( (samp)._Texture, (uv), (lod) )
#define PdxTex2DMultiSampled(samp,texelcoord,sampleidx) (samp)._Texture.Load( (texelcoord), (sampleidx) )
#define PdxTex2DMSSize(samp,size,samples) (samp)._Texture.GetDimensions( (size).x, (size).y, (samples) )

#define PdxTex3D(samp,uv) PdxSampleTex3D( (samp)._Texture, (samp)._Sampler, (uv) )
#define PdxTex3DLod(samp,uv,lod) PdxSampleTex3DLod( (samp)._Texture, (samp)._Sampler, (uv), (lod) )
#define PdxTex3DLoad(samp,uv,lod) PdxTexture3DLoad( (samp)._Texture, (uv), (lod) )

#define PdxTexCube(samp,uv) (samp)._Texture.Sample( (samp)._Sampler, (uv) )
#define PdxTexCubeLod(samp,uv,lod) (samp)._Texture.SampleLevel( (samp)._Sampler, (uv), (lod) )
#define PdxTexCubeBias(samp,uv,bias) (samp)._Texture.SampleBias( (samp)._Sampler, (uv), (bias) )

#define PdxTex2DCmpLod0(samp,uv,value) (samp)._Texture.SampleCmpLevelZero( (samp)._Sampler, (uv), (value) )

#ifdef PDX_USE_MIPLEVELTOOL
float4 IntToNiceColor( in float lod)
{
	uint mip = round(lod);
	uint HueDivision = 6; // As in how many times the color wheel is divided
	uint SatDivision = 5;

	float Hue = fmod( mip / float(HueDivision), 1.0f );
	float Saturation = 1.0f - ( 1.0f / float(SatDivision) ) * ( mip / HueDivision );
	float Value = Saturation;

	float3 HSV = float3(clamp( Hue, 0.0f, 1.0f ), clamp( Saturation, 0.0f, 1.0f ), clamp( Value, 0.0f, 1.0f ));
	float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	float3 p = abs( frac(HSV.xxx + K.xyz) * 6.0 - K.www );

	float4 RGB = float4( HSV.z * lerp( K.xxx, clamp(p - K.xxx, 0.0, 1.0), HSV.y ), 1.00f );

	RGB.x = clamp( RGB.x, 0.0f, 1.0f );
	RGB.y = clamp( RGB.y, 0.0f, 1.0f );
	RGB.z = clamp( RGB.z, 0.0f, 1.0f );

	return RGB;
}

float4 PdxMipTool( in float lod )
{
	return IntToNiceColor(lod );
}

float4 PdxMipToolEstimateLOD(in Texture2D tex, in float2 uv)
{
    uint width, height;
	#ifdef PDX_SCREEN_RES_WIDTH
	float resScale = PDX_SCREEN_RES_WIDTH / 3840.;
	#else
	float resScale = 1.;
	#endif
    tex.GetDimensions(width, height);

  	float du_dx = resScale * ddx(uv.x * width);
    float dv_dx = resScale * ddx(uv.y * height);
    float du_dy = resScale * ddy(uv.x * width);
    float dv_dy = resScale * ddy(uv.y * height);

    float lengthX = sqrt(du_dx*du_dx + dv_dx*dv_dx);
    float lengthY = sqrt(du_dy*du_dy + dv_dy*dv_dy);
    float rho = max(lengthX, lengthY);

	return PdxMipTool( log2(rho) );
}

#define PdxSampleTex2DMipToolParticles(tex,samp,uv) ( ( PdxMipToolEstimateLOD( (tex), (uv) ) ) * float4(1., 1., 1., (tex).Sample( (samp), (uv) ).w ) )
#define PdxSampleTex2DMipTool(tex,samp,uv) ( ( PdxMipToolEstimateLOD( (tex), (uv) ) * (tex).Sample( (samp), (uv) ) ) )
#define PdxSampleTex2DLodMipTool(tex,samp,uv,lod) ( PdxMipTool( (lod) ) * ( (tex).SampleLevel( (samp), (uv), (lod) ) * float4(1.0, 1.0, 1.0, 1.) ) ) 
#define PdxTexture2DLoadMipTool(tex,uv,lod) ( PdxMipTool( (lod) ) * (tex).Load( int3((uv), (lod)) ) )

// These are for the combined TextureSampler objects
#define PdxTex2DMipToolParticles(samp,uv) PdxSampleTex2DMipToolParticles( (samp)._Texture, (samp)._Sampler, (uv) )
#define PdxTex2DMipTool(samp,uv) PdxSampleTex2DMipTool( (samp)._Texture, (samp)._Sampler, (uv) )
#define PdxTex2DLodMipTool(samp,uv,lod) ( PdxSampleTex2DLodMipTool( (samp)._Texture, (samp)._Sampler, (uv), (lod) ) )
#define PdxTex2DLoadMipTool(samp,uv,lod) ( PdxTexture2DLoadMipTool( (samp)._Texture, (uv), (lod) ) )
#endif // PDX_USE_MIPLEVELTOOL

// Vulkan fails to compile shaders with this function call properly
// Commenting it out until we can fix this issue
//#define PdxCalculateLod(samp,uv) (samp)._Texture.CalculateLevelOfDetail( (samp)._Sampler, (uv) )

float4x4 FixProjection( float4x4 ProjectionMatrix )
{
	// Enable for "debug" drawing to see if some objects is missing fix
	#if 0
	for ( int i = 0; i < 4; ++i )
	{
		GetMatrixData( ProjectionMatrix, 0, i ) *= 0.5;
		GetMatrixData( ProjectionMatrix, 1, i ) *= 0.5;
	}
	#endif
	
	return ProjectionMatrix;
}

#define PdxBufferFloat  Buffer<float>
#define PdxBufferFloat2	Buffer<float2>
#define PdxBufferFloat3	Buffer<float3>
#define PdxBufferFloat4	Buffer<float4>
#define PdxBufferInt  	Buffer<int>
#define PdxBufferInt2	Buffer<int2>
#define PdxBufferInt3	Buffer<int3>
#define PdxBufferInt4	Buffer<int4>
#define PdxBufferUint   Buffer<uint>
#define PdxBufferUint2	Buffer<uint2>
#define PdxBufferUint3	Buffer<uint3>
#define PdxBufferUint4	Buffer<uint4>

#define PdxStructuredBuffer StructuredBuffer
#define PdxRWStructuredBuffer RWStructuredBuffer
#define PdxRawBuffer ByteAddressBuffer
#define PdxRWRawBuffer RWByteAddressBuffer 
#define PdxRasterizerOrderedBuffer RasterizerOrderedBuffer
#define PdxRasterizerOrderedStructuredBuffer RasterizerOrderedStructuredBuffer

float 	PdxReadBuffer( in PdxBufferFloat Buf, int Index )  		{ return Buf.Load( Index ); }
float2	PdxReadBuffer2( in PdxBufferFloat2 Buf, int Index )		{ return Buf.Load( Index ); }
float3	PdxReadBuffer3( in PdxBufferFloat3 Buf, int Index )		{ return Buf.Load( Index ); }
float4	PdxReadBuffer4( in PdxBufferFloat4 Buf, int Index )		{ return Buf.Load( Index ); }

int  	PdxReadBuffer( in PdxBufferInt Buf, int Index ) 		{ return Buf.Load( Index ); }
int2 	PdxReadBuffer2( in PdxBufferInt2 Buf, int Index )		{ return Buf.Load( Index ); }
int3 	PdxReadBuffer3( in PdxBufferInt3 Buf, int Index )    	{ return Buf.Load( Index ); }
int4 	PdxReadBuffer4( in PdxBufferInt4 Buf, int Index )    	{ return Buf.Load( Index ); }

uint  	PdxReadBuffer( in PdxBufferUint Buf, int Index )    	{ return Buf.Load( Index ); }
uint2 	PdxReadBuffer2( in PdxBufferUint2 Buf, int Index )  	{ return Buf.Load( Index ); }
uint3 	PdxReadBuffer3( in PdxBufferUint3 Buf, int Index )  	{ return Buf.Load( Index ); }
uint4 	PdxReadBuffer4( in PdxBufferUint4 Buf, int Index )  	{ return Buf.Load( Index ); }

#define PdxReadRWBuffer(buffer,index) (buffer)[(index)]
#define PdxWriteRWBuffer(buffer,index,value) (buffer)[(index)] = (value)

#define Quaternion float4
