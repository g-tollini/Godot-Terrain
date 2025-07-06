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
	bool _VertexUsefbmmap;
	bool _FragmentUsefbmmap;
	float _MeshSize;
	float _ShadowStrength;
	float _SoftShadows;
	float _ShadowAdaptiveStepSize;
	bool _FragmentShadows;
	bool _ShadowPropagation;
};

layout(set = 0, binding = 1) uniform sampler2D fbmmap;
layout(set = 0, binding = 2, rgba16f) restrict uniform image2D heightmap;

// Thread groups size
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Two techniques for computing shadow height. The functions return the shadow height for texel xy
float shadow_propagation(in ivec2 xy, in ivec2 dimensions, in vec2 uv, in vec3 fbm);
float shadow_ray_marching(in ivec2 xy, in ivec2 dimensions, in vec2 uv, in vec3 fbm);

void main()
{
	ivec2 dimensions = imageSize(heightmap);
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
	
	float shadowheight = height;
	if (_ShadowPropagation)
		shadowheight = shadow_propagation(xy, dimensions, uv, fbm);
	else
		shadowheight = shadow_ray_marching(xy, dimensions, uv, fbm);
		
	float shadowHeight_unorm = 0.5 * (shadowheight + _Offset.y) / _TerrainHeight;
	
	imageStore(heightmap, xy, vec4(fbm_unorm.x, shadowHeight_unorm, 0, 0));
}

float shadow_propagation(in ivec2 xy, in ivec2 dimensions, in vec2 uv, in vec3 fbm)
{
	vec2 towards_light = _LightDirection.xz;
	float abs_x = abs(towards_light.x);
	float abs_y = abs(towards_light.y);
	
	ivec2 towards_light_sample_1_xy;
	ivec2 towards_light_sample_2_xy;
	float sample_1_weight;
	
	//float repeat_distance = 5; // repeat shadow propagation from a distance so that it propagates faster ; but then it may introduce incorrect shadows
	//ivec2 towards_light_sample_repeat_1_xy;
	//ivec2 towards_light_sample_repeat_2_xy;
	
	if (abs_x > abs_y)
	{
		towards_light /= abs_x;
		towards_light_sample_1_xy = xy + ivec2(towards_light.x, floor(towards_light.y));
		towards_light_sample_2_xy = xy + ivec2(towards_light.x, ceil(towards_light.y));
		//towards_light_sample_repeat_1_xy = xy + ivec2(repeat_distance * towards_light.x, floor(repeat_distance * towards_light.y));
		//towards_light_sample_repeat_2_xy = xy + ivec2(repeat_distance * towards_light.x, ceil(repeat_distance * towards_light.y));
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
		//towards_light_sample_repeat_1_xy = xy + ivec2(floor(repeat_distance * towards_light.x), repeat_distance * towards_light.y);
		//towards_light_sample_repeat_2_xy = xy + ivec2(ceil(repeat_distance * towards_light.x), repeat_distance * towards_light.y);
		if (towards_light.x > 0)
			sample_1_weight = towards_light.x;
		else
			sample_1_weight = 1 + towards_light.x;
	}
	
	towards_light_sample_1_xy = clamp(ivec2(0), dimensions - ivec2(1), towards_light_sample_1_xy);
	towards_light_sample_2_xy = clamp(ivec2(0), dimensions - ivec2(1), towards_light_sample_2_xy);
	//towards_light_sample_repeat_1_xy = clamp(ivec2(0), dimensions - ivec2(1), towards_light_sample_repeat_1_xy);
	//towards_light_sample_repeat_2_xy = clamp(ivec2(0), dimensions - ivec2(1), towards_light_sample_repeat_2_xy);
	
	// Adjust height of the vertex by fbm result scaled by final desired amplitude
	float height = fbm.x;
	float shadowHeight = height;
	
	// Propagate neighboring shadows
	//towards_light_sample_1_xy = xy + ivec2(1, 0);
	//towards_light_sample_2_xy = xy + ivec2(1, 1);
	vec4 sample_1 = imageLoad(heightmap, towards_light_sample_1_xy);
	vec4 sample_2 = imageLoad(heightmap, towards_light_sample_2_xy);
	//vec4 sample_repeat_1 = imageLoad(heightmap, towards_light_sample_repeat_1_xy);
	//vec4 sample_repeat_2 = imageLoad(heightmap, towards_light_sample_repeat_2_xy);
	
	float decay = length(towards_light) * _MeshSize / dimensions.x * abs(_LightDirection.y) / _TerrainHeight / 16;
	
	float neighbors_shadowHeight_unorm = mix(sample_1.g, sample_2.g, sample_1_weight);
	float neighbors_shadowHeight = 2 * neighbors_shadowHeight_unorm - 1;
	shadowHeight = max(height, neighbors_shadowHeight - decay);
	
	return (shadowHeight + 1) * _TerrainHeight - _Offset.y;
}

// Samples fbm texture and returns point coordinates in world space
vec3 fbm_sample_to_world_space(in vec2 uv); // with sampling
vec3 fbm_sample_to_world_space(in vec2 uv, in vec3 fbm); // without sampling

float shadow_ray_marching(in ivec2 xy, in ivec2 dimensions, in vec2 uv, in vec3 fbm)
{
	float min_step_size = 5;
	float adaptive_step_multiplyer = _ShadowAdaptiveStepSize * _Scale / _TerrainHeight;
	
	vec2 step_uv = uv;
	vec3 current_position = fbm_sample_to_world_space(step_uv, fbm);
	float height = current_position.y;
	float shadowHeight = height;
	
	float step_size = min_step_size;
	int remaining_steps = 30;
	
	while (remaining_steps > 0)
	{
		vec3 next_step = step_size * _LightDirection;
		step_uv += next_step.xz / _MeshSize;
		if (any(greaterThanEqual(step_uv, vec2(1))) || any(lessThanEqual(step_uv, vec2(0))))
		{
			if (step_uv.x > 1)
			{
				next_step *= - (step_uv.x - 1) / next_step.x;
				step_uv += next_step.xz / _MeshSize;
			}
			else if (step_uv.x < 0)
			{
				next_step *= - (0 - step_uv.x) / next_step.x;
				step_uv += next_step.xz / _MeshSize;
			}
			if (step_uv.y > 1)
			{
				next_step *= - (step_uv.y - 1) / next_step.y;
				step_uv += next_step.xz / _MeshSize;
			}
			else if (step_uv.y < 0)
			{
				next_step *= - (0 - step_uv.y) / next_step.y;
				step_uv += next_step.xz / _MeshSize;
			}
			remaining_steps = min(remaining_steps, 3);
		}
		current_position = fbm_sample_to_world_space(step_uv);
		float rayDeltaHeight = length(step_uv - uv) * _MeshSize * abs(_LightDirection.y);
		if (shadowHeight + rayDeltaHeight < current_position.y)
			shadowHeight = current_position.y - rayDeltaHeight;
		step_size = max(min_step_size, adaptive_step_multiplyer * (shadowHeight + rayDeltaHeight - current_position.y));
		remaining_steps--;
	}
	
	return shadowHeight;
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
