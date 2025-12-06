Code
[[
	// Sine wave, remapped to 0-1
	float Sin01( float Angle )
	{
		return ( sin( Angle ) * 0.5 ) + 0.5;
	}

	// Cubic bezier 	// Reference: https://www.tinaja.com/text/bezmath.html
	float SlopeFromT (float T, float A, float B, float C)
	{
		return 1.0 / ( 3.0 * A * T * T + 2.0 * B * T + C ); 
	}
	float XFromT ( float T, float A, float B, float C, float D )
	{
		return A * ( T * T * T ) + B * ( T * T ) + C * T + D;
	}
	float YFromT ( float T, float E, float F, float G, float H )
	{
		return E * ( T * T * T ) + F * ( T * T ) + G * T + H;
	}
	float CubicBezier( float Value, float2 Point1, float2 Point2 )
	{
		float y0 = 0.0;
		float x0 = 0.0;
		float y1 = Point1.y;
		float x1 = Point1.x;
		float y2 = Point2.y;
		float x2 = Point2.x;
		float y3 = 1.0;
		float x3 = 1.0;

		float A = x3 - 3.0 * x2 + 3.0 * x1 - x0;
		float B = 3.0 * x2 - 6.0 * x1 + 3.0 * x0;
		float C = 3.0 * x1 - 3.0 * x0;
		float D = x0;

		float E = y3 - 3.0 * y2 + 3.0 * y1 - y0;
		float F = 3.0 * y2 - 6.0 * y1 + 3.0 * y0;
		float G = 3.0 * y1 - 3.0 * y0;
		float H = y0;

		float CurrentT = Value;
		for (int i = 0; i < 5; i++ )
		{
			float CurrentX = XFromT( CurrentT, A, B, C , D ); 
			float CurrentSlope = SlopeFromT ( CurrentT, A, B, C );
			CurrentT -= ( CurrentX - Value ) * ( CurrentSlope );
			CurrentT = clamp( CurrentT, 0.0, 1.0 ); 
		} 

		float y = YFromT ( CurrentT, E, F, G, H );
		return y;
	}
]]
