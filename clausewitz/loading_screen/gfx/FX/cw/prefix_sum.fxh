#/******************************************************************************
# * GPUPrefixSums
# * Chained Scan with Decoupled Lookback Implementation
# *
# * SPDX-License-Identifier: MIT
# * Copyright Thomas Smith 3/5/2024
# * https://github.com/b0nes164/GPUPrefixSums
# *
# * Based off of Research by:
# *          Duane Merrill, Nvidia Corporation
# *          Michael Garland, Nvidia Corporation
# *          https://research.nvidia.com/publication/2016-03_single-pass-parallel-prefix-scan-decoupled-look-back
# * 
# ******************************************************************************/

Includes = {
	"cw/miscmath.fxh"
}

Code
[[
    #define MAX_DISPATCH_DIM                    65535U
    #define NUM_UINT4_ELEMENTS_IN_PARTITION     768U
    #define NUM_THREADS_IN_GROUP                256U
    #define NUM_UINT4_ELEMENTS_PER_THREAD       3U
    #define MIN_WAVE_SIZE                       4U
    #define WAVE_PART_SIZE                      32U

    #define MAX_SPIN_COUNT                      8U

    #define FLAG_NOT_READY  0           //Flag indicating this partition tile's local reduction is not ready
    #define FLAG_REDUCTION  1           //Flag indicating this partition tile's local reduction is ready
    #define FLAG_INCLUSIVE  2           //Flag indicating this partition tile has summed all preceding tiles and added to its sum.
    #define FLAG_MASK       3           //Mask used to retrieve the flag (= 0b11)
]]

ConstantBuffer( PdxConstantBuffer0 )
{
    uint _VectorizedInputSize;
    uint _PartitionCount;
    uint _Pad0;
    uint _Pad1;
};

# Input buffer has type uint instead of uint4 because compaction could write to the same uint4 from different cores which would result in wrong results.
RWBufferTexture RWInputBuffer
{
    Ref = PdxRWBufferTexture0
    Type = uint
}

RWStructuredBufferTexture PartitionIndexBuffer
{
    Ref = PdxRWBufferTexture1
    Type = uint
    globallycoherent = yes
}

RWStructuredBufferTexture PartitionReductionsBuffer
{
    Ref = PdxRWBufferTexture2
    Type = uint
    globallycoherent = yes
}

RWBufferTexture RWIndexOutputBuffer
{
    Ref = PdxRWBufferTexture3
    Type = uint
}

