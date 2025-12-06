Includes = {
	"cw/camera.fxh"
	"cw/fullscreen_vertexshader.fxh"
}

PixelShader =
{		
	ConstantBuffer( PdxConstantBuffer0 )
	{
		uint2 _SourceSize;
		uint2 _DestinationSize;
		uint _LinearizeDepth;
	};

	Code
	[[
		#if defined( MIN_FILTER )
		#define FILTER min
		#elif defined( MAX_FILTER )
		#define FILTER max
		#endif
		// Shader will not compile without an explicitly defined filter function

		float LinearizeDepth( float Depth )
		{
			return ZNear * ZFar / ( ZFar + Depth * ( ZNear - ZFar ) );
		}
			
		float ReadValue( uint2 ReadIndex )
		{
			return ( _LinearizeDepth == 1 ) ? LinearizeDepth( Source[ReadIndex].x ) : Source[ReadIndex].x;
		}
			
		float DoPass( in VS_OUTPUT_FULLSCREEN Input )
		{
			if( _SourceSize.x == _DestinationSize.x && _SourceSize.y == _DestinationSize.y )
			{
				// Source and Destination have the same size. Likely this is mip0
				// We need to sample a single pixel to perform any linearizing math and/or multi sample resolve
				return ReadValue( Input.position.xy );
			}

			uint2 WriteIndex = Input.position.xy;
			uint2 ReadIndex = WriteIndex * 2;
				
			float4 Values = float4( ReadValue( ReadIndex ).x, 
									ReadValue( ReadIndex + uint2(1,0) ).x,
									ReadValue( ReadIndex + uint2(0,1) ).x,
									ReadValue( ReadIndex + uint2(1,1) ).x );

			float Value = FILTER( Values.x, FILTER( Values.y, FILTER( Values.z, Values.w ) ) );
				
			float2 Ratio = float2( _SourceSize ) / float2( _DestinationSize );
			bool NeedExtraSampleX = Ratio.x > 2.0;
			bool NeedExtraSampleY = Ratio.y > 2.0;
    
			Value = NeedExtraSampleX ? FILTER( Value, FILTER( ReadValue( ReadIndex + uint2(2,0) ), ReadValue( ReadIndex + uint2(2,1) ) ) ) : Value;
			Value = NeedExtraSampleY ? FILTER( Value, FILTER( ReadValue( ReadIndex + uint2(0,2) ), ReadValue( ReadIndex + uint2(1,2) ) ) ) : Value;
			Value = (NeedExtraSampleX && NeedExtraSampleY) ? FILTER( Value, ReadValue( ReadIndex + uint2(2,2) ) ) : Value;

			return Value;
		}
	]]
	MainCode DownsamplePixelShader
	{			
		Texture Source
		{
			Ref = PdxTexture0
			format = float
		} 
		
		Input = "VS_OUTPUT_FULLSCREEN"
		Output = "PDX_COLOR"
		Code
		[[			
			PDX_MAIN
			{
				return vec4( DoPass( Input ) );
			}		
		]]
	}
	MainCode DownsamplePixelShaderMultisampled
	{			
		Texture Source
		{
			Ref = PdxTexture0
			format = float
			MultiSampled = yes
		} 
		
		Input = "VS_OUTPUT_FULLSCREEN"
		Output = "PDX_COLOR"
		Code
		[[			
			PDX_MAIN
			{
				return vec4( DoPass( Input ) );
			}		
		]]
	}
}

DepthStencilState DepthStencilState
{
	DepthEnable = no
	DepthWriteEnable = no
}

Effect DownsampleDepth
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "DownsamplePixelShader"
}
Effect DownsampleDepthMultisampled
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "DownsamplePixelShaderMultisampled"
}
