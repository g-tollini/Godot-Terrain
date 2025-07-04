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
};

layout(set = 0, binding = 1) uniform sampler2D fbmmap;
layout(set = 0, binding = 2, rgba16f) restrict uniform image2D heightmap;

// Thread groups size
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

void main()
{
	int x = ivec2(gl_GlobalInvocationID.xy).x;
	ivec2 dimensions = imageSize(heightmap);
	for (int y = 0 ; y < imageSize(heightmap).y ; y++)
	{
		ivec2 xy = ivec2(x, y);
		vec2 uv = vec2(xy) / vec2(dimensions);
		
		// vertices positions range from 0.5 * _MeshSize * vec3(-1, 0, -1)
		// to 0.5 * _MeshSize * vec3(1, 0, 1)
		vec3 pos = _MeshSize * vec3(uv.x - 0.5, 0, uv.y - 0.5);
		vec3 noise_pos = (pos + vec3(_Offset.x, 0, _Offset.z)) / _Scale;

		// The fractional brownian motion
		vec3 n = texture(fbmmap, uv).xyz; // values in -1 ; 1
		
		// Adjust height of the vertex by fbm result scaled by final desired amplitude
		float height = n.x;
		float shadowheight = n.x;
		// Dummy shadows
		if (y > 0)
			shadowheight = max(height, imageLoad(heightmap, ivec2(x, y-1)).g);
		
		imageStore(heightmap, xy, vec4(height, shadowheight, 0, 0));
	}
}
