
RWBufferTexture PdxShaderDebugBuffer
{
	Ref = PdxShaderDebugBuffer
	type = uint
}

ConstantBuffer( PdxShaderDebugConstants )
{
	uint _ShaderDebugBufferSize;
	int _PrintfEnabled;
	int _AssertEnabled;
}

Code 
[[
	// These defines are intentionally broken, c++ code will rename them to PDX_PRINTF_ENABLED/PDX_ASSERT_ENABLED if printf/assert is enabled (-gfxprintf and/or -gfxassert is on the commandline)
	// We do this so that printf resources are not referenced by any shaders when it is disabled (even tho it might still include and use the code in this file)
	#define _PDX_PRINTF_ENABLED_
	#define _PDX_ASSERT_ENABLED_
	
#if defined( PDX_PRINTF_ENABLED ) || defined( PDX_ASSERT_ENABLED )
	#define PRINTF_MACRO( Content ) if ( PrintfEnabled ) { Content; }
	#define ASSERT_FAIL_MACRO( Content ) if ( AssertEnabled && _AssertEnabled ) { Content; }
	#define ASSERT_FORMAT_MACRO( Content ) if ( !AssertTrigger ) { ASSERT_FAIL_MACRO( Content ); AssertTrigger = false; }
	
#ifdef PDX_DIRECTX_11
	namespace EType
	{
		static uint Type_BufferFull = 1;
		static uint Type_StringID = 2;
		static uint Type_int = 3;
		static uint Type_uint = 4;
		static uint Type_float = 5;
	};
#else
	enum EType : uint
	{
		Type_BufferFull = 1,
		Type_StringID,
		Type_int,
		Type_uint,
		Type_float,
	};
#endif
	
	
#if defined( PDX_PRINTF_ENABLED )
	static bool PrintfEnabled = false;
	
	// This is used to conditionally turn on printf for specific vertices/pixels etc, since you most likely do not want it for everything
	void SetPrintfEnabled( bool Enabled )
	{
		PrintfEnabled = Enabled && ( _PrintfEnabled == 1 );
	}
#endif
	
	
#if defined( PDX_ASSERT_ENABLED )
	static bool AssertEnabled = true;
	static bool AssertTrigger = false;
	
	// Similar to SetPrintfEnabled, asserts can be enabled/disabled based on custom contidions
	// Note unlike printf, asserts are enabled by default for all invocations
	void SetAssertEnabled( bool Enabled )
	{
		AssertEnabled = Enabled;
	}
	
	void WriteAssertTrigger( bool Trigger )
	{
		AssertTrigger = Trigger;
	}
#endif
	
	
	static uint WritePos = 0;
	
	// Allocates the amount of data needed from the buffer, return false if buffer is full
	bool AllocatePrintfWrites( uint NumWrites )
	{
		InterlockedAdd( PdxShaderDebugBuffer[0], NumWrites, WritePos );
		WritePos++; // Skip over counter (PdxShaderDebugBuffer[0])
		if ( ( WritePos + NumWrites ) > ( _ShaderDebugBufferSize - 1 ) ) // -1 since we allocate one spare for notifying full buffer
		{
			if ( WritePos < _ShaderDebugBufferSize )
			{
				PdxShaderDebugBuffer[WritePos] = EType::Type_BufferFull;
			}
			return false;
		}
		return true;
	}

	
	struct SStringID
	{
		uint _ID;
	};
	SStringID GetStringID( uint ID )
	{
		SStringID StringID;
		StringID._ID = ID;
		return StringID;
	}
	// HLSL does not allow "a ? b : c", with non native types so we have to use this to support conditional strings 
	SStringID ConditionalString( bool Condition, SStringID ID1, SStringID ID2 )
	{
		if ( Condition )
		{
			return ID1;
		}
		else
		{
			return ID2;
		}
	}
	
	uint PrintfArgSize( SStringID ID ) { return 2; }
	void WritePrintfArg( SStringID ID )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_StringID;
		PdxShaderDebugBuffer[WritePos++] = ID._ID;
	}
	
	
	uint PrintfArgSize( int Value ) { return 2; }
	uint PrintfArgSize( int2 Value ) { return 3; }
	uint PrintfArgSize( int3 Value ) { return 4; }
	uint PrintfArgSize( int4 Value ) { return 5; }
	void WritePrintfArg( int Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_int;
		PdxShaderDebugBuffer[WritePos++] = Value;
	}
	void WritePrintfArg( int2 Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_int;
		PdxShaderDebugBuffer[WritePos++] = Value.x;
		PdxShaderDebugBuffer[WritePos++] = Value.y;
	}
	void WritePrintfArg( int3 Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_int;
		PdxShaderDebugBuffer[WritePos++] = Value.x;
		PdxShaderDebugBuffer[WritePos++] = Value.y;
		PdxShaderDebugBuffer[WritePos++] = Value.z;
	}
	void WritePrintfArg( int4 Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_int;
		PdxShaderDebugBuffer[WritePos++] = Value.x;
		PdxShaderDebugBuffer[WritePos++] = Value.y;
		PdxShaderDebugBuffer[WritePos++] = Value.z;
		PdxShaderDebugBuffer[WritePos++] = Value.w;
	}
	
	
	uint PrintfArgSize( uint Value ) { return 2; }
	uint PrintfArgSize( uint2 Value ) { return 3; }
	uint PrintfArgSize( uint3 Value ) { return 4; }
	uint PrintfArgSize( uint4 Value ) { return 5; }
	void WritePrintfArg( uint Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_uint;
		PdxShaderDebugBuffer[WritePos++] = Value;
	}
	void WritePrintfArg( uint2 Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_uint;
		PdxShaderDebugBuffer[WritePos++] = Value.x;
		PdxShaderDebugBuffer[WritePos++] = Value.y;
	}
	void WritePrintfArg( uint3 Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_uint;
		PdxShaderDebugBuffer[WritePos++] = Value.x;
		PdxShaderDebugBuffer[WritePos++] = Value.y;
		PdxShaderDebugBuffer[WritePos++] = Value.z;
	}
	void WritePrintfArg( uint4 Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_uint;
		PdxShaderDebugBuffer[WritePos++] = Value.x;
		PdxShaderDebugBuffer[WritePos++] = Value.y;
		PdxShaderDebugBuffer[WritePos++] = Value.z;
		PdxShaderDebugBuffer[WritePos++] = Value.w;
	}
	
	
	uint PrintfArgSize( float Value ) { return 2; }
	uint PrintfArgSize( float2 Value ) { return 3; }
	uint PrintfArgSize( float3 Value ) { return 4; }
	uint PrintfArgSize( float4 Value ) { return 5; }
	void WritePrintfArg( float Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_float;
		PdxShaderDebugBuffer[WritePos++] = asuint( Value );
	}
	void WritePrintfArg( float2 Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_float;
		PdxShaderDebugBuffer[WritePos++] = asuint( Value.x );
		PdxShaderDebugBuffer[WritePos++] = asuint( Value.y );
	}
	void WritePrintfArg( float3 Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_float;
		PdxShaderDebugBuffer[WritePos++] = asuint( Value.x );
		PdxShaderDebugBuffer[WritePos++] = asuint( Value.y );
		PdxShaderDebugBuffer[WritePos++] = asuint( Value.z );
	}
	void WritePrintfArg( float4 Value )
	{
		PdxShaderDebugBuffer[WritePos++] = EType::Type_float;
		PdxShaderDebugBuffer[WritePos++] = asuint( Value.x );
		PdxShaderDebugBuffer[WritePos++] = asuint( Value.y );
		PdxShaderDebugBuffer[WritePos++] = asuint( Value.z );
		PdxShaderDebugBuffer[WritePos++] = asuint( Value.w );
	}
#endif
]]
