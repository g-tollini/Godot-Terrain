#[compute]
#version 450

// This is the uniform buffer that contains all of the settings we sent over from the cpu in _render_callback. Must match with the one in the fragment shader.
layout(set = 0, binding = 0, std140) uniform UniformBufferObject {
	mat4 MVP;
	vec3 _LightDirection;
	float _GradientRotation;
	float _NoiseRotation;
	float _TerrainHeight;
	vec2 _AngularVariance;
	float _Scale;
	float _Octaves;
	float _AmplitudeDecay;
	float _NormalStrength;
	vec3 _Offset;
	float _Seed;
	float _InitialAmplitude;
	float _Lacunarity;
	vec2 _SlopeRange;
	vec4 _LowSlopeColor;
	vec4 _LowSlopeTexST;
	vec4 _HighSlopeColor;
	vec4 _HighSlopeTexST;
	float _FrequencyVarianceLowerBound;
	float _FrequencyVarianceUpperBound;
	float _SlopeDamping;
	vec4 _AmbientLight;
	bool _UseOriginalNormals;
	bool _EnableTexturing;
	bool _VertexUseFbmMap;
	bool _FragmentUseFbmMap;
	float _FragmentFbmMapBias;
	bool _FragmentEnhanceWithNoise;
	float _MeshSize;
	bool _EnableCastShadows;
	float _ShadowStrength;
	float _SoftShadows;
	float _ShadowAdaptiveStepSize;
	float _ShadowMinStepSize;
	float _ShadowMaxStepCount;
	float _ShadowCumulativeStepsRatio;
	bool _ShadowStopOnHit;
	bool _BinaryShadows;
	bool _CumulativeRayMarching;
	bool _FragmentShadows;
	bool _RayStepsHeatmap;
	bool _ShadowPropagation;
	bool _RotateShadowMapTowardsLight;
	bool _ClearShadowMap;
};

#define PI 3.141592653589793238462
#define THREAD_GROUP_SIZE_Y 512

layout(set = 0, binding = 1) uniform sampler2D fbmmap;
layout(set = 0, binding = 2, rgba16f) restrict uniform image2D shadowmap;

// Thread groups size
layout(local_size_x = 1, local_size_y = THREAD_GROUP_SIZE_Y, local_size_z = 1) in;

// Technique for computing shadow height. The function returns the shadow height for texel xy
vec4 rotated_shadowmap_height_propagation(in ivec2 xy, in ivec2 dimensions, in vec2 uv);
vec2 uv_shadowmap_to_terrain(in vec2 uv);

shared float line_cache[THREAD_GROUP_SIZE_Y];

void main()
{
	ivec2 dimensions = imageSize(shadowmap);
	ivec2 xy = ivec2(gl_GlobalInvocationID.xy).xy;

	vec2 uv = vec2(xy) / (vec2(dimensions) - vec2(1));
	
	vec4 shadowMap = vec4(0);
	
	uv = uv_shadowmap_to_terrain(uv);
	int y = int(gl_LocalInvocationID.y);
	line_cache[y] = 0;
	
	if (any(greaterThanEqual(uv, vec2(1))) ||
		any(lessThanEqual(uv, vec2(0))) )
	{
		shadowMap = vec4(0);
	}
	else
	{
		shadowMap = rotated_shadowmap_height_propagation(xy, dimensions, uv);
	}
	
	imageStore(shadowmap, xy, shadowMap);
}

vec4 rotated_shadowmap_height_propagation(in ivec2 xy, in ivec2 dimensions, in vec2 uv)
{
	int y = int(gl_LocalInvocationID.y);
	vec2 terrain_uv = uv;
	float terrain_height_unorm = texture(fbmmap, terrain_uv).x;
	float shadow_height_unorm = terrain_height_unorm;
	
	vec2 l = normalize(_LightDirection.xz);
	float nl = dot(l, l);
	float cos_theta = l.y / nl;
	float sin_theta = - (-l.x / nl);
	
	float theta = -atan(l.x, l.y);
	float phi = PI / 4.0 - mod(theta, PI / 2.0);
	float a_p = sqrt(2) * cos(phi);
	float decay_unorm = 0.5 * _LightDirection.y * _MeshSize / float(dimensions.y) * a_p / _TerrainHeight;
	
	line_cache[y] = shadow_height_unorm;
	memoryBarrierShared();
	barrier();
	
	int max_steps = min(int(ceil(log2(THREAD_GROUP_SIZE_Y))), int(_ShadowMaxStepCount));
	
	int step_size_y = 1;
	int step = 0;
	int shadow_at_step = 0;
	
	while (step < max_steps)
	{
		float towards_light_shadow_height_unorm = line_cache[min(y + step_size_y, THREAD_GROUP_SIZE_Y - 1)];
		if (towards_light_shadow_height_unorm - step_size_y * decay_unorm > shadow_height_unorm)
		{
			shadow_height_unorm = towards_light_shadow_height_unorm - step_size_y * decay_unorm;
			shadow_at_step = step;
		}
		
		line_cache[y] = shadow_height_unorm;
		memoryBarrierShared();
		barrier();
		step_size_y = 2 * step_size_y + 1;
		step++;
	}
	
	return vec4(shadow_height_unorm - terrain_height_unorm, 0, float(shadow_at_step) / float(_ShadowMaxStepCount), 0);
}

vec2 uv_shadowmap_to_terrain(in vec2 uv)
{
	vec2 l = normalize(_LightDirection.xz);
	float nl = dot(l, l);
	float cos_theta = l.y / nl;
	float sin_theta = -l.x / nl;
	
	float theta = atan(l.x, l.y);
	float phi = PI / 4.0 - mod(theta, PI / 2.0);
	float a_p = sqrt(2) * cos(phi);
	
	vec2 uv_p = uv - vec2(0.5);
	uv_p = a_p * vec2(
		uv_p.x * cos_theta - uv_p.y * sin_theta, 
		uv_p.x * sin_theta + uv_p.y * cos_theta);
	uv_p += vec2(0.5);
	
	uv_p = clamp(vec2(0), vec2(1), uv_p);
	
	return uv_p;
}
