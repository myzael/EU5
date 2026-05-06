Includes = {
	"cw/shadow.fxh"
	"cw/terrain.fxh"
	"jomini/jomini_lighting.fxh"
	"jomini/jomini_fog.fxh"	
	"jomini/jomini_spline.fxh"
	"jomini/jomini_spline_unpacking.fxh"
	"jomini/gradient_border_constants.fxh"
	"flatmap_lerp.fxh"
	"fog_of_war.fxh"
	"constants.fxh"
	"standardfuncsgfx.fxh"
	"terrain.fxh"
}

VertexStruct VS_CUSTOM_SPLINE_OUTPUT
{
	float4 Position			: PDX_POSITION;
	float2 UV				: TEXCOORD0;
	float3 Tangent			: TEXCOORD1;
	float3 Normal			: TEXCOORD2;
	float3 WorldSpacePos	: TEXCOORD3;
	float  MaxU				: TEXCOORD4;
	float  Width			: TEXCOORD5;
@ifdef PDX_ENABLE_SPLINE_GRAPHICS1
	float  DistanceToMain	: TEXCOORD6;
	float  Transparency 	: TEXCOORD7;
@else
	int DataIndex1			: TEXCOORD6;
	int DataIndex2			: TEXCOORD7;
	float DataDelta			: TEXCOORD8;
@endif
	float FlatMapCutoff		: TEXCOORD9;
};

VertexShader =
{
	MainCode VS_game
	{
		Input = "VS_PACKED_SPLINE_INPUT"
		Output = "VS_CUSTOM_SPLINE_OUTPUT"
		Code
		[[
			PDX_MAIN
			{
				VS_SPLINE_INPUT UnpackedInput = UnPackSplineInput(Input); 
				VS_CUSTOM_SPLINE_OUTPUT  Out;
			
				Out.UV 				= UnpackedInput.UV;
				Out.Tangent 		= UnpackedInput.Tangent;
				Out.WorldSpacePos 	= UnpackedInput.Position;
				Out.MaxU 			= UnpackedInput.MaxU;
				Out.Normal 			= UnpackedInput.Normal;
				float2 FlatMapBlend = GetNoisyFlatMapLerp( Out.WorldSpacePos , GetFlatMapLerp());
				float2 RoadNormal = Out.Tangent.zx;
				RoadNormal.y = -RoadNormal.y;
				RoadNormal*= sign(Out.UV.y-0.5f);
				#ifdef CAMERA_POSITION_TO_START_INCREASING_ROADS
					float MaxZoomOutDistance = 1.0f/CAMERA_POSITION_TO_START_INCREASING_ROADS;
				#else
					float MaxZoomOutDistance = 1.0f/75.0f;
				#endif
				#ifdef ZOOM_OUT_ROADS_SCALE
					float SizeMult = ZOOM_OUT_ROADS_SCALE;
				#else
					float SizeMult =  0.3f;
				#endif
				float ExtraSizeLod  =  log2(max (1.0f,CameraPosition.y*MaxZoomOutDistance)); 
				float TotalExtraSize = ExtraSizeLod*SizeMult;
				#ifdef FLATMAP_FARAWAY_CUTOFF
					Out.FlatMapCutoff = TotalExtraSize*FLATMAP_FARAWAY_CUTOFF;
				#else
					Out.FlatMapCutoff = TotalExtraSize*0.5f;
				#endif
				Out.WorldSpacePos.xz+=RoadNormal*TotalExtraSize;
				
				AdjustFlatMapHeight( Out.WorldSpacePos );
				
				Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Out.WorldSpacePos, 1.0f ) );
				Out.Position.z = FixProjectionAndMul( ViewProjectionMatrix, float4( Out.WorldSpacePos+float3(0.0f,1.0f,0.0f), 1.0f ) ).z;
				#ifdef UV_X_FARAWAY_SIZE_MULT
				float InvUvXMult = 1.0/(1.0 + TotalExtraSize*UV_X_FARAWAY_SIZE_MULT);
				#else
				float InvUvXMult = 1.0/(1.0 + TotalExtraSize);
				#endif
				Out.UV.x= Out.UV.x * InvUvXMult + (1-InvUvXMult)*0.5;
				return Out;
			}		
		]]
	}
}

