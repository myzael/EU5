Includes = {
	"cw/camera.fxh"
	"cw/gpu_spline.fxh"
}

StructuredBufferTexture ControlPointBuffer
{
	Ref = PdxBufferTexture0
	Type = SControlPoint
}

RWStructuredBufferTexture NumVisibleSegmentsBuffer
{
	Ref = PdxRWBufferTexture0
	Type = uint
}

RWBufferTexture SegmentOffsetsBuffer
{
	Ref = PdxRWBufferTexture1
	type = uint
}

RWBufferTexture VisibleSegmentsBuffer
{
	Ref = PdxRWBufferTexture2
	type = uint
}

struct SGfxDispatchIndirectArgs
{
	uint _ThreadGroupCountX;
	uint _ThreadGroupCountY;
	uint _ThreadGroupCountZ;
};

RWStructuredBufferTexture DispatchIndirectBuffer
{
	Ref = PdxRWBufferTexture3
	type = SGfxDispatchIndirectArgs
}

struct SGfxDrawInstancedIndirectArgs
{
	uint _VertexCountPerInstance;
	uint _InstanceCount;
	uint _StartVertexLocation;
	uint _StartInstanceLocation;
};

RWStructuredBufferTexture DrawIndirectBuffer
{
	Ref = PdxRWBufferTexture4
	Type = SGfxDrawInstancedIndirectArgs
}

