Includes = {
	"cw/utility.fxh"
}

supports_additional_shader_options = {
	PDX_GUI_SPRITE_EFFECT
	PDX_GUI_FRAME_BLEND_EFFECT
}

Code
[[
	// Previously PDX_GUI_MAX_NUM_SPRITES, however this is just a hard coded constant and is directly reflected here instead. 
	// See NPdxGuiHelpers::MaxSprites in code..
	
	static const int MaxSprites = 11;
]]

PixelShader =
{
	ConstantBuffer( PdxGuiSpriteConstants )
	{
		#TODO [FM]: PSGE-5875
		#All instances of '11' here represent the value in the MaxSprites variable. However, due to our 
		#current shader reordering of code, we can't declare our constant in a way that it appears above the constant buffers. 
		
		float4 SpriteTextureAndFrameUVSize[11];
		float4 SpriteBorder[11];
		float4 SpriteTranslateRotateUVAndAlpha[11];
		float4 SpriteSize;
		float4 SpriteUVRect;
		int4   SpriteFramesTypeBlendMode[11];
		int4   SpriteFrameAndGridSize[11];
		float4 SpriteModifyTexturesColors[11];
		float4 SpriteFrameBlendAlpha[11/4+11%2];
		uint4  MirrorFlags[11/4+11%2];
		int    ModifyTexturesCount;
		float  SamplerBias;
	};

	Code
	[[
		// Icon resamplers, gated by PDXGUI_ICON_FILTER_* global defines driven from
		// the game's "Icon Scaling Quality" setting.
		//   NONE     = point-sample mip 0 (snap UV to texel center). Maximum sharpness.
		//   (default) = engine bilinear+mip path (PdxTex2DGrad/Bias) — Smooth tier.
		//   MITCHELL = Mitchell-Netravali bicubic from mip 0. Sharp without ringing.

#ifdef PDXGUI_ICON_FILTER_NONE
		// "None" tier: point-sampled nearest-neighbor of mip 0. Snaps the UV to the
		// nearest texel center so the bilinear sampler returns that texel's value
		// directly, with no blending — pure source pixels at any zoom.
		float4 SamplePointMip0( in PdxTextureSampler2D tex, float2 uv, float2 texSize )
		{
			float2 texelCenter = ( floor( uv * texSize ) + 0.5 ) / texSize;
			return PdxTex2DLod0( tex, texelCenter );
		}
#endif // PDXGUI_ICON_FILTER_NONE

		// Mitchell-Netravali bicubic (B = C = 1/3 — the canonical "no-ringing,
		// still-sharp" parameters from the 1988 paper). Mitchell's negative side-lobes
		// are small, so it doesn't amplify high frequencies at hard edges — no
		// ladder/staircase on diagonals and curves in UI icons.
		// 4×4 kernel implemented as a 3×3 pattern of bilinear fetches: the inner
		// positive-weight pair on each axis (taps at offsets 0 and +1 from texPos1)
		// folds into a single hardware-bilinear sample at the weight-ratio midpoint,
		// turning what would be 16 point fetches into 9 bilinear fetches with
		// identical math.
#ifdef PDXGUI_ICON_FILTER_MITCHELL
		// Mitchell B=C=1/3 weights as closed-form cubics in f ∈ [0,1).
		//
		// The kernel is piecewise:
		//   |x| < 1:    (7|x|^3 - 12|x|^2 + 16/3) / 6     (inner lobe, positive)
		//   1 ≤ |x| < 2: (-7/3·|x|^3 + 12|x|^2 - 20|x| + 32/3) / 6  (outer lobe, slightly negative)
		// The 4 taps have inputs at distances {1+f, f, 1-f, 2-f} from the resample
		// position. Inputs 1+f and 2-f always land in [1,2] (outer); f and 1-f always
		// land in [0,1] (inner). So each weight is a single fixed cubic in f — no
		// branches, no kernel-function calls. Vectorized into float4 below.
		//
		// Partition of unity: w0+w1+w2+w3 = 1 for all f (verified by hand —
		// constant terms sum to 1, f/f²/f³ terms cancel exactly). No normalization
		// needed.
		float4 ComputeMitchellWeights4( float f )
		{
			float f2 = f * f;
			float f3 = f2 * f;
			// Each component is one tap's cubic:
			//   .x = w0 = MitchellOuter(1+f)  = 1/18 - f/2 + 5f²/6 - 7f³/18
			//   .y = w1 = MitchellInner(f)    = 8/9       - 2f²   + 7f³/6
			//   .z = w2 = MitchellInner(1-f)  = 1/18 + f/2 + 3f²/2 - 7f³/6
			//   .w = w3 = MitchellOuter(2-f)  =            - f²/3  + 7f³/18
			const float4 c0 = float4( 1.0/18.0,  8.0/9.0,    1.0/18.0,    0.0       );
			const float4 c1 = float4( -0.5,      0.0,        0.5,          0.0       );
			const float4 c2 = float4( 5.0/6.0,  -2.0,        1.5,         -1.0/3.0   );
			const float4 c3 = float4( -7.0/18.0, 7.0/6.0,   -7.0/6.0,      7.0/18.0  );
			return c0 + c1 * f + c2 * f2 + c3 * f3;
		}

		float4 SampleMitchellMip0( in PdxTextureSampler2D tex, float2 uv, float2 texSize )
		{
			float2 invTexSize = 1.0 / texSize;
			float2 samplePos  = uv * texSize;
			// texPos1: center of the texel just left of the resampled position (in texel
			// coords; texel n's center is at coord n+0.5, so this lands on n+0.5 for an
			// integer n). f is the fractional offset from there, in [0, 1).
			float2 texPos1    = floor( samplePos - 0.5 ) + 0.5;
			float2 f          = samplePos - texPos1;

			// 4 taps at integer offsets {-1, 0, +1, +2} from texPos1 along each axis.
			float4 wx = ComputeMitchellWeights4( f.x );
			float4 wy = ComputeMitchellWeights4( f.y );
			float wx0 = wx.x, wx1 = wx.y, wx2 = wx.z, wx3 = wx.w;
			float wy0 = wy.x, wy1 = wy.y, wy2 = wy.z, wy3 = wy.w;

			// Inner pair (wx1, wx2) on each axis collapses into one bilinear fetch:
			// hardware bilinear at offset ox12 = wx2 / (wx1 + wx2) between the two
			// texel centers returns wx1*T[1] + wx2*T[2] when multiplied by (wx1+wx2).
			// Both inner weights come from Mitchell's positive lobe (|x| < 1), so the
			// offset stays in [0,1] and the sampler can encode the pair exactly.
			// The outer taps (wx0, wx3) span the negative side-lobes and can't be
			// folded the same way; they remain as point fetches at integer texel
			// centers — hardware bilinear at a centered UV returns just that texel.
			float wx12 = wx1 + wx2;
			float wy12 = wy1 + wy2;
			float ox12 = wx2 / wx12;
			float oy12 = wy2 / wy12;

			float xc0  = ( texPos1.x - 1.0  ) * invTexSize.x;
			float xc12 = ( texPos1.x + ox12 ) * invTexSize.x;
			float xc3  = ( texPos1.x + 2.0  ) * invTexSize.x;

			float yc0  = ( texPos1.y - 1.0  ) * invTexSize.y;
			float yc12 = ( texPos1.y + oy12 ) * invTexSize.y;
			float yc3  = ( texPos1.y + 2.0  ) * invTexSize.y;

			float4 result = float4( 0.0, 0.0, 0.0, 0.0 );
			result += PdxTex2DLod0( tex, float2( xc0,  yc0  ) ) * ( wx0  * wy0  );
			result += PdxTex2DLod0( tex, float2( xc12, yc0  ) ) * ( wx12 * wy0  );
			result += PdxTex2DLod0( tex, float2( xc3,  yc0  ) ) * ( wx3  * wy0  );

			result += PdxTex2DLod0( tex, float2( xc0,  yc12 ) ) * ( wx0  * wy12 );
			result += PdxTex2DLod0( tex, float2( xc12, yc12 ) ) * ( wx12 * wy12 );
			result += PdxTex2DLod0( tex, float2( xc3,  yc12 ) ) * ( wx3  * wy12 );

			result += PdxTex2DLod0( tex, float2( xc0,  yc3  ) ) * ( wx0  * wy3  );
			result += PdxTex2DLod0( tex, float2( xc12, yc3  ) ) * ( wx12 * wy3  );
			result += PdxTex2DLod0( tex, float2( xc3,  yc3  ) ) * ( wx3  * wy3  );

			return result;
		}
#endif // PDXGUI_ICON_FILTER_MITCHELL

		float4 SampleIconFilteredGrad( in PdxTextureSampler2D tex, float2 uv, float2 ddxUV, float2 ddyUV )
		{
#ifdef PDXGUI_ICON_FILTER_NONE
			float2 texSize;
			PdxTex2DSize( tex, texSize );
			return SamplePointMip0( tex, uv, texSize );
#elif defined(PDXGUI_ICON_FILTER_MITCHELL)
			// Sharp = 50/50 blend of mip-0 Mitchell and hardware-auto-LOD. Mitchell
			// alone collapses to central-texel sampling at integer downsample on
			// pixel-aligned UI; the hardware side anti-aliases by picking a fractional
			// LOD per fragment. Blending the two gives Sharp a result that's visibly
			// distinct from both None (pure mip 0) and Smooth (pure auto-LOD).
			float2 texSize;
			PdxTex2DSize( tex, texSize );
			float4 vSharp = SampleMitchellMip0( tex, uv, texSize );
			float4 vSoft  = PdxTex2DGrad( tex, uv, ddxUV, ddyUV );
			return lerp( vSharp, vSoft, 0.5 );
#endif
			return PdxTex2DGrad( tex, uv, ddxUV, ddyUV );
		}

		float4 SampleIconFilteredBias( in PdxTextureSampler2D tex, float2 uv, float bias )
		{
#ifdef PDXGUI_ICON_FILTER_NONE
			float2 texSize;
			PdxTex2DSize( tex, texSize );
			return SamplePointMip0( tex, uv, texSize );
#elif defined(PDXGUI_ICON_FILTER_MITCHELL)
			// See Grad variant above — same blend, but the soft side uses PdxTex2DBias
			// since this code path has no explicit derivatives.
			float2 texSize;
			PdxTex2DSize( tex, texSize );
			float4 vSharp = SampleMitchellMip0( tex, uv, texSize );
			float4 vSoft  = PdxTex2DBias( tex, uv, bias );
			return lerp( vSharp, vSoft, 0.5 );
#endif
			return PdxTex2DBias( tex, uv, bias );
		}

		float CalcBorderUV( float UV, float UVEdge, float UVScale )
		{
			float Offset = UV - UVEdge;
			Offset *= UVScale;
			return Offset + UVEdge;

			// Could be just multiply and add?
			//return UV * UVScale + UVEdge - UVEdge * UVScale; // 'UVEdge - UVEdge * UVScale' constant
		}
		
		float CalcInternalUV( float UV, float UVCutoff, float UVTileFactor, float UVScale, float UVOffset )
		{
			float Offset = UV - UVCutoff;
			Offset *= UVTileFactor;
			Offset = mod( Offset, 1.0 );
			Offset *= UVScale;
			return Offset + UVOffset;
		}
		
		float4 SampleSpriteTexture(
			in PdxTextureSampler2D SpriteTexture,
			float2 uv,
			float4 UVRect,
			float2 BorderUVScale,
			float4 BorderUVCutoff,
			float2 MiddleUVTileFactor,
			float2 MiddleUVScale,
			float2 MiddleUVOffset,
			float2 TranslateUV,
			float RotateUV,
			float2 Dimension )
		{
#ifdef PDX_GUI_SPRITE_EFFECT
			uv = lerp( UVRect.xy, UVRect.zw, uv );

			float2 texDdx = ddx(uv * BorderUVScale);
			float2 texDdy = ddy(uv * BorderUVScale);

			if ( uv.x <= BorderUVCutoff.x )
			{
				uv.x = CalcBorderUV( uv.x, UVRect.x, BorderUVScale.x );
			}
			else if ( uv.x >= BorderUVCutoff.z )
			{
				uv.x = CalcBorderUV( uv.x, UVRect.z, BorderUVScale.x );
			}
			else
			{
				uv.x = CalcInternalUV( uv.x, BorderUVCutoff.x, MiddleUVTileFactor.x, MiddleUVScale.x, MiddleUVOffset.x );
			}
			
			if ( uv.y <= BorderUVCutoff.y )
			{
				uv.y = CalcBorderUV( uv.y, UVRect.y, BorderUVScale.y );
			}
			else if ( uv.y >= BorderUVCutoff.w )
			{
				uv.y = CalcBorderUV( uv.y, UVRect.w, BorderUVScale.y );
			}
			else
			{
				uv.y = CalcInternalUV( uv.y, BorderUVCutoff.y, MiddleUVTileFactor.y, MiddleUVScale.y, MiddleUVOffset.y );
			}

			uv += TranslateUV;

			{
				float s = sin( RotateUV );
				float c = cos( RotateUV );

				uv.x = uv.x * Dimension.x - Dimension.x * 0.5;
				uv.y = uv.y * Dimension.y - Dimension.y * 0.5;

				float UVx = uv.x;
				float UVy = uv.y;

				uv.x = UVx * c - UVy * s;
				uv.y = UVy * c + UVx * s;

				uv.x = uv.x / Dimension.x + 0.5;
				uv.y = uv.y / Dimension.y + 0.5;
			}

			return SampleIconFilteredGrad( SpriteTexture, uv, texDdx, texDdy );
#else
			return SampleIconFilteredBias( SpriteTexture, uv, SamplerBias );
#endif
		}

		float4 CalcSpriteUV( int Index, int Frame )
		{
			int2 FrameSize     = SpriteFrameAndGridSize[Index].xy;

			if ( FrameSize.x <= 0 || FrameSize.y <= 0 )
				return float4( 0.0, 0.0, 1.0, 1.0 );

			int2 GridSize = SpriteFrameAndGridSize[Index].zw;
			if ( GridSize.x <= 0 || GridSize.y <= 0 )
				return float4( 0.0, 0.0, 1.0, 1.0 );

			int2 GridPos;
			GridPos.y = min( Frame / GridSize.x, GridSize.y - 1 );
			GridPos.x = min( Frame - GridPos.y * GridSize.x, GridSize.x - 1 );

			float2 FrameUVSize = SpriteTextureAndFrameUVSize[Index].zw;

			float4 UVRect;
			UVRect.xy = GridPos * FrameUVSize;
			UVRect.zw = FrameUVSize;

			return UVRect;
		}

		float4 SampleSpriteTexture( 
			in PdxTextureSampler2D SpriteTexture, 
			float2 UV, 
			int Index, 
			int Frame, 
			int Type )
		{
			float4 UVRect             = float4( 0.0, 0.0, 1.0, 1.0 );
			float4 BorderUVRect       = float4( 0.0, 0.0, 1.0, 1.0 );
			float2 BorderUVScale      = float2( 1.0, 1.0 );
			float2 MiddleUVScale      = float2( 1.0, 1.0 );
			float2 MiddleUVOffset     = float2( 0.0, 0.0 );
			float2 MiddleUVTileFactor = float2( 1.0, 1.0 );
			float4 BorderSize         = float4( 0.0, 0.0, 0.0, 0.0 );
			float4 BorderUV           = float4( 0.0, 0.0, 0.0, 0.0 );
			float4 BorderUVCutoff     = float4( 0.0, 0.0, 1.0, 1.0 );

#ifdef PDX_GUI_SPRITE_EFFECT
			UVRect = CalcSpriteUV( Index, Frame );
			float2 UVRectSize = UVRect.zw;
			float2 UVRectBR   = UVRect.xy + UVRectSize;
			float2 UVRectTL   = UVRect.xy;

			BorderUVRect = float4( UVRectTL, UVRectBR );

			float2 ImageSize = float2( SpriteFrameAndGridSize[Index].xy );
			if ( SpriteFrameAndGridSize[Index].x <= 0 || SpriteFrameAndGridSize[Index].y <= 0 )
			{
				ImageSize = SpriteTextureAndFrameUVSize[Index].xy;
			}

			if ( Type != 0 )
			{
				BorderUVScale = SpriteSize.xy / ImageSize;
				BorderSize    = SpriteBorder[Index];

				float BorderWidth = BorderSize.x + BorderSize.z;
				if ( BorderWidth > SpriteSize.x )
				{
					float ScaleFactor = SpriteSize.x / BorderWidth;
					BorderSize.x = BorderSize.x * ScaleFactor;
					BorderSize.z = SpriteSize.x - BorderSize.x;
				}

				float BorderHeight = BorderSize.y + BorderSize.w;
				if ( BorderHeight > SpriteSize.y )
				{
					float ScaleFactor = SpriteSize.y / BorderHeight;
					BorderSize.y = BorderSize.y * ScaleFactor;
					BorderSize.w = SpriteSize.y - BorderSize.y;
				}

				BorderUV.xy = ( BorderSize.xy / ImageSize ) * UVRectSize.xy;
				BorderUV.zw = ( BorderSize.zw / ImageSize ) * UVRectSize.xy;

				float2 TextureMiddle = ImageSize - BorderSize.xy - BorderSize.zw;
				if ( Type == 1 && TextureMiddle.x > 0.0 && TextureMiddle.x > 0.0 )
				{
					float2 Middle = SpriteSize.xy - BorderSize.xy - BorderSize.zw;
					MiddleUVScale.xy = Middle / TextureMiddle;
				}
			}

			BorderUVCutoff.xy = UVRectTL + BorderUV.xy / BorderUVScale.xy;
			BorderUVCutoff.zw = UVRectBR - BorderUV.zw / BorderUVScale.xy;

			MiddleUVTileFactor = MiddleUVScale;
			MiddleUVTileFactor.x = MiddleUVTileFactor.x / ( BorderUVCutoff.z - BorderUVCutoff.x );
			MiddleUVTileFactor.y = MiddleUVTileFactor.y / ( BorderUVCutoff.w - BorderUVCutoff.y );

			MiddleUVScale = UVRectSize.xy - BorderUV.xy - BorderUV.zw;
			MiddleUVOffset = UVRect.xy + BorderUV.xy;

#endif // PDX_GUI_SPRITE_EFFECT

			float2 TranslateUV = SpriteTranslateRotateUVAndAlpha[Index].xy;
			float  RotateUV    = SpriteTranslateRotateUVAndAlpha[Index].z;

			return SampleSpriteTexture(
				SpriteTexture,
				UV,
				BorderUVRect,
				BorderUVScale,
				BorderUVCutoff,
				MiddleUVTileFactor,
				MiddleUVScale,
				MiddleUVOffset,
				TranslateUV,
				RotateUV,
				SpriteSize.xy );
		}

		float4 SampleSpriteTexture( in PdxTextureSampler2D SpriteTexture, float2 UV, int Index )
		{
			int Frame0 = SpriteFramesTypeBlendMode[Index].x;
			int Type   = SpriteFramesTypeBlendMode[Index].z;
			float4 Color0 = SampleSpriteTexture( SpriteTexture, UV, Index, Frame0, Type );
#if defined(PDX_GUI_FRAME_BLEND_EFFECT)
			int Frame1 = SpriteFramesTypeBlendMode[Index].y;

			float4 Color1 = SampleSpriteTexture( SpriteTexture, UV, Index, Frame1, Type );
			return lerp( Color0, Color1, SpriteFrameBlendAlpha[Index/4][Index%4] );
#else
			return Color0;
#endif
		}

		
		// This needs to be in sync with "CPdxGuiImageSprite::EBlendMode"
		float4 Blend( float4 Base, float4 Blend, float Opacity, inout float BlendMask, int Mode )
		{			
			float4 ReturnBlend = Base;

			int ModeId = Mode & 0xf;

			if ( ModeId == 0 ) // Add 
			{
				ReturnBlend = float4( Add( Base.rgb, Blend.rgb, Opacity ), Base.a );
			}
			else if ( ModeId == 1 ) // Overlay
			{
				ReturnBlend = float4( Overlay( Base.rgb, Blend.rgb, Opacity ), Base.a );
			}
			else if ( ModeId == 2 ) // Multiply
			{
				ReturnBlend = float4( Multiply( Base.rgb, Blend.rgb, Opacity ), Base.a);
			}
			else if ( ModeId == 3 ) // ColorDodge
			{
				ReturnBlend = float4( ColorDodge( Base.rgb, Blend.rgb, Opacity ), Base.a );
			}
			else if ( ModeId == 4 ) // Lighten
			{
				ReturnBlend = float4( Lighten( Base.rgb, Blend.rgb, Opacity ), Base.a );
			}
			else if ( ModeId == 5 ) // Darken
			{
				ReturnBlend = float4( Darken( Base.rgb, Blend.rgb, Opacity ), Base.a );
			}
			else if ( ModeId == 6 ) // Mask
			{
				int ChannelIdx = ( 0xf & ( Mode >> 4 ) );
				BlendMask = Blend[ChannelIdx] * Opacity;
			}
			else if ( ModeId == 7 ) // Normal
			{
				ReturnBlend = float4( lerp( Base, Blend, Opacity * Blend.a ).rgb, Base.a );
			}
			else if ( ModeId == 8 ) // AlphaMultiply
			{				
				int ChannelIdx = ( 0xf & ( Mode >> 4 ) );
				ReturnBlend = float4( Base.rgb, Base.a * lerp( 1.0, Blend[ ChannelIdx ], Opacity ) );
			}
			
			return ReturnBlend;
		}

		float2 GetUVForIndex( int Index, float2 UV )
		{
			// NOTE: The bits *must* correspond to the "PdxGui::MirrorFlags" enum

			uint Flags = MirrorFlags[Index/4][Index%4];

			if ( ( Flags & 1u ) != 0 ) // First bit set is a horizontal flip
			{
				UV.x = 1.0 - UV.x;
			}

			if ( ( Flags & 2u ) != 0 ) // Second bit set is a vertical flip
			{
				UV.y = 1.0 - UV.y;
			}

			return UV;
		}
		
		void ApplyModifyTextures( inout float4 Base, float2 UV )
		{
#ifdef PDX_GUI_SPRITE_EFFECT			
			float4 ModifyTextures[MaxSprites-1];

			float BlendMask = 1.0f;

		if ( MaxSprites > 10 )
		{
			if ( ModifyTexturesCount > 9 )
			{
				ModifyTextures[9] = SampleSpriteTexture( ModifyTexture9, GetUVForIndex( 10, UV ), 10 );
			}
		}
		if ( MaxSprites > 9 )
		{
			if ( ModifyTexturesCount > 8 )
			{
				ModifyTextures[8] = SampleSpriteTexture( ModifyTexture8, GetUVForIndex( 9, UV ), 9 );
			}
		}
		if ( MaxSprites > 8 )
		{
			if ( ModifyTexturesCount > 7 )
			{
				ModifyTextures[7] = SampleSpriteTexture( ModifyTexture7, GetUVForIndex( 8, UV ), 8 );
			}
		}
		if ( MaxSprites > 7 )
		{
			if ( ModifyTexturesCount > 6 )
			{
				ModifyTextures[6] = SampleSpriteTexture( ModifyTexture6, GetUVForIndex( 7, UV ), 7 );
			}
		}
		if ( MaxSprites > 6 )
		{
			if ( ModifyTexturesCount > 5)
			{
				ModifyTextures[5] = SampleSpriteTexture( ModifyTexture5, GetUVForIndex( 6, UV ), 6 );
			}
		}
		if ( MaxSprites > 5 )
		{
			if ( ModifyTexturesCount > 4 )
			{
				ModifyTextures[4] = SampleSpriteTexture( ModifyTexture4, GetUVForIndex( 5, UV ), 5 );
			}
		}
		if ( MaxSprites > 4 )
		{
			if ( ModifyTexturesCount> 3 )
			{
				ModifyTextures[3] = SampleSpriteTexture( ModifyTexture3, GetUVForIndex( 4, UV ), 4 );
			}
		}
		if ( MaxSprites > 3 )
		{
			if ( ModifyTexturesCount > 2 )
			{
				ModifyTextures[2] = SampleSpriteTexture( ModifyTexture2, GetUVForIndex( 3, UV ), 3 );
			}
		}
		if ( MaxSprites > 2 )
		{
			if ( ModifyTexturesCount > 1 )
			{
				ModifyTextures[1] = SampleSpriteTexture( ModifyTexture1, GetUVForIndex( 2, UV ), 2 );
			}
		}
		if ( MaxSprites > 10 )
		{
			if ( ModifyTexturesCount > 0 )
			{
				ModifyTextures[0] = SampleSpriteTexture( ModifyTexture0, GetUVForIndex( 1, UV ), 1 );
			}
		}
				
			for ( int i = 0; i < ModifyTexturesCount; ++i )
			{
				float4 ModifyTextureBase = ModifyTextures[i];
				ModifyTextureBase = ModifyTextureBase * SpriteModifyTexturesColors[i+1];
				
				Base = Blend( 
					Base, 
					ModifyTextureBase, 
					BlendMask * SpriteTranslateRotateUVAndAlpha[i+1].w, 
					BlendMask, 
					SpriteFramesTypeBlendMode[i+1].w );
			}
#endif // PDX_GUI_SPRITE_EFFECT
		}
		
		float4 SampleImageSprite( in PdxTextureSampler2D SpriteTexture, float2 UV )
		{
			float4 Base = SampleSpriteTexture( SpriteTexture, UV, 0 );

			UV = (UV - SpriteUVRect.xy) / SpriteUVRect.zw;

			ApplyModifyTextures( Base, UV );

			return Base;
		}
	]]
}