PixelShader =
{
	TextureSampler DiffuseTexture
	{
		Ref = PdxTexture0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler NormalTexture
	{
		Ref = PdxTexture1
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler MaterialTexture
	{
		Ref = PdxTexture2
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler FlatMapTexture
	{
		Ref = PdxTexture3
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler MaskTexture
	{
		Ref = PdxTexture4
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	
	TextureSampler PencilNoiseMap
	{
		Ref = PdxTexture11
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/map/rivers/charcoal_noise.dds"
	}

	TextureSampler EnvironmentMap
	{
		Ref = JominiEnvironmentMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		Type = "Cube"
	}
	TextureSampler ShadowTexture
	{
		Ref = PdxShadowmap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		CompareFunction = less_equal
		SamplerType = "Compare"
	}
	
	Code
	[[
		VS_SPLINE_OUTPUT ConvertToJominiOutput (VS_CUSTOM_SPLINE_OUTPUT Input)
		{
			VS_SPLINE_OUTPUT Out;
	 		Out.Position      = Input.Position;
			Out.UV            = Input.UV;
	 		Out.Tangent       = Input.Tangent;
			Out.Normal        = Input.Normal;
	 		Out.WorldSpacePos = Input.WorldSpacePos;
	 		Out.MaxU          = Input.MaxU;
	 		Out.Width         = Input.Width;
		#ifdef PDX_ENABLE_SPLINE_GRAPHICS1
			Out.DistanceToMain	= Input.Transparency;
			Out.Transparency    = Input.Transparency;
		#else
			Out.DataIndex1	= Input.DataIndex1;
			Out.DataIndex2  = Input.DataIndex2;
			Out.DataDelta   = Input.DataDelta;
		#endif
			return Out;
		}

		float4 GetPixelColor(			
			VS_CUSTOM_SPLINE_OUTPUT  Input,
			float2 UV,
			float2 ddx,
			float2 ddy,
			float EdgeOpacityThresholdInWorldSpace,
			float MaskValue,
			int RoadTypeID)
		{	
			float2 FlatMapBlend = GetNoisyFlatMapLerp( Input.WorldSpacePos , GetFlatMapLerp());
			float4 FinalColor = vec4(0.0f);
			if( FlatMapBlend.x < 1.0f )
			{			
				float4 Diffuse;
				float4 Material;
				float3 Normal;	
				
				// Using ddx and ddy because there is a code path that supportes stacking texture on top			
				// Which results in discontinuties in texture lookup if we don't use ddx, ddy
				Diffuse = PdxTex2DGrad( DiffuseTexture, UV, ddx, ddy );									
				Diffuse.a *= MaskValue;
				Diffuse.a *= JominiFlatSplineEdgeOpacity( Input.UV.x / UVScale, Input.MaxU / UVScale, EdgeOpacityThresholdInWorldSpace);
				Material = PdxTex2DGrad( MaterialTexture, UV, ddx, ddy );									
				Normal = JominiFlatSplineSampleNormal( NormalTexture, normalize( Input.Normal ), normalize( Input.Tangent ), UV, ddx, ddy);
#if defined( GRADIENT_BORDERS ) && ! defined(NO_BORDERS)
				float2 MapCoords = Input.WorldSpacePos.xz * _WorldSpaceToTerrain0To1;
				float3 ColorOverlay;
				float PreLightingBlend;
				float PostLightingBlend;
				GetProvinceOverlayAndBlendCustom( MapCoords, ColorOverlay, PreLightingBlend, PostLightingBlend );
				Diffuse.rgb = ApplyGradientBorderColorPreLighting( Diffuse.rgb, ColorOverlay, PreLightingBlend );
				float4 HighlightColor = BilinearColorSampleAtOffset( MapCoords, IndirectionMapSize, InvIndirectionMapSize, ProvinceColorIndirectionTexture, ProvinceColorTexture, HighlightProvinceColorsOffset );
				Diffuse.rgb = lerp( Diffuse.rgb, HighlightColor.rgb, HighlightColor.a );
#endif
				SMaterialProperties MaterialProps = GetMaterialProperties( Diffuse.rgb, Normal, Material.a, Material.g, Material.b );
				SLightingProperties LightingProps = GetSunLightingProperties( Input.WorldSpacePos, ShadowTexture );
			
				FinalColor.rgb = CalculateSunLighting( MaterialProps, LightingProps, EnvironmentMap );
				FinalColor.a = Diffuse.a;
#if defined( GRADIENT_BORDERS ) && ! defined(NO_BORDERS)
				FinalColor.rgb = ApplyGradientBorderColor( FinalColor.rgb, ColorOverlay, PostLightingBlend );
#endif
#ifndef UNDERWATER
				FinalColor.rgb = ApplyFogOfWar( FinalColor.rgb, Input.WorldSpacePos, FogOfWarAlpha );
				FinalColor.rgb = ApplyDistanceFog( FinalColor.rgb, Input.WorldSpacePos );
#endif
				DebugReturn( FinalColor.rgb, MaterialProps, LightingProps, EnvironmentMap );			
			}
			
			
			bool IsRoadsMapMode = GetMapModeId() == 1;
			FlatMapBlend = saturate(FlatMapBlend + vec2(IsRoadsMapMode));

			// Flatmap roads rendering
			if( FlatMapBlend.x > 0.0f )
			{
				float Distance = Remap( PdxTex2D( FlatMapTexture, UV ).r, 0.0, 1.0, -1.0, 1.0 );
				float PencilNoise = PdxTex2D( PencilNoiseMap, Input.WorldSpacePos.xz * 0.125f ).r;
				Distance += Remap( PencilNoise, 0.0f, 1.0f, -0.5f, 0.5f );
				
				float CameraDist = length( CameraPosition - Input.WorldSpacePos );
				float Fuzz = Remap( CameraDist, 50.0, 400.0, 0.4, 1.0 );
				float Offset = Remap( CameraDist, 50.0, 400.0, 0.0, -0.5 );
				
				// Detect sentinel values via gradient_width:
				// 0.222 = roads-only, 0.333 = roads+rivers
				
				if( IsRoadsMapMode )
				{
					Distance += 1.0f;
					
					// Per-road-type colors (see ROAD_TYPE_ID specializations)
					float3 RoadTypeColor;
					float BrightnessMul;
					float BrightnessBias;
					
					if( RoadTypeID == 0 )
					{
						RoadTypeColor = float3( 0.0, 0.7, 0.0 );
						BrightnessMul = 1.20f;
						BrightnessBias = 0.06f;
					}
					else if( RoadTypeID == 1 )
					{
						RoadTypeColor = float3( 1.0, 0.4, 0.0 );
						BrightnessMul = 1.28f;
						BrightnessBias = 0.075f;
					}
					else if( RoadTypeID == 2 )
					{
						RoadTypeColor = float3( 1.0, 0.0, 0.0 );
						BrightnessMul = 1.35f;
						BrightnessBias = 0.09f;
					}
					else
					{
						RoadTypeColor = float3( 1.0, 0.0, 1.0 );
						BrightnessMul = 1.20f;
						BrightnessBias = 0.06f;
					}
					
					float3 LineColor = saturate( RoadTypeColor * BrightnessMul + BrightnessBias );
					float SharpFuzz = Fuzz * 0.7f;
					
					float OutlineAlpha = smoothstep( Offset - SharpFuzz, Offset + SharpFuzz, Distance + 1.25f );
					float CoreAlpha = smoothstep( Offset - SharpFuzz, Offset + SharpFuzz, Distance + 1.0f );
					
					FinalColor = lerp( FinalColor, float4( 0.05, 0.05, 0.05, OutlineAlpha ), FlatMapBlend.x );
					FinalColor = lerp( FinalColor, float4( LineColor, CoreAlpha ), FlatMapBlend.x );
				}
				else
				{
					float RoadAlpha = smoothstep( Offset - Fuzz, Offset + Fuzz, Distance );
					FinalColor = lerp( FinalColor, float4( 0.0, 0.0, 0.0, RoadAlpha ), FlatMapBlend.x );
				}
				if(Input.FlatMapCutoff > UV.y || Input.FlatMapCutoff > 1 - UV.y )
				{
					discard;
				}
			}
			
			FinalColor.a *= GlobalOpacity;
			if( GetFlatMapLerp() < 1.0 && !IsRoadsMapMode )
			{
				float3 FoggedColor = ApplyFogOfWar( FinalColor.rgb, Input.WorldSpacePos, FogOfWarAlpha );
				FoggedColor = ApplyDistanceFog( FoggedColor, Input.WorldSpacePos );
				FinalColor.rgb = lerp( FoggedColor, FinalColor.rgb, GetFlatMapLerp() );
			}
			
			return FinalColor;
		}
		
		float4 GetPixelColorWithMaskApplied(
			VS_CUSTOM_SPLINE_OUTPUT  Input,
			int MaskIndex,
			int RoadTypeID)
		{
			float2 UV = Input.UV;
			float2 dx=float2(0,0), dy=float2(0,0);
			
			dx = ddx(UV);
			dy = ddy(UV);																				
							
			float2 Mask = float2(1,1);			
			Mask = JominiFlatSplineSampleMask( MaskTexture, ConvertToJominiOutput( Input ) );
			
			return GetPixelColor( Input, UV, dx, dy, 0, Mask[MaskIndex], RoadTypeID );	
		}
		
	]]
		
	MainCode Background
	{
		Input = "VS_CUSTOM_SPLINE_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[	
			PDX_MAIN
			{	
				//clip(-1);
#ifndef ROAD_TYPE_ID
#define ROAD_TYPE_ID 0
#endif				
				return GetPixelColorWithMaskApplied( Input, 0, ROAD_TYPE_ID );				
			}
		]]
	}
	
	MainCode Foreground
	{
		Input = "VS_CUSTOM_SPLINE_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[	
			
			PDX_MAIN
			{		
				//clip(-1);
#ifndef ROAD_TYPE_ID
#define ROAD_TYPE_ID 0
#endif
				return GetPixelColorWithMaskApplied( Input, 1, ROAD_TYPE_ID );				
			}
		]]
	}
	
	MainCode StackedTexturesPass
	{
		Input = "VS_CUSTOM_SPLINE_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[	
			
			PDX_MAIN
			{		
				//clip(-1);
#ifndef ROAD_TYPE_ID
#define ROAD_TYPE_ID 0
#endif
				float2 UV = Input.UV;
				float2 dx=float2(0,0), dy=float2(0,0);
			
				JominiFlatSplineStackedUV( ConvertToJominiOutput(Input), 8, UV, dx, dy );
			
				return GetPixelColor( Input, UV, dx, dy, 1.2, 1, ROAD_TYPE_ID );	
			}
		]]
	}
	
	MainCode SingleTexturePass
	{
		Input = "VS_CUSTOM_SPLINE_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[	
			
			PDX_MAIN
			{		
				//clip(-1);
#ifndef ROAD_TYPE_ID
#define ROAD_TYPE_ID 0
#endif
				float2 UV = Input.UV;
				float2 dx=float2(0,0), dy=float2(0,0);
			
				dx = ddx(UV);
				dy = ddy(UV);
				
				return GetPixelColor( Input, UV, dx, dy, 1.2, 1, ROAD_TYPE_ID );
			}
		]]
	}
}

