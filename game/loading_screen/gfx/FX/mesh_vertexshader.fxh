Includes = {
	"cw/pdxmesh.fxh"
	"constants.fxh"
	"city_grid.fxh"
}

struct SCityGfxConstants
{
	float 	_CountryOwner;
	float	_SquishToCell_Scale;
	float	_LocationId;
	float 	_Padding;
	float2	_CellCorner0;
	float2	_CellCorner1;
	float2	_CellCorner2;
	float2	_CellCorner3;
};

VertexShader = {
	Code [[	
#if defined(ENABLE_TERRAIN)
	#if defined( PDX_MESH_SNAP_VERTICES_TO_TERRAIN_CLAMPED )
			float3 SnapVerticesToTerrainCapped( float3 WorldSpacePos, float4x4 WorldMatrix )
			{
				static const float MaxSlope = 0.5f; //relative slope value: 0.0f = no adjustment, 1.0f = capped to 45 degrees, inf = capped to ~90 degrees
				float3 MeshPos = float3( GetMatrixData( WorldMatrix, 0, 3 ), GetMatrixData( WorldMatrix, 1, 3 ), GetMatrixData( WorldMatrix, 2, 3 ) );
				float Dist2d = length( MeshPos.xz - WorldSpacePos.xz );
				float TerrainHeight = GetHeight( WorldSpacePos.xz );
				float MaxOffset = Dist2d * MaxSlope;
				float YOffset = clamp( TerrainHeight - MeshPos.y, -MaxOffset, MaxOffset );

				return float3( WorldSpacePos.x, WorldSpacePos.y + YOffset, WorldSpacePos.z );
			}
	#endif
	#ifdef BRIDGE
			float3 SnapVerticesToTerrainBridge(float3 WorldSpacePos, float4x4 WorldMatrix, float4 ObjectPosition)
			{
				float YScale = length( float3( GetMatrixData( WorldMatrix, 0, 1 ), GetMatrixData( WorldMatrix, 1, 1 ), GetMatrixData( WorldMatrix, 2, 1 ) ) );
				float3 MeshPos = float3( GetMatrixData( WorldMatrix, 0, 3 ), GetMatrixData( WorldMatrix, 1, 3 ), GetMatrixData( WorldMatrix, 2, 3 ) );
				float4 WorldPositionCenter = ObjectPosition;
				WorldPositionCenter.x = 0.0f;
				WorldPositionCenter = mul(WorldMatrix, WorldPositionCenter);
				float TerrainHeight = GetHeight( WorldPositionCenter.xz );
				return float3( WorldSpacePos.x, TerrainHeight + ObjectPosition.y * YScale, WorldSpacePos.z );
			}
	#endif
#endif
		VS_OUTPUT_PDXMESH StandardVertexShader( VS_INPUT_PDXMESH Input, uint JointsInstanceIndex, int ObjectInstanceIndex, float4x4 WorldMatrix )
		{
			VS_OUTPUT_PDXMESH Out;

			float4 Position = float4( Input.Position.xyz, 1.0 );
			float3 BaseNormal = Input.Normal;
			float3 BaseTangent = Input.Tangent.xyz;
#ifdef ENABLE_TERRAIN
		#ifdef PDX_MESH_SNAP_MESH_TO_TERRAIN 
			WorldMatrix[1][3]=GetHeight(float2(WorldMatrix[0][3],WorldMatrix[2][3]));
		#endif
#endif

		#ifdef PDX_MESH_BLENDSHAPES
			ApplyBlendShapes( Position.xyz, BaseNormal, BaseTangent, Input.BlendShapeInstanceIndex, Input.ObjectInstanceIndex, Input.VertexID );
		#endif
		
		#ifdef PDX_MESH_SKINNED
			float4 SkinnedPosition = vec4( 0.0 );
			float3 SkinnedNormal = vec3( 0.0 );
			float3 SkinnedTangent = vec3( 0.0 );
			float3 SkinnedBitangent = vec3( 0.0 );

			float4 Weights = float4( Input.BoneWeight.xyz, 1.0 - Input.BoneWeight.x - Input.BoneWeight.y - Input.BoneWeight.z );
			for( int i = 0; i < PDXMESH_MAX_INFLUENCE; ++i )
			{
				uint BoneIndex = Input.BoneIndex[i];
				uint OffsetIndex = BoneIndex + JointsInstanceIndex;

				float4x4 VertexMatrix = PdxMeshGetJointVertexMatrix( OffsetIndex );

				SkinnedPosition += mul( VertexMatrix, Position ) * Weights[ i ];

				float3 XAxis = float3( GetMatrixData( VertexMatrix, 0, 0 ), GetMatrixData( VertexMatrix, 0, 1 ), GetMatrixData( VertexMatrix, 0, 2 ) );
				float3 YAxis = float3( GetMatrixData( VertexMatrix, 1, 0 ), GetMatrixData( VertexMatrix, 1, 1 ), GetMatrixData( VertexMatrix, 1, 2 ) );
				float3 ZAxis = float3( GetMatrixData( VertexMatrix, 2, 0 ), GetMatrixData( VertexMatrix, 2, 1 ), GetMatrixData( VertexMatrix, 2, 2 ) );
				
				float XSqMagnitude = dot( XAxis, XAxis );
				float YSqMagnitude = dot( YAxis, YAxis );
				float ZSqMagnitude = dot( ZAxis, ZAxis );
				
				float3 SqScale = float3( XSqMagnitude, YSqMagnitude, ZSqMagnitude );
				float3 SqScaleReciprocal = float3( 1.f, 1.f, 1.f ) / SqScale;
				
				float3 ScaledNormal = BaseNormal * SqScaleReciprocal;
				float3 ScaledTangent = BaseTangent * SqScaleReciprocal;
				
				float3x3 VertexRotationMatrix = CastTo3x3( VertexMatrix );
				
				float3 Normal = mul( VertexRotationMatrix, ScaledNormal );
				float3 Tangent = mul( VertexRotationMatrix, ScaledTangent );
				float3 Bitangent = cross( Normal, Tangent ) * Input.Tangent.w;

				Normal = normalize( Normal );
				Tangent = normalize( Tangent );
				Bitangent = normalize( Bitangent );

				SkinnedNormal += Normal * Weights[i];
				SkinnedTangent += Tangent * Weights[i];
				SkinnedBitangent += Bitangent * Weights[i];
			}

			Out.Normal = normalize( mul( CastTo3x3(WorldMatrix), normalize( SkinnedNormal ) ) );
			Out.Tangent = normalize( mul( CastTo3x3(WorldMatrix), normalize( SkinnedTangent ) ) );
			Out.Bitangent = normalize( mul( CastTo3x3(WorldMatrix), normalize( SkinnedBitangent ) ) );
			Out.Position = mul( WorldMatrix, SkinnedPosition );
		#else
			Out.Normal = normalize( mul( CastTo3x3( WorldMatrix ), BaseNormal ) );
			Out.Tangent = normalize( mul( CastTo3x3( WorldMatrix ), BaseTangent ) );
			Out.Bitangent = normalize( cross( Out.Normal, Out.Tangent ) * Input.Tangent.w );
			Out.Position = mul( WorldMatrix, Position );
		#endif
		
		#ifdef CITY_GRID_SQUISH
			#ifdef PDX_MESH_SKINNED
			ApplyCitySquish( Out.Position.xyz, SkinnedPosition.xyz, ObjectInstanceIndex );
			#else
			ApplyCitySquish( Out.Position.xyz, Position.xyz, ObjectInstanceIndex );
			#endif
		#endif
		#if defined(ENABLE_TERRAIN)
			#if defined( PDX_MESH_SNAP_VERTICES_TO_TERRAIN_CLAMPED )
				Out.Position.xyz = SnapVerticesToTerrainCapped( Out.Position.xyz, WorldMatrix );
			#elif defined( PDX_MESH_SNAP_VERTICES_TO_TERRAIN )
				Out.Position.xyz = SnapVerticesToTerrain( Out.Position.xz, Input.Position.y, WorldMatrix );
			#elif defined(BRIDGE)
				Out.Position.xyz =  SnapVerticesToTerrainBridge(Out.Position.xyz, WorldMatrix, Position);
			#endif
			#if defined(TERRAIN)
				#ifndef SHOW_IN_PAPERMAP
					AdjustFlatMapHeight( Out.Position.xyz );
				#endif
			#endif
		#endif
			Out.WorldSpacePos = Out.Position.xyz;
			Out.WorldSpacePos /= WorldMatrix[3][3];
			Out.Position = FixProjectionAndMul( ViewProjectionMatrix, Out.Position );
	
			Out.UV0 = Input.UV0;
		#ifdef PDX_MESH_UV1
			Out.UV1 = Input.UV1;
		#else
			Out.UV1 = vec2( 0.0 );
		#endif
		#ifdef PDX_MESH_UV2
			Out.UV2 = Input.UV2;
		#else
			Out.UV2 = vec2( 0.0 );
		#endif
	
			return Out;
		}
		VS_OUTPUT_PDXMESH StandardVertexShader( VS_INPUT_PDXMESH Input, uint JointsInstanceIndex, float4x4 WorldMatrix )
		{
			#ifdef PDX_MESH_BLENDSHAPES
			int ObjectInstanceIndex = Input.ObjectInstanceIndex;
			#else
			int ObjectInstanceIndex = 0;
			#endif
			return StandardVertexShader( Input, JointsInstanceIndex, ObjectInstanceIndex, WorldMatrix );
		}
		VS_OUTPUT_PDXMESH StandardVertexShader( in VS_INPUT_PDXMESHSTANDARD Input )
		{
			return StandardVertexShader( PdxMeshConvertInput( Input ), Input.InstanceIndices.x, Input.InstanceIndices.y, PdxMeshGetWorldMatrix( Input.InstanceIndices.y ) );
		}
		
		
		VS_OUTPUT_PDXMESHSHADOW StandardVertexShaderShadow( VS_INPUT_PDXMESH Input, uint JointsInstanceIndex, int ObjectInstanceIndex, float4x4 WorldMatrix )
		{			
			VS_OUTPUT_PDXMESHSHADOW Out;
			
			float4 Position = float4( Input.Position.xyz, 1.0 );

		#if defined(PDX_MESH_SNAP_MESH_TO_TERRAIN) && defined(ENABLE_TERRAIN) 
			WorldMatrix[1][3]=GetHeight(float2(WorldMatrix[0][3],WorldMatrix[2][3]));
		#endif

		#ifdef PDX_MESH_BLENDSHAPES
			ApplyBlendShapesPositionOnly( Position.xyz, Input.BlendShapeInstanceIndex, Input.ObjectInstanceIndex, Input.VertexID );
		#endif
			
		#ifdef PDX_MESH_SKINNED
			float4 vWeight = float4( Input.BoneWeight.xyz, 1.0 - Input.BoneWeight.x - Input.BoneWeight.y - Input.BoneWeight.z );
			float4 vSkinnedPosition = vec4( 0.0 );
			for( int i = 0; i < PDXMESH_MAX_INFLUENCE; ++i )
			{
				int nIndex = int( Input.BoneIndex[i] );
				float4x4 VertexMatrix = PdxMeshGetJointVertexMatrix( nIndex + JointsInstanceIndex );
				vSkinnedPosition += mul( VertexMatrix, Position ) * vWeight[ i ];
			}
			Out.Position = mul( WorldMatrix, vSkinnedPosition );
		#else
			Out.Position = mul( WorldMatrix, Position );
		#endif
		#ifdef CITY_GRID_SQUISH
			#ifdef PDX_MESH_SKINNED
			ApplyCitySquish( Out.Position.xyz, vSkinnedPosition.xyz, ObjectInstanceIndex );
			#else
			ApplyCitySquish( Out.Position.xyz, Position.xyz, ObjectInstanceIndex );
			#endif
		#endif
		#if defined(ENABLE_TERRAIN)
			#if defined( PDX_MESH_SNAP_VERTICES_TO_TERRAIN_CLAMPED )
				Out.Position.xyz = SnapVerticesToTerrainCapped( Out.Position.xyz, WorldMatrix );
			#elif defined( PDX_MESH_SNAP_VERTICES_TO_TERRAIN )
				Out.Position.xyz = SnapVerticesToTerrain( Out.Position.xz, Input.Position.y, WorldMatrix );
			#elif defined(BRIDGE)
				Out.Position.xyz =  SnapVerticesToTerrainBridge(Out.Position.xyz, WorldMatrix, Position);
			#endif
			#ifdef TERRAIN
				#ifndef SHOW_IN_PAPERMAP
					AdjustFlatMapHeight( Out.Position.xyz );
				#endif
			#endif
		#endif
				
			Out.Position = FixProjectionAndMul( ViewProjectionMatrix, Out.Position );
			Out.UV = Input.UV0;
			return Out;
		}
		VS_OUTPUT_PDXMESHSHADOW StandardVertexShaderShadow( VS_INPUT_PDXMESH Input, uint JointsInstanceIndex, float4x4 WorldMatrix )
		{
			#ifdef PDX_MESH_BLENDSHAPES
			int ObjectInstanceIndex = Input.ObjectInstanceIndex;
			#else
			int ObjectInstanceIndex = 0;
			#endif
			return StandardVertexShaderShadow( Input, JointsInstanceIndex, ObjectInstanceIndex, WorldMatrix );
		}
		VS_OUTPUT_PDXMESHSHADOWSTANDARD StandardVertexShaderShadow( in VS_INPUT_PDXMESHSTANDARD Input )
		{
			VS_OUTPUT_PDXMESHSHADOW Basic = StandardVertexShaderShadow( PdxMeshConvertInput( Input ), Input.InstanceIndices.x, PdxMeshGetWorldMatrix( Input.InstanceIndices.y ) );
			VS_OUTPUT_PDXMESHSHADOWSTANDARD Out;
			Out.Position = Basic.Position;
			Out.UV_InstanceIndex = float3( Basic.UV, float( Input.InstanceIndices.y ) );
			return Out;
		}
	]]
}