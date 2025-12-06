
BufferTexture PdxBindlessDebugBuffer
{
	Ref = PdxBindlessDebugBuffer
	type = uint
}

Code
[[
#ifdef PDX_ENABLE_BINDLESS_DEBUG
	uint GetBindlessHandleType( uint Handle ) { return ( Handle >> 24 ) & 0xFF; }
	
	void GetResourceTypeOffsetAndSize( uint ResourceType, out uint Offset, out uint Size )
	{
		uint Index = 1 + 2 * min( ResourceType, PdxBindlessDebugBuffer[0] - 1 );
		Offset = PdxBindlessDebugBuffer[Index];
		Size = PdxBindlessDebugBuffer[Index + 1];
	}

	void VerifyHandle( uint Handle, uint ResourceType )
	{
		if ( GetBindlessHandleType( Handle ) == 0xFF )
		{
			ASSERT_FAIL( "Attempting to use an invalid bindless handle, (index, type) ('%d', '%d')", GetBindlessHandleIndex( Handle ), GetBindlessHandleType( Handle ) );
		}
		else
		{
			ASSERT_FORMAT( GetBindlessHandleType( Handle ) == ResourceType, "ResourceType missmatch expected '%d' got '%d'", ResourceType, GetBindlessHandleType( Handle ) );
			ASSERT_FORMAT( ResourceType <= PdxBindlessDebugBuffer[0], "Resource type out of range, num resource types '%d', got index '%d'", PdxBindlessDebugBuffer[0], ResourceType );
		
			uint Offset;
			uint Size;
			GetResourceTypeOffsetAndSize( ResourceType, Offset, Size );
		
			uint ResourceIndex = GetBindlessHandleIndex( Handle );
			ASSERT_FORMAT( ResourceIndex < Size, "Resource index out of range, resource type '%d', num resources '%d', got index '%d'", ResourceType, Size, ResourceIndex );
		
			uint ExpectedHandle = PdxBindlessDebugBuffer[Offset + ResourceIndex];
			if ( GetBindlessHandleType( ExpectedHandle ) == 0xFF )
			{
				ASSERT_FAIL( "Attempting to access an invalid bindless resource for handle (index, type) ('%d', '%d')", GetBindlessHandleIndex( Handle ), GetBindlessHandleType( Handle ) );
			}
			else
			{
				ASSERT_FORMAT( ExpectedHandle == Handle, "Resource handle missmatch, expected (index, type) ('%d', '%d'), got ('%d', '%d')", GetBindlessHandleIndex( ExpectedHandle ), GetBindlessHandleType( ExpectedHandle ), GetBindlessHandleIndex( Handle ), GetBindlessHandleType( Handle ) );
			}
		}
	}
#endif
]]
