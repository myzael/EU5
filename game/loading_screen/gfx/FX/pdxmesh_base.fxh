Includes = {
	"cw/camera.fxh"
	"cw/pdxmesh.fxh"
	"cw/shadow.fxh"
	"cw/utility.fxh"
	"jomini/jomini_fog.fxh"
	"jomini/jomini_lighting.fxh"
	"jomini/jomini_water.fxh"
	"constants.fxh"
	"fog_of_war.fxh"
	"standardfuncsgfx.fxh"
	"units_data.fxh"
	"gbuffer.fxh"
	"specular_back_light.fxh"
	"mesh_vertexshader.fxh"
}

ConstantBuffer( CityRepaintUnitColorOpacity )
{
	float BuildingRepaintOpacityUnitColorPrimary;
	float BuildingRepaintOpacityUnitColorSecondary;
	float BuildingRepaintOpacityUnitColorTerciary;
};

struct SIllustrationData
{	
	float _RandomUV;
	float _ProportionImage;
	float2 _UVMove;
	float4 _UVRemap;
	float  _CustomFlags;
}

PixelShader =
{
	TextureSampler DiffuseMap
	{
		Index = 0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler PropertiesMap
	{
		Index = 1
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler NormalMap
	{
		Index = 2
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler CountryColorsMask
	{
		Index = 3
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler UniqueMap
    {
		Index = 5
        MagFilter = "Linear"
        MinFilter = "Linear"
        MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
    }
	TextureSampler TrimDiffuseMap
    {
		Index = 6
        MagFilter = "Linear"
        MinFilter = "Linear"
        MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
    }
	TextureSampler TrimNormalMap
    {
		Index = 9
        MagFilter = "Linear"
        MinFilter = "Linear"
        MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
    }
	TextureSampler TrimPropertiesMap
    {
		Index = 10
        MagFilter = "Linear"
        MinFilter = "Linear"
        MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
    }
	
	TextureSampler DiffuseMapOverride
	{
		Ref = PdxMeshCustomTexture0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Mirror"
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
	TextureSampler ClimateMap
	{
		Ref = ClimateMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}

}

VertexStruct VS_OUTPUT
{
    float4 Position			: PDX_POSITION;
	float3 Normal			: TEXCOORD0;
	float3 Tangent			: TEXCOORD1;
	float3 Bitangent		: TEXCOORD2;
	float2 UV0				: TEXCOORD3;
	float2 UV1				: TEXCOORD4;
	float3 WorldSpacePos	: TEXCOORD5;
	uint InstanceIndex 	: TEXCOORD6;
};


VertexShader =
{
	Code
	[[
		
		VS_OUTPUT ConvertOutput( VS_OUTPUT_PDXMESH In )
		{
			VS_OUTPUT Out;
			
			Out.Position = In.Position;
			Out.Normal = In.Normal;
			Out.Tangent = In.Tangent;
			Out.Bitangent = In.Bitangent;
			Out.UV0 = In.UV0;
			Out.UV1 = In.UV1;
			Out.WorldSpacePos = In.WorldSpacePos;
			return Out;
		}
		void CalculateSineAnimation( float2 UV, inout float3 Position, inout float3 Normal, inout float4 Tangent )
		{
			float AnimSeed = UV.x;
			const float LARGE_WAVE_FREQUENCY = 3.14f;	// Higher values simulates higher wind speeds / more turbulence
			const float SMALL_WAVE_FREQUENCY = 9.0f;	// Higher values simulates higher wind speeds / more turbulence
			const float WAVE_LENGTH_POW = 0.7f;			// Higher values gives higher frequency at the end of the flag
			const float WAVE_LENGTH_INV_SCALE = 7.0f;	// Higher values gives higher frequency overall
			const float WAVE_SCALE = 0.25f;				// Higher values gives a stretchier flag
			const float ANIMATION_SPEED = 0.5f;			// Speed

			float Time = GetScaledGlobalTime() * 1.0f * ANIMATION_SPEED;
			
			float LargeWave = sin( Time * LARGE_WAVE_FREQUENCY );
			float SmallWaveV = Time * SMALL_WAVE_FREQUENCY - pow( AnimSeed, WAVE_LENGTH_POW ) * WAVE_LENGTH_INV_SCALE;
			float SmallWaveD = -( WAVE_LENGTH_POW * pow( AnimSeed, WAVE_LENGTH_POW ) * WAVE_LENGTH_INV_SCALE );
			float SmallWave = sin( SmallWaveV );
			float CombinedWave = SmallWave + LargeWave;

			float Wave = WAVE_SCALE * AnimSeed * CombinedWave;
			float Derivative = WAVE_SCALE * ( CombinedWave + cos( SmallWaveV ) * SmallWaveD );
			float3 AnimationDir = float3( -1, 0.08, 0 );	// cross( Tangent.xyz, float3(0,1,0) );
			Position += AnimationDir * Wave;

			float2 WaveTangent = normalize( float2(  Derivative, 1.0f ) );
			float3 WaveNormal = normalize( float3( WaveTangent.y, 0.0f, -WaveTangent.x ));
			float WaveNormalStrength = 1.0f;
			Normal = normalize( lerp( Normal, WaveNormal, 1.0f * AnimSeed ) ); // wave normal strength
		}

		float4x4 CalculateRightMatrix(  in float4x4 WorldMatrix)
			{
					return float4x4(
					     0, 0,  sqrt(WorldMatrix[0][2]*WorldMatrix[0][2] +WorldMatrix[1][2] * WorldMatrix[1][2] +WorldMatrix[2][2] *WorldMatrix[2][2])/*Scale of the third column*/, 					  WorldMatrix[0][3] ,
    					 0,  sqrt(WorldMatrix[0][1]*WorldMatrix[0][1] +WorldMatrix[1][1] * WorldMatrix[1][1] +WorldMatrix[2][1] *WorldMatrix[2][1])/*Scale of the second column*/, 0, 				 	WorldMatrix[1][3] ,
    					 sqrt(WorldMatrix[0][0]*WorldMatrix[0][0] +WorldMatrix[1][0] * WorldMatrix[1][0] +WorldMatrix[2][0] *WorldMatrix[2][0])/*Scale of the first column*/, 0, 0, 						WorldMatrix[2][3] ,
    					 0, 0, 0, WorldMatrix[3][3] 
					);
			}
	]]
	
	MainCode VS_standard
	{
		Input = "VS_INPUT_PDXMESHSTANDARD"
		Output = "VS_OUTPUT"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT Out = ConvertOutput( StandardVertexShader( Input ) );
				Out.InstanceIndex = Input.InstanceIndices.y;
				return Out;
			}
		]]
	}

	MainCode VS_standard_shadow
	{
		Input = "VS_INPUT_PDXMESHSTANDARD"
		Output = "VS_OUTPUT_PDXMESHSHADOWSTANDARD"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PDXMESHSHADOWSTANDARD Out = StandardVertexShaderShadow( Input );
				return Out;
			}
		]]
	}

	MainCode VS_mapobject
	{
		Input = "VS_INPUT_PDXMESH_MAPOBJECT"
		Output = "VS_OUTPUT"
		Code
		[[
			PDX_MAIN
			{
				float4x4 WorldMatrix = UnpackAndGetMapObjectWorldMatrix( Input.Index24_Packed1_Opacity6_Sign1 );
				WorldMatrix[1][3]=GetHeight(float2 (WorldMatrix[0][3],WorldMatrix[2][3]));
				VS_OUTPUT Out = ConvertOutput( StandardVertexShader( PdxMeshConvertInput( Input ), 0/*bone offset not supported*/, WorldMatrix ) );
				Out.InstanceIndex = Input.Index24_Packed1_Opacity6_Sign1;
				return Out;
			}
		]]
	}

	MainCode VS_mapobject_shadow
	{
		Input = "VS_INPUT_PDXMESH_MAPOBJECT"
		Output = "VS_OUTPUT_MAPOBJECT_SHADOW"
		Code
		[[
			PDX_MAIN
			{
				float4x4 WorldMatrix = UnpackAndGetMapObjectWorldMatrix( Input.Index24_Packed1_Opacity6_Sign1 );
				WorldMatrix[1][3]=GetHeight(float2 (WorldMatrix[0][3],WorldMatrix[2][3]));
				VS_OUTPUT_PDXMESHSHADOW Shadow = StandardVertexShaderShadow( PdxMeshConvertInput( Input ), 0/*bone offset not supported*/, WorldMatrix ) ;
				VS_OUTPUT_MAPOBJECT_SHADOW Out ;
				Out.Position = Shadow.Position;
				Out.UV = Shadow.UV;
				Out.Index24_Packed1_Opacity6_Sign1 = Input.Index24_Packed1_Opacity6_Sign1;
				return Out;
			}
		]]
	}

	MainCode VS_sine_animation
	{
		Input = "VS_INPUT_PDXMESHSTANDARD"
		Output = "VS_OUTPUT"
		Code
		[[
			PDX_MAIN
			{
				CalculateSineAnimation( Input.UV0, Input.Position, Input.Normal, Input.Tangent );

				float4x4 WorldMatrix = PdxMeshGetWorldMatrix( Input.InstanceIndices.y );
				#if defined(PDX_MESH_SNAP_MESH_TO_TERRAIN) && defined(ENABLE_TERRAIN)
				WorldMatrix[1][3]=GetHeight(float2 (WorldMatrix[0][3],WorldMatrix[2][3]));
				#endif
				#ifdef FLAG
						VS_OUTPUT Out = ConvertOutput( StandardVertexShader( PdxMeshConvertInput( Input ), 0/*bone offset not supported*/, CalculateRightMatrix(WorldMatrix) )) ;
				#else
					VS_OUTPUT Out = ConvertOutput( StandardVertexShader( PdxMeshConvertInput( Input ), 0/*bone offset not supported*/, WorldMatrix )) ;
				#endif

				Out.InstanceIndex = Input.InstanceIndices.y;
				return Out;
			}
		]]
	}
	MainCode VS_sine_animation_shadow
	{
		Input = "VS_INPUT_PDXMESHSTANDARD"
		Output = "VS_OUTPUT_PDXMESHSHADOWSTANDARD"
		Code
		[[
			PDX_MAIN
			{

				CalculateSineAnimation( Input.UV0, Input.Position, Input.Normal, Input.Tangent );
				float4x4 WorldMatrix = PdxMeshGetWorldMatrix( Input.InstanceIndices.y );
				#ifdef FLAG
					VS_OUTPUT_PDXMESHSHADOW Basic = StandardVertexShaderShadow( PdxMeshConvertInput( Input ), 0/*bone offset not supported*/, CalculateRightMatrix(WorldMatrix) );
				#else
					VS_OUTPUT_PDXMESHSHADOW Basic = StandardVertexShaderShadow( PdxMeshConvertInput( Input ), 0/*bone offset not supported*/, WorldMatrix )) ;
				#endif
				VS_OUTPUT_PDXMESHSHADOWSTANDARD Out;
				Out.Position = Basic.Position;
				Out.UV_InstanceIndex = float3( Basic.UV, float( Input.InstanceIndices.y ) );
				return Out;
			}
		]]
	}
}

