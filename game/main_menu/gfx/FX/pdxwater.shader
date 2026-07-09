Includes = {
	"cw/heightmap.fxh"
	"jomini/jomini_province_overlays.fxh"
	"water_default.fxh"
	"jomini/jomini_water_pdxmesh.fxh"
	"jomini/jomini_mapobject.fxh"
	"jomini/jomini_fog.fxh"
	"standardfuncsgfx.fxh"
	"fog_of_war.fxh"
	"gbuffer.fxh"
	"winter.fxh"
	"terrain.fxh"
}

VertexStruct VS_OUTPUT_WATER_EXT
{
	float4 Position			: PDX_POSITION;
	float3 WorldSpacePos	: TEXCOORD0;
	float2 UV01				: TEXCOORD1;
	float4 ShadowProj		: TEXCOORD2;
};

VertexShader =
{
	MainCode WaterVertexShader
	{
		Input = "VS_INPUT_WATER"
		Output = "VS_OUTPUT_WATER_EXT"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_WATER_EXT VertexOut;
				VertexOut.WorldSpacePos = float3( Input.Position.x, _WaterHeight, Input.Position.y );
				
				#ifdef JOMINIWATER_BORDER_LERP
					VertexOut.WorldSpacePos.x = JOMINIWATER_MapSize.x + Input.Position.x * JOMINIWATER_BorderLerpSize;
				#endif
				
				VertexOut.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( VertexOut.WorldSpacePos.xyz, 1.0 ) );
				
				VertexOut.UV01 = float2( VertexOut.WorldSpacePos.x / JOMINIWATER_MapSize.x, 1.0 - VertexOut.WorldSpacePos.z / JOMINIWATER_MapSize.y );

				VertexOut.ShadowProj = mul( ShadowMapTextureMatrix, float4( VertexOut.WorldSpacePos, 1.0 ) );
				
				return VertexOut;
			}
		]]
	}

	Code
	[[
		VS_OUTPUT_WATER_EXT ConvertOutputWaterExt( VS_OUTPUT_PDXMESH MeshOutput )
		{
			VS_OUTPUT_WATER_EXT Output;
				
			Output.Position = MeshOutput.Position;
			Output.WorldSpacePos = MeshOutput.WorldSpacePos;
			Output.UV01 = float2( MeshOutput.WorldSpacePos.x / MapSize.x, 1.0 - MeshOutput.WorldSpacePos.z / MapSize.y );
			
			return Output;
		}
	]]

	MainCode VS_jomini_water_mesh_ext
	{
		Input = "VS_INPUT_PDXMESHSTANDARD"
		Output = "VS_OUTPUT_WATER_EXT"
		Code
		[[
			PDX_MAIN
			{
				return ConvertOutputWaterExt( PdxMeshVertexShaderStandard( Input ) );
			}
		]]
	}

	MainCode VS_jomini_water_mapobject_ext
	{
		Input = "VS_INPUT_PDXMESH_MAPOBJECT"
		Output = "VS_OUTPUT_WATER_EXT"
		Code
		[[
			PDX_MAIN
			{
				return ConvertOutputWaterExt( PdxMeshVertexShader( PdxMeshConvertInput( Input ), 0, UnpackAndGetMapObjectWorldMatrix( Input.Index24_Packed1_Opacity6_Sign1 ) ) );				
			}
		]]
	}

}