Code
[[

// Compaction uses exclusive prefix sum
#ifdef PREFIX_SUM_COMPACTION
#define PREFIX_SUM_EXCLUSIVE
#endif

    // Wave-local prefix sums for all the elements in a given partition
    groupshared uint4 GS_PartitionWavePrefixSums[ NUM_UINT4_ELEMENTS_IN_PARTITION ];

#ifdef PREFIX_SUM_COMPACTION
    // Input elements to be compacted stored in groupshared memory
    groupshared uint4 GS_PartitionInputElements[ NUM_UINT4_ELEMENTS_IN_PARTITION ];
#endif

    // Total sum of all elements for every wave in a given partition
    groupshared uint GS_WaveReductions[ NUM_THREADS_IN_GROUP / MIN_WAVE_SIZE ];

    groupshared uint GS_PartitionIndex;
    groupshared uint GS_PrevPartitionsReduction;

#ifdef PREFIX_SUM_FALLBACK
    groupshared bool GS_FallbackNeeded;
    groupshared uint GS_FallbackPrevPartitionIndex;
    groupshared uint GS_FallbackWaveReductions[ NUM_THREADS_IN_GROUP / MIN_WAVE_SIZE ];
#endif

    inline uint GetWaveIndex( uint GroupThreadID )
    {
        return GroupThreadID / WaveGetLaneCount();
    }

    inline uint GetPartitionStartElementIndex( uint PartitionIndex )
    {
        return PartitionIndex * NUM_UINT4_ELEMENTS_IN_PARTITION;
    }

    inline uint GetWaveStartElementIndexInPartition( uint GroupThreadID )
    {
        const uint WaveWorkingSetSize = NUM_UINT4_ELEMENTS_PER_THREAD * WaveGetLaneCount();
        return GetWaveIndex( GroupThreadID ) * WaveWorkingSetSize;
    }

    // ( x, y, z, w ) -> ( x, x+y, x+y+z, x+y+z+w )
    inline uint4 CalcInclusivePrefixSumUint4( uint4 Value )
    {
        Value.y += Value.x;
        Value.z += Value.y;
        Value.w += Value.z;

        return Value;
    }

    // This function calculates exclusive prefix sums for a partition and fills 2 groupshared arrays:
    // - GS_PartitionWavePrefixSums[ NumElements ]: stores wave-local prefix sum for every element in a partition
    // - GS_WaveReductions[ NumWaves ]: stores total sum of all elements (reduction) for every wave
    inline void PartitionScan( uint GroupThreadID, uint PartitionIndex )
    {
        uint WaveReduction = 0;
        uint ElementIndex = GetWaveStartElementIndexInPartition( GroupThreadID ) + WaveGetLaneIndex();

        [unroll]
        for ( uint i = 0; i < NUM_UINT4_ELEMENTS_PER_THREAD; ++i )
        {
            uint4 LocalPrefixSums = 0;

            const uint GlobalElementIndex = GetPartitionStartElementIndex( PartitionIndex ) + ElementIndex;
            if ( GlobalElementIndex < _VectorizedInputSize )
            {
                uint4 InputValues;
                
                const uint GlobalElementIndexScalar = GlobalElementIndex * 4;
                InputValues.x = RWInputBuffer[ GlobalElementIndexScalar ];
                InputValues.y = RWInputBuffer[ GlobalElementIndexScalar + 1 ];
                InputValues.z = RWInputBuffer[ GlobalElementIndexScalar + 2 ];
                InputValues.w = RWInputBuffer[ GlobalElementIndexScalar + 3 ];

#ifdef PREFIX_SUM_COMPACTION
                // Read input values and store them in groupshared memory
                GS_PartitionInputElements[ ElementIndex ] = InputValues;

                // RWInputBuffer stores zeros for elements we want to be removed after compaction.
                // Compaction itself is done with a prefix sum of the array of binary flags
                //   where 1 indicates that the element should be preserved and 0 - that the element should be dropped.
                // Here we clamp non-zero input values to 1 to get this array of binary flags.
                InputValues = clamp( InputValues, 0, 1 );

#ifdef PREFIX_SUM_DEBUG
                //Write 0's to the input buffer so we can verify everything functions correctly.
                RWInputBuffer[ GlobalElementIndexScalar ] = 0;
                RWInputBuffer[ GlobalElementIndexScalar + 1 ] = 0;
                RWInputBuffer[ GlobalElementIndexScalar + 2 ] = 0;
                RWInputBuffer[ GlobalElementIndexScalar + 3 ] = 0;
#endif
#endif

                LocalPrefixSums = CalcInclusivePrefixSumUint4( InputValues );
            }

            const uint PrevLanesSum = WavePrefixSum( LocalPrefixSums.w );

#ifdef PREFIX_SUM_EXCLUSIVE
            GS_PartitionWavePrefixSums[ ElementIndex ] = uint4( 0, LocalPrefixSums.xyz ) + PrevLanesSum + WaveReduction;
#else
            GS_PartitionWavePrefixSums[ ElementIndex ] = LocalPrefixSums.xyzw + PrevLanesSum + WaveReduction;
#endif // PREFIX_SUM_EXCLUSIVE

            WaveReduction += WaveReadLaneAt( LocalPrefixSums.w + PrevLanesSum, WaveGetLaneCount() - 1 );

            ElementIndex += WaveGetLaneCount();
        }

        if ( WaveIsFirstLane() )
        {
            GS_WaveReductions[ GetWaveIndex( GroupThreadID ) ] = WaveReduction;
        }
    }

    inline void ReductionScanSingleWave( uint GroupThreadID )
    {
        if ( GroupThreadID < NUM_THREADS_IN_GROUP / WaveGetLaneCount() )
        {
            GS_WaveReductions[ GroupThreadID ] += WavePrefixSum( GS_WaveReductions[ GroupThreadID ] );
        }
    }

    // WARNING: This function hasn't been tested!
    // If we run into issues on GPUs with less than 16 wave sizes this function should be the primary suspect.
    inline void ReductionScanMultipleWaves( uint GroupThreadID )
    {
        const uint ScanSize = NUM_THREADS_IN_GROUP / WaveGetLaneCount();
        if ( GroupThreadID < ScanSize )
        {
            GS_WaveReductions[ GroupThreadID ] += WavePrefixSum( GS_WaveReductions[ GroupThreadID ] );
        }

        GroupMemoryBarrierWithGroupSync();

        const uint LaneLog = countbits( WaveGetLaneCount() - 1 );
        uint Offset = LaneLog;
        uint j = WaveGetLaneCount();
        for ( ; j < ( ScanSize >> 1 ); j <<= LaneLog )
        {
            if ( GroupThreadID < ( ScanSize >> Offset ) )
            {
                GS_WaveReductions[ ( ( GroupThreadID + 1 ) << Offset ) - 1 ] +=
                    WavePrefixSum( GS_WaveReductions[ ( ( GroupThreadID + 1 ) << Offset ) - 1 ] );
            }

            GroupMemoryBarrierWithGroupSync();

            if ( ( GroupThreadID & ( ( j << LaneLog ) - 1 ) ) >= j && ( GroupThreadID + 1 ) & ( j - 1 ) )
            {
                GS_WaveReductions[ GroupThreadID ] +=
                    WaveReadLaneAt( GS_WaveReductions[ ( ( GroupThreadID >> Offset ) << Offset ) - 1 ], 0 );
            }

            Offset += LaneLog;
        }

        GroupMemoryBarrierWithGroupSync();

        // If ScanSize is not a power of WaveGetLaneCount()
        const uint Index = GroupThreadID + j;
        if ( Index < ScanSize )
        {
            GS_WaveReductions[ Index ] +=
                WaveReadLaneAt( GS_WaveReductions[ ( ( Index >> Offset ) << Offset ) - 1 ], 0 );
        }
    }

    inline void DownSweep( uint GroupThreadID, uint PartitionIndex )
    {
        uint PrevReduction = ( PartitionIndex > 0 ) ? GS_PrevPartitionsReduction : 0;

        // Add wave-local reductions from this partition
        if ( GroupThreadID >= WaveGetLaneCount() )
        {
            PrevReduction += GS_WaveReductions[ GetWaveIndex( GroupThreadID ) - 1 ];
        }

        uint ElementIndex = GetWaveStartElementIndexInPartition( GroupThreadID ) + WaveGetLaneIndex();

        [unroll]
        for ( uint i = 0; i < NUM_UINT4_ELEMENTS_PER_THREAD; ++i )
        {
            const uint GlobalElementIndex = GetPartitionStartElementIndex( PartitionIndex ) + ElementIndex;
            if ( GlobalElementIndex >= _VectorizedInputSize )
            {
                break;
            }

#ifdef PREFIX_SUM_COMPACTION
            // Prefix sums of the binary flags represent the indices of the corresponding elements in the final compacted array.
            // We read this indices and store them in ScatterIndices.
            const uint4 ScatterIndices = GS_PartitionWavePrefixSums[ ElementIndex ] + PrevReduction;

            // GS_PartitionInputElements stores original input elements
            const uint4 InputElements = GS_PartitionInputElements[ ElementIndex ];

            [unroll]
            for ( uint j = 0; j < 4; ++j )
            {
                // We want to preserve only non-zero input elements
                if ( InputElements[ j ] != 0 )
                {
                     // Move input elements to their compacted places
                    RWInputBuffer[ ScatterIndices[ j ] ] = InputElements[ j ];

#ifdef OUTPUT_COMPACTED_INDICES
                    // Store final indices of the compacted elements in a separate buffer
                    const uint GlobalElementIndexScalar = GlobalElementIndex * 4 + j;
                    RWIndexOutputBuffer[ ScatterIndices[ j ] ] = GlobalElementIndexScalar;
#endif
                }
            }
#else
            const uint GlobalElementIndexScalar = GlobalElementIndex * 4;
            uint4 Result = GS_PartitionWavePrefixSums[ ElementIndex ] + PrevReduction;
            RWInputBuffer[ GlobalElementIndexScalar ] = Result.x;
            RWInputBuffer[ GlobalElementIndexScalar + 1 ] = Result.y;
            RWInputBuffer[ GlobalElementIndexScalar + 2 ] = Result.z;
            RWInputBuffer[ GlobalElementIndexScalar + 3 ] = Result.w;
#endif // PREFIX_SUM_COMPACTION

            ElementIndex += WaveGetLaneCount();
        }
    }

    inline void AcquirePartitionIndex( uint GroupThreadID )
    {
        if ( GroupThreadID == 0 )
        {
            InterlockedAdd( PartitionIndexBuffer[ 0 ], 1, GS_PartitionIndex );
        }
    }

    inline void SetPartitionReductionReadyFlag( uint GroupThreadID, uint PartitionIndex )
    {
        const uint LastScanWaveIndex = NUM_THREADS_IN_GROUP / WaveGetLaneCount() - 1;
        if ( GroupThreadID == LastScanWaveIndex )
        {
            // PartitionReductionsBuffer stores per-partition uint values with the following bit layout:
            //   - Two least significant bits of the value are used for the partition status flag
            //   - The rest of the bits contain the sum of all the elements of the partition
            const uint StatusFlag = ( PartitionIndex != 0 ) ? FLAG_REDUCTION : FLAG_INCLUSIVE;
            const uint PartitionReduction = GS_WaveReductions[ LastScanWaveIndex ];

#ifdef PREFIX_SUM_FALLBACK
            // When doing fallback multiple threadgroups can update PartitionReductionsBuffer[ PartitionIndex ]
            // therefore we should use CompareStore here instead of a simple Add.
            InterlockedCompareStore( PartitionReductionsBuffer[ PartitionIndex ], 0, ( PartitionReduction << 2 ) | StatusFlag );
#else
            InterlockedAdd( PartitionReductionsBuffer[ PartitionIndex ], ( PartitionReduction << 2 ) | StatusFlag );
#endif
        }
    }

#ifdef PREFIX_SUM_FALLBACK
    inline void FallbackWaveReductionScan( uint GroupThreadID, uint PartitionIndex )
    {
        uint WaveReduction = 0;
        const uint ScanBegin = GetPartitionStartElementIndex( PartitionIndex ) + GroupThreadID;
        const uint ScanEnd = ( PartitionIndex + 1 ) * NUM_UINT4_ELEMENTS_IN_PARTITION;

        for ( uint GlobalElementIndex = ScanBegin; GlobalElementIndex < ScanEnd; GlobalElementIndex += NUM_THREADS_IN_GROUP )
        {
            uint4 InputValues;
    
            const uint GlobalElementIndexScalar = GlobalElementIndex * 4;
            InputValues.x = RWInputBuffer[ GlobalElementIndexScalar ];
            InputValues.y = RWInputBuffer[ GlobalElementIndexScalar + 1 ];
            InputValues.z = RWInputBuffer[ GlobalElementIndexScalar + 2 ];
            InputValues.w = RWInputBuffer[ GlobalElementIndexScalar + 3 ];

            WaveReduction += WaveActiveSum( dot( InputValues, uint4( 1, 1, 1, 1 ) ) );
        }

        if ( WaveIsFirstLane() )
        {
            GS_FallbackWaveReductions[ GetWaveIndex( GroupThreadID ) ] = WaveReduction;
        }
    }

    inline uint FallbackPartitionReductionScanSingleWave( uint GroupThreadID )
    {
        uint Reduction;
        if ( GroupThreadID < NUM_THREADS_IN_GROUP / WaveGetLaneCount() )
        {
            Reduction = WaveActiveSum( GS_FallbackWaveReductions[ GroupThreadID ] );
        }

        return Reduction;
    }

    // WARNING: This function hasn't been tested!
    // If we run into issues on GPUs with less than 16 wave sizes this function should be the primary suspect.
    inline uint FallbackPartitionReductionScanMultipleWaves( uint GroupThreadID )
    {
        const uint ReductionSize = NUM_THREADS_IN_GROUP / WaveGetLaneCount();
        if ( GroupThreadID < ReductionSize )
        {
            GS_FallbackWaveReductions[ GroupThreadID ] = WaveActiveSum( GS_FallbackWaveReductions[ GroupThreadID ] );
        }

        GroupMemoryBarrierWithGroupSync();

        const uint LaneLog = countbits( WaveGetLaneCount() - 1 );
        uint Offset = LaneLog;
        uint j = WaveGetLaneCount();
        for ( ; j < ( ReductionSize >> 1 ); j <<= LaneLog )
        {
            if ( GroupThreadID < ( ReductionSize >> Offset ) )
            {
                GS_FallbackWaveReductions[ ( ( GroupThreadID + 1 ) << Offset ) - 1 ] =
                        WaveActiveSum( GS_FallbackWaveReductions[ ( ( GroupThreadID + 1 ) << Offset ) - 1 ] );
            }

            GroupMemoryBarrierWithGroupSync();
            Offset += LaneLog;
        }

        uint Reduction;
        if ( GroupThreadID == 0 )
        {
            Reduction = GS_FallbackWaveReductions[ ReductionSize - 1 ];
        }

        return Reduction;
    }

    inline uint FallbackCalculatePartitionReduction( uint GroupThreadID, uint PartitionIndex )
    {
        FallbackWaveReductionScan( GroupThreadID, PartitionIndex );

        GroupMemoryBarrierWithGroupSync();

        if ( NUM_THREADS_IN_GROUP / WaveGetLaneCount() <= WaveGetLaneCount() )
        {
            return FallbackPartitionReductionScanSingleWave( GroupThreadID );
        }

        return FallbackPartitionReductionScanMultipleWaves( GroupThreadID );
    }

    inline uint FallbackUpdatePartitionStatus( uint PartitionIndex, uint Reduction )
    {
        const uint StatusFlag = ( PartitionIndex != 0 ) ? FLAG_REDUCTION : FLAG_INCLUSIVE;

        uint PrevStatus;
        InterlockedCompareExchange( PartitionReductionsBuffer[ PartitionIndex ], 0,
                                    ( Reduction << 2 ) | StatusFlag, PrevStatus );

        return PrevStatus;
    }

    // For a given partition sum up the reductions of all the preceding partitions.
    // The resulted sum is stored in GS_PrevPartitionsReduction.
    //
    // To avoid deadlock on some GPUs (Intel) we check the status of the previous partition MAX_SPIN_COUNT times
    // and if its reduction is still not ready we fallback to calculating this reduction manually.
    // We repeat this process until we either find the partition with FLAG_INCLUSIVE or manually reach the very first partition.
    inline void LookbackWithFallback( uint GroupThreadID, uint PartitionIndex )
    {
        uint SpinCount = 0;
        uint PrevReductionsSum = 0;
        uint PrevPartitionIndex = PartitionIndex - 1;

        while ( WaveReadLaneAt( GS_FallbackNeeded, 0 ) == true )
        {
            // Wait until all the waves read GS_FallbackNeeded.
            GroupMemoryBarrierWithGroupSync();

            if ( GroupThreadID == 0 )
            {
                // Try doing the lookback MAX_SPIN_COUNT times.
                while ( SpinCount < MAX_SPIN_COUNT )
                {
                    const uint FlagPayload = PartitionReductionsBuffer[ PrevPartitionIndex ];

                    if ( ( FlagPayload & FLAG_MASK ) > FLAG_NOT_READY )
                    {
                        // Sum up the reductions of the partitions up to and including the found partition.
                        PrevReductionsSum += ( FlagPayload >> 2 );

                        if ( ( FlagPayload & FLAG_MASK ) == FLAG_INCLUSIVE )
                        {
                            // Found a partition with its inclusive prefix sums already calculated - no need to look further back.
                            GS_PrevPartitionsReduction = PrevReductionsSum;
                            GS_FallbackNeeded = false;
                            InterlockedAdd( PartitionReductionsBuffer[ PartitionIndex ], ( PrevReductionsSum << 2 ) | 1 );
                            break;
                        }
                        else
                        {
                            PrevPartitionIndex--;
                        }
                    }
                    else
                    {
                        SpinCount++;
                    }
                }

                if ( GS_FallbackNeeded )
                {
                    GS_FallbackPrevPartitionIndex = PrevPartitionIndex;
                }
            }

            // Wait until all the waves get the updated GS_FallbackNeeded and GS_FallbackPrevPartitionIndex.
            GroupMemoryBarrierWithGroupSync();

            if ( GS_FallbackNeeded )
            {
                // Manually calculate the sum of all the elements in a partition.
                // We use all the waves in the workgroup here.
                uint PrevReduction = FallbackCalculatePartitionReduction( GroupThreadID, GS_FallbackPrevPartitionIndex );

                if ( GroupThreadID == 0 )
                {
                    uint PrevStatus = FallbackUpdatePartitionStatus( PrevPartitionIndex, PrevReduction );

                    PrevReductionsSum += PrevStatus == 0 ? PrevReduction : PrevStatus >> 2;

                    if ( PrevPartitionIndex == 0 || ( PrevStatus & FLAG_MASK ) == FLAG_INCLUSIVE )
                    {
                        // Found a partition with its inclusive prefix sums - no need to look further back.
                        GS_PrevPartitionsReduction = PrevReductionsSum;
                        GS_FallbackNeeded = false;
                        InterlockedAdd( PartitionReductionsBuffer[ PartitionIndex ], ( PrevReductionsSum << 2 ) | 1 );
                    }
                    else
                    {
                        // Inclusive prefix not found yet - we need to look further back.
                        PrevPartitionIndex--;
                        SpinCount = 0;
                    }
                }
            }

            // Wait until all the waves get the updated GS_FallbackNeeded.
            GroupMemoryBarrierWithGroupSync();
        }
    }
#endif // PREFIX_SUM_FALLBACK

    // For a given partition sum up the reductions of all the preceding partitions using one thread.
    // The resulted sum is stored in GS_PrevPartitionsReduction.
    inline void Lookback( uint PartitionIndex )
    {
        uint PrevReductionsSum = 0;
        uint PrevPartitionIndex = PartitionIndex - 1;

        while ( true )
        {
            const uint FlagPayload = PartitionReductionsBuffer[ PrevPartitionIndex ];

            if ( ( FlagPayload & FLAG_MASK ) > FLAG_NOT_READY )
            {
                // Sum up the reductions of the partitions up to and including the found partition.
                PrevReductionsSum += ( FlagPayload >> 2 );

                if ( ( FlagPayload & FLAG_MASK ) == FLAG_INCLUSIVE )
                {
                    // Found a partition with its inclusive prefix sums already calculated - no need to look further back.
                    GS_PrevPartitionsReduction = PrevReductionsSum;
                    InterlockedAdd( PartitionReductionsBuffer[ PartitionIndex ], ( PrevReductionsSum << 2 ) | 1 );
                    break;
                }
                else
                {
                    PrevPartitionIndex--;
                }
            }
        }
    }

    // For a given partition sum up the reductions of all the preceding partitions using one wave.
    // The resulted sum is stored in GS_PrevPartitionsReduction.
    // Note: Simple single-threaded Lookback() function is currently used by default instead if this one.
    inline void LookbackWave( uint PartitionIndex )
    {
        uint PrevReductionsSum = 0;

        int PrevPartitionIndex = (int)PartitionIndex - (int)WaveGetLaneIndex() - 1;
        const uint NumWaveParts = CeilingDivide( WaveGetLaneCount(), WAVE_PART_SIZE );

        while ( true )
        {
            const uint FlagPayload = PrevPartitionIndex >= 0 ? PartitionReductionsBuffer[ PrevPartitionIndex ] : FLAG_INCLUSIVE;

            if ( WaveActiveAllTrue( ( FlagPayload & FLAG_MASK ) > FLAG_NOT_READY ) )
            {
                const uint4 InclusiveBallot = WaveActiveBallot( ( FlagPayload & FLAG_MASK ) == FLAG_INCLUSIVE );

                // Check if any of the preceding partitions have FLAG_INCLUSIVE set.
                if ( InclusiveBallot.x || InclusiveBallot.y || InclusiveBallot.z || InclusiveBallot.w )
                {
                    // Found a partition with its inclusive prefix sums already calculated - no need to look further back.
                    uint InclusiveIndex = 0;
                    for ( uint WavePartIndex = 0; WavePartIndex < NumWaveParts; ++WavePartIndex )
                    {
                        if ( countbits( InclusiveBallot[ WavePartIndex ] ) > 0 )
                        {
                            InclusiveIndex += firstbitlow( InclusiveBallot[ WavePartIndex ] );
                            break;
                        }
                        else
                        {
                            InclusiveIndex += WAVE_PART_SIZE;
                        }
                    }

                    // Sum up the reductions of the partitions up to and including the found partition.
                    PrevReductionsSum += WaveActiveSum( WaveGetLaneIndex() <= InclusiveIndex ? ( FlagPayload >> 2 ) : 0 );

                    // Update the reduction value of the current partition and set the status flag to FLAG_INCLUSIVE.
                    if ( WaveIsFirstLane() )
                    {
                        GS_PrevPartitionsReduction = PrevReductionsSum;
                        InterlockedAdd( PartitionReductionsBuffer[ PartitionIndex ], ( PrevReductionsSum << 2 ) | 1 );
                    }

                    break;
                }
                else
                {
                    // Manually sum up the reductions and step one wave back through partitions.
                    PrevReductionsSum += WaveActiveSum( FlagPayload >> 2 );
                    PrevPartitionIndex -= WaveGetLaneCount();
                }
            }
        }
    }
]]

