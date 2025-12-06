Includes = {
	"cw/fullscreen_vertexshader.fxh"
}

PixelShader =
{
	MainCode DepthBufferMotionVectors
	{
		ConstantBuffer( PdxConstantBuffer2 )
		{
			float4x4 _InvProjectionMatrix;
			float4x4 _InvViewMatrix;
			float4x4 _PrevViewProjectionMatrix;
			uint2 _RenderResolution;
			float2 _JitterDiff;
		};
	
		TextureSampler DepthBuffer
		{
			Ref = PdxTexture0
			MagFilter = "Point"
			MinFilter = "Point"
			MipFilter = "Point"
			SampleModeU = "Clamp"
			SampleModeV = "Clamp"
		}
	
		Input = "VS_OUTPUT_FULLSCREEN"
		Output = "PDX_COLOR"
		Code
		[[
			float3 CalculateWorldSpacePosition( float Depth, float2 UV )
			{
				float x = UV.x * 2.0 - 1.0;
				float y = 1.0 - UV.y * 2.0;
				
				float4 ProjectedPos = float4( x, y, Depth, 1.0 );
				float4 ViewSpacePos = mul( _InvProjectionMatrix, ProjectedPos );
				return mul( _InvViewMatrix, float4( ViewSpacePos.xyz / ViewSpacePos.w, 1.0 ) ).xyz;
			}
			
			PDX_MAIN
			{
				//return float4( 0, 0, 0, 0 );
				
				float3 WorldSpacePos = CalculateWorldSpacePosition( PdxTex2DLod0( DepthBuffer, Input.uv ).r, Input.uv );

				float4 PreviousPos = mul( _PrevViewProjectionMatrix, float4( WorldSpacePos, 1.0 ) );
				PreviousPos /= PreviousPos.w; 
				
				// Remap to 0->1 range and invert y
				PreviousPos.xy *= float2( 0.5, -0.5 );
				PreviousPos.xy += vec2( 0.5 );
				// Scale to render resolution
				PreviousPos.xy *= _RenderResolution;
				
				// Velocity is in pixels
				float2 Velocity = PreviousPos.xy - Input.position.xy;
				return float4( Velocity - _JitterDiff, 0, 0 );
			}	
		]]
	}
}

DepthStencilState NoDepth
{
	DepthEnable = no
	DepthWriteEnable = no
}

Effect DepthBufferMotionVectors
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "DepthBufferMotionVectors"
	
	DepthStencilState = NoDepth
}
