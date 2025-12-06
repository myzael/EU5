Includes = {
	"cw/fullscreen_vertexshader.fxh"
	"cw/camera.fxh"
}

PixelShader =
{
	MainCode PixelShader
	{
		VertexStruct PS_OUTPUT
		{
			float4 _Color : PDX_COLOR;
			float _Depth : PDX_Depth;
		};
		
		ConstantBuffer( PdxConstantBuffer0 )
		{
			float3 _GridColor;
			float _GridAlpha;
			float _MinGridSpacing;
			float _MaxGridSpacing;
		}
		
		Input = "VS_OUTPUT_FULLSCREEN"
		Output = "PS_OUTPUT"
		Code
		[[
			// NOTE: with large camera position this can cause precision issues, it is solvable by centering the grid around the camera (and providing camera matrices without the "offset")
			// however it complicates the implementation quite a bit so will keep it simple for now and reevaluate if we run into issues
			// Roughly based on http://asliceofrendering.com/scene%20helper/2020/01/05/InfiniteGrid/
			float4 CalculateGrid( float3 WorldSpacePos, float Scale, float3 GridColor, float Alpha )
			{
				float2 ScaledPos = WorldSpacePos.xz / Scale;
				float2 Derivative = fwidth( WorldSpacePos.xz ) / Scale; // Scale the derivative separately to avoid discontinuities
				float2 Grid = abs( frac( ScaledPos - 0.5 ) - 0.5 ) / Derivative;
				float GridFactor = saturate( 1.0 - min( min( Grid.x, Grid.y ), 1.0 ) );
				float4 Color = float4( GridColor, GridFactor * Alpha );
				
				// z axis
				float Minimumx = min( Derivative.x, 1 );
				if ( WorldSpacePos.x > -Scale * Minimumx && WorldSpacePos.x < Scale * Minimumx )
				{
					Color.rgb = float3( 0.0, 0.0, 1.0 );
				}
					
				// x axis
				float Minimumz = min( Derivative.y, 1 );
				if ( WorldSpacePos.z > -Scale * Minimumz && WorldSpacePos.z < Scale * Minimumz )
				{
					Color.rgb = float3( 1.0, 0.0, 0.0 );
				}
  
				return Color;
			}
			
			PDX_MAIN
			{			
				PS_OUTPUT Out;
				
				float3 NearPoint = WorldSpacePositionFromDepth( 0.0, Input.uv );
				float3 FarPoint = WorldSpacePositionFromDepth( 1.0, Input.uv );
				
				// Intersect "view ray" with y-plane
				float t = -NearPoint.y / ( FarPoint.y - NearPoint.y );
				clip( t );
				
				// Calculate the worldspace intersection
				float3 WorldSpacePos = NearPoint + t * ( FarPoint - NearPoint );
				
				float CameraDistanceFromPlane = length( CameraPosition - WorldSpacePos );
				float GridLogFactor = log10( CameraDistanceFromPlane );
				float GridScaleIndex = clamp( floor( GridLogFactor ), _MinGridSpacing, _MaxGridSpacing );
				float GridSubdivisionMultiplier = 10.0;
				float Scale = pow( GridSubdivisionMultiplier, GridScaleIndex );
				float ScaleInner = pow( GridSubdivisionMultiplier, GridScaleIndex - 1 );
				
				float InnerGridLerpFactor = 1.0 - smoothstep( 0.0, 1.0, GridLogFactor - GridScaleIndex );
				
				float4 Color = CalculateGrid( WorldSpacePos, Scale, _GridColor, _GridAlpha * (1.0 - InnerGridLerpFactor) );
				Color += CalculateGrid( WorldSpacePos, ScaleInner, _GridColor, _GridAlpha * InnerGridLerpFactor );
				
				// Fade out the grid at grazing angles
				float GridFadeFactor = smoothstep( 0.0, 0.05, abs( dot( float3( 0, 1, 0 ), normalize( CameraPosition - WorldSpacePos ) ) ) );
				Color.w *= GridFadeFactor;
				
				float4 ClipSpacePosition = FixProjectionAndMul( ViewProjectionMatrix, float4( WorldSpacePos, 1.0 ) );
				
				Out._Color = Color;
				// Only write depth where lines are visible
				Out._Depth = ( Color.w < 0.01 ) ? 1.0 : ( ClipSpacePosition.z / ClipSpacePosition.w );
				
				return Out;
			}
		]]
	}
}

DepthStencilState DepthStencilState
{
	depthfunction = less_equal
}

BlendState BlendState
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
}

Effect Grid
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "PixelShader"
}