BlendState BlendState
{
	BlendEnable = yes
		SourceBlend = "src_alpha"
		DestBlend = "inv_src_alpha"
		WriteMask = "RED|GREEN|BLUE"
}

RasterizerState RasterizerState
{
	DepthBias = -50000
		#fillmode = wireframe
		#CullMode = none
}

DepthStencilState DepthStencilState
{
	DepthWriteEnable = no
}

Effect Background
{
	VertexShader = "VS_game"
	PixelShader = "Background"
	Defines = {"ENABLE_TERRAIN" "ENABLE_FOG" "ENABLE_GAME_CONSTANTS" }
}
Effect Foreground
{
	VertexShader = "VS_game"
	PixelShader = "Foreground"
	Defines = {"ENABLE_TERRAIN" "ENABLE_FOG" "ENABLE_GAME_CONSTANTS" }
}

Effect StackedTexturesPass
{
	VertexShader = "VS_game"
	PixelShader = "StackedTexturesPass"	
	Defines = {"ENABLE_TERRAIN" "ENABLE_FOG" "ENABLE_GAME_CONSTANTS" }
}
Effect SingleTexturePass
{
	VertexShader = "VS_game"
	PixelShader = "SingleTexturePass"
	Defines = {"ENABLE_TERRAIN" "ENABLE_FOG" "ENABLE_GAME_CONSTANTS" }
}

Code
[[
	#define CAMERA_POSITION_TO_START_INCREASING_ROADS 75.0f
	#define FLATMAP_FARAWAY_CUTOFF 0.45f
	#define	ZOOM_OUT_ROADS_SCALE 0.3f
	#define UV_X_FARAWAY_SIZE_MULT 10.0f
]]