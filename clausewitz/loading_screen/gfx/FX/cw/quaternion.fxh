Code
[[
    // Create a quaternion to rotate from Vector1 to Vector2
    // Both inputs have to be normalised vectors
    Quaternion CreateQuaternion( float3 Vector1, float3 Vector2 )
    {
        Quaternion Quat;
        Quat.xyz = cross( Vector1, Vector2 );
        Quat.w = 1 + dot( Vector1, Vector2 );
        return normalize( Quat );
    } 

    float3 RotateVector( Quaternion Quat, float3 Vector )
	{
		return Vector + 2.0 * cross( Quat.xyz, cross( Quat.xyz, Vector ) + Quat.w * Vector );
	}
]]