#/******************************************************************************
# * GPUSorting
# * OneSweep Implementation
# *
# * SPDX-License-Identifier: MIT
# * Copyright Thomas Smith 2/21/2024
# * https://github.com/b0nes164/GPUSorting
# * 
# * Based off of Research by:
# *          Andy Adinets, Nvidia Corporation
# *          Duane Merrill, Nvidia Corporation
# *          https://research.nvidia.com/publication/2022-06_onesweep-faster-least-significant-digit-radix-sort-gpus
# *
# ******************************************************************************/
Code
[[
    #define MAX_DISPATCH_DIM    65535U  //The max value of any given dispatch dimension
    #define RADIX               256U    //Number of digit bins
    #define RADIX_MASK          255U    //Mask of digit bins
    #define HALF_RADIX          128U    //For smaller waves where bit packing is necessary
    #define HALF_MASK           127U    // '' 
    #define RADIX_LOG           8U      //log2(RADIX)
    #define RADIX_PASSES        4U      //(Key width) / RADIX_LOG. TODO[DvdB]: make this dynamic so we can sort smaller numbers in less passes.

    #define FLAG_NOT_READY      0       //Flag value inidicating neither inclusive sum, nor reduction of a partition tile is ready
    #define FLAG_REDUCTION      1       //Flag value indicating reduction of a partition tile is ready
    #define FLAG_INCLUSIVE      2       //Flag value indicating inclusive sum of a partition tile is ready
    #define FLAG_MASK           3       //Mask used to retrieve flag values

    //TODO[DvdB]: These should be part of the tweakables
    #define D_DIM               256U    
    #define D_TOTAL_SMEM        4096U

    #define KEYS_PER_THREAD     15U
    #define PART_SIZE           3840U // Keys per thread * threads per thread block
]]

ConstantBuffer( PdxConstantBuffer0 )
{
    uint NumKeys;
    uint RadixShift;
    uint ThreadBlocks;
    uint IsPartial;
};

# Buffer holding device level offsets for each binning pass
RWStructuredBufferTexture GlobalHistogramBuffer
{
	Ref = PdxRWBufferTexture0
    Type = uint
}

# Buffer used to store reduced sums of partition tiles
RWStructuredBufferTexture PassHistogramBuffer
{
	Ref = PdxRWBufferTexture1
    Type = uint
	globallycoherent = yes
}

# Buffer used to atomically assign partition tile indexes
RWStructuredBufferTexture IndexBuffer
{
	Ref = PdxRWBufferTexture2
    Type = uint
	globallycoherent = yes
}

# Buffer either to be sorted or used as sorting keys
RWStructuredBufferTexture SortBufferu
{
	Ref = PdxRWBufferTexture3
    Type = uint
}

RWStructuredBufferTexture SortBufferi
{
	Ref = PdxRWBufferTexture3
    Type = int
}

RWStructuredBufferTexture SortBufferf
{
	Ref = PdxRWBufferTexture3
    Type = float
}

RWStructuredBufferTexture ResultBufferu
{
	Ref = PdxRWBufferTexture4
    Type = uint
}

RWStructuredBufferTexture ResultBufferi
{
	Ref = PdxRWBufferTexture4
    Type = int
}

RWStructuredBufferTexture ResultBufferf
{
	Ref = PdxRWBufferTexture4
    Type = float
}

#
RWStructuredBufferTexture PayloadBufferu
{
	Ref = PdxRWBufferTexture5
    Type = uint
}

RWStructuredBufferTexture PayloadBufferi
{
	Ref = PdxRWBufferTexture5
    Type = int
}

RWStructuredBufferTexture PayloadBufferf
{
	Ref = PdxRWBufferTexture5
    Type = float
}

RWStructuredBufferTexture ResultPayloadBufferu
{
	Ref = PdxRWBufferTexture6
    Type = uint
}

RWStructuredBufferTexture ResultPayloadBufferi
{
	Ref = PdxRWBufferTexture6
    Type = int
}

RWStructuredBufferTexture ResultPayloadBufferf
{
	Ref = PdxRWBufferTexture6
    Type = float
}

Code
[[
    //Radix Tricks by Michael Herf
    //http://stereopsis.com/radix.html
    inline uint FloatToUint( float f )
    {
        uint mask = -( (int) ( asuint( f ) >> 31 ) ) | 0x80000000;
        return asuint( f ) ^ mask;
    }

    inline float UintToFloat( uint u )
    {
        uint mask = ( ( u >> 31 ) - 1 ) | 0x80000000;
        return asfloat( u ^ mask );
    }

    inline uint IntToUint( int i )
    {
        return asuint( i ^ 0x80000000 );
    }

    inline int UintToInt( uint u )
    {
        return asint( u ^ 0x80000000 );
    }
]]