PixelShader =
{
	Code
	[[	
		
		SIllustrationData GetIllustrationUserData( uint InstanceIndex )
		{
			float4 Raw0 = Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 0 ];
			float4 Raw1 = Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 1 ];
			float4 Raw2 = Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + 2 ];
			
			SIllustrationData Ret;
			Ret._RandomUV = Raw0.x;
			Ret._ProportionImage = Raw0.y;
			Ret._UVMove = float2( Raw0.z, Raw0.w );
			Ret._UVRemap = float4(Raw1.x, Raw1.y,Raw1.z, Raw1.w);
			Ret._CustomFlags = Raw2.x;
			return Ret;
		};
			
		// This is passed on through SEntityCustomDataInstance
		#if defined( ANIMATE_UV )
			static const int USER_DATA_UV_ANIMATION = 0;
		#endif
		#if defined(FLAG)
			static const int  USER_DATA_COA_SLOT = 1;
		#endif
		// END of SEntityCustomDataInstance
	
		float2 MirrorOutsideUV(float2 UV)
		{
			if ( UV.x < 0.0 ) UV.x = -UV.x;
			else if ( UV.x > 1.0 ) UV.x = 2.0 - UV.x;
			if ( UV.y < 0.0 ) UV.y = -UV.y;
			else if ( UV.y > 1.0 ) UV.y = 2.0 - UV.y;
			return UV;
		}
	
		float4 GetUserData( uint InstanceIndex, int DataOffset )
		{
			return Data[ InstanceIndex + PDXMESH_USER_DATA_OFFSET + DataOffset ];
		}

		float GetOpacity( uint InstanceIndex )
		{
			#ifdef JOMINI_MAP_OBJECT
				return UnpackAndGetMapObjectOpacity( InstanceIndex );
			#else
				return PdxMeshGetOpacity( InstanceIndex );
			#endif
		}
	]]
	
	MainCode PS_red
	{
		Input = "VS_OUTPUT"
		Output = "PS_OUTPUT"
		Code
		[[
			PDX_MAIN
			{
				return PS_Return( float3(1,0,0), 1 );
			}
		]]
	}
	
	MainCode PS_standard
	{
		Input = "VS_OUTPUT"
		Output = "PS_OUTPUT"
		Code
		[[
			#if defined( ATLAS )
				#ifndef DIFFUSE_UV_SET
					#define DIFFUSE_UV_SET Input.UV1
				#endif
				
				#ifndef NORMAL_UV_SET
					#define NORMAL_UV_SET Input.UV1
				#endif
				
				#ifndef PROPERTIES_UV_SET
					#define PROPERTIES_UV_SET Input.UV1
				#endif
				
				#ifndef UNIQUE_UV_SET
					#define UNIQUE_UV_SET Input.UV0
				#endif
				
			#elif  defined( SHIP )

				#ifndef DIFFUSE_UV_SET
					#define DIFFUSE_UV_SET Input.UV0
				#endif
				
				#ifndef NORMAL_UV_SET
					#define NORMAL_UV_SET Input.UV0
				#endif
				
				#ifndef PROPERTIES_UV_SET
					#define PROPERTIES_UV_SET Input.UV0
				#endif
				
				#ifndef UNIQUE_UV_SET
					#define UNIQUE_UV_SET Input.UV0
				#endif
			#else
				#ifndef DIFFUSE_UV_SET
					#define DIFFUSE_UV_SET Input.UV0
				#endif
				
				#ifndef NORMAL_UV_SET
					#define NORMAL_UV_SET Input.UV0
				#endif
				
				#ifndef PROPERTIES_UV_SET
					#define PROPERTIES_UV_SET Input.UV0
				#endif
			#endif
			
	#ifdef  FLAG
		float3 SampleCoa(uint InstanceIndex ,float2 UV)
		{
			#ifdef UNIT_BUFFERS
						float4 OffsetAndScale = CoaOffsetAndScale[GetUnitCountryIndex(InstanceIndex)];
			#else
						float4 OffsetAndScale =GetUserData( InstanceIndex, USER_DATA_COA_SLOT);
			#endif 
				float Ddx = ddx(UV.x);
				float UVIsRight= saturate(sign(Ddx));
				float2 FixedUV;
				FixedUV.x = lerp(1 - UV.x, UV.x, UVIsRight);
				FixedUV.y = UV.y;
				float2 SaturatedUVs = saturate( FixedUV );
				float2 COACoords = OffsetAndScale.xy + SaturatedUVs * OffsetAndScale.zw;
				#ifdef PDX_USE_MIPLEVELTOOL
					float4 FlagTex = PdxTex2DMipTool( CoaAtlas, COACoords );
				#else
					float4 FlagTex = PdxTex2D( CoaAtlas, COACoords );
				#endif // PDX_USE_MIPLEVELTOOL
				//coa is in srgb we need to undoit
				FlagTex = FlagTex * FlagTex;

				//highlight UVs that are way outside the expected 0 to 1 range
				float epsilon = 0.05f;
				int highlightBrokenUV = (SaturatedUVs.x < FixedUV.x - epsilon) || (SaturatedUVs.x > FixedUV.x + epsilon) || (SaturatedUVs.y < FixedUV.y - epsilon) || (SaturatedUVs.y > FixedUV.y + epsilon);

				return saturate(FlagTex.xyz + float3(1.0f,1.0f,1.0f) * highlightBrokenUV);
				
		}
	#endif

			PDX_MAIN
			{
				#ifdef ANIMATE_UV
					float2 UvAnimation = GetUserData( Input.InstanceIndex, USER_DATA_UV_ANIMATION ).rg;
					float2 UvAnimationAdd = UvAnimation * GetScaledGlobalTime();
				#else	
					float2 UvAnimationAdd = vec2( 0.0f );
				#endif

				#ifndef ILLUSTRATION
					#ifdef PDX_USE_MIPLEVELTOOL
						float4 Diffuse = PdxTex2DMipTool( DiffuseMap, DIFFUSE_UV_SET + UvAnimationAdd );
					#else
						float4 Diffuse = PdxTex2D( DiffuseMap, DIFFUSE_UV_SET + UvAnimationAdd );
					#endif // PDX_USE_MIPLEVELTOOL
					#ifdef ANIMATE_UV
						Diffuse.a = PdxTex2D( DiffuseMap, DIFFUSE_UV_SET ).a;
					#endif
				#else
					float4 Diffuse;
					#if !defined(UNIT_BUFFERS) && !defined(FLAG)
						SIllustrationData IllustrationData = GetIllustrationUserData(Input.InstanceIndex);
						float RandomUV = IllustrationData._RandomUV;
						float ProportionImage = IllustrationData._ProportionImage; 
						float2 UVMove = IllustrationData._UVMove;
						float4 RemapData  = IllustrationData._UVRemap;
						uint IllustrationFlags =  uint(IllustrationData._CustomFlags);
					#else
						float RandomUV = 0.0f;
						float ProportionImage = 1.0f;
						float2 UVMove = float2(0.0f, 0.0f);
						float4 RemapData = float4(0.0f, 1.0f, 0.0f, 1.0f);
						uint  IllustrationFlags =  0;
					#endif
					
					#if !(defined(FLAG))
							float2 TexCoordInitial = DIFFUSE_UV_SET + UvAnimationAdd;
							TexCoordInitial.x = TexCoordInitial.x * ProportionImage + RandomUV;
							
							TexCoordInitial += ( GetScaledGlobalTime() * UVMove );
							float2 TexCoord;
							TexCoord.x = (RemapData.x + frac(TexCoordInitial.x) * RemapData.y);
							TexCoord.y = (RemapData.z + frac(TexCoordInitial.y) * RemapData.w);
							clip(TexCoord.y);
							clip(1-TexCoord.y);
							if((TexCoord.x<=0 || TexCoord.x>=1 ))
							{
								if( IllustrationFlags & 1)//paint twice the texture
								{
									TexCoord.x = (RemapData.x + frac(TexCoordInitial.x+0.5) * RemapData.y);
									clip(TexCoord.x);
									clip(1-TexCoord.x);
								}
								else{
									clip(-1);
								}
							}
							float2 Dd = DIFFUSE_UV_SET * RemapData.yw;
							Dd.x*=ProportionImage;
							Dd = ddx(Dd.x);
							Dd = ddy(Dd.y);
							Diffuse = PdxTex2DGrad( DiffuseMapOverride, TexCoord,Dd.x,Dd.y);
						#ifdef ANIMATE_UV					
							Diffuse.a = PdxTex2DGrad( DiffuseMapOverride, DIFFUSE_UV_SET,Dd.x,Dd.y).a;
						#endif
					#endif
				#endif


				#ifdef UNDERWATER
					Diffuse.rgb *= 0.25;
				#endif
				#if defined(TERRAIN) && defined(ENABLE_TERRAIN)
					#ifndef SHOW_IN_PAPERMAP
						float FlatmapFade = 1.0f - GetNoisyFlatMapLerp( Input.WorldSpacePos, GetFlatMapLerp() ).x;	
					#else
						#ifdef NOT_SHOW_WITHOUT_PAPERMAP
							float FlatmapFade = 1.0f - 2*GetNoisyFlatMapLerp( Input.WorldSpacePos, 1.0f - GetFlatMapLerp() ).x;	
						#else
							float FlatmapFade = 1.0f;
						#endif
					#endif
					
					clip(FlatmapFade-0.00001f);
					//TODO CAESAR-1630
					#ifndef	MAP_TABLE
						Diffuse.a = PdxMeshApplyOpacity( Diffuse.a, Input.Position.xy, GetOpacity( Input.InstanceIndex ) * FlatmapFade );				
					#endif
				
					// Devastation
					#if !defined(TERRAIN_DISABLED)
						float LocalHeight = Input.WorldSpacePos.y - GetHeight( Input.WorldSpacePos.xz );
						ApplyDevastationBuilding( Diffuse.rgb, Input.WorldSpacePos.xz, LocalHeight, DIFFUSE_UV_SET );
					#endif
				#else
				 	Diffuse.a = PdxMeshApplyOpacity( Diffuse.a, Input.Position.xy, GetOpacity( Input.InstanceIndex ) );		
				#endif
				
				#if defined( GRADIENT_BORDERS )
								float2 MapCoords = Input.WorldSpacePos.xz * _WorldSpaceToTerrain0To1;
				#endif
				
				float4 Properties = PdxTex2D( PropertiesMap, PROPERTIES_UV_SET + UvAnimationAdd );

				float4 NormalPacked = PdxTex2D( NormalMap, NORMAL_UV_SET + UvAnimationAdd );
				float3 NormalSample = UnpackRRxGNormal( NormalPacked );
				
				#if  defined(FLAG)
					#if defined ( PENNANT ) || defined ( ENSIGN )
						Diffuse.rgb = SampleCountryColor(GetUnitCountryIndex(Input.InstanceIndex),3);
					#else
						Diffuse.rgb = SampleCoa(Input.InstanceIndex,DIFFUSE_UV_SET);
					#endif
				#endif

				#if defined(HULL)
				
					float4 TrimDiffuse = PdxTex2D( TrimDiffuseMap, Input.UV1 );
					float4 TrimNormalPacked = PdxTex2D( TrimNormalMap, Input.UV1 );
					float3 TrimNormalSample = UnpackRRxGNormal( TrimNormalPacked );
					float4 TrimProperties = PdxTex2D( TrimPropertiesMap, Input.UV1 );

                    int CountryIndex = GetUnitCountryIndex(Input.InstanceIndex);
					float4 HullMask = PdxTex2D( UniqueMap, Input.UV0 );
                    //Sample Units colors primary secondary and terciary
					float3 HullColorPrimary = SampleCountryColor(CountryIndex, 3);
					float3 HullColorSecondary = SampleCountryColor(CountryIndex, 4);
					float3 HullColorTerciary = SampleCountryColor(CountryIndex, 5);

					Diffuse.rgb *= TrimDiffuse.rgb;
					NormalSample = GetOverlay( TrimNormalSample, NormalSample, 1.0 );
					//Properties = lerp( TrimProperties, Properties, 1-TrimDiffuse.a );


					Diffuse.rgb = Overlay( Diffuse.rgb, HullColorSecondary, HullMask.r * ShipRepaintOpacityUnitColorSecondary );
					Diffuse.rgb = Overlay( Diffuse.rgb, HullColorTerciary, HullMask.g * ShipRepaintOpacityUnitColorTerciary );
					Diffuse.rgb = Overlay( Diffuse.rgb, HullColorPrimary, HullMask.b * ShipRepaintOpacityUnitColorPrimary );

				#endif
				
				float3x3 TBN = Create3x3( normalize( Input.Tangent ), normalize( Input.Bitangent ), normalize( ((PDX_IsFrontFace * 2) - 1) * Input.Normal ) );
				float3 Normal = mul( NormalSample, TBN );
				
				#if defined( ATLAS )
					float4 Unique = PdxTex2D( UniqueMap, UNIQUE_UV_SET );
					
					// multiply AO
					Diffuse.rgb *= Unique.bbb;
				#endif
				
				
				#if defined(REPAINT_BUILIDNG_COUNTRY_COLORS)
					int CountryIndex = GetUnitCountryIndex(Input.InstanceIndex);
					float4 Mask = PdxTex2D( CountryColorsMask, Input.UV0 );
					float3 ColorPrimary = SampleCountryColor(CountryIndex, 3);
					float3 ColorSecondary = SampleCountryColor(CountryIndex, 4);
					float3 ColorTerciary = SampleCountryColor(CountryIndex, 5);

					Diffuse.rgb = lerp( Diffuse.rgb, ColorSecondary, Mask.r * BuildingRepaintOpacityUnitColorSecondary );
					Diffuse.rgb = lerp( Diffuse.rgb, ColorTerciary, Mask.g * BuildingRepaintOpacityUnitColorTerciary );
					Diffuse.rgb = lerp( Diffuse.rgb, ColorPrimary, Mask.b * BuildingRepaintOpacityUnitColorPrimary );
				#endif

				#if defined( ENABLE_SNOW )
					ApplySnowMeshWithAmount( Diffuse.rgb, Normal, Properties, Input.WorldSpacePos, ClimateMap, 2.0 );
				#endif
				#ifdef CITY_GRADIENT
					SCityGfxConstants CityConstants;
					float4 UserDataRaw0 = Data[Input.InstanceIndex + PDXMESH_USER_DATA_OFFSET];
					SCityGfxConstants CityGfxConstants;
					CityGfxConstants._CountryOwner = UserDataRaw0.x;
					CityGfxConstants._LocationId = UserDataRaw0.z;
				#endif
				// Gradient borders pre light
			#ifdef CITY_GRADIENT
				float2 CityColorIndex;
				const float COLOR_TEXTURE_WIDTH = 256;
				CityColorIndex.y = floor(CityGfxConstants._LocationId/ COLOR_TEXTURE_WIDTH);
				CityColorIndex.x = CityGfxConstants._LocationId- CityColorIndex.y * COLOR_TEXTURE_WIDTH;
				CityColorIndex = CityColorIndex  + vec2(0.5);
				#ifdef PDX_USE_MIPLEVELTOOL
					float4 PrimaryCityColor = PdxTex2DLoad0MipTool( ProvinceColorTexture, int2( CityColorIndex  ) );
				#else
					float4 PrimaryCityColor = PdxTex2DLoad0( ProvinceColorTexture, int2( CityColorIndex  ) );
				#endif // PDX_USE_MIPLEVELTOOL
			#endif
				#ifndef NO_BORDERS
					#if defined( GRADIENT_BORDERS )
						float3 ColorOverlay;
						float PreLightingBlend;
						float PostLightingBlend;
						#ifdef CITY_GRADIENT
							GetProvinceOverlayAndBlendForCityCustom( MapCoords, CityColorIndex, PrimaryCityColor, ColorOverlay, PreLightingBlend, PostLightingBlend );
						#else
							GetProvinceOverlayAndBlendCustom( MapCoords, ColorOverlay, PreLightingBlend, PostLightingBlend );
						#endif
						Diffuse.rgb = ApplyGradientBorderColorPreLighting( Diffuse.rgb, ColorOverlay, PreLightingBlend );
					#endif
				#endif

				#if defined( GRADIENT_BORDERS )
					#ifdef CITY_GRADIENT
						#ifdef PDX_USE_MIPLEVELTOOL
							float4 HighlightColor = PdxTex2DLoad0MipTool( ProvinceColorTexture, int2( CityColorIndex + HighlightProvinceColorsOffset));
						#else
							float4 HighlightColor = PdxTex2DLoad0( ProvinceColorTexture, int2( CityColorIndex + HighlightProvinceColorsOffset));
						#endif // PDX_USE_MIPLEVELTOOL
					#else
						float4 HighlightColor = BilinearColorSampleAtOffset( MapCoords, IndirectionMapSize, InvIndirectionMapSize, ProvinceColorIndirectionTexture, ProvinceColorTexture, HighlightProvinceColorsOffset );
					#endif

					Diffuse.rgb = lerp( Diffuse.rgb, HighlightColor.rgb, HighlightColor.a );
				#endif

				float3 Color = Diffuse.rgb;
				float Alpha = Diffuse.a;

				#ifndef ILLUSTRATION				
					SMaterialProperties MaterialProps = GetMaterialProperties( Diffuse.rgb, Normal, Properties.a, Properties.g, Properties.b );
					SLightingProperties LightingProps;
					#ifndef FLATLIGHT
						LightingProps = GetSunLightingProperties( Input.WorldSpacePos, ShadowTexture );



						#ifdef LIGHT_INTENSITY_FACTOR
						LightingProps._LightIntensity *= LIGHT_INTENSITY_FACTOR; // LIGHT_INTENSITY_FACTOR is required to be defined with a value, for example "LIGHT_INTENSITY_FACTOR 2.5"
						#endif
						#ifdef CUBEMAP_INTENSITY_FACTOR
						LightingProps._CubemapIntensity *= CUBEMAP_INTENSITY_FACTOR; // CUBEMAP_INTENSITY_FACTOR is required to be defined with a value, for example "CUBEMAP_INTENSITY_FACTOR 2.5"
						#endif
						#ifdef ROUGHTNESS_FACTOR
						MaterialProps._Roughness = pow(MaterialProps._Roughness, ROUGHTNESS_FACTOR);// ROUGHTNESS_FACTOR is required to be defined with a value, for example "ROUGHTNESS_FACTOR 0.5"
						//MaterialProps._Roughness = MaterialProps._Roughness*ROUGHTNESS_FACTOR;// ROUGHTNESS_FACTOR is required to be defined with a value, for example "ROUGHTNESS_FACTOR 0.5"
						#endif

						Color = CalculateSunLighting( MaterialProps, LightingProps, EnvironmentMap );
						ApplySpecularBackLight( Color, MaterialProps, LightingProps );


						// Color overlay post light
						#ifndef NO_BORDERS
							#if defined( GRADIENT_BORDERS )
								Color = ApplyGradientBorderColor( Color, ColorOverlay, PostLightingBlend );
							#endif
						#endif

						#if !defined(UNDERWATER) && defined(ENABLE_FOG)
							Color = ApplyFogOfWar( Color, Input.WorldSpacePos, FogOfWarAlpha );
							Color = ApplyDistanceFog( Color, Input.WorldSpacePos );
						#endif
										
						#ifdef UNDERWATER
							clip( _WaterHeight - Input.WorldSpacePos.y + 0.1 ); // +0.1 to avoid gap between water and mesh
						
							Alpha = CompressWorldSpace( Input.WorldSpacePos );
						#endif
						DebugReturn( Color, MaterialProps, LightingProps, EnvironmentMap );					
					#else
						LightingProps = GetSunLightingProperties( Input.WorldSpacePos, ShadowTexture );
						LightingProps._ToLightDir = float3(0.0, 1.0, 0.0);
						LightingProps._LightIntensity = float3(1.0, 1.0, 1.0);
						LightingProps._ShadowTerm = 0.0f;

						Color = CalculateSunLighting( MaterialProps, LightingProps, EnvironmentMap );
						ApplySpecularBackLight( Color, MaterialProps, LightingProps );
					#endif
					return PS_Return( Color, Alpha, MaterialProps );
				#else
					return PS_Return( Color, Alpha );
				#endif
				clip( Alpha - 0.0001f );

			}
		]]
	}
}


BlendState BlendState
{
	BlendEnable = no
}

BlendState alpha_blend
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
}

BlendState alpha_additive
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "ONE"
	WriteMask = "RED|GREEN|BLUE|ALPHA"
}

BlendState alpha_to_coverage
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
	AlphaToCoverage = yes
}

BlendState added_alphas
{
	BlendEnable = yes
	SourceBlend = "src_alpha"
	DestBlend = "inv_src_alpha"
	SourceAlpha = "ONE"
	DestAlpha = "ONE"
	blendop = "Add"
}

DepthStencilState DepthStencilState
{
	StencilEnable = yes
	FrontStencilPassOp = replace
	StencilRef = 1
}

DepthStencilState depth_no_write
{
	DepthEnable = yes
	DepthWriteEnable = no
}


RasterizerState ShadowRasterizerState
{
	DepthBias = 40000
	SlopeScaleDepthBias = 2
}

RasterizerState ShadowRasterizerState_two_sided
{
	DepthBias = 40000
	SlopeScaleDepthBias = 2
	CullMode = None
}

RasterizerState RasterizerState_two_sided
{
	CullMode = None
}

