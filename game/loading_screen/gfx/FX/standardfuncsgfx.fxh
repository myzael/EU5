
# game constants
ConstantBuffer( GameSharedConstants )
{
	float2		MapSize; //TODO This is bleeding to jomini (jomini_water_pdx_mesh.fxh), so name change is impossible, must fix it there to not use game values
	float 		_GCGlobalTime;
	float 		_GCScaledGlobalTime;
	
	float		_GCFlatMapHeight;
	float		_GCFlatMapLerp;//The real flat map lerp
	float		_GCSimulatedFlatMapLerp; //What should be the flat map lerp if none of the flatmap modifiers were on effect
	float		_GCEnableSnow;
	
	float 		_GCFlatMapNoiseSize;
	float 		_GCFlatMapLerpHeight0;
	float 		_GCFlatMapLerpHeight1;
	float		_GCWaterHeight;
	
	float		_GCGrassScatterNormalSmoothing;
	float		_GCGrassScatterRoughnessScale;
	float		_GCGrassScatterStrength;
	float		_GCGrassScatterDebug;
	
	float3		_GCSpecularBackLightDiffuse;
	float 		_GCSpecularBacklightIntensityMin;
	
	float 		_GCSpecularBacklightIntensityMax;
	float 		_GCSpecularBacklightRoughnessMin;
	float 		_GCSpecularBacklightRoughnessMax;	
	
	float 		_GCFlatMapAsFoWEnabled;
	float		_GCFlatMapFadeEdgeWidth;
	float		_GCFlatMapFadeEdgeDarkness;
	float		_GCFlatMapFadeEdgeNoiseSize;

	float 		_GCBorderTakeTerraIncognitaIntoAccount;
};

	Code
	[[
	#if defined(ENABLE_GAME_CONSTANTS)
		float2 GetMapSize(){
			return MapSize;
		}

		float 		GetGlobalTime(){
			return _GCGlobalTime;
		}

		float 		GetScaledGlobalTime(){
			return _GCScaledGlobalTime;
		}

			
		float		GetFlatMapHeight(){
			return _GCFlatMapHeight;
		}
		float		GetFlatMapLerp(){//The real flat map lerp
			return _GCFlatMapLerp;
		}
		float		GetSimulatedFlatMapLerp(){ //What should be the flat map lerp if none of the flatmap modifiers were on effect
			return _GCSimulatedFlatMapLerp;
		}
		float		GetEnableSnow(){
			return _GCEnableSnow;
		}
			
		float		GetFlatMapNoiseSize(){
			return _GCFlatMapNoiseSize;
		}
		float 		GetFlatMapLerpHeight0(){
			return _GCFlatMapLerpHeight0;
		}
		float 		GetFlatMapLerpHeight1(){
			return _GCFlatMapLerpHeight1;
		}
		float		GetWaterHeight(){
			return _GCWaterHeight;
		}

		float		GetGrassScatterNormalSmoothing(){
			return _GCGrassScatterNormalSmoothing;
		}
		float		GetGrassScatterRoughnessScale(){
			return _GCGrassScatterRoughnessScale;
		}
		float		GetGrassScatterStrength(){
			return _GCGrassScatterStrength;
		}
		float		GetGrassScatterDebug(){
			return _GCGrassScatterDebug;
		}
			
		float3		GetSpecularBackLightDiffuse(){
			return _GCSpecularBackLightDiffuse;
		}
		float 		GetSpecularBacklightIntensityMin(){
			return _GCSpecularBacklightIntensityMin;
		}
		
		float 		GetSpecularBacklightIntensityMax(){
			return _GCSpecularBacklightIntensityMax;
		}	
		float 		GetSpecularBacklightRoughnessMin(){
			return _GCSpecularBacklightRoughnessMin;
		}
		float 		GetSpecularBacklightRoughnessMax(){
			return _GCSpecularBacklightRoughnessMax;
		}
		
		float 		GetFlatMapAsFoWEnabled(){
			return _GCFlatMapAsFoWEnabled;
		}
		float		GetFlatMapFadeEdgeWidth(){
			return _GCFlatMapFadeEdgeWidth;
		}
		float		GetFlatMapFadeEdgeDarkness(){
			return _GCFlatMapFadeEdgeDarkness;
		}
		float		GetFlatMapFadeEdgeNoiseSize(){
			return _GCFlatMapFadeEdgeNoiseSize;
		}
		
		float GetBorderTakeTerraIncognitaIntoAccount()
		{
			return _GCBorderTakeTerraIncognitaIntoAccount;
		}
	#else
			float2 GetMapSize(){
			return float2(1.0,1.0);
		}

		float 		GetGlobalTime(){
			return 0.0;
		}
			
		float 		GetScaledGlobalTime(){
			return 0.0;
		}
			
		float		GetFlatMapHeight(){
			return 0.0;
		}
		float		GetFlatMapLerp(){//The real flat map lerp
			return 0.0;
		}
		float		GetSimulatedFlatMapLerp(){ //What should be the flat map lerp if none of the flatmap modifiers were on effect
			return 0.0;
		}
		float		GetEnableSnow(){
			return 0.0;
		}
			
		float		GetFlatMapNoiseSize(){
			return 0.0;
		}
		float 		GetFlatMapLerpHeight0(){
			return 0.0;
		}
		float 		GetFlatMapLerpHeight1(){
			return 0.0;
		}
		float		GetWaterHeight(){
			return 0.0;
		}
			
		float		GetGrassScatterNormalSmoothing(){
			return 0.0;
		}
		float		GetGrassScatterRoughnessScale(){
			return 0.0;
		}
		float		GetGrassScatterStrength(){
			return 0.0;
		}
		float		GetGrassScatterDebug(){
			return 0.0;
		}
			
		float3		GetSpecularBackLightDiffuse(){
			return float3(0.0,0.0,0.0);
		}
		float 		GetSpecularBacklightIntensityMin(){
			return 0.0;
		}
		
		float 		GetSpecularBacklightIntensityMax(){
			return 0.0;
		}	
		float 		GetSpecularBacklightRoughnessMin(){
			return 0.0;
		}
		float 		GetSpecularBacklightRoughnessMax(){
			return 0.0;
		}
		
		float 		GetFlatMapAsFoWEnabled(){
			return 0.0;
		}
		float		GetFlatMapFadeEdgeWidth(){
			return 0.0;
		}
		float		GetFlatMapFadeEdgeDarkness(){
			return 0.0;
		}
		float		GetFlatMapFadeEdgeNoiseSize(){
			return 0.0;
		}

		float GetBorderTakeTerraIncognitaIntoAccount()
		{
			return 0.0;
		}
	#endif
	]]
