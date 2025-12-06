# Contains common structures used for all GPU spline shaders.

Includes = {
	"cw/heightmap.fxh"
	"cw/random.fxh"
}

struct SControlPoint
{
	float2 _Position;
	uint _SegmentIdx;
	uint _Pad0;
};

ConstantBuffer( GpuSplineConstants )
{
	uint _SegmentCount;
	uint _SegmentBufferSize;
	uint _ControlPointCount;
	uint _ControlPointBufferSize;

	uint _TessellationFactor;
	float _MinWorldHeight;
	float _MaxWorldHeight;
	float _MaxSplineWidth;

	float4 _FrustumPlanes[4];
}

struct SSegmentData
{
	uint _StartIdx;
	uint _EndIdx;
	bool _Looping;
	uint _PatchBufferOffset;

	int4 _AABB;
};

# TODO[TS]: Should we alias this resource as both RW and not? We only write to it in one rarely used shader.
RWStructuredBufferTexture SegmentDataBuffer
{
	Ref = GpuSplineSegmentDataBuffer
	Type = SSegmentData
}

struct SPatchData
{
	float4 _Points[8];

	uint _StartControlPoint;
	uint _IdxWithinEmittedSegment;
	uint _SegmentIdx;
	uint _Pad0;
};

RWStructuredBufferTexture PatchDataBuffer
{
	Ref = GpuSplinePatchDataBuffer
	Type = SPatchData
}

RWBufferTexture PatchLengthsBuffer
{
	Ref = GpuSplinePatchLengthsBuffer
	Type = uint
}

struct SAttribute
{
	uint _DataIndex;
	float _Width;
};

StructuredBufferTexture AttributeBuffer
{
	Ref = GpuSplineAttributeBuffer
	Type = SAttribute
}

Code
[[
#ifndef PDX_ENABLE_SPLINE_GRAPHICS1
	// We need to do a prefix sum over the lengths of the patches, but we can only do prefix sums
	// on arrays of uints. So we scale by this value first, then scale down afterwards.
	#define SCALING_FACTOR 1000.0f

	struct SSplinePointData
	{
		float2 UV; // x = 0-1 over width of spline. y = 0-x in worldspace
		float3 Position; // Base interpolated worldspace position (center of spline)

		float3 Normal;
		float3 Tangent;

		float HalfSideMask; // -0.5 or 0.5, dependin on the side of the spline.
		uint StartControlPointIdx; // Start control point for attribute interpolation
		uint EndControlPointIdx; // Start control point for attribute interpolation
		float CurveT; // T 0-1 value over current spline patch

		float MaxU; // Maximum U value on whole segment
	};

	// InstanceID is assumed to be the patch index
	SSplinePointData CalcSplinePointData( uint InstanceID, uint VertexID )
	{
		SSplinePointData SplinePoint;

		uint PatchIdx = InstanceID;
		// We use triangle strips such that each two vertices correspond to one of the tessellated points
		uint TessellationIdx = VertexID / 2;
		SplinePoint.CurveT = TessellationIdx / float( _TessellationFactor - 1 );

		float4 TessellatedPoint = PatchDataBuffer[ PatchIdx ]._Points[ TessellationIdx ];

		SplinePoint.StartControlPointIdx = PatchDataBuffer[ PatchIdx ]._StartControlPoint;
		SplinePoint.EndControlPointIdx = SplinePoint.StartControlPointIdx + 1;

		uint SegmentIdx = PatchDataBuffer[ PatchIdx ]._SegmentIdx;
		uint TessellatedStartIdx = SegmentDataBuffer[ SegmentIdx ]._StartIdx + 1;
		uint TessellatedEndIdx = SegmentDataBuffer[ SegmentIdx ]._EndIdx - 1;

		// Next patch
		uint NextPatchOffset = PatchLengthsBuffer[ PatchIdx ];

		// This patch
		uint ThisPatchOffset = PatchIdx > 0 ? PatchLengthsBuffer[ PatchIdx - 1 ] : 0;

		// Next segment
		uint NumPatchesInThisSegment = TessellatedEndIdx - TessellatedStartIdx + ( SegmentDataBuffer[ SegmentIdx ]._Looping ? 1 : 0 );
		uint PatchIdxOfFirstPatchInThisSegment = PatchIdx - PatchDataBuffer[ PatchIdx ]._IdxWithinEmittedSegment;
		uint PatchIdxOfLastPatchInThisSegment = PatchIdxOfFirstPatchInThisSegment + NumPatchesInThisSegment - 1;
		uint NextSegmentOffset = PatchLengthsBuffer[ PatchIdxOfLastPatchInThisSegment ];

		// This segment
		uint ThisSegmentOffset = PatchIdxOfFirstPatchInThisSegment > 0 ? PatchLengthsBuffer[ PatchIdxOfFirstPatchInThisSegment - 1 ] : 0;

		// Derive the offsets
		uint ThisPatchLength = NextPatchOffset - ThisPatchOffset;
		uint ThisSegmentLength = NextSegmentOffset - ThisSegmentOffset;
		uint ThisPatchLocalOffset = NextPatchOffset - ThisSegmentOffset - ThisPatchLength;

		// Write them
		SplinePoint.MaxU = ThisSegmentLength / SCALING_FACTOR;
		SplinePoint.UV.x = ( ThisPatchLocalOffset + ThisPatchLength * SplinePoint.CurveT ) / SCALING_FACTOR;
		SplinePoint.UV.y = float( VertexID & 1 );
		SplinePoint.HalfSideMask = float( VertexID & 1 ) - 0.5;

		// We defer this as long as possible to hide the read ([TS]: check if this actually has any impact)
		SplinePoint.Position = float3( TessellatedPoint.x, GetHeight( TessellatedPoint.xy ), TessellatedPoint.y );
		SplinePoint.Normal = float3( 0, 1, 0 ); // TODO[TS]: PSGE-7505: We need to generate correct interpolated normals here
		SplinePoint.Tangent = float3( TessellatedPoint.z, 0, -TessellatedPoint.w ); // TODO: Invert in tesselation!

		return SplinePoint;
	}
#endif
]]