ComputeShader =
{
    # Init does not require flattening
	MainCode CS_InitSweep
	{
		VertexStruct CS_INPUT
		{
			uint3 id : PDX_DispatchThreadID
		};

		Input = "CS_INPUT"
		NumThreads = { 256 1 1 }
		Code
		[[
			PDX_MAIN
			{
                const uint TotalThreadCount = 256 * 256;
                const uint ClearEnd = ThreadBlocks * RADIX * RADIX_PASSES;
                
                for ( uint ThreadIndex = Input.id.x; ThreadIndex < ClearEnd; ThreadIndex += TotalThreadCount )
                {
                    PassHistogramBuffer[ ThreadIndex ] = 0;
                }

                if ( Input.id.x < RADIX * RADIX_PASSES )
                {
                    GlobalHistogramBuffer[ Input.id.x ] = 0;
                }    
                
                if ( Input.id.x < RADIX_PASSES )
                {
                    IndexBuffer[ Input.id.x ] = 0;
                }                    
            }
        ]]
    }
}

Code
[[ 
    static const int G_HIST_DIM = 128U; //The number of threads in a global hist threadblock
    static const int G_HIST_PART_SIZE = 32768U;  //The size of a GlobalHistogram partition tile.

    static const int SEC_RADIX_START = RADIX;           //Offset for retrieving value from global histogram buffer
    static const int THIRD_RADIX_START = RADIX * 2;     //Offset for retrieving value from global histogram buffer
    static const int FOURTH_RADIX_START = RADIX * 3;    //Offset for retrieving value from global histogram buffer
]]

ComputeShader =
{
    MainCode CS_GlobalHistogram
	{
        VertexStruct CS_INPUT
        {
            uint3 GroupThreadId : PDX_GroupThreadID
            uint3 GroupId : PDX_GroupID 
        };

        Input = "CS_INPUT"
        NumThreads = { G_HIST_DIM 1 1 }
        Code
        [[
            static const int GroupHistogramSize = RADIX * 2;
            groupshared uint4 GroupHistogram[ GroupHistogramSize ];

            inline bool isPartialDispatch()
            {
                return IsPartial & 1;
            }

            inline uint flattenGid( uint3 gid )
            {
                // ( IsPartial >> 1 ) is the number of full partitions.
                return isPartialDispatch() ? gid.x + ( IsPartial >> 1 ) * MAX_DISPATCH_DIM : gid.x + gid.y * MAX_DISPATCH_DIM;
            }

            inline uint ExtractDigit( uint key, uint shift )
            {
                return key >> shift & RADIX_MASK;
            }

            // Histogram, 64 threads to a histogram
            inline void HistogramDigitCounts( uint GroupThreadId, uint GroupId )
            {
                const uint HistgramOffset = GroupThreadId / 64 * RADIX; // This is either 0 or 256 ( RADIX )
                const uint PartitionEnd = GroupId == ThreadBlocks - 1 ? NumKeys : ( GroupId + 1 ) * G_HIST_PART_SIZE;
                
                uint t;
                for ( uint i = GroupThreadId + GroupId * G_HIST_PART_SIZE; i < PartitionEnd; i += G_HIST_DIM )
                {
            #if defined( KEY_UINT )
                    t = SortBufferu[ i ];
            #elif defined( KEY_INT )
                    t = IntToUint( SortBufferi[ i ] );
            #elif defined( KEY_FLOAT )
                    t = FloatToUint( SortBufferf[ i ] );
            #endif
                    InterlockedAdd( GroupHistogram[ ExtractDigit( t, 0 ) + HistgramOffset ].x, 1 );
                    InterlockedAdd( GroupHistogram[ ExtractDigit( t, 8 ) + HistgramOffset ].y, 1 );
                    InterlockedAdd( GroupHistogram[ ExtractDigit( t, 16 ) + HistgramOffset ].z, 1 );
                    InterlockedAdd( GroupHistogram[ ExtractDigit( t, 24 ) + HistgramOffset ].w, 1 );
                }
            }

            //reduce counts and atomically add to device
            inline void ReduceWriteDigitCounts( uint GroupThreadId )
            {
                for ( uint i = GroupThreadId; i < RADIX; i += G_HIST_DIM )
                {
                    InterlockedAdd( GlobalHistogramBuffer[ i ], GroupHistogram[ i ].x + GroupHistogram[ i + RADIX ].x );
                    InterlockedAdd( GlobalHistogramBuffer[ i + SEC_RADIX_START ], GroupHistogram[ i ].y + GroupHistogram[ i + RADIX ].y );
                    InterlockedAdd( GlobalHistogramBuffer[ i + THIRD_RADIX_START ], GroupHistogram[ i ].z + GroupHistogram[ i + RADIX ].z );
                    InterlockedAdd( GlobalHistogramBuffer[ i + FOURTH_RADIX_START ], GroupHistogram[ i ].w + GroupHistogram[ i + RADIX ].w );
                }
            }

            PDX_MAIN
            {
                //clear shared memory
                for ( uint i = Input.GroupThreadId.x; i < GroupHistogramSize; i += G_HIST_DIM )
                {
                    GroupHistogram[ i ] = 0;
                }
                GroupMemoryBarrierWithGroupSync();
                
                HistogramDigitCounts( Input.GroupThreadId.x, flattenGid( Input.GroupId ) );
                GroupMemoryBarrierWithGroupSync();
                
                ReduceWriteDigitCounts( Input.GroupThreadId.x );
            }
        ]]
    }
}

