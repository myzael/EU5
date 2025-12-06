ConstantBuffer( PdxCamera )
{
	float4x4	ViewProjectionMatrix;
	float4x4	InvViewProjectionMatrix;
	float4x4	ViewMatrix;
	float4x4	InvViewMatrix;
	float4x4	ProjectionMatrix;
	float4x4	InvProjectionMatrix;

	float4x4 	ShadowMapTextureMatrix;

	float3		CameraPosition;
	float		ZNear;
	float3		CameraLookAtDir;
	float		ZFar;
	float3		CameraUpDir;
	float 		CameraFoV;
	float3		CameraRightDir;
	float 		_UpscaleLodBias;
	float 		_UpscaleLodBiasNative;
	float 		_UpscaleLodBiasMultiplier;
	float 		_UpscaleLodBiasMultiplierNative;
	float 		_UpscaleLodBiasEnabled;
}

Code
[[
	float CalcViewSpaceDepth( float Depth )
	{
		Depth = 2.0 * Depth - 1.0;
		float ZLinear = 2.0 * ZNear * ZFar / (ZFar + ZNear - Depth * (ZFar - ZNear));
		return ZLinear;
	}

	float3 ViewSpacePosFromDepth( float Depth, float2 UV )
	{
		float x = UV.x * 2.0 - 1.0;
		float y = (1.0 - UV.y) * 2.0 - 1.0;

		float4 ProjectedPos = float4( x, y, Depth, 1.0 );

		float4 ViewSpacePos = mul( InvProjectionMatrix, ProjectedPos );

		return ViewSpacePos.xyz / ViewSpacePos.w;
	}

	float3 WorldSpacePositionFromDepth( float Depth, float2 UV )
	{
		float3 WorldSpacePos = mul( InvViewMatrix, float4( ViewSpacePosFromDepth( Depth, UV ), 1.0 ) ).xyz;
		return WorldSpacePos;
	}

	float2 ScreenSpaceUvFromWorldSpacePosition( float3 WorldSpacePos )
	{
		float4 ClipSpacePos = mul( ViewProjectionMatrix, float4( WorldSpacePos, 1.0 ) );
		float2 NDC = ClipSpacePos.xy / ClipSpacePos.w;
		float2 UV;
		UV.x = (NDC.x + 1.0) * 0.5;
		UV.y = (1.0 - NDC.y) * 0.5;
		return UV;
	}
]]
