

class_name ComputeUtils

static func ComputeFbmMap(
	# Main rendering device
	main_rd : RenderingDevice,
	fbm_render_rdtex : RID,
	# Compute rendering device
	local_rd : RenderingDevice,
	fbm_compute_shader : RID,
	local_rd_texture : RID,
	fbm_texture_width : int,
	# Noise settings
	p_uniform_buffer : RID,
	# Importing a saved fbm map
	use_imported_fbm : bool = false, 
	imported_fbm : Texture2D = null) -> void:

	if local_rd == null:
		push_error("Local RenderingDevice provided to compute_fbm is null")
		return 
		
	if !local_rd.texture_is_valid(local_rd_texture):
		push_error("RD Texture provided to ComputeFbmMap is invalid for the given RenderingDevice")
		return
	
	if use_imported_fbm:
		if imported_fbm == null:
			push_error("You need to assign a texture to 'import_fbm' in order to use imported fbm")
			return
		
		var image = imported_fbm.get_image()
		image.convert(Image.FORMAT_RGBAH)
		main_rd.texture_update(fbm_render_rdtex, 0, image.get_data())
		return
		
	# Uniforms
	var uniform := RDUniform.new()
	
	# The gpu needs to know the layout of the uniform variables, even though we have many variables here on the cpu, they're all in one uniform buffer, and so there is technically only one shader uniform
	uniform.binding = 0
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.add_id(p_uniform_buffer)
		
	var fbm_uniform := RDUniform.new()
	fbm_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	fbm_uniform.binding = 1
	fbm_uniform.add_id(local_rd_texture)

	var compute_fbm_uniform_set = local_rd.uniform_set_create([uniform, fbm_uniform], fbm_compute_shader, 0)
	var compute_fbm_pipeline = local_rd.compute_pipeline_create(fbm_compute_shader)
	
	var compute_list := local_rd.compute_list_begin()
	local_rd.compute_list_bind_compute_pipeline(compute_list, compute_fbm_pipeline)
	local_rd.compute_list_bind_uniform_set(compute_list, compute_fbm_uniform_set, 0)
	
	local_rd.compute_list_dispatch(compute_list, fbm_texture_width / 8, fbm_texture_width / 8, 1)
	local_rd.compute_list_end()

	local_rd.submit()
	local_rd.sync()

static func ComputeHeightMap(
	# Compute rendering device
	local_rd : RenderingDevice,
	heightmap_compute_shader : RID,
	fbm_compute_rdtex : RID,
	fbm_texture_width : int,
	heightmap_compute_rdtex : RID,
	heightmap_texture_width : int,
	# Noise settings
	p_uniform_buffer : RID) -> void:

	if local_rd == null:
		push_error("Local RenderingDevice provided to compute_fbm is null")
		return 
		
	if !local_rd.texture_is_valid(fbm_compute_rdtex):
		push_error("Fbm RD Texture provided to ComputeHeightMap is invalid for the given RenderingDevice")
		return
	if !local_rd.texture_is_valid(heightmap_compute_rdtex):
		push_error("Heightmap RD Texture provided to ComputeHeightMap is invalid for the given RenderingDevice")
		return
	
	# Uniforms
	var uniform := RDUniform.new()
	
	# The gpu needs to know the layout of the uniform variables, even though we have many variables here on the cpu, they're all in one uniform buffer, and so there is technically only one shader uniform
	uniform.binding = 0
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.add_id(p_uniform_buffer)
	
	# Binding the fbm uniform for the compute shader to read the fbm
	var fbm_sampler_state := RDSamplerState.new()
	fbm_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	fbm_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	var fbm_sampler = local_rd.sampler_create(fbm_sampler_state)
	
	var fbm_uniform := RDUniform.new()
	fbm_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	fbm_uniform.binding = 1
	fbm_uniform.add_id(fbm_sampler)
	fbm_uniform.add_id(fbm_compute_rdtex)
		
	var heightmap_uniform := RDUniform.new()
	heightmap_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	heightmap_uniform.binding = 2
	heightmap_uniform.add_id(heightmap_compute_rdtex)

	var compute_heightmap_uniform_set = local_rd.uniform_set_create([uniform, fbm_uniform, heightmap_uniform], heightmap_compute_shader, 0)
	var compute_heightmap_pipeline = local_rd.compute_pipeline_create(heightmap_compute_shader)
	
	var compute_list := local_rd.compute_list_begin()
	local_rd.compute_list_bind_compute_pipeline(compute_list, compute_heightmap_pipeline)
	local_rd.compute_list_bind_uniform_set(compute_list, compute_heightmap_uniform_set, 0)
	
	local_rd.compute_list_dispatch(compute_list, fbm_texture_width / 8, fbm_texture_width / 8, 1)
	local_rd.compute_list_end()

	local_rd.submit()
	local_rd.sync()