# Note: When debugging the buffer might look strange at first glance, but that is because the values are shifted 2 to the left and a flag is or'ed into it.
ComputeShader =
{
    MainCode CS_Scan
	{
        VertexStruct CS_INPUT
        {
            uint3 GroupThreadId : PDX_GroupThreadID
            uint3 GroupId : PDX_GroupID 
        };

        Input = "CS_INPUT"
        NumThreads = { RADIX 1 1 }
        Code
        [[
            groupshared uint GroupScan[ RADIX ];

            inline void LoadInclusiveScan( uint GroupThreadId, uint GroupId )
            {
                const uint t = GlobalHistogramBuffer[ GroupThreadId + GroupId * RADIX ];
                GroupScan[ GroupThreadId ] = t + WavePrefixSum( t );
            }

            inline void GlobalHistExclusiveScan( uint GroupThreadId, uint GroupId )
            {
                GroupMemoryBarrierWithGroupSync();

                //TODO[DvdB]: What does this actually do? :thinking:
                if ( GroupThreadId < ( RADIX / WaveGetLaneCount() ) )
                {
                    GroupScan[ ( GroupThreadId + 1 ) * WaveGetLaneCount() - 1 ] += WavePrefixSum( GroupScan[ ( GroupThreadId + 1 ) * WaveGetLaneCount() - 1 ] );
                }

                GroupMemoryBarrierWithGroupSync();

                const uint LaneMask = WaveGetLaneCount() - 1;
                //TODO[DvdB]: Can't ( WaveGetLaneIndex() + 1 & LaneMask ) be replaced by ( WaveGetLaneIndex() )?
                // ( GroupThreadId & ~LaneMask ) is always a multiple of WaveGetLaneCount()
                const uint Index = ( WaveGetLaneIndex() + 1 & LaneMask ) + ( GroupThreadId & ~LaneMask );
                PassHistogramBuffer[ Index + GroupId * RADIX * ThreadBlocks ] = ( ( WaveGetLaneIndex() != LaneMask ? GroupScan[ GroupThreadId ] : 0) + ( GroupThreadId >= WaveGetLaneCount() ? WaveReadLaneAt( GroupScan[ GroupThreadId - 1 ], 0 ) : 0 ) ) << 2 | FLAG_INCLUSIVE;
            }
            
            PDX_MAIN
            {
                //Scan does not require flattening
                LoadInclusiveScan( Input.GroupThreadId.x, Input.GroupId.x );    
                GlobalHistExclusiveScan( Input.GroupThreadId.x, Input.GroupId.x );                                  
            }
        ]]
    }
}