ComputeShader =
{
    MainCode CS_InitChainedScan
    {
        VertexStruct CS_INPUT
        {
            uint3 DispatchThreadID : PDX_DispatchThreadID
        };

        Input = "CS_INPUT"
        NumThreads = { 256 1 1 }
        Code
        [[
            PDX_MAIN
            {
                const uint TotalThreadCount = 256 * 256;

                for ( uint ThreadIndex = Input.DispatchThreadID.x; ThreadIndex < _PartitionCount; ThreadIndex += TotalThreadCount )
                {
                    PartitionReductionsBuffer[ ThreadIndex ] = 0;
                }

                if ( Input.DispatchThreadID.x == 0 )
                {
                    PartitionIndexBuffer[ 0 ] = 0;
                }
            }
        ]]
    }
}

ComputeShader =
{
    MainCode CS_ChainedScanDecoupledLookback
    {
        VertexStruct CS_INPUT
        {
            uint3 GroupThreadID : PDX_GroupThreadID
        };

        Input = "CS_INPUT"
        NumThreads = { NUM_THREADS_IN_GROUP 1 1 }
        Code
        [[
            PDX_MAIN
            {
                const uint GroupThreadID = Input.GroupThreadID.x;

                // Atomically acquire unique index for this partition
                AcquirePartitionIndex( GroupThreadID );

#ifdef PREFIX_SUM_FALLBACK
                if ( GroupThreadID == 0 )
                {
                    GS_FallbackNeeded = true;
                }
#endif

                // Wait until acquired GS_PartitionIndex is available for all waves
                GroupMemoryBarrierWithGroupSync();

                const uint PartitionIndex = GS_PartitionIndex;

                // Calculate wave-wide prefix sums and wave reductions for this partition.
                // Results are stored in GS_PartitionWavePrefixSums and GS_WaveReductions.
                // This is done by all waves of the thread group concurrently.
                PartitionScan( GroupThreadID, PartitionIndex );

                // Wait until all waves have calculated their local reductions
                GroupMemoryBarrierWithGroupSync();

                // Now we can calculate prefix sums of wave-local reductions to get partition-wide prefix sums.
                // This can be done with a single wave if there is enough lanes in a wave to cover NUM_THREADS_IN_GROUP.
                // The results are stored in GS_WaveReductions.
                if ( NUM_THREADS_IN_GROUP / WaveGetLaneCount() <= WaveGetLaneCount() )
                {
                    ReductionScanSingleWave( GroupThreadID );
                }
                else
                {
                    ReductionScanMultipleWaves( GroupThreadID );
                }

                // Now when the reduction scan for this partition is done we can signal its status to other thread groups.
                // Any thread can do that so we use the thread that scanned last wave reduction to elide an extra barrier.
                SetPartitionReductionReadyFlag( GroupThreadID, PartitionIndex );

                // Once the reduction for the whole partition has been calculated we can start
                // looking through the reductions of the preceding partitions.
                // The resulted sum of all reductions of all previous partitions is stored in GS_PrevPartitionsReduction.
#ifdef PREFIX_SUM_FALLBACK
                if ( PartitionIndex > 0 )
                {
                    LookbackWithFallback( GroupThreadID, PartitionIndex );
                }
                else
                {
                    GroupMemoryBarrierWithGroupSync();
                }
#else
                if ( PartitionIndex > 0 && GroupThreadID == 0 )
                {
                    Lookback( PartitionIndex );
                }

                // Wait until GS_PrevPartitionsReduction is available for all waves
                GroupMemoryBarrierWithGroupSync();
#endif // PREFIX_SUM_FALLBACK

                // Calculate final prefix sums using GS_PrevPartitionsReduction and GS_PartitionWavePrefixSums.
                // This is done by all waves of the thread group concurrently.
                DownSweep( GroupThreadID, PartitionIndex );
            }
        ]]
    }
}

Effect PrefixSumInitChainedScan
{
    ComputeShader = "CS_InitChainedScan"
}

Effect PrefixSumChainedScanDecoupledLookback
{
    ComputeShader = "CS_ChainedScanDecoupledLookback"
}