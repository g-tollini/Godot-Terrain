#[compute]
#version 450

// src_tex = mip level N (input, readonly)
layout(set = 0, binding = 0, rgba16f) uniform readonly image2D src_tex;

// dst_tex = mip level N+1 (output, writeonly)
layout(set = 0, binding = 1, rgba16f) uniform writeonly image2D dst_tex;

layout(local_size_x = 8, local_size_y = 8) in;

void main()
{
	ivec2 dst_coord = ivec2(gl_GlobalInvocationID.xy);
	ivec2 src_coord = dst_coord * 2;
	
	ivec2 dimensions = imageSize(dst_tex);
	if (any(greaterThanEqual(dst_coord, dimensions)))
		return;
	vec2 uv = vec2(dst_coord) / vec2(dimensions);

	vec4 a = imageLoad(src_tex, src_coord);
	vec4 b = imageLoad(src_tex, src_coord + ivec2(1, 0));
	vec4 c = imageLoad(src_tex, src_coord + ivec2(0, 1));
	vec4 d = imageLoad(src_tex, src_coord + ivec2(1, 1));

	vec4 max_color = max(max(a, b), max(c, d));
	imageStore(dst_tex, dst_coord, max_color);
}
