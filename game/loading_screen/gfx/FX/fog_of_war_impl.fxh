Includes = {
	"cw/utility.fxh"
}

ConstantBuffer( GameFogOfWar )
{
	float4 	FoWColor1;
	float4 	FoWColor2;
	float	FoWBaseAlpha;
	float	FoWNeighborAlpha;
}

Code
[[
	#define FOG_OF_WAR_BLEND_FUNCTION CalcFogOfWarBlend
	float4 CalcFogOfWarBlend( float Alpha )
	{
		Alpha = saturate( Alpha );
		
		float Blend = smoothstep( 0.0f, FoWNeighborAlpha, Alpha );
		float4 Color = lerp( FoWColor2, FoWColor1, Blend );
		Color.a *= RemapClamped( Alpha, FoWNeighborAlpha, 1.0f, 1.0f, 0.0f );
		return Color;
	}
]]