# Utils shared between mesh1 and mesh2

Includes = {
	"cw/random.fxh"
}

Code
[[
	void PdxMeshApplyDitheredOpacity( in float Opacity, in float2 NoiseCoordinate )
	{
		#ifdef PDXMESH_SCREENDOOR_DITHER
			const float4x4 ThresholdMatrix =
			{
				1.0  / 17.0,  9.0  / 17.0,  3.0 / 17.0, 11.0 / 17.0,
				13.0 / 17.0,  5.0  / 17.0, 15.0 / 17.0,  7.0 / 17.0,
				4.0  / 17.0,  12.0 / 17.0,  2.0 / 17.0, 10.0 / 17.0,
				16.0 / 17.0,  8.0  / 17.0, 14.0 / 17.0,  6.0 / 17.0
			};
			float Factor = ThresholdMatrix[NoiseCoordinate.x % 4][NoiseCoordinate.y % 4];
		#else
			float Factor = CalcRandom( NoiseCoordinate );
		#endif
		clip( Opacity - Factor * sign( Opacity ));
		clip( 0.5 - (Opacity == 0.0) ); //ensure that with sign 0 we also clip the opacity
	}
]]
