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
	bool _VertexUseFbmMap;
	bool _FragmentUseFbmMap;
	float _FragmentFbmMapBias;
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
};

#define PI 3.141592653589793238462

layout(set = 0, binding = 1) uniform sampler2D fbmmap;
layout(set = 0, binding = 2, rgba16f) restrict uniform image2D shadowmap;

// Thread groups size
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Two techniques for computing shadow height. The functions return the shadow height for texel xy
vec4 shadow_propagation(in ivec2 xy, in ivec2 dimensions, in vec2 uv, in vec3 fbm);
vec4 shadow_ray_marching(in ivec2 xy, in vec2 uv);

vec2 uv_shadowmap_to_terrain(in vec2 uv);

void main()
{
	ivec2 dimensions = imageSize(shadowmap);
	ivec2 xy = ivec2(gl_GlobalInvocationID.xy).xy;

	vec2 uv = vec2(xy) / (vec2(dimensions) - vec2(1));
	
	// Sampling fbm texture
	// vertices positions range from 0.5 * _MeshSize * vec3(-1, 0, -1)
	// to 0.5 * _MeshSize * vec3(1, 0, 1)
	vec3 pos = _MeshSize * vec3(uv.x - 0.5, 0, uv.y - 0.5);
	vec3 noise_pos = (pos + vec3(_Offset.x, 0, _Offset.z)) / _Scale;

	// Sampling the precomputed fbm texture
	vec3 fbm_unorm = texture(fbmmap, uv).xyz; // values in 0 ; 1
	vec3 fbm = 2 * (fbm_unorm - vec3(0.5)); // values in -1 ; 1
	float height = fbm.x;
	
	float shadowDepth = 0;
	vec4 shadowMap = vec4(0);
	
	if (_RotateShadowMapTowardsLight)
		uv = uv_shadowmap_to_terrain(uv);
	
	if (any(greaterThanEqual(uv, vec2(1))) ||
		any(lessThanEqual(uv, vec2(0))) )
		shadowMap = vec4(0);
	else if (_ShadowPropagation)
		shadowMap = shadow_propagation(xy, dimensions, uv, fbm);
	else
		shadowMap = shadow_ray_marching(xy, uv);
	
	imageStore(shadowmap, xy, shadowMap);
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

vec4 shadow_propagation(in ivec2 xy, in ivec2 dimensions, in vec2 uv, in vec3 fbm)
{
	vec2 towards_light = _LightDirection.xz;
	float abs_x = abs(towards_light.x);
	float abs_y = abs(towards_light.y);
	
	ivec2 towards_light_sample_1_xy;
	ivec2 towards_light_sample_2_xy;
	float sample_1_weight;
	
	if (abs_x > abs_y)
	{
		towards_light /= abs_x;
		towards_light_sample_1_xy = xy + ivec2(towards_light.x, floor(towards_light.y));
		towards_light_sample_2_xy = xy + ivec2(towards_light.x, ceil(towards_light.y));
		if (towards_light.y > 0)
			sample_1_weight = towards_light.y;
		else
			sample_1_weight = 1 + towards_light.y;
	}
	else
	{
	 	towards_light /= abs_y;
		towards_light_sample_1_xy = xy + ivec2(floor(towards_light.x), towards_light.y);
		towards_light_sample_2_xy = xy + ivec2(ceil(towards_light.x), towards_light.y);
		if (towards_light.x > 0)
			sample_1_weight = towards_light.x;
		else
			sample_1_weight = 1 + towards_light.x;
	}
	
	towards_light_sample_1_xy = clamp(ivec2(0), dimensions - ivec2(1), towards_light_sample_1_xy);
	towards_light_sample_2_xy = clamp(ivec2(0), dimensions - ivec2(1), towards_light_sample_2_xy);
	
	// Propagate neighboring shadows
	vec4 fbm_sample_1 = texture(fbmmap, vec2(towards_light_sample_1_xy) / vec2(dimensions));
	vec4 fbm_sample_2 = texture(fbmmap, vec2(towards_light_sample_2_xy) / vec2(dimensions));
	vec4 shadow_sample_1 = imageLoad(shadowmap, towards_light_sample_1_xy);
	vec4 shadow_sample_2 = imageLoad(shadowmap, towards_light_sample_2_xy);
	
	float decay = length(towards_light) * _MeshSize / dimensions.x * abs(_LightDirection.y);
	
	float neighbors_shadowHeight_unorm = mix(fbm_sample_1.r + shadow_sample_1.r, fbm_sample_2.r + shadow_sample_2.r, sample_1_weight);
	float height_unorm = 0.5 * (fbm.x + 1);
	
	float shadowDepth = max(0, 2 * (neighbors_shadowHeight_unorm - height_unorm) * _TerrainHeight - decay);
	float shadowDepth_unorm = 0.5 * shadowDepth / _TerrainHeight;
	
	return vec4(shadowDepth_unorm, 0, 0, 0);
}

// Samples fbm texture and returns point coordinates in world space
vec3 fbm_sample_to_world_space(in vec2 uv); // with sampling
vec3 fbm_sample_to_world_space(in vec2 uv, in vec3 fbm); // without sampling
vec4 shadowmap_bilinear_sample(in vec2 uv);

vec4 shadow_ray_marching(in ivec2 xy, in vec2 uv)
{
	int max_steps = 100;
	float min_step_size = clamp(0.05, 10, _ShadowMinStepSize);
	float adaptive_step_multiplyer = 10 * _ShadowAdaptiveStepSize;
	int remaining_steps = int(_ShadowMaxStepCount);
	
	vec4 shadowMap = vec4(0);
	if (_ShadowCumulativeStepsRatio == 0) // clearing the texture
		return shadowMap;
	
	if (_CumulativeRayMarching)
	{
		remaining_steps = int(max(1.0, _ShadowMaxStepCount * _ShadowCumulativeStepsRatio));
		shadowMap = imageLoad(shadowmap, xy);
		if (_ShadowStopOnHit && shadowMap.w > 0)
			return shadowMap;
	}
	
	float shadowDepth = 2 * shadowMap.x * _TerrainHeight;
	float duv = shadowMap.y; // != 0 only when _CumulativeRayMarching
	float num_steps = shadowMap.z;
	float shadow_at_step = shadowMap.w;	
		
	float height = fbm_sample_to_world_space(uv).y;
	
	vec2 step_uv = uv + duv * _LightDirection.xz; // resume to where the previous ray marching stopped
	vec3 current_position = fbm_sample_to_world_space(step_uv);
	
	float step_size = min_step_size;
	step_uv += step_size * _LightDirection.xz / _MeshSize;
	
	while (remaining_steps > 0 &&
		all(lessThanEqual(step_uv, vec2(1))) &&
		all(greaterThanEqual(step_uv, vec2(0))) )
	{
		num_steps += 1 / _ShadowMaxStepCount;
		current_position = fbm_sample_to_world_space(step_uv);
		float rayDeltaHeight = length(step_uv - uv) * _MeshSize * abs(_LightDirection.y);
		if (_CumulativeRayMarching)
		{
			vec2 shadowmap_uv = _RotateShadowMapTowardsLight ? uv_terrain_to_shadowmap(step_uv) : step_uv;
			vec4 current_step_shadowMap = shadowmap_bilinear_sample(shadowmap_uv);
			float current_step_shadowDepth = 2 * current_step_shadowMap.x * _TerrainHeight;
			float current_step_duv = current_step_shadowMap.y;
			float current_step_new_ShadowDepth = current_position.y + current_step_shadowDepth - height - rayDeltaHeight;
			if (current_step_new_ShadowDepth > shadowDepth)
			{
				shadowDepth = current_step_new_ShadowDepth;
				shadow_at_step = num_steps;
				if (_ShadowStopOnHit)
					remaining_steps = 0;
			}
			step_uv += current_step_duv * _LightDirection.xz;
		}
		else if (height + rayDeltaHeight < current_position.y)
		{
			shadowDepth = max(shadowDepth, current_position.y - height - rayDeltaHeight);
			shadow_at_step = num_steps;
			if (_ShadowStopOnHit)
				remaining_steps = 0;
		}
		step_size = max(min_step_size, adaptive_step_multiplyer * (height + rayDeltaHeight - current_position.y));
		
		step_uv += step_size * _LightDirection.xz / _MeshSize;
		remaining_steps--;
	}
	
	shadowMap.x = 0.5 * shadowDepth / _TerrainHeight;
	shadowMap.y = length(step_uv - uv); // for cumulative ray marching
	shadowMap.z = num_steps;
	shadowMap.w = shadow_at_step;
		
	return shadowMap;
}

vec3 fbm_sample_to_world_space(in vec2 uv, in vec3 fbm)
{
	// vertices positions range from 0.5 * _MeshSize * vec3(-1, 0, -1)
	// to 0.5 * _MeshSize * vec3(1, 0, 1)
	vec3 pos = _MeshSize * vec3(uv.x - 0.5, 0, uv.y - 0.5); // code copied from other shaders
	//vec3 noise_pos = (pos + vec3(_Offset.x, 0, _Offset.z)) / _Scale; // we don't need this as we are sampling the fbm texture instead of evaluating fbm(noise_pos.xz)
	
	// Adjust height of the vertex by fbm result scaled by final desired amplitude
	pos.y += _TerrainHeight * fbm.x + _TerrainHeight - _Offset.y; // copied from vertex shader
	
	return pos;
}

vec3 fbm_sample_to_world_space(in vec2 uv)
{
	// Sampling the precomputed fbm texture
	vec3 fbm_unorm = texture(fbmmap, uv).xyz; // values in 0 ; 1
	vec3 fbm = 2 * (fbm_unorm - vec3(0.5)); // values in -1 ; 1
	
	return fbm_sample_to_world_space(uv, fbm);
}

vec4 shadowmap_bilinear_sample(in vec2 uv)
{
	ivec2 dimensions = imageSize(shadowmap);
	ivec2 xy = ivec2(uv * dimensions);

	vec4 a = imageLoad(shadowmap, xy);
	vec4 b = imageLoad(shadowmap, xy + ivec2(1, 0));
	vec4 c = imageLoad(shadowmap, xy + ivec2(0, 1));
	vec4 d = imageLoad(shadowmap, xy + ivec2(1, 1));
	
	return mix(mix(a, b, uv.x), mix(c, d, uv.x), uv.y);
}