PixelShader =
{
	# Jomini specific
	TextureSampler ShadowMap
	{
		Ref = PdxShadowmap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		CompareFunction = less_equal
		SamplerType = "Compare"
	}

	# Game specific
	TextureSampler ClimateMap
	{
		Ref = ClimateMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
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
	
	TextureSampler FlatMapTexture
	{
		Ref = FlatMap0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	
	TextureSampler FlatMapDetail
	{
		Ref = FlatMap1
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}

	TextureSampler DetailDiffuseIce
	{
		Ref = DynamicTerrainMask7
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/terrain2/terrain_textures/unmasked/ice_diffuse.dds"
	}

	TextureSampler DetailNormalIce
	{
		Ref = DynamicTerrainMask8
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/terrain2/terrain_textures/unmasked/ice_normal.dds"
	}

	TextureSampler DetailPropertiesIce
	{
		Ref = DynamicTerrainMask9
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/terrain2/terrain_textures/unmasked/ice_properties.dds"
	}

	TextureSampler SeaCurrentWaves
	{
		Ref = DynamicTerrainMask11
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/particles/textures/wave_2x2.dds"
	}	

	# TODO, get rid of Fog calculation in jomini?
	MainCode WaterPixelShader
	{
		Input = "VS_OUTPUT_WATER_EXT"
		Output = "PS_OUTPUT"
		Code
		[[

			
			void ApplyIce( inout SWaterOutput Water, in VS_OUTPUT_WATER_EXT Input )
			{
				float WinternessWater = GetSnowAmountForWater( Water._Normal, Input.WorldSpacePos, ClimateMap );
				float WinternessTerrain = GetSnowAmountForTerrain( Water._Normal, Input.WorldSpacePos, ClimateMap );
				float Winterness = lerp( WinternessWater, WinternessTerrain, 0.5f );
							
				if( Winterness > 0.0f )
				{
					float2 CoastTextureUV; //We have clear watercolor in land that in sea, we'll take advantage of that to generate the ice without extra tetures
					CoastTextureUV.x = Input.WorldSpacePos.x;
					CoastTextureUV.y = Input.WorldSpacePos.z;
					CoastTextureUV*= _WorldSpaceToTerrain0To1;
					CoastTextureUV.y = 1-CoastTextureUV.y;
					float CoastMask =  saturate(PdxTex2D( FlatMapTexture, CoastTextureUV ).a);
					float2 UV = Input.WorldSpacePos.xz * _InvMaterialTileSize;


					float UntileNoise = PdxTex2D( TerrainBlendNoise, Input.WorldSpacePos.xz * 0.058125   ).r;
					float4 Diffuse = SampleNoTile( DetailDiffuseIce, UV, UntileNoise, 0.37 );

					
					float BaseBlend = RemapClamped( Winterness, IceWinternessMin, IceWinternessMax, 0.0f, 1.0f );
					float FrozenStep = smoothstep(0.9,1.0,WinternessWater);
					float RealIceWaterDepthMax = lerp(IceWaterDepthMax, max(Water._Depth*2,IceWaterDepthMax),FrozenStep);
					BaseBlend *= RemapClamped( Water._Depth, IceWaterDepthMin, RealIceWaterDepthMax, 1.0f, 0.0f );
					BaseBlend *= smoothstep(0.4,0.5,CoastMask+FrozenStep);
					BaseBlend += saturate(CoastMask-0.4);

					float IceBaseBlend = smoothstep( 0.0f, IceBaseFadeRange, BaseBlend );

					float WaterBaseBlend = 1.0f - BaseBlend;// smoothstep( 1.0f, 0.5, BaseBlend );
					
					float2 Weights = float2( IceBaseBlend + Diffuse.a, WaterBaseBlend * 2.0f );
					
					float BlendStart = max( Weights.x, Weights.y ) - IceDetailFadeRange;
					
					float2 Blend = max( Weights - vec2( BlendStart ), vec2( 0.0f ) );
					float2 Normalized = Blend / ( dot(Blend, vec2(1.0f) ) + 0.0000001f );
					
					if( Normalized.x > 0.0f )
					{
						float3 Normal = UnpackRRxGNormal( PdxTex2D( DetailNormalIce, UV ) ).xzy;
						float4 Properties = SampleNoTile( DetailPropertiesIce, UV, UntileNoise, 0.37 );
						
						float Snow = smoothstep( IceBaseFadeRange, 1.0f, BaseBlend );
						Snow *= smoothstep( 0.4f, 1.0f, WinternessTerrain );
						if( Snow > 0.0f )
						{
							float2 SnowUV = UV.xy;
							float4 SnowDiffuse = PdxTex2D( DetailDiffuseSnow, SnowUV );
							float3 SnowNormal = UnpackRRxGNormal( PdxTex2D( DetailNormalSnow, SnowUV ) ).xzy;
							float4 SnowProperties = PdxTex2D( DetailPropertiesSnow, SnowUV );
							
							Diffuse = lerp( Diffuse, SnowDiffuse, Snow );
							Normal = normalize( lerp( Normal, SnowNormal, Snow ) );
							Properties = lerp( Properties, SnowProperties, Snow );
						}
						
						SMaterialProperties MaterialProps = GetMaterialProperties( Diffuse.rgb, Normal, Properties.a, Properties.g, Properties.b );
						SLightingProperties LightingProps = GetSunLightingProperties( Input.WorldSpacePos, 1.0f );

						float3 Color = CalculateSunLighting( MaterialProps, LightingProps, EnvironmentMap );
						
						Water._Color.rgb = Color * Normalized.x + Water._Color.rgb * Normalized.y;
						Water._Normal = Normal * Normalized.x + Water._Normal * Normalized.y;
						
						float IceReflectionAmount = Water._ReflectionAmount * ( 1.0f - Snow ); //hack for SSR
						Water._ReflectionAmount = IceReflectionAmount * Normalized.x + Water._ReflectionAmount * Normalized.y;
					}
				}
			}
			PDX_MAIN
			{
				float2 FlatMapBlend = GetNoisyFlatMapLerp( Input.WorldSpacePos, GetFlatMapLerp() );
				float2 FlatMapCoords = Input.WorldSpacePos.xz * _WorldSpaceToTerrain0To1;
				float4 WaterSeaCurrentInterference = vec4(0);
				SSeaCurrentLocationData SeaCurrentLocationData = CalcSeaCurrent(FlatMapCoords) ;
				if(SeaCurrentLocationData._RotationData != 0)
				{
					float Noise = PdxTex2DLod0( TerrainBlendNoise, 4*Input.WorldSpacePos.xz / max( 1.0f, GetFlatMapNoiseSize() ) ).r;
					Noise *= lerp(0.2,1.25,saturate((CameraPosition.y-50)/700));
					float Time = GetGlobalTime() * _SeaCurrentsAnimationSpeed3D;
					float2 UV = Input.WorldSpacePos.xz - SeaCurrentLocationData._LocationPosition;
					float2 RotatedUVs = RotateUV(UV* _SeaCurrentsUVScale3D,vec2(0.0f), SeaCurrentLocationData._RotationData+PI*0.5);
					RotatedUVs +=  SeaCurrentLocationData._LocationPosition + Noise;
					RotatedUVs.y += Time;
					float TotalSeaCurrentSeparation = _SeaCurrentsWavesSeparation3D + 1.0;
					float2 RUVdivSeparation = RotatedUVs/TotalSeaCurrentSeparation;
					float2 RotatedUvsFrac = (frac(RUVdivSeparation )) * TotalSeaCurrentSeparation;
					
					float2 RandomSeed = floor(RUVdivSeparation );
					float4 SeededNoise  = float4(CalcRandom(RandomSeed.x*1.1245+RandomSeed.y),
												 CalcRandom(RandomSeed.x*0.7335+RandomSeed.y*1.2345),
												 CalcRandom(RandomSeed.x*0.597+RandomSeed.y*1.4925),
												 CalcRandom(RandomSeed.x*2.7335+RandomSeed.y*0.5445)
												 );
					float2 ToCheckUV = RotatedUvsFrac;
					float2 MultipliyerUV =  vec2(1.0)+(SeededNoise.zw-vec2(0.5))*_SeaCurrentsUVScaleDistorsion3D;
					ToCheckUV-=SeededNoise.xy*(_SeaCurrentsWavesSeparation3D);
					ToCheckUV*=MultipliyerUV;
					float TotalRandom =  SeededNoise.x+SeededNoise.y+SeededNoise.z+SeededNoise.w;
					if(  _SeaCurrentsDisappearenceDebug3D||( TotalRandom > 1.8 &&ToCheckUV.x > 0.0 && ToCheckUV.y > 0.0 && ToCheckUV.x < 1.0 && ToCheckUV.y < 1.0 && CalcRandom(RandomSeed)<_SeaCurrentsSpawnChance3D))
					{
						float2 FinalUvsFrac=ToCheckUV*0.5;
						
						FinalUvsFrac+=float2(0.5 *(0.5>CalcRandom(RandomSeed.x*1.5748)>0.5) ,0.5 * (CalcRandom(RandomSeed.y*1.6987)>0.5));//randomize between 1 of 4 diferent waves
						WaterSeaCurrentInterference = PdxTex2D(SeaCurrentWaves,FinalUvsFrac);
						float2 LocalPosition= RotateUV(UV, vec2(0.0), SeaCurrentLocationData._RotationData);
						LocalPosition *= _SeaCurrentsDisappearenceUvScale3D;
						LocalPosition.x+=Time;
						float2 LocalPositionSin = sin(LocalPosition.x+sin(LocalPosition.y+Time)*0.125);
						float Value =dot(LocalPositionSin,LocalPositionSin);
						float Dissapear = saturate(Value-_SeaCurrentsDisappearenceThresshold3D)*_SeaCurrentsDisappearenceDissapearanceSpeed3D+_SeaCurrentsDisappearenceThressholdCorrection3D;
						float DissapearPow=1.0+4*saturate(1.0-Dissapear);
						WaterSeaCurrentInterference.a=pow(WaterSeaCurrentInterference.a*Dissapear, DissapearPow);
						WaterSeaCurrentInterference.a *= CalcSeaCurrentLocationForce(FlatMapCoords,Input.WorldSpacePos.xz, SeaCurrentLocationData);
						WaterSeaCurrentInterference.rgb = vec3(WaterSeaCurrentInterference.a);
						if(_SeaCurrentsDisappearenceDebug3D)
						{
							WaterSeaCurrentInterference.a=1.0;
							WaterSeaCurrentInterference.rgb= lerp( WaterSeaCurrentInterference.rgb, vec3(saturate(Dissapear)),_SeaCurrentsDisappearenceDebug3D);
						}
						
					}
					// if(RotatedUvsFrac.x<= 0.01 || RotatedUvsFrac.x+0.01>=TotalSeaCurrentSeparation) //Debug code to check chunk borders
					// {
					// 	WaterSeaCurrentInterference.a=1.0;
					// 	WaterSeaCurrentInterference.rgb =  float3(0.0,1.0,0.0);
					// }
					// if(RotatedUvsFrac.y<= 0.01 || RotatedUvsFrac.y+0.01>=TotalSeaCurrentSeparation)
					// {
					// 	WaterSeaCurrentInterference.a=1.0;
					// 	WaterSeaCurrentInterference.rgb =  float3(0.0,1.0,0.0);
					// }
					//WaterSeaCurrentInterference.a=1.0;
					//WaterSeaCurrentInterference.rgb =  float3(0.0,1.0,0.0);
				}
				float2 HeightmapCoordinate = Input.WorldSpacePos.xz;
				#ifdef JOMINIWATER_BORDER_LERP
					HeightmapCoordinate.x -= JOMINIWATER_MapSize.x;
				#endif
				float Height = GetHeight( HeightmapCoordinate );
				
				SWaterParameters Params;
				Params._ScreenSpacePos = Input.Position;
				Params._WorldSpacePos = Input.WorldSpacePos;
				Params._WorldUV = Input.UV01;
				Params._Depth = Input.WorldSpacePos.y - Height;
				Params._NoiseScale = 0.05f;
				Params._WaveSpeedScale = 1.0f;
				Params._WaveNoiseFlattenMult = lerp(1.0f,2.0f,saturate(WaterSeaCurrentInterference.a));
				Params._FlowNormal = CalcFlow( FlowMapTexture, FlowNormalTexture, Params._WorldUV, Params._WorldSpacePos.xz, Params._FlowFoamMask );
				Params._FlowNormal = lerp(Params._FlowNormal,float3(0.0,1.0,0.0), saturate(WaterSeaCurrentInterference.a*4));
				//Material._FlowNormal = float3(1.0,0.0f,0.0f);
				SWaterOutput Water = CalcWater( Params );
				ApplyIce( Water, Input );
				Water._Color.rgb += WaterSeaCurrentInterference.a*WaterSeaCurrentInterference.rgb*0.25;
				//Water._Color.rgb = lerp(Water._Color.rgb, WaterSeaCurrentInterference.rgb, WaterSeaCurrentInterference.a*WaterSeaCurrentInterference.a*0.25);
				Water._Normal = lerp(Params._FlowNormal,float3(0.0,1.0,0.0),  saturate(WaterSeaCurrentInterference.a*4));
				
				#if  defined(WATER_COLOR_OVERLAY)
				
					float2 ColorMapCoords = float2( Input.UV01.x, 1.0f - Input.UV01.y ) + ( 1.0f / GetMapSize() ) * 0.5f;
					float3 BorderColor;
					float BorderPreLightingBlend;
					float BorderPostLightingBlend;
					GetProvinceOverlayAndBlendCustom( ColorMapCoords, BorderColor, BorderPreLightingBlend, BorderPostLightingBlend );

					// Make border colors visible only below the sea level
					float AccurateHeight = GetHeight( ColorMapCoords );
					BorderPreLightingBlend *= 1.0f - Levels( max( AccurateHeight - ( _WaterHeight - 0.05f ), 0.0f ), 0.0f, 0.05f );

					Water._Color.rgb = lerp( Water._Color.rgb, BorderColor, BorderPreLightingBlend );
				#endif
				
				
				if( FlatMapBlend.x > 0.0f )
				{
					
					float3 FlatMap = FlatTerrainShader( Input.WorldSpacePos, FlatMapCoords, FlatMapTexture, FlatMapDetail, false ).rgb;
					Water._Color.rgb = lerp( Water._Color.rgb, FlatMap * FlatMapBlend.y, FlatMapBlend.x );
					Water._ReflectionAmount *= 1.0f - FlatMapBlend.x;
				}

				float ShadowTerm = 1.0;
					
				#ifdef SHADOWS_ENABLED
				ShadowTerm = CalculateShadow( Input.ShadowProj, ShadowMap );
				if (ShadowTerm < 1.0)
				{
					if (SHADOWS_INTENSITY < 0.5)
					{
						ShadowTerm = lerp(1.0, ShadowTerm, SHADOWS_INTENSITY / 0.5);
					}
					else
					{
						ShadowTerm = lerp(ShadowTerm, 0.0, (SHADOWS_INTENSITY - 0.5) / 0.5);
					}
					
				}
				#endif

				Water._Color.rgb *= ShadowTerm;
				
				SMaterialProperties Material;
				Material._PerceptualRoughness = 0.0f;
				Material._Roughness = 0.0f;
				Material._Metalness = 0.0f;				
				Material._DiffuseColor = Water._Color.rgb;
				Material._SpecularColor = vec3( Water._ReflectionAmount );
				Material._Normal = Water._Normal;
				
				Water._Color.rgb = ApplyFogOfWar( Water._Color.rgb, Input.WorldSpacePos, FogOfWarAlpha );
				if( GetFlatMapLerp() < 1.0f )
				{
					float3 FoggedColor = ApplyDistanceFog( Water._Color.rgb, Input.WorldSpacePos );
					Water._Color.rgb = lerp( FoggedColor, Water._Color.rgb, GetFlatMapLerp() );
				}
				//float4 MapColor = BilinearColorSample( FlatMapCoords, IndirectionMapSize, InvIndirectionMapSize, ProvinceColorIndirectionTexture, SeaColorsTexture );
				//float WaterMask = RemapClamped( MapColor.r, 1.0, 0.8, 0.0, 1.0 );
				//Water._Color.a *= WaterMask;
				if(Water._Color.a <= 0.0)
				{
					discard;
				}
				return PS_Return( Water._Color, Material );
			}
		]]
	}
}

RasterizerState WaterRasterizer
{
	DepthBias = -10
}

RasterizerState RasterizerStateBorderLerp
{
	DepthBias = -200
	SlopeScaleDepthBias = -1
}

DepthStencilState DepthStencilStateBorderLerp
{
	DepthWriteEnable = no
}

BlendState GBufferBlendState
{
	BlendEnable = yes
	SourceBlend = "SRC_COLOR"
	DestBlend = "ZERO"
	BlendOp = "ADD"
	SourceAlpha = "ONE"
	DestAlpha = "ZERO"
	BlendOpAlpha = "ADD"
	WriteMask = "RED|GREEN|BLUE|ALPHA"
}

Effect water
{
	VertexShader = "WaterVertexShader"
	PixelShader = "WaterPixelShader"

	RasterizerState = "WaterRasterizer"
	
	Defines = {
		"SHADOWS_ENABLED"
		"SHADOWS_INTENSITY 0.5" # Values between 0.0 and 1.0, with 0.5 being the default intensity.
		"WATER_COLOR_OVERLAY"
	}

	BlendStates = { "BlendState" "GBufferBlendState" "GBufferBlendState" "GBufferBlendState" }
}

Effect water_border_lerp
{
	VertexShader = "WaterVertexShader"
	PixelShader = "WaterPixelShader"
	
	RasterizerState = "RasterizerStateBorderLerp"
	DepthStencilState = "DepthStencilStateBorderLerp"
	
	Defines = { "JOMINIWATER_BORDER_LERP"  }
}

Effect lake
{
	VertexShader = "VS_jomini_water_mesh_ext"
	PixelShader = "WaterPixelShader"
}

Effect lake_mapobject
{
	VertexShader = "VS_jomini_water_mapobject_ext"
	PixelShader = "WaterPixelShader"
}