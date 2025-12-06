BufferTexture Permutation
{
	Ref = PdxNoise0
	type = uint
}

BufferTexture Gradient
{
	Ref = PdxNoise1
	type = float2
}

struct OctaveAmplitude
{
    float _Amplitude;
    float3 _Padding;
}

ConstantBuffer( PdxNoise )
{
    uint _OctaveCount;
    uint3 _Padding;
	OctaveAmplitude _Amplitudes[10]; #Needs to match MaxOctaves defined in c++;
}

Code
[[
#ifdef PDX_ENABLE_SIMPLEX_NOISE_2D
    //Reference used: https://web.archive.org/web/20221020032155/https://weber.itn.liu.se/~stegu/simplexnoise/SimplexNoise.java

    // Skewing and unskewing factors for 2 dimensions.
    static const float F2 = 0.5f * ( sqrt( 3.0f) -1.0f );
    static const float G2 = ( 3.0f - sqrt( 3.0f ) ) / 6.0f;

    float Simplex2D( float2 Point )
    {      
        // Skew the input space to determine which simplex cell we're in
        float SkewFactor = ( Point.x + Point.y ) * F2; // Hairy factor for 2D
        int2 SkewedPoint = floor( Point + SkewFactor );

        float UnskewFactor = ( SkewedPoint.x + SkewedPoint.y ) * G2;
        float2 UnskewedCellOrigin = SkewedPoint - UnskewFactor; // Unskew the cell origin back to (x,y) space
        float2 DistanceFromCellOrigin = Point - UnskewedCellOrigin; // The x,y distances from the cell origin

        // For the 2D case, the simplex shape is an equilateral triangle.
        // Determine which simplex we are in.
        int2 SkewedSecondCornerOffset = int2( 0, 1 ); // Offsets for second (middle) corner of simplex in (i,j) coords
        if( DistanceFromCellOrigin.x > DistanceFromCellOrigin.y ) 
        {
            SkewedSecondCornerOffset = SkewedSecondCornerOffset.yx;
        } 

        // upper triangle, YX order: (0,0)->(0,1)->(1,1)
        // A step of (1,0) in (i,j) means a step of (1-c,-c) in (x,y), and
        // a step of (0,1) in (i,j) means a step of (-c,1-c) in (x,y), where
        // c = (3-sqrt(3))/6
        float2 UnskewedSeconeCornerOffset = DistanceFromCellOrigin - SkewedSecondCornerOffset + G2; // Offsets for middle corner in (x,y) unskewed coords
        float2 UnskewedThirdCornerOffset = DistanceFromCellOrigin - 1.0 + 2.0f * G2; // Offsets for last corner in (x,y) unskewed coords
        
        // Work out the hashed gradient indices of the three simplex corners
        int2 SkewedPointClamped = SkewedPoint & 255;
        int gi0 = Permutation[ SkewedPointClamped.x + Permutation[ SkewedPointClamped.y ] ] % 12;
        int gi1 = Permutation[ SkewedPointClamped.x + SkewedSecondCornerOffset.x + Permutation[ SkewedPointClamped.y + SkewedSecondCornerOffset.y ] ] % 12;
        int gi2 = Permutation[ SkewedPointClamped.x + 1 + Permutation[ SkewedPointClamped.y + 1 ] ] % 12;
     
        // Calculate the contribution from the three corners    
        float3 NoiseValues;
          
        float t0 = 0.5f - DistanceFromCellOrigin.x * DistanceFromCellOrigin.x - DistanceFromCellOrigin.y * DistanceFromCellOrigin.y;
        t0 *= t0;
        NoiseValues.x = t0 * t0 * dot( Gradient[ gi0 ].xy, float2( DistanceFromCellOrigin.x, DistanceFromCellOrigin.y ) );

        float t1 = 0.5f - UnskewedSeconeCornerOffset.x * UnskewedSeconeCornerOffset.x - UnskewedSeconeCornerOffset.y * UnskewedSeconeCornerOffset.y;
        t1 *= t1;
        NoiseValues.y = t1 * t1 * dot( Gradient[ gi1 ].xy, float2( UnskewedSeconeCornerOffset.x, UnskewedSeconeCornerOffset.y ) );

        float t2 = 0.5f - UnskewedThirdCornerOffset.x * UnskewedThirdCornerOffset.x - UnskewedThirdCornerOffset.y * UnskewedThirdCornerOffset.y;
        t2 *= t2;
        NoiseValues.z = t2 * t2 * dot( Gradient[ gi2 ].xy, float2( UnskewedThirdCornerOffset.x, UnskewedThirdCornerOffset.y ) );
        
        float3 Mask = float3( (float)t0 > 0, (float)t1 > 0.0f, (float)t2 > 0.0f );
        NoiseValues *= Mask;

        // Add contributions from each corner to get the final noise value.
        // The result is scaled to return values in the interval [0,1].
        return ( 70.0f * ( NoiseValues.x + NoiseValues.y + NoiseValues.z ) + 1.0f ) / 2.0f;
    }

    float SampleNoise2D( float2 Point )
    { 
        float AmplitudeSum = 0.0f;
        float NoiseValue = 0.0f;
       
        for( uint Octave = 0; Octave < _OctaveCount; ++Octave )
        {
            uint Frequency = 1 << Octave;
            NoiseValue += _Amplitudes[ Octave ]._Amplitude * Simplex2D( Point * Frequency );
            AmplitudeSum += _Amplitudes[ Octave ]._Amplitude;
        }

        return NoiseValue / AmplitudeSum;
    }
#endif
]]
