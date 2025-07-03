#version 450

#include "Scripts/Shaders/buffer.gdshaderinc"
#include "Scripts/Shaders/noise.gdshaderinc"

// Heightmap
layout(set = 0, binding = 3) uniform sampler2D heightmap;

// This is the vertex data layout that we defined in initialize_render after line 198
layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec4 a_Color;

// This is what the vertex shader will output and send to the fragment shader.
layout(location = 2) out vec4 v_Color;
layout(location = 3) out vec3 pos;

void main() {
	// Passes the vertex color over to the fragment shader, even though we don't use it but you can use it if you want I guess
	v_Color = a_Color;

	// The fragment shader also calculates the fractional brownian motion for pixel perfect normal vectors and lighting, so we pass the vertex position to the fragment shader
	pos = a_Position;

	// Initial noise sample position offset and scaled by uniform variables
	vec3 noise_pos = (pos + vec3(_Offset.x, 0, _Offset.z)) / _Scale;
	
	// vertices positions range from 0.5 * _MeshSize * vec3(-1, 0, -1)
	// to 0.5 * _MeshSize * vec3(1, 0, 1)
	vec2 pos_min_xz = -0.5 * _MeshSize * vec2(1);
	vec2 uv = (pos.xz - pos_min_xz) / _MeshSize;

	// The fractional brownian motion
	vec3 n;
	if (_VertexUseHeightmap)
		n = 2 * (texture(heightmap, uv).xyz - vec3(0.5));
	else
		n = fbm(noise_pos.xz);

	// Adjust height of the vertex by fbm result scaled by final desired amplitude
	pos.y += _TerrainHeight * n.x + _TerrainHeight - _Offset.y;
	
	// Multiply final vertex position with model/view/projection matrices to convert to clip space
	gl_Position = MVP * vec4(pos, 1);
}
