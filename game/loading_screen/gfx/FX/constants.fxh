Code
[[
	static const float TWO_PI = 6.28318530718f;
	static const float HALF_PI = 1.57079632679f;
	
// --------------------------------------------------------------
// ------------------    Lighting       -------------------------
// --------------------------------------------------------------
static const float SHADOW_AMBIENT_MIN_FACTOR = 0.0;
static const float SHADOW_AMBIENT_MAX_FACTOR = 0.3;


// --------------------------------------------------------------
// ------------------    TERRAIN        -------------------------
// --------------------------------------------------------------
static const float COLORMAP_OVERLAY_STRENGTH 			= 0.75f;


// --------------------------------------------------------------
// ------------------    WATER          -------------------------
// --------------------------------------------------------------
static const float  WATER_TIME_SCALE	= 1.0f / 50.0f;


// DEVASTATION //
// Water
#define WATER_DEVASTATION_COLOR float3( 0.18, 0.125, 0.09 )
#define WATER_DEVASTATION_MULT 1.5
#define SHORE_DEVASTATION_COLOR float3( 0.172, 0.13, 0.11 )
#define SHORE_DEVASTATION_MULT 1.25
// Road
#define ROAD_DEVASTATION_COLOR float3( 0.172, 0.13, 0.11 )
#define ROAD_DEVASTATION_MULT 1.6
#define ROAD_DEVASTATION_MAX 0.66

// Building
#define BUILDING_DEVASTATION_MULT 2.0
#define BUILDING_DEVASTATION_UV_SCALE 30
#define BUILDING_DEVASTATION_HEIGHT_MIN 0.0
#define BUILDING_DEVASTATION_HEIGHT_MAX 1.2

// Decal
#define DECAL_DEVASTATION_COLOR float3( 0.172, 0.13, 0.11 )
#define DECAL_DEVASTATION_MULT 2.0
]]
