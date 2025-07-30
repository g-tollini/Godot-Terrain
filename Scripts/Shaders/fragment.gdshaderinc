#version 450

#include "Scripts/Shaders/buffer.gdshaderinc"
#include "Scripts/Shaders/noise.gdshaderinc"

// Texturing
layout(set = 0, binding = 1) uniform sampler2D low_slope_texture;
layout(set = 0, binding = 2) uniform sampler2D high_slope_texture;

// Precomputed fbm texture
layout(set = 0, binding = 3) uniform sampler2D fbmmap;

// ShadowMap
layout(set = 0, binding = 4) uniform sampler2D shadowmap;

// These are the variables that we expect to receive from the vertex shader
layout(location = 2) in vec4 a_Color;
layout(location = 3) in vec3 pos;

// This is what the fragment shader will output, usually just a pixel color
layout(location = 0) out vec4 frag_color;

// Returns shadow depth (ie distance between terrain and light / shadow limit) at position
vec4 shadow_ray_marching(in vec3 position);
vec3 fragment_fbm(vec3 position);
vec2 uv_shadowmap_to_terrain(in vec2 uv);
vec2 uv_terrain_to_shadowmap(in vec2 uv);

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
	if (_FragmentUseFbmMap) // even when using the precomputed fbm texture for the vertex displacement, evaluating the fbm for each fragment instead of interpolating the sampled values gives a way better shading
	{
		vec2 uv0 = (mul0 + 1) * vec2(-uv.x, uv.y); // using different flipped uvs like vec2(-uv.x, uv.y) aims at countering the effect of uneven low frequency terrain not producing high frequency random visuals when sampled
		vec2 uv1 = (mul1 + 1) * vec2(uv.x, -uv.y); // adding +1 so that the frequency multiplicators are not multiple of each other which would produce straight lines in some places

		vec2 mirrored_uv0 = vec2(1) - abs(mod(uv0, 2.0) - 1.0);
		vec2 mirrored_uv1 = vec2(1) - abs(mod(uv1, 2.0) - 1.0);

		float bias_uv = - _FragmentFbmMapBias;
		float bias_uv0 = - 2 * _FragmentFbmMapBias;
		float bias_uv1 = - 2 * _FragmentFbmMapBias;

		n = 2 * (texture(fbmmap, uv, bias_uv).xyz - vec3(0.5)) +
		  1 / sqrt(mul1) * 2 * (texture(fbmmap, mirrored_uv0, bias_uv0).xyz - vec3(0.5)) // no sqrt here because it looked nicer without it
		+ 1 / sqrt(mul1) * 2 * (texture(fbmmap, mirrored_uv1, bias_uv1).xyz - vec3(0.5));

		if (_FragmentEnhanceWithNoise) // should be based fragment distance to camera
		{
			// Enhance terrain appearance when looking closely using perlin noise
			float mul = 300;
			vec2 uv_noise = mul * noise_pos.xz;

			n += 1.2 * ( 1 / sqrt(mul1) * perlin_noise2D(uv_noise)
				+ 1 / sqrt(mul1) * perlin_noise2D(2 * uv_noise)
				+ 1 / sqrt(mul1) * perlin_noise2D(4 * uv_noise));
		}
	}
	else
	{
		n = fbm(noise_pos.xz);
	}
	n *= _TerrainHeight;

	// To more easily customize the color slope blending this is a separate normal vector with its horizontal gradients significantly reduced so the normal points upwards more
	vec3 slope_normal = normalize(vec3(-n.y, 1, -n.z) * vec3(_SlopeDamping, 1, _SlopeDamping));

	// Use the slope of the above normal to create the blend value between the two terrain colors
	float material_blend_factor = smoothstep(_SlopeRange.x, _SlopeRange.y, 1 - slope_normal.y);

	// This is the actual surface normal vector
	vec3 normal = normalize(vec3(-n.y, _UseOriginalNormals ? 1 : _Scale, -n.z));

	// Texturing
	vec4 lowSlopeTexSample = vec4(1);
	vec4 highSlopeTexSample = vec4(1);
	if(_EnableTexturing)
	{
		// Horizontal
		vec2 uv_y = uv * _LowSlopeTexST.xy + _LowSlopeTexST.zw;
		// Vertical
		vec2 uv_x = uv * _HighSlopeTexST.xy + _HighSlopeTexST.zw;
		vec2 uv_z = uv * _HighSlopeTexST.xy + _HighSlopeTexST.zw;

		lowSlopeTexSample = texture(low_slope_texture, uv_y);

		float nx = abs(normal.x);
		float nz = abs(normal.z);
		float highSlopeTex_blend = nz / (nx + nz);

		vec4 highSlopeTexSample_x = texture(high_slope_texture, uv_x);
		vec4 highSlopeTexSample_z = texture(high_slope_texture, uv_z);

		highSlopeTexSample = mix(highSlopeTexSample_x, highSlopeTexSample_z, highSlopeTex_blend);
	}

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

	vec4 shadowMap;
	float shadow = 0; // 0 means no shadow, 1 means completely dark
	if (_EnableCastShadows && _ShadowStrength != 0)
	{
		// Compute shadows
		if (_FragmentShadows)
		{
			shadowMap = shadow_ray_marching(pos);
		}
		else
		{
			if (_RotateShadowMapTowardsLight)
				uv = uv_terrain_to_shadowmap(uv);
			shadowMap = texture(shadowmap, uv);
		}

		float shadowDepth_unorm = shadowMap.x;
		float shadowDepth = max(2 * shadowDepth_unorm * _TerrainHeight, 0); // how far above the terrain the light / shadow limit is
		shadow = _ShadowStrength * clamp(0, 1 / _ShadowStrength, 0.5 * shadowDepth / _TerrainHeight);

		float light_shadow_threshold = 0.005;
		if (shadow > light_shadow_threshold || (_ShadowStopOnHit && shadow > 0))
		{
			float base_shadow_strength = (1 - _SoftShadows) * _ShadowStrength / 10.0;

			shadow = base_shadow_strength + clamp(0, 1 - base_shadow_strength, shadow); // hard shadows
			
			float soft_shadow_slider_coeff = 0.15; // to limit the _SoftShadows slider values (in [0 ; 1]) to values that look good
			float soft = smoothstep(0.5 * soft_shadow_slider_coeff * _SoftShadows, soft_shadow_slider_coeff * _SoftShadows, shadow - base_shadow_strength); // soft shadows
			
			if (_BinaryShadows)
				shadow = (_ShadowStrength / 10.0);
			shadow = shadow * soft;
		}

		// Apply shadows
		lit *= mix(1 - shadow, sqrt(1 - shadow), 0.2);
		lit.a = 1;
	}

	// Shadowmap ray marching number of steps heatmap
	vec3 cold = vec3(0.4, 0.7, 0.4); // blue
	vec3 cold_medium = vec3(0.5, 0.5, 0.8); // yellow
	vec3 medium_hot = vec3(0.9, 0.6, 0.2); // orange
	vec3 hot = vec3(1, 0.2, 0.1); // red

	vec3 heat;
	float value = shadowMap.z;
	float threshold0 = 0.4;
	float threshold1 = 0.8;
	if (value < threshold0)
		heat = mix(cold, cold_medium, value / threshold0);
	else if (value < threshold1)
		heat = mix(cold_medium, medium_hot, (value - threshold0) / (threshold1 - threshold0));
	else
		heat = mix(medium_hot, hot, (value - threshold1) / (1 - threshold1));


	if	(_RayStepsHeatmap)
		lit = vec4(heat, 1);

	// Convert from linear rgb to srgb for proper color output, ideally you'd do this as some final post processing effect because otherwise you will need to revert this gamma correction elsewhere
	frag_color = pow(lit, vec4(2.2));
}

// Returns shadow depth (ie distance between terrain and light / shadow limit) at position
vec4 shadow_ray_marching(in vec3 position)
{
	vec3 pos_min = -0.5 * _MeshSize * vec3(1);
	vec3 pos_max = 0.5 * _MeshSize * vec3(1);
	float min_step_size = clamp(0.05, 10, _ShadowMinStepSize);
	float adaptive_step_multiplyer = 10 * _ShadowAdaptiveStepSize;
	int remaining_steps = int(_ShadowMaxStepCount);

	vec3 current_position = position;
	vec3 n = fragment_fbm(position);

	current_position.y = (n.x + 1) * _TerrainHeight - _Offset.y;
	float height = current_position.y;
	float shadowDepth = 0;

	float step_size = min_step_size;
	float num_steps = 0;
	float shadow_at_step = 0;
	current_position += step_size * _LightDirection;

	while (remaining_steps > 0 &&
		all(lessThanEqual(current_position.xz, pos_max.xz)) &&
		all(greaterThanEqual(current_position.xz, pos_min.xz)) )
	{
		num_steps += 1 / _ShadowMaxStepCount;
		n = fragment_fbm(current_position);
		current_position.y = (n.x + 1) * _TerrainHeight - _Offset.y;
		float rayDeltaHeight = length((current_position - position).xz) * abs(_LightDirection.y);
		if (height + rayDeltaHeight < current_position.y)
		{
			shadowDepth = max(shadowDepth, current_position.y - height - rayDeltaHeight);
			shadow_at_step = num_steps;
			if (_ShadowStopOnHit)
				remaining_steps = 0;
		}
		step_size = max(min_step_size, adaptive_step_multiplyer * (height + rayDeltaHeight - current_position.y));

		vec3 next_step = step_size * _LightDirection;
		current_position += next_step;
		remaining_steps--;
	}

	return vec4(0.5 * shadowDepth / _TerrainHeight, 0, num_steps, shadow_at_step);
}

vec3 fragment_fbm(vec3 position)
{
	if (_FragmentUseFbmMap)
	{
		vec2 uv = position.xz / _MeshSize + vec2(0.5);
		vec3 fbm_unorm = texture(fbmmap, uv, -_FragmentFbmMapBias).xyz;
		return 2 * (fbm_unorm - vec3(0.5));
	}
	else
	{
		vec3 noise_position = (position + vec3(_Offset.x, 0, _Offset.z)) / _Scale;
		return fbm(noise_position.xz);
	}
}

vec2 uv_terrain_to_shadowmap(in vec2 uv)
{
	vec2 l = normalize(_LightDirection.xz);
	float nl = dot(l, l);
	float cos_theta = l.y / nl;
	float sin_theta = - (-l.x / nl);

	float theta = -atan(l.x, l.y);
	float phi = PI / 4.0 - mod(theta, PI / 2.0);
	float a_p = sqrt(2) * cos(phi);

	vec2 uv_p = uv - vec2(0.5);
	uv_p = (1.0 / a_p) * vec2(
		uv_p.x * cos_theta - uv_p.y * sin_theta,
		uv_p.x * sin_theta + uv_p.y * cos_theta);
	uv_p += vec2(0.5);

	uv_p = clamp(vec2(0), vec2(1), uv_p);

	return uv_p;
}
