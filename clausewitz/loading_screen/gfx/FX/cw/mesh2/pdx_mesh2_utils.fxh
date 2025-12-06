Code
[[
	uint2 Read2( PdxBufferUint Buf, uint Offset )
	{
		return uint2( Buf[Offset], Buf[Offset + 1] );
	}
	float2 Read2Float( PdxBufferUint Buf, uint Offset )
	{
		return asfloat( Read2( Buf, Offset ) );
	}
	
	uint3 Read3( PdxBufferUint Buf, uint Offset )
	{
		return uint3( Buf[Offset], Buf[Offset + 1], Buf[Offset + 2] );
	}
	float3 Read3Float( PdxBufferUint Buf, uint Offset )
	{
		return asfloat( Read3( Buf, Offset ) );
	}
	
	uint4 Read4( PdxBufferUint Buf, uint Offset )
	{
		return uint4( Buf[Offset], Buf[Offset + 1], Buf[Offset + 2], Buf[Offset + 3] );
	}
	float4 Read4Float( PdxBufferUint Buf, uint Offset )
	{
		return asfloat( Read4( Buf, Offset ) );
	}
	
	#define PDX_MESH2_MATRIX34_DATA_STRIDE 12
	float4x4 ReadMatrix34( PdxBufferUint Buf, uint Offset )
	{
		float4 XAxis = float4( Read3Float( Buf, Offset ), 0.0 );
		float4 YAxis = float4( Read3Float( Buf, Offset + 3 ), 0.0 );
		float4 ZAxis = float4( Read3Float( Buf, Offset + 6 ), 0.0 );
		float4 Translation = float4( Read3Float( Buf, Offset + 9 ), 1.0 );
		return Create4x4( XAxis, YAxis, ZAxis, Translation );
	}
	
	
	// Unpack 2 int16 packed into a uint32
	int2 UnpackInt16_x2( int Packed )
	{
		return int2( Packed << 16, Packed ) >> 16;
	}
	// Unpack 2 snorm16 packed into a uint32
	float2 UnpackSnorm16_x2( int Packed )
	{
		return clamp( float2( UnpackInt16_x2( Packed ) ) / 32767.0, vec2( -1.0 ), vec2( 1.0 ) );
	}
	
	// Unpack 2 uint16 packed into a uint32
	uint2 UnpackUint16_x2( uint Packed )
	{
		return uint2( Packed & 0xffff, Packed >> 16 );
	}
	// Unpack 2 unorm16 packed into a uint32
	float2 UnpackUnorm16_x2( uint Packed )
	{
		return float2( UnpackUint16_x2( Packed ) ) / UINT16_MAX;
	}
	
	// Unpack 4 uint8 packed into a uint32
	uint4 UnpackUint8_x4( uint Packed )
	{
		return uint4( Packed & 0xff, ( Packed >> 8 ) & 0xff, ( Packed >> 16 ) & 0xff, Packed >> 24 );
	}
	// Unpack 4 unorm8 packed into a uint32
	float4 UnpackUnorm8_x4( uint Packed )
	{
		return float4( UnpackUint8_x4( Packed ) ) / UINT8_MAX;
	}
	

	// Unpack 2 uints, the first uses "NumBitsForX" bits the second uses "32 - NumBitsForX" bits
	uint2 UnpackUintX_UintY( uint Packed, const uint NumBitsForX )
	{
		const uint YMask = ( 1u << ( 32 - NumBitsForX ) ) - 1;
		return uint2( Packed >> ( 32 - NumBitsForX ), Packed & YMask );
	}
	
	// Unpack 1 uint and 1 normalized float, the uint uses "NumBitsForX" bits the float uses "32 - NumBitsForX" bits
	// Note that 24 bits for Y is at the limit of what "integer floats" can handle, so NumBitsForX should be >= 8
	void UnpackUintX_UnormY( uint Packed, const uint NumBitsForX, out uint UintXOut, out float UnormYOut )
	{
		uint2 UintX_UintY = UnpackUintX_UintY( Packed, NumBitsForX );
		UintXOut = UintX_UintY.x;
		UnormYOut = float( UintX_UintY.y ) / float( ( 1u << ( 32 - NumBitsForX ) ) - 1 );
	}
	
	
	// Custom format used for skin data, first 6 bits store a "uint6" and last 26 bits store a "uint26"
	uint2 UnpackUint6_Uint26( uint Packed )
	{
		return UnpackUintX_UintY( Packed, 6 );
	}
	
	// Custom format used for skin data, first 8 bits store a "uint8" and last 24 bits store a "unorm24"
	void UnpackUint8_Unorm24( uint Packed, out uint Uint8Out, out float Unorm24Out )
	{
		UnpackUintX_UnormY( Packed, 8, Uint8Out, Unorm24Out );
	}
	// Custom format used for skin data, first 16 bits store a "uint16" and last 16 bits store a "unorm16"
	void UnpackUint16_Unorm16( uint Packed, out uint Uint16Out, out float Unorm16Out )
	{
		UnpackUintX_UnormY( Packed, 16, Uint16Out, Unorm16Out );
	}
]]