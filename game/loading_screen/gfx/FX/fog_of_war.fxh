Includes = {
	"fog_of_war_impl.fxh"
	"jomini/jomini_fog_of_war.fxh"
}

TextureSampler FogOfWarAlpha
{
	Ref = JominiFogOfWar
	MagFilter = "Linear"
	MinFilter = "Linear"
	MipFilter = "Linear"
	SampleModeU = "Wrap"
	SampleModeV = "Wrap"
}