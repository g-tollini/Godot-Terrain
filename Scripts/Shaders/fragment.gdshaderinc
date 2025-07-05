#version 450

#include "Scripts/Shaders/buffer.gdshaderinc"
#include "Scripts/Shaders/noise.gdshaderinc"

// Texturing
layout(set = 0, binding = 1) uniform sampler2D low_slope_texture;
layout(set = 0, binding = 2) uniform sampler2D high_slope_texture;

// Precomputed fbm texture
layout(set = 0, binding = 3) uniform sampler2D fbmmap;

// Heightmap
layout(set = 0, binding = 4) uniform sampler2D heightmap;

// These are the variables that we expect to receive from the vertex shader
layout(location = 2) in vec4 a_Color;
layout(location = 3) in vec3 pos;

// This is what the fragment shader will output, usually just a pixel color
layout(location = 0) out vec4 frag_color;


void main() {
	// Recalculate initial noise sampling position same as vertex shader
	vec3 noise_pos = (pos + vec3(_Offset.x, 0, _Offset.z)) / _Scale;

	// vertices positions range from 0.5 * _MeshSize * vec3(-1, 0, -1)
	// to 0.5 * _MeshSize * vec3(1, 0, 1)
	vec2 pos_min_xz = -0.5 * _MeshSize * vec2(1);
	vec2 uv = (pos.xz - pos_min_xz) / _MeshSize;
	float mul0 = 16;
	float mul1 = 32;
	float mul2 = 64;

	// Calculate fbm, we don't care about the height just the derivatives here for the normal vector so the ` + _TerrainHeight - _Offset.y` drops off as it isn't relevant to the derivative
	vec3 n;
	if (_FragmentUseHeightmap) // even when using the precomputed fbm texture for the vertex displacement, evaluating the fbm for each fragment instead of interpolating the sampled values gives a way better shading
		n = 2 * (texture(fbmmap, uv).xyz - vec3(0.5)) +
		  1 / (mul2) * 2 * (texture(fbmmap, mul0 * vec2(-uv.x, uv.y)).xyz - vec3(0.5)) // no sqrt here because it looked nicer without it
		+ 1 / (mul2) * 2 * (texture(fbmmap, mul0 * vec2(uv.x, -uv.y)).xyz - vec3(0.5)) // using different flipped uvs like vec2(-uv.x, uv.y) aims at countering the effect of uneven low frequency terrain not producing high frequency random visuals when sampled
		+ 1 / sqrt(mul1) * 2 * (texture(fbmmap, mul1 * vec2(uv.x, -uv.y)).xyz - vec3(0.5)) // using sqrt so that the amplitude does not decay too much
		+ 1 / sqrt(mul1) * 2 * (texture(fbmmap, mul2 * vec2(-uv.x, uv.y)).xyz - vec3(0.5)); // we actually increase the amplitude of the sample with the frequency, we should be doing the opposite but this gives better results imo
	else
		n = fbm(noise_pos.xz);
	n *= _TerrainHeight;

	// To more easily customize the color slope blending this is a separate normal vector with its horizontal gradients significantly reduced so the normal points upwards more
	vec3 slope_normal = normalize(vec3(-n.y, 1, -n.z) * vec3(_SlopeDamping, 1, _SlopeDamping));

	// Use the slope of the above normal to create the blend value between the two terrain colors
	float material_blend_factor = smoothstep(_SlopeRange.x, _SlopeRange.y, 1 - slope_normal.y);

	// This is the actual surface normal vector
	vec3 normal = normalize(vec3(-n.y, 1, -n.z));

	// Texturing
	// Horizontal
	vec2 uv_y = 0.001 * uv * _LowSlopeTexST.xy + _LowSlopeTexST.zw;
	// Vertical
	vec2 uv_x = -0.001 * uv * _HighSlopeTexST.xy + _HighSlopeTexST.zw;
	vec2 uv_z = -0.001 * uv * _HighSlopeTexST.xy + _HighSlopeTexST.zw;

	vec4 lowSlopeTexSample = texture(low_slope_texture, uv_y);
	vec4 highSlopeTexSample_x = texture(high_slope_texture, uv_x);
	vec4 highSlopeTexSample_z = texture(high_slope_texture, uv_z);

	float nx = abs(normal.x);
	float nz = abs(normal.z);
	float highSlopeTex_blend = nz / (nx + nz);
	vec4 highSlopeTexSample = mix(highSlopeTexSample_x, highSlopeTexSample_z, highSlopeTex_blend);

	// Blend between the two terrain colors
	vec4 albedo = mix(lowSlopeTexSample * _LowSlopeColor, highSlopeTexSample * _HighSlopeColor, vec4(material_blend_factor));

	// Lambertian diffuse, negative dot product values clamped off because negative light doesn't exist
	//float ndotl = clamp(dot(_LightDirection, normal), 0, 1);
	float ndotl = 0.5 * (1 + dot(_LightDirection, normal));

	// Direct light cares about the diffuse result, ambient light does not
	vec4 direct_light = albedo * ndotl;
	vec4 ambient_light = albedo * _AmbientLight;

	// Combine lighting values, clip to prevent pixel values greater than 1 which would really really mess up the gamma correction below
	vec4 lit = clamp(direct_light + ambient_light, vec4(0), vec4(1));

	vec4 heightmap_sample = texture(heightmap, uv);
	float height = heightmap_sample.x;
	float shadowHeight = heightmap_sample.y;
	float shadowDepthCoeff = 3;
	float shadowStrength = 1 - shadowDepthCoeff * clamp(0, 1 / shadowDepthCoeff, (shadowHeight - height) * _TerrainHeight / _Scale);
	//if (shadowHeight > height + 0.1)
		//lit *= 0.5 * (shadowStrength + shadowStrength * shadowStrength);

	lit.a = 1;

	// Convert from linear rgb to srgb for proper color output, ideally you'd do this as some final post processing effect because otherwise you will need to revert this gamma correction elsewhere
	frag_color = pow(lit, vec4(2.2));
}
