Includes = {
	"cw/lighting_constants.fxh"
}

PixelShader =
{
	Code
	[[
		float CalcLightFalloff( float LightRadius, float Distance, float Falloff )
		{
			// TODO other, square, falloff?
			return saturate( (LightRadius - Distance) / Falloff );
		}
		
		float CalcLightFalloff( float LightRadius, float Distance )
		{
			// This is basically the unreal method, square distance falloff but capped at "LightRadius" distance and capped at intensity 1 at distance 0.
			return pow( saturate( 1.0 - pow( Distance / LightRadius, 4.0 ) ), 2.0 ) / ( Distance * Distance + 1.0 );
		}
		
		
		float3 MetalnessToDiffuse( float Metalness, float3 Diffuse )
		{
			return lerp( Diffuse, vec3(0.0), Metalness );
		}

		float3 MetalnessToSpec( float Metalness, float3 Diffuse, float Spec )
		{
			return lerp( vec3(Spec), Diffuse, Metalness );
		}
		
		
		#ifndef PDX_NumMips
			#define PDX_NumMips 10.0
		#endif
		
		#ifndef PDX_MipOffset
			#define PDX_MipOffset 2.0
		#endif
		
		#define PDX_SimpleLighting
		
		
		struct SMaterialProperties
		{
			float 	_PerceptualRoughness;
			float 	_Roughness;
			float	_Metalness;
			
			float3	_DiffuseColor;
			float3	_SpecularColor;
			float3	_Normal;
		};
		
		struct SLightingProperties
		{
			float3		_ToCameraDir;
			float3		_ToLightDir;
			float3		_LightIntensity;
			float		_ShadowTerm;
			float		_CubemapIntensity;
			// this rotation matrix is used to rotate cubemap sampling vectors, thus "faking" a rotation of the cubemap
			float4x4	_CubemapYRotation;
		};
		
		float RemapSpec( float SampledSpec )
		{
			return 0.25 * SampledSpec;
		}
			
		float RoughnessFromPerceptualRoughness( float PerceptualRoughness )
		{
			return PerceptualRoughness * PerceptualRoughness;
		}
		
		float BurleyToMipSimple( float PerceptualRoughness )
		{
		   float Scale = PerceptualRoughness * (1.7 - 0.7 * PerceptualRoughness);
		   return Scale * ( PDX_NumMips - 1 - PDX_MipOffset );
		}
		
		float3 GetSpecularDominantDir( float3 Normal, float3 Reflection, float Roughness )
		{
			float Smoothness = saturate( 1.0 - Roughness );
			float LerpFactor = Smoothness * ( sqrt( Smoothness ) + Roughness );
			return normalize( lerp( Normal, Reflection, LerpFactor ) );
		}
		
		float GetReductionInMicrofacets( float Roughness )
		{
			return 1.0 / (Roughness*Roughness + 1.0);
		}
		
		float F_Schlick( float f0, float f90, float CosAngle )
		{
			return f0 + ( f90 - f0 ) * pow( 1.0 - CosAngle, 5.0 );
		}
		
		float3 F_Schlick( float3 f0, float3 f90, float CosAngle )
		{
			return f0 + ( f90 - f0 ) * pow( 1.0 - CosAngle, 5.0 );
		}
        
		
		float DisneyDiffuse( float NdotV, float NdotL, float LdotH, float LinearRoughness )
		{
			float EnergyBias = lerp( 0.0, 0.5, LinearRoughness );
			float EnergyFactor = lerp( 1.0, 1.0 / 1.51, LinearRoughness );
			float f90 = EnergyBias + 2.0 * LdotH * LdotH * LinearRoughness;
			float LightScatter = F_Schlick( 1.0, f90, NdotL );
			float ViewScatter = F_Schlick( 1.0, f90, NdotV );
			
			return LightScatter * ViewScatter * EnergyFactor;
		}
		
		float CalcDiffuseBRDF( float NdotV, float NdotL, float LdotH, float PerceptualRoughness )
		{
		#ifdef PDX_SimpleLighting
			return 1.0 / PI;
		#else
			return DisneyDiffuse( NdotV, NdotL, LdotH, PerceptualRoughness ) / PI;
		#endif
		}
		
		
		float D_GGX( float NdotH, float Alpha )
		{
			float Alpha2 = Alpha * Alpha;
			float f = ( NdotH * Alpha2 - NdotH ) * NdotH + 1.0;
			return Alpha2 / (PI * f * f);
		}
		
		float G1( float CosAngle, float k )
		{
			return 1.0 / ( CosAngle * ( 1.0 - k ) + k );
		}
		
		float V_Schlick( float NdotL, float NdotV, float Alpha )
		{
			float k = Alpha * 0.5;
			return G1( NdotL, k ) * G1( NdotV, k ) * 0.25;
		}
		
		float V_Optimized( float LdotH, float Alpha )
		{
			float k = Alpha * 0.5;
			float k2 = k*k;
			float invk2 = 1.0 - k2;
			return 0.25 / ( LdotH * LdotH * invk2 + k2 );
		}
        
		float3 CalcSpecularBRDF( float3 SpecularColor, float LdotH, float NdotH, float NdotL, float NdotV, float Roughness )
		{
			float3 F = F_Schlick( SpecularColor, vec3(1.0), LdotH );
			float D = D_GGX( NdotH, lerp( 0.03, 1.0, Roughness ) ); // Remap to avoid super small and super bright highlights
		#ifdef PDX_SimpleLighting
			float Vis = V_Optimized( LdotH, Roughness );
		#else
			float Vis = V_Schlick( NdotL, NdotV, Roughness );
		#endif
			return D * F * Vis;
		}

		void CalculateLightingFromLight( SMaterialProperties MaterialProps, float3 ToCameraDir, float3 ToLightDir, float3 LightIntensity, out float3 DiffuseOut, out float3 SpecularOut )
		{
			float3 H = normalize( ToCameraDir + ToLightDir );
			float NdotV = saturate( dot( MaterialProps._Normal, ToCameraDir ) ) + 1e-5;
			float NdotL = saturate( dot( MaterialProps._Normal, ToLightDir ) ) + 1e-5;
			float NdotH = saturate( dot( MaterialProps._Normal, H ) );
			float LdotH = saturate( dot( ToLightDir, H ) );
			
			float DiffuseBRDF = CalcDiffuseBRDF( NdotV, NdotL, LdotH, MaterialProps._PerceptualRoughness );
			DiffuseOut = DiffuseBRDF * MaterialProps._DiffuseColor * LightIntensity * NdotL;
			
		#ifdef PDX_HACK_ToSpecularLightDir
			float3 H_Spec = normalize( ToCameraDir + PDX_HACK_ToSpecularLightDir );
			float NdotL_Spec = saturate( dot( MaterialProps._Normal, PDX_HACK_ToSpecularLightDir ) ) + 1e-5;
			float NdotH_Spec = saturate( dot( MaterialProps._Normal, H_Spec ) );
			float LdotH_Spec = saturate( dot( PDX_HACK_ToSpecularLightDir, H_Spec ) );
			float3 SpecularBRDF = CalcSpecularBRDF( MaterialProps._SpecularColor, LdotH_Spec, NdotH_Spec, NdotL_Spec, NdotV, MaterialProps._Roughness );
			SpecularOut = SpecularBRDF * LightIntensity * NdotL;
		#else
			float3 SpecularBRDF = CalcSpecularBRDF( MaterialProps._SpecularColor, LdotH, NdotH, NdotL, NdotV, MaterialProps._Roughness );
			SpecularOut = SpecularBRDF * LightIntensity * NdotL;
		#endif
		}
		
		void CalculateLightingFromLight( SMaterialProperties MaterialProps, SLightingProperties LightingProps, out float3 DiffuseOut, out float3 SpecularOut )
		{
			CalculateLightingFromLight( MaterialProps, LightingProps._ToCameraDir, LightingProps._ToLightDir, LightingProps._LightIntensity * LightingProps._ShadowTerm, DiffuseOut, SpecularOut );
		}
	
		void CalculateLightingFromIBL( SMaterialProperties MaterialProps, SLightingProperties LightingProps, PdxTextureSamplerCube EnvironmentMap, out float3 DiffuseIBLOut, out float3 SpecularIBLOut )
		{
			float3 RotatedDiffuseCubemapUV = mul( CastTo3x3( LightingProps._CubemapYRotation ), MaterialProps._Normal );
			float3 DiffuseRad = PdxTexCubeLod( EnvironmentMap, RotatedDiffuseCubemapUV, ( PDX_NumMips - 1 - PDX_MipOffset ) ).rgb * LightingProps._CubemapIntensity; // TODO, maybe we should split diffuse and spec intensity?
			DiffuseIBLOut = DiffuseRad * MaterialProps._DiffuseColor;
			
			float3 ReflectionVector = reflect( -LightingProps._ToCameraDir, MaterialProps._Normal );
			float3 DominantReflectionVector = GetSpecularDominantDir( MaterialProps._Normal, ReflectionVector, MaterialProps._Roughness );

			float NdotR = saturate( dot( MaterialProps._Normal, DominantReflectionVector ) );
			float3 SpecularReflection = F_Schlick( MaterialProps._SpecularColor, vec3(1.0), NdotR );
			float SpecularFade = GetReductionInMicrofacets( MaterialProps._Roughness );

			float MipLevel = BurleyToMipSimple( MaterialProps._PerceptualRoughness );
			float3 RotatedSpecularCubemapUV = mul( CastTo3x3( LightingProps._CubemapYRotation ), DominantReflectionVector );
			float3 SpecularRad = PdxTexCubeLod( EnvironmentMap, RotatedSpecularCubemapUV, MipLevel ).rgb * LightingProps._CubemapIntensity; // TODO, maybe we should split diffuse and spec intensity?
			SpecularIBLOut = SpecularRad * SpecularFade * SpecularReflection;
		}
	]]
}
