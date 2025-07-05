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
	bool _ShadowPropagation;
};

layout(set = 0, binding = 1) uniform sampler2D fbmmap;
layout(set = 0, binding = 2, rgba16f) restrict uniform image2D heightmap;

// Thread groups size
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// returns shadow height for texel xy
float shadow_propagation(in ivec2 xy, in ivec2 dimensions, in vec2 uv, in vec3 fbm);

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

	// The fractional brownian motion
	vec3 n = texture(fbmmap, uv).xyz; // values in 0 ; 1
	float height = n.x;
	
	float shadowheight = 0;
	if (_ShadowPropagation)
		shadowheight = shadow_propagation(xy, dimensions, uv, n);
	
	imageStore(heightmap, xy, vec4(height, shadowheight, 0, 0));
}

float shadow_propagation(in ivec2 xy, in ivec2 dimensions, in vec2 uv, in vec3 fbm)
{
	vec2 towards_light_d_uv = _LightDirection.xz;
	float abs_x = abs(towards_light_d_uv.x);
	float abs_y = abs(towards_light_d_uv.y);
	
	ivec2 towards_light_sample_1_xy;
	ivec2 towards_light_sample_2_xy;
	float sample_1_weight;
	
	//float repeat_distance = 5; // repeat shadow propagation from a distance so that it propagates faster ; but then it may introduce incorrect shadows
	//ivec2 towards_light_sample_repeat_1_xy;
	//ivec2 towards_light_sample_repeat_2_xy;
	
	if (abs_x > abs_y)
	{
		towards_light_d_uv /= abs_x;
		towards_light_sample_1_xy = xy + ivec2(towards_light_d_uv.x, floor(towards_light_d_uv.y));
		towards_light_sample_2_xy = xy + ivec2(towards_light_d_uv.x, ceil(towards_light_d_uv.y));
		//towards_light_sample_repeat_1_xy = xy + ivec2(repeat_distance * towards_light_d_uv.x, floor(repeat_distance * towards_light_d_uv.y));
		//towards_light_sample_repeat_2_xy = xy + ivec2(repeat_distance * towards_light_d_uv.x, ceil(repeat_distance * towards_light_d_uv.y));
		if (towards_light_d_uv.y > 0)
			sample_1_weight = towards_light_d_uv.y;
		else
			sample_1_weight = 1 + towards_light_d_uv.y;
	}
	else
	{
	 	towards_light_d_uv /= abs_y;
		towards_light_sample_1_xy = xy + ivec2(floor(towards_light_d_uv.x), towards_light_d_uv.y);
		towards_light_sample_2_xy = xy + ivec2(ceil(towards_light_d_uv.x), towards_light_d_uv.y);
		//towards_light_sample_repeat_1_xy = xy + ivec2(floor(repeat_distance * towards_light_d_uv.x), repeat_distance * towards_light_d_uv.y);
		//towards_light_sample_repeat_2_xy = xy + ivec2(ceil(repeat_distance * towards_light_d_uv.x), repeat_distance * towards_light_d_uv.y);
		if (towards_light_d_uv.x > 0)
			sample_1_weight = towards_light_d_uv.x;
		else
			sample_1_weight = 1 + towards_light_d_uv.x;
	}
	
	towards_light_sample_1_xy = clamp(ivec2(0), dimensions - ivec2(1), towards_light_sample_1_xy);
	towards_light_sample_2_xy = clamp(ivec2(0), dimensions - ivec2(1), towards_light_sample_2_xy);
	//towards_light_sample_repeat_1_xy = clamp(ivec2(0), dimensions - ivec2(1), towards_light_sample_repeat_1_xy);
	//towards_light_sample_repeat_2_xy = clamp(ivec2(0), dimensions - ivec2(1), towards_light_sample_repeat_2_xy);
	
	
	// Adjust height of the vertex by fbm result scaled by final desired amplitude
	float height = fbm.x;
	float shadowheight = height;
	
	// Propagate neighboring shadows
	//towards_light_sample_1_xy = xy + ivec2(1, 0);
	//towards_light_sample_2_xy = xy + ivec2(1, 1);
	vec4 sample_1 = imageLoad(heightmap, towards_light_sample_1_xy);
	vec4 sample_2 = imageLoad(heightmap, towards_light_sample_2_xy);
	//vec4 sample_repeat_1 = imageLoad(heightmap, towards_light_sample_repeat_1_xy);
	//vec4 sample_repeat_2 = imageLoad(heightmap, towards_light_sample_repeat_2_xy);
	
	float decay = (length(towards_light_d_uv) / _MeshSize) * (abs(_LightDirection.y)) / 2;
	
	float neighbors_shadowheight = mix(sample_1.g, sample_2.g, sample_1_weight) - decay;
	//float repeat_shadowheight = mix(sample_repeat_1.g, sample_repeat_2.g, sample_1_weight) - repeat_distance * decay;
	shadowheight = max(height, neighbors_shadowheight);
	
	return shadowheight;
}