ComputeShader =
{
	MainCode CS_SplineSegmentAABBGeneration
	{
		VertexStruct CS_INPUT
		{
			# x = Control point index
			# y = unused
			# z = unused
			uint3 DispatchThreadID : PDX_DispatchThreadID
		};

		Input = "CS_INPUT"
		NumThreads = { 512 1 1 }
		Code
		[[
			PDX_MAIN
			{
				uint ControlPointIdx = Input.DispatchThreadID.x;
				if ( ControlPointIdx >= _ControlPointCount )
				{
					return;
				}

				uint SegmentIdx = ControlPointBuffer[ ControlPointIdx ]._SegmentIdx;
				int2 ControlPointPosition = (int2)ControlPointBuffer[ ControlPointIdx ]._Position;


				// TODO[TS]: We are creating the AABBs from all of the points associated with the
				// segment, but this is very conservative!
				// b-splines have a much tighter bounding box that we can find with some math, but
				// this might be hard to do in a shader.
				//
				// NOTE[TS]: Currently this relies on that we're starting from an AABB of (INT32_MAX, INT32_MAX, INT32_MIN, INT32_MIN)
				// Swizzling here makes the value const for some reason, so we just index the vector.
				InterlockedMin( SegmentDataBuffer[ SegmentIdx ]._AABB[ 0 ], ControlPointPosition.x - (int)_MaxSplineWidth);
				InterlockedMin( SegmentDataBuffer[ SegmentIdx ]._AABB[ 1 ], ControlPointPosition.y - (int)_MaxSplineWidth);
				InterlockedMax( SegmentDataBuffer[ SegmentIdx ]._AABB[ 2 ], ControlPointPosition.x + (int)_MaxSplineWidth);
				InterlockedMax( SegmentDataBuffer[ SegmentIdx ]._AABB[ 3 ], ControlPointPosition.y + (int)_MaxSplineWidth);
			}
		]]
	}

	MainCode CS_SplineReset
	{
		VertexStruct CS_INPUT
		{
		};

		Input = "CS_INPUT"
		NumThreads = { 1 1 1 }
		Code
		[[
			PDX_MAIN
			{
				// TODO[TS]: Do we care that some of these could be elided?
				DispatchIndirectBuffer[ 0 ]._ThreadGroupCountX = 0;
				DispatchIndirectBuffer[ 0 ]._ThreadGroupCountY = 0;
				DispatchIndirectBuffer[ 0 ]._ThreadGroupCountZ = 1;

				DrawIndirectBuffer[ 0 ]._VertexCountPerInstance = _TessellationFactor * 2; // Vertex count
				DrawIndirectBuffer[ 0 ]._InstanceCount = 0;
				DrawIndirectBuffer[ 0 ]._StartVertexLocation = 0;
				DrawIndirectBuffer[ 0 ]._StartInstanceLocation = 0;

				NumVisibleSegmentsBuffer[ 0 ] = 0;

				// TODO[TS]: It would be useful for debugging, if we could clear the other buffers, like the visible segments buffer.
			}
		]]
	}

	MainCode CS_SplineSegmentCulling
	{
		VertexStruct CS_INPUT
		{
			# x = Segment index
			# y = unused
			# z = unused
			uint3 DispatchThreadID : PDX_DispatchThreadID
		};

		Input = "CS_INPUT"
		NumThreads = { 64 1 1 }
		Code
		[[
#define JOB_SIZE 64U

			float CalcDistanceFromPlane( float3 Point, float4 Plane )
			{
				return dot( Plane.xyz, Point ) + Plane.w;
			}

			PDX_MAIN
			{
				const uint SegmentIdx = Input.DispatchThreadID.x;

				if ( SegmentIdx >= _SegmentCount )
				{
					return;
				}

				const SSegmentData SegmentData = SegmentDataBuffer[ SegmentIdx ];

				// Frustum culling: https://www.cse.chalmers.se/~uffe/vfc.pdf
				for ( int plane = 0; plane < 4; ++plane ) // We skip the near and far plane.
				{
					float3 p = float3( SegmentData._AABB.x, _MinWorldHeight, SegmentData._AABB.y );
					const float3 PlaneNormal = _FrustumPlanes[ plane ].xyz;

					if ( PlaneNormal.x <= 0.0f )
					{
						p.x = SegmentData._AABB.z;
					}

					if ( PlaneNormal.y <= 0.0f )
					{
						p.y = _MaxWorldHeight;
					}

					if ( PlaneNormal.z <= 0.0f )
					{
						p.z = SegmentData._AABB.w;
					}

					if ( CalcDistanceFromPlane( p, _FrustumPlanes[ plane ] ) > 0.0f )
					{
						// Entire segment is outside of frustum - we can cull it all.
						SegmentOffsetsBuffer[ SegmentIdx ] = 0;
						return;
					}
				}

				// At least part of the segment is within frustum.

				// Write our segment index to the list of visible segments for the tessellator
				uint PrevNumSegments;
				InterlockedAdd( NumVisibleSegmentsBuffer[ 0 ], 1, PrevNumSegments );

				// Calculate number of patches to allocate.
				// -2 as we don't generate patches for the first and last control points - they're just there for interpolation
				const uint NumPatches = SegmentData._EndIdx - SegmentData._StartIdx - 2 + ( SegmentData._Looping ? 1 : 0 );
				SegmentOffsetsBuffer[ SegmentIdx ] = NumPatches;

				// The tessellation dispatch x count is the total number of visible segments divided by the JOB_SIZE.
				const uint NumSegmentJobs = 1 + ( PrevNumSegments + 1 ) / JOB_SIZE;
				InterlockedMax( DispatchIndirectBuffer[ 0 ]._ThreadGroupCountX, NumSegmentJobs );

				// The tessellation dispatch y count is the number of patches of the largest segment.
				InterlockedMax( DispatchIndirectBuffer[ 0 ]._ThreadGroupCountY, NumPatches );
			}
		]]
	}

	MainCode CS_SplineTessellate
	{
		VertexStruct CS_INPUT
		{
			# TODO[TS]: It would probably be faster to have patch index on X coordinate!
			# x = Visible segment index
			# y = Patch index within segment. Note that y dispatch size will be that of the segment with the most control points.
			# z = unused
			uint3 DispatchThreadID : PDX_DispatchThreadID
		};

		Input = "CS_INPUT"
		NumThreads = { 64 1 1 }
		Code
		[[
			float2 GetPointOnCubicBSpline( float T, float2 P0, float2 P1, float2 P2, float2 P3 )
			{
				return ( P0 * ( 1.0f - 3.0f * T + 3.0f * T * T - T * T * T ) + P1 * ( 4.0f - 6.0f * T * T + 3.0f * T * T * T ) + P2 * ( 1.0f + 3.0f * T + 3.0f * T * T - 3.0f * T * T * T ) + P3 * T * T * T ) * ( 1.0f / 6.0f );
			}

			float2 GetDerivativeOnCubicBSpline( float T, float2 P0, float2 P1, float2 P2, float2 P3 )
			{
				return ( P0 * ( -3.0f + 6.0f * T - 3.0f * T * T ) + P1 * ( -12.0f * T + 9.0f * T * T ) + P2 * ( 3.0f + 6.0f * T - 9.0f * T * T ) + P3 * ( 3.0f * T * T ) ) * ( 1.0f / 6.0f );
			}

			float2 GetTangentOnCubicBSpline( float T, float2 P0, float2 P1, float2 P2, float2 P3 )
			{
				return normalize( GetDerivativeOnCubicBSpline( T, P0, P1, P2, P3 ) );
			}

			PDX_MAIN
			{
				uint VisibleSegmentIdx = Input.DispatchThreadID.x;
				if ( VisibleSegmentIdx >= NumVisibleSegmentsBuffer[ 0 ] )
				{
					return;
				}

				uint SegmentIdx = VisibleSegmentsBuffer[ VisibleSegmentIdx ];
				SSegmentData SegmentData = SegmentDataBuffer[ SegmentIdx ];

				uint TessellatedStartIdx = SegmentData._StartIdx + 1;
				uint TessellatedEndIdx = SegmentData._EndIdx - 1;
				uint LastLocalControlPointIdx = TessellatedEndIdx - TessellatedStartIdx;
				uint NumPatchesInSegment = LastLocalControlPointIdx + ( SegmentData._Looping ? 1 : 0 );
				uint PatchIdxWithinSegment = Input.DispatchThreadID.y;

				if ( PatchIdxWithinSegment >= NumPatchesInSegment )
				{
					return;
				}

				uint LocalControlPointIdx = Input.DispatchThreadID.y;
				uint ControlPointIdx = TessellatedStartIdx + LocalControlPointIdx;

				// Determine the four points used for the b spline.
				// We first try to gather points for which we have data. If any of the points don't
				// have data, then we wrap the point indices if we're looping, or extrapolate new
				// points if we aren't.
				float2 Point0Position = ControlPointBuffer[ ControlPointIdx - 1 ]._Position;
				float2 Point1Position = ControlPointBuffer[ ControlPointIdx + 0 ]._Position;
				float2 Point2Position = ControlPointBuffer[ ControlPointIdx + 1 ]._Position;
				float2 Point3Position;

				// TODO[TS]: We should have a control point indirection buffer, then simply add an
				// extra control point idx at the start when looping = true.
				if ( ControlPointIdx == TessellatedEndIdx && SegmentData._Looping )
				{
					// SegmentData._Looping must necessarily be true!
					Point3Position = ControlPointBuffer[ TessellatedStartIdx ]._Position;
				}
				else
				{
					Point3Position = ControlPointBuffer[ ControlPointIdx + 2 ]._Position;
				}

				const uint PatchIdx = SegmentOffsetsBuffer[ VisibleSegmentIdx ] + PatchIdxWithinSegment;

				// Write bookkeeping data
				PatchDataBuffer[ PatchIdx ]._SegmentIdx = SegmentIdx;
				PatchDataBuffer[ PatchIdx ]._IdxWithinEmittedSegment = LocalControlPointIdx;
				PatchDataBuffer[ PatchIdx ]._StartControlPoint = ControlPointIdx;

				// Increment number of indirect instances, which also is the index which we write into
				// TODO[TS]: This is a bit scary! We're relying on that the sum of the emitted patches is equal to the final _InstanceCount!
				InterlockedAdd( DrawIndirectBuffer[ 0 ]._InstanceCount, 1 );

				float Length = 0.0f;
				float2 PreviousPosition;
				const float PER_TESSELLATED_POINT_T = 1.0 / ( (float)( _TessellationFactor - 1 ) );
				for ( uint i = 0; i < _TessellationFactor; ++i )
	 			{
					float CurveT = float( i ) * PER_TESSELLATED_POINT_T;
					float2 Position = GetPointOnCubicBSpline( CurveT, Point0Position, Point1Position, Point2Position, Point3Position );
					PatchDataBuffer[ PatchIdx ]._Points[ i ].xy = Position;
					float2 Tangent = GetTangentOnCubicBSpline( CurveT, Point0Position, Point1Position, Point2Position, Point3Position );
					PatchDataBuffer[ PatchIdx ]._Points[ i ].zw = Tangent;

					if ( i > 0 )
					{
						// TODO[TS]: This behavior is not completely correct! We should only be grabbing t = 0/.3/.6/1 points for length consideration
						// (this is for when we have adaptive tessellation - tessellation count should not influence UVs)
						Length += length( Position - PreviousPosition );
					}
					PreviousPosition = Position;
				}

				PatchLengthsBuffer[ PatchIdx ] = uint( Length * SCALING_FACTOR );
			}
		]]
	}
}

Effect SplineSegmentAABBGeneration
{
	ComputeShader = "CS_SplineSegmentAABBGeneration"
}

Effect SplineReset
{
	ComputeShader = "CS_SplineReset"
}

Effect SplineCull
{
	ComputeShader = "CS_SplineSegmentCulling"
}

Effect SplineTessellate
{
	ComputeShader = "CS_SplineTessellate"
}