ComputeShader =
{
    MainCode CS_DigitBinning
	{
        VertexStruct CS_INPUT
        {
            uint3 GroupThreadId : PDX_GroupThreadID
        };

        Input = "CS_INPUT"
        NumThreads = { D_DIM 1 1 }
        Code
        [[
            groupshared uint GroupDigitBinning[ D_TOTAL_SMEM ]; //Shared memory for DigitBinningPass and DownSweep kernels

            struct KeyStruct
            {
                uint k[ KEYS_PER_THREAD ];
            };

            struct OffsetStruct
            {
                uint o[ KEYS_PER_THREAD ];
            };

            struct DigitStruct
            {
                uint d[ KEYS_PER_THREAD ];
            };

            inline uint WaveHistsSizeWGE16()
            {
                return D_DIM / WaveGetLaneCount() * RADIX;
            }

            inline void ClearWaveHists( uint GroupThreadId )
            {
                const uint HistsEnd = WaveHistsSizeWGE16();
                for ( uint i = GroupThreadId; i < HistsEnd; i += D_DIM )
                {
                    GroupDigitBinning[ i ] = 0;
                }                    
            }

            // Which 8 bits of the key are we processing.
            inline uint CurrentPass()
            {
                return RadixShift >> 3;
            }

            inline void AssignPartitionTile( uint GroupThreadId, inout uint PartitionIndex )
            {
                if ( GroupThreadId == 0 )
                {
                    InterlockedAdd( IndexBuffer[ CurrentPass() ], 1, GroupDigitBinning[ D_TOTAL_SMEM - 1 ] );
                }
                    
                GroupMemoryBarrierWithGroupSync();
                PartitionIndex = GroupDigitBinning[ D_TOTAL_SMEM - 1 ];
            }

            inline uint getWaveIndex( uint GroupThreadId )
            {
                return GroupThreadId / WaveGetLaneCount();
            }

            inline uint SubPartSizeWGE16()
            {
                return KEYS_PER_THREAD * WaveGetLaneCount();
            }

            inline uint SharedOffsetWGE16( uint GroupThreadId )
            {
                return WaveGetLaneIndex() + getWaveIndex( GroupThreadId ) * SubPartSizeWGE16();
            }

            inline uint DeviceOffsetWGE16( uint GroupThreadId, uint PartitionIndex )
            {
                return SharedOffsetWGE16( GroupThreadId ) + PartitionIndex * PART_SIZE;
            }

            inline void LoadKey( inout uint key, uint index )
            {
            #if defined( KEY_UINT )
                key = SortBufferu[ index ];
            #elif defined( KEY_INT )
                key = UintToInt( SortBufferi[ index ] );
            #elif defined( KEY_FLOAT )
                key = FloatToUint( SortBufferf[ index ] );
            #endif
            }

            inline void LoadDummyKey( inout uint key )
            {
                key = 0xffffffff;
            }

            inline KeyStruct LoadKeysWGE16( uint GroupThreadId, uint PartitionIndex )
            {
                KeyStruct keys;
                [unroll]
                for ( uint i = 0, t = DeviceOffsetWGE16( GroupThreadId, PartitionIndex ); i < KEYS_PER_THREAD; ++i, t += WaveGetLaneCount() )
                {
                    LoadKey( keys.k[ i ], t );
                }
                return keys;
            }

            inline KeyStruct LoadKeysPartialWGE16( uint GroupThreadId, uint PartitionIndex )
            {
                KeyStruct keys;
                [unroll]
                for ( uint i = 0, t = DeviceOffsetWGE16( GroupThreadId, PartitionIndex ); i < KEYS_PER_THREAD; ++i, t += WaveGetLaneCount() )
                {
                    if ( t < NumKeys )
                    {
                        LoadKey( keys.k[ i ], t );
                    }
                    else
                    {
                        LoadDummyKey( keys.k[ i ] );
                    }                        
                }
                return keys;
            }

            inline uint WaveFlagsWGE16()
            {
                // If WaveGetLaneCount is a multiple of 32 use 0xffffffff else ( 1 << WaveGetLaneCount ) - 1
                return ( WaveGetLaneCount() & 31 ) ? ( 1U << WaveGetLaneCount() ) - 1 : 0xffffffff;
            }

            inline void WarpLevelMultiSplitWGE16( uint key, uint waveParts, inout uint4 waveFlags )
            {
                [unroll]
                for ( uint k = 0; k < RADIX_LOG; ++k )
                {
                    const bool t = key >> ( k + RadixShift ) & 1;
                    const uint4 ballot = WaveActiveBallot(t);
                    for ( uint wavePart = 0; wavePart < waveParts; ++wavePart )
                    {
                        waveFlags[ wavePart ] &= ( t ? 0 : 0xffffffff ) ^ ballot[ wavePart ];
                    }
                }
            }

            inline uint ExtractDigit(uint key)
            {
                return key >> RadixShift & RADIX_MASK;
            }

            inline uint FindLowestRankPeer( uint4 waveFlags, uint waveParts )
            {
                uint lowestRankPeer = 0;
                for ( uint wavePart = 0; wavePart < waveParts; ++wavePart )
                {
                    uint fbl = firstbitlow( waveFlags[ wavePart ] );
                    if ( fbl == 0xffffffff )
                    {
                        lowestRankPeer += 32;
                    }            
                    else
                    {
                        return lowestRankPeer + fbl;
                    }            
                }
                return 0; //will never happen
            }

            inline void CountPeerBits( inout uint peerBits, inout uint totalBits, uint4 waveFlags, uint waveParts )
            {
                for (uint wavePart = 0; wavePart < waveParts; ++wavePart)
                {
                    if ( WaveGetLaneIndex() >= wavePart * 32 )
                    {
                        const uint ltMask = WaveGetLaneIndex() >= ( wavePart + 1 ) * 32 ? 0xffffffff : ( 1U << ( WaveGetLaneIndex() & 31 ) ) - 1;
                        peerBits += countbits( waveFlags[ wavePart ] & ltMask );
                    }
                    totalBits += countbits( waveFlags[ wavePart ] );
                }
            }

            inline OffsetStruct RankKeysWGE16( uint GroupThreadId, KeyStruct keys )
            {
                OffsetStruct offsets;
                const uint waveParts = ( WaveGetLaneCount() + 31 ) / 32; //CeilingDivide
                [unroll]
                for ( uint i = 0; i < KEYS_PER_THREAD; ++i )
                {
                    uint4 waveFlags = WaveFlagsWGE16(); // bit set for each lane
                    WarpLevelMultiSplitWGE16( keys.k[i], waveParts, waveFlags );
                    
                    const uint index = ExtractDigit( keys.k[i]) + ( getWaveIndex( GroupThreadId ) * RADIX );
                    const uint lowestRankPeer = FindLowestRankPeer( waveFlags, waveParts );
                    
                    uint peerBits = 0;
                    uint totalBits = 0;
                    CountPeerBits( peerBits, totalBits, waveFlags, waveParts );
                    
                    uint preIncrementVal;
                    if ( peerBits == 0 )
                    {
                        InterlockedAdd( GroupDigitBinning[ index ], totalBits, preIncrementVal );
                    }
                        
                    offsets.o[ i ] = WaveReadLaneAt( preIncrementVal, lowestRankPeer ) + peerBits;
                }
                
                return offsets;
            }

            inline uint WaveHistInclusiveScanCircularShiftWGE16( uint GroupThreadId )
            {
                uint histReduction = GroupDigitBinning[ GroupThreadId ];
                for ( uint i = GroupThreadId + RADIX; i < WaveHistsSizeWGE16(); i += RADIX )
                {
                    histReduction += GroupDigitBinning[ i ];
                    GroupDigitBinning[ i ] = histReduction - GroupDigitBinning[ i ];
                }
                return histReduction;
            }

            inline uint PassHistOffset( uint index )
            {
                return ( ( CurrentPass() * ThreadBlocks) + index ) << RADIX_LOG;
            }

            inline void DeviceBroadcastReductionsWGE16( uint GroupThreadId, uint partIndex, uint histReduction )
            {
                if ( partIndex < ThreadBlocks - 1 )
                {
                    InterlockedAdd( PassHistogramBuffer[ GroupThreadId + PassHistOffset( partIndex + 1 ) ], FLAG_REDUCTION | histReduction << 2 );
                }
            }

            inline void WaveHistReductionExclusiveScanWGE16( uint GroupThreadId, uint histReduction )
            {
                if ( GroupThreadId < RADIX )
                {
                    const uint laneMask = WaveGetLaneCount() - 1;
                    GroupDigitBinning[ ( ( WaveGetLaneIndex() + 1 ) & laneMask ) + ( GroupThreadId & ~laneMask ) ] = histReduction;
                }
                GroupMemoryBarrierWithGroupSync();
                            
                if ( GroupThreadId < RADIX / WaveGetLaneCount() )
                {
                    GroupDigitBinning[ GroupThreadId * WaveGetLaneCount() ] = WavePrefixSum( GroupDigitBinning[ GroupThreadId * WaveGetLaneCount() ] );
                }
                GroupMemoryBarrierWithGroupSync();
                            
                if ( GroupThreadId < RADIX && WaveGetLaneIndex() )
                {
                    GroupDigitBinning[ GroupThreadId ] += WaveReadLaneAt( GroupDigitBinning[ GroupThreadId - 1 ], 1 );
                }                    
            }

            inline void UpdateOffsetsWGE16( uint GroupThreadId, inout OffsetStruct offsets, KeyStruct keys )
            {
                if ( GroupThreadId >= WaveGetLaneCount() )
                {
                    const uint t = getWaveIndex( GroupThreadId ) * RADIX;
                    [unroll]
                    for ( uint i = 0; i < KEYS_PER_THREAD; ++i )
                    {
                        const uint t2 = ExtractDigit( keys.k[ i ] );
                        offsets.o[i] += GroupDigitBinning[ t2 + t ] + GroupDigitBinning[ t2 ];
                    }
                }
                else
                {
                    [unroll]
                    for ( uint i = 0; i < KEYS_PER_THREAD; ++i )
                    {
                        offsets.o[ i ] += GroupDigitBinning[ ExtractDigit( keys.k[ i ] ) ];
                    }                        
                }
            }

            inline void ScatterKeysShared( OffsetStruct offsets, KeyStruct keys )
            {
                [unroll]
                for (uint i = 0; i < KEYS_PER_THREAD; ++i)
                {
                    GroupDigitBinning[ offsets.o[ i ] ] = keys.k[ i ];
                }
            }            
            
            inline void Lookback( uint GroupThreadId, uint partIndex, uint exclusiveHistReduction )
            {
                if ( GroupThreadId < RADIX )
                {
                    uint lookbackReduction = 0;
                    for ( uint k = partIndex; k >= 0; )
                    {
                        const uint flagPayload = PassHistogramBuffer[ GroupThreadId + PassHistOffset( k ) ];
                        if ( ( flagPayload & FLAG_MASK ) == FLAG_INCLUSIVE )
                        {
                            lookbackReduction += flagPayload >> 2;
                            if ( partIndex < ThreadBlocks - 1 )
                            {
                                InterlockedAdd( PassHistogramBuffer[ GroupThreadId + PassHistOffset( partIndex + 1 ) ], 1 | lookbackReduction << 2 );
                            }
                            GroupDigitBinning[ GroupThreadId + PART_SIZE ] = lookbackReduction - exclusiveHistReduction;
                            break;
                        }
                                
                        if ( ( flagPayload & FLAG_MASK ) == FLAG_REDUCTION )
                        {
                            lookbackReduction += flagPayload >> 2;
                            k--;
                        }
                    }
                }
            }

            inline void WriteKey( uint deviceIndex, uint groupSharedIndex )
            {
            #if defined( KEY_UINT )
                ResultBufferu[ deviceIndex ] = GroupDigitBinning[ groupSharedIndex ];
            #elif defined( KEY_INT )
              ResultBufferi[ deviceIndex ] = UintToInt( GroupDigitBinning[ groupSharedIndex ] );
            #elif defined( KEY_FLOAT )
              ResultBufferf[ deviceIndex ] = UintToFloat( GroupDigitBinning[ groupSharedIndex ] );
            #endif
            }

            inline void ScatterKeysOnlyDeviceAscending( uint gtid )
            {
                for (uint i = gtid; i < PART_SIZE; i += D_DIM)
                {
                    WriteKey( GroupDigitBinning[ ExtractDigit( GroupDigitBinning[ i ] ) + PART_SIZE ] + i, i );
                }                    
            }

            inline uint DescendingIndex( uint deviceIndex )
            {
                return NumKeys - deviceIndex - 1;
            }

            inline void ScatterKeysOnlyDeviceDescending( uint gtid )
            {
                if( RadixShift == 24 ) //TODO[DvdB]: Only the last pass does descending, when we add support for less than 32 bit keys we need to make sure we change this value!
                {
                    for ( uint i = gtid; i < PART_SIZE; i += D_DIM )
                    {
                        WriteKey( DescendingIndex( GroupDigitBinning[ ExtractDigit( GroupDigitBinning[ i ] ) + PART_SIZE ] + i ), i );
                    }                        
                }
                else
                {
                    ScatterKeysOnlyDeviceAscending( gtid );
                }
            }

            inline void ScatterKeysOnlyDevice( uint gtid )
            {
            #if defined( SHOULD_ASCEND )
                ScatterKeysOnlyDeviceAscending( gtid );
            #else
                ScatterKeysOnlyDeviceDescending( gtid );
            #endif
            }

            inline void ScatterPairsKeyPhaseAscending( uint gtid, inout DigitStruct digits )
            {
                [unroll]
                for ( uint i = 0, t = gtid; i < KEYS_PER_THREAD; ++i, t += D_DIM )
                {
                    digits.d[ i ] = ExtractDigit( GroupDigitBinning[ t ] );
                    WriteKey( GroupDigitBinning[digits.d[ i ] + PART_SIZE ] + t, t );
                }
            }

            inline void ScatterPairsKeyPhaseDescending( uint gtid, inout DigitStruct digits )
            {
                if ( RadixShift == 24 ) //TODO[DvdB]: Only the last pass does descending, when we add support for less than 32 bit keys we need to make sure we change this value!
                {
                    [unroll]
                    for ( uint i = 0, t = gtid; i < KEYS_PER_THREAD; ++i, t += D_DIM )
                    {
                        digits.d[ i ] = ExtractDigit( GroupDigitBinning[ t ] );
                        WriteKey( DescendingIndex( GroupDigitBinning[ digits.d[ i ] + PART_SIZE ] + t ), t );
                    }
                }
                else
                {
                    ScatterPairsKeyPhaseAscending( gtid, digits );
                }
            }

            inline void LoadPayload( inout uint payload, uint deviceIndex )
            {
            #if defined( PAYLOAD_UINT )
                payload = PayloadBufferu[ deviceIndex ];
            #elif defined( PAYLOAD_INT)
                payload = asuint( PayloadBufferi[ deviceIndex ] );
            #elif defined( PAYLOAD_FLOAT )
                payload = asuint( PayloadBufferf[ deviceIndex ] );
            #endif
            }

            inline void LoadPayloadsWGE16( uint gtid, uint partIndex, inout KeyStruct payloads )
            {
                [unroll]
                for ( uint i = 0, t = DeviceOffsetWGE16( gtid, partIndex ); i < KEYS_PER_THREAD; ++i, t += WaveGetLaneCount() )
                {
                    LoadPayload( payloads.k[ i ], t );
                }
            }

            inline void ScatterPayloadsShared( OffsetStruct offsets, KeyStruct payloads )
            {
                ScatterKeysShared( offsets, payloads );
            }

            inline void WritePayload( uint deviceIndex, uint groupSharedIndex )
            {
            #if defined( PAYLOAD_UINT )
                ResultPayloadBufferu[ deviceIndex ] = GroupDigitBinning[ groupSharedIndex ];
            #elif defined( PAYLOAD_INT )
                ResultPayloadBufferi[ deviceIndex ] = asint( GroupDigitBinning[ groupSharedIndex ] );
            #elif defined( PAYLOAD_FLOAT )
                ResultPayloadBufferf[ deviceIndex ] = asfloat( GroupDigitBinning[ groupSharedIndex ] );
            #endif
            }

            inline void ScatterPayloadsAscending(uint gtid, DigitStruct digits)
            {
                [unroll]
                for ( uint i = 0, t = gtid; i < KEYS_PER_THREAD; ++i, t += D_DIM )
                {
                    WritePayload( GroupDigitBinning[ digits.d[ i ] + PART_SIZE ] + t, t );
                }
                    
            }

            inline void ScatterPayloadsDescending(uint gtid, DigitStruct digits)
            {
                if ( RadixShift == 24 ) //TODO[DvdB]: Only the last pass does descending, when we add support for less than 32 bit keys we need to make sure we change this value!
                {
                    [unroll]
                    for ( uint i = 0, t = gtid; i < KEYS_PER_THREAD; ++i, t += D_DIM )
                    {
                        WritePayload( DescendingIndex( GroupDigitBinning[ digits.d[ i ] + PART_SIZE] + t ), t );
                    }                        
                }
                else
                {
                    ScatterPayloadsAscending( gtid, digits );
                }
            }

            inline void ScatterPairsDevice( uint gtid, uint partIndex, OffsetStruct offsets )
            {
                DigitStruct digits;
            #if defined( SHOULD_ASCEND )
                ScatterPairsKeyPhaseAscending( gtid, digits );
            #else
                ScatterPairsKeyPhaseDescending( gtid, digits );
            #endif
                GroupMemoryBarrierWithGroupSync();
                
                KeyStruct payloads;
                LoadPayloadsWGE16( gtid, partIndex, payloads );
                ScatterPayloadsShared( offsets, payloads );
                GroupMemoryBarrierWithGroupSync();
                
            #if defined( SHOULD_ASCEND )
                ScatterPayloadsAscending( gtid, digits );
            #else
                ScatterPayloadsDescending( gtid, digits );
            #endif
            }

            inline void ScatterDevice( uint gtid, uint partIndex, OffsetStruct offsets) 
            {
            #if defined( SORT_PAIRS )
               ScatterPairsDevice( gtid, partIndex, offsets );
            #else
                ScatterKeysOnlyDevice( gtid );
            #endif
            }

            inline void ScatterKeysOnlyDevicePartialAscending( uint gtid, uint finalPartSize )
            {
                for ( uint i = gtid; i < PART_SIZE; i += D_DIM )
                {
                    if ( i < finalPartSize )
                    {
                        WriteKey( GroupDigitBinning[ ExtractDigit( GroupDigitBinning[ i ] ) + PART_SIZE ] + i, i );
                    }                        
                }
            }

            inline void ScatterKeysOnlyDevicePartialDescending(uint gtid, uint finalPartSize)
            {
                if ( RadixShift == 24 ) //TODO[DvdB]: Only the last pass does descending, when we add support for less than 32 bit keys we need to make sure we change this value!
                {
                    for ( uint i = gtid; i < PART_SIZE; i += D_DIM )
                    {
                        if ( i < finalPartSize )
                        {
                            WriteKey( DescendingIndex( GroupDigitBinning[ ExtractDigit( GroupDigitBinning[ i ] ) + PART_SIZE ] + i ), i );
                        }                            
                    }
                }
                else
                {
                    ScatterKeysOnlyDevicePartialAscending( gtid, finalPartSize );
                }
            }

            inline void ScatterKeysOnlyDevicePartial( uint gtid, uint partIndex )
            {
                const uint finalPartSize = NumKeys - partIndex * PART_SIZE;
            #if defined( SHOULD_ASCEND )
                ScatterKeysOnlyDevicePartialAscending( gtid, finalPartSize );
            #else
                ScatterKeysOnlyDevicePartialDescending( gtid, finalPartSize );
            #endif
            }

            inline void ScatterPairsKeyPhaseAscendingPartial( uint gtid, uint finalPartSize, inout DigitStruct digits )
            {
                [unroll]
                for ( uint i = 0, t = gtid; i < KEYS_PER_THREAD; ++i, t += D_DIM )
                {
                    if( t < finalPartSize )
                    {
                        digits.d[ i ] = ExtractDigit( GroupDigitBinning[ t ] );
                        WriteKey( GroupDigitBinning[ digits.d[ i ] + PART_SIZE ] + t, t );
                    }
                }
            }

            inline void ScatterPairsKeyPhaseDescendingPartial( uint gtid, uint finalPartSize, inout DigitStruct digits )
            {
                if ( RadixShift == 24 ) //TODO[DvdB]: Only the last pass does descending, when we add support for less than 32 bit keys we need to make sure we change this value!
                {
                    [unroll]
                    for ( uint i = 0, t = gtid; i < KEYS_PER_THREAD; ++i, t += D_DIM )
                    {
                        if ( t < finalPartSize )
                        {
                            digits.d[ i ] = ExtractDigit( GroupDigitBinning[ t ] );
                            WriteKey( DescendingIndex( GroupDigitBinning[ digits.d[ i ] + PART_SIZE ] + t ), t );
                        }
                    }
                }
                else
                {
                    ScatterPairsKeyPhaseAscendingPartial( gtid, finalPartSize, digits );
                }
            }

            inline void LoadPayloadsPartialWGE16( uint gtid, uint partIndex, inout KeyStruct payloads )
            {
                [unroll]
                for (uint i = 0, t = DeviceOffsetWGE16( gtid, partIndex ); i < KEYS_PER_THREAD; ++i, t += WaveGetLaneCount() )
                {
                    if (t < NumKeys)
                    {
                        LoadPayload( payloads.k[ i ], t );
                    }                        
                }
            }

            inline void ScatterPayloadsAscendingPartial( uint gtid, uint finalPartSize, DigitStruct digits )
            {
                [unroll]
                for ( uint i = 0, t = gtid; i < KEYS_PER_THREAD; ++i, t += D_DIM )
                {
                    if ( t < finalPartSize )
                    {
                        WritePayload( GroupDigitBinning[ digits.d[ i ] + PART_SIZE ] + t, t );
                    }                        
                }
            }

            inline void ScatterPayloadsDescendingPartial( uint gtid, uint finalPartSize, DigitStruct digits )
            {
                if ( RadixShift == 24 ) //TODO[DvdB]: Only the last pass does descending, when we add support for less than 32 bit keys we need to make sure we change this value!
                {
                    [unroll]
                    for ( uint i = 0, t = gtid; i < KEYS_PER_THREAD; ++i, t += D_DIM )
                    {
                        if ( t < finalPartSize )
                        {
                            WritePayload( DescendingIndex( GroupDigitBinning[ digits.d[ i ] + PART_SIZE ] + t ), t );
                        }                            
                    }
                }
                else
                {
                    ScatterPayloadsAscendingPartial( gtid, finalPartSize, digits );
                }
            }

            inline void ScatterPairsDevicePartial( uint gtid, uint partIndex, OffsetStruct offsets )
            {
                DigitStruct digits;
                const uint finalPartSize = NumKeys - partIndex * PART_SIZE;
            #if defined( SHOULD_ASCEND )
                ScatterPairsKeyPhaseAscendingPartial( gtid, finalPartSize, digits );
            #else
                ScatterPairsKeyPhaseDescendingPartial( gtid, finalPartSize, digits );
            #endif
                GroupMemoryBarrierWithGroupSync();
                
                KeyStruct payloads;
                LoadPayloadsPartialWGE16( gtid, partIndex, payloads );
                ScatterPayloadsShared( offsets, payloads );
                GroupMemoryBarrierWithGroupSync();
                
            #if defined( SHOULD_ASCEND )
                ScatterPayloadsAscendingPartial( gtid, finalPartSize, digits );
            #else
                ScatterPayloadsDescendingPartial( gtid, finalPartSize, digits );
            #endif
            }

            inline void ScatterDevicePartial( uint gtid, uint partIndex, OffsetStruct offsets )
            {
            #if defined( SORT_PAIRS )
                ScatterPairsDevicePartial( gtid, partIndex, offsets );
            #else
                ScatterKeysOnlyDevicePartial( gtid, partIndex );
            #endif
            }

            PDX_MAIN
            {   
                uint PartitionIndex;
                KeyStruct keys;
                OffsetStruct offsets;

                if ( WaveHistsSizeWGE16() < PART_SIZE )
                {
                    ClearWaveHists( Input.GroupThreadId.x );
                }

                AssignPartitionTile( Input.GroupThreadId.x, PartitionIndex );
                if ( WaveHistsSizeWGE16() >= PART_SIZE )
                {
                    GroupMemoryBarrierWithGroupSync();
                    ClearWaveHists( Input.GroupThreadId.x );
                    GroupMemoryBarrierWithGroupSync();
                }
            
                if ( PartitionIndex < ThreadBlocks - 1 )
                {
                    keys = LoadKeysWGE16( Input.GroupThreadId.x, PartitionIndex );
                }
                    
                if ( PartitionIndex == ThreadBlocks - 1 )
                {
                    keys = LoadKeysPartialWGE16( Input.GroupThreadId.x, PartitionIndex );
                }
                
                uint ExclusiveHistReduction;
                offsets = RankKeysWGE16( Input.GroupThreadId.x, keys );
                GroupMemoryBarrierWithGroupSync();
                
                uint histReduction;
                if ( Input.GroupThreadId.x < RADIX )
                {
                    histReduction = WaveHistInclusiveScanCircularShiftWGE16( Input.GroupThreadId.x );
                    DeviceBroadcastReductionsWGE16( Input.GroupThreadId.x, PartitionIndex, histReduction );
                    histReduction += WavePrefixSum( histReduction ); //take advantage of barrier to begin scan
                }
                GroupMemoryBarrierWithGroupSync();

                WaveHistReductionExclusiveScanWGE16( Input.GroupThreadId.x, histReduction );
                GroupMemoryBarrierWithGroupSync();
                    
                UpdateOffsetsWGE16( Input.GroupThreadId.x, offsets, keys );
                if ( Input.GroupThreadId.x < RADIX )
                {
                    ExclusiveHistReduction = GroupDigitBinning[ Input.GroupThreadId.x ]; //take advantage of barrier to grab value
                }
                GroupMemoryBarrierWithGroupSync();
                
                ScatterKeysShared( offsets, keys );
                Lookback( Input.GroupThreadId.x, PartitionIndex, ExclusiveHistReduction );
                GroupMemoryBarrierWithGroupSync();
                
                if ( PartitionIndex < ThreadBlocks - 1 )
                {
                    ScatterDevice( Input.GroupThreadId.x, PartitionIndex, offsets );
                }
                    
                if ( PartitionIndex == ThreadBlocks - 1 )
                {
                    ScatterDevicePartial( Input.GroupThreadId.x, PartitionIndex, offsets ); 
                }                                               
            }
        ]]
    }
}

Effect Init
{
	ComputeShader = "CS_InitSweep"
}

Effect CreateGlobalHistogram
{
	ComputeShader = "CS_GlobalHistogram"
}

Effect Scan
{
	ComputeShader = "CS_Scan"
}

Effect DigitBinning
{
	ComputeShader = "CS_DigitBinning"
}
