

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

static func ComputeShadowMap(
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
		push_error("Fbm RD Texture provided to ComputeShadowMap is invalid for the given RenderingDevice")
		return
	if !local_rd.texture_is_valid(heightmap_compute_rdtex):
		push_error("Heightmap RD Texture provided to ComputeShadowMap is invalid for the given RenderingDevice")
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

	var compute_shadowmap_uniform_set = local_rd.uniform_set_create([uniform, fbm_uniform, heightmap_uniform], heightmap_compute_shader, 0)
	var compute_shadowmap_pipeline = local_rd.compute_pipeline_create(heightmap_compute_shader)
	
	var compute_list := local_rd.compute_list_begin()
	local_rd.compute_list_bind_compute_pipeline(compute_list, compute_shadowmap_pipeline)
	local_rd.compute_list_bind_uniform_set(compute_list, compute_shadowmap_uniform_set, 0)
	
	local_rd.compute_list_dispatch(compute_list, fbm_texture_width / 1, fbm_texture_width / 512, 1)
	local_rd.compute_list_end()

	local_rd.submit()
	local_rd.sync()

static func ComputeMaximumMipMap(
	# CPU image
	fbm_image : Image,
	# Main rendering device
	main_rd : RenderingDevice,
	fbm_render_rdtex : RID,
	fbm_tex_format : RDTextureFormat,
	# Compute rendering device
	local_rd : RenderingDevice,
	# Compute texture
	fbm_compute_rdtex : RID,
	# Compute shader
	maximum_mipmap_compute_shader : RID,
	# Source mip level
	src_mip_level : int) -> void:

	if local_rd == null:
		push_error("Local RenderingDevice provided to compute_maximum_mipmap is null")
		return
		
	# The method used reads back and uploads data to GPU for each mip level
	# I could not figure a way to modify the mipmaps directly on GPU
		
	var fbm_texture_width = fbm_image.get_width()
	var src_mip_width = fbm_texture_width / pow(2, src_mip_level)
	var dst_mip_width = src_mip_width / 2
		
	var src_mip_offset = fbm_image.get_mipmap_offset(src_mip_level)
	var dst_mip_offset = fbm_image.get_mipmap_offset(src_mip_level + 1)
	
	var src_mip_data_size = dst_mip_offset - src_mip_offset
	var dst_mip_data_size = src_mip_data_size / 4
	
	# fbm_image contains up to date data, previously read back from GPU
	var fbm_data = fbm_image.get_data()
	# Selecting the source mip level data
	var src_mip_data = fbm_data.slice(src_mip_offset, src_mip_offset + src_mip_data_size)
	
	var mip_format = RDTextureFormat.new()
	mip_format.texture_type = fbm_tex_format.texture_type
	mip_format.format = fbm_tex_format.format
	mip_format.width = src_mip_width
	mip_format.height = src_mip_width
	mip_format.depth = fbm_tex_format.depth
	mip_format.mipmaps = 1
	mip_format.samples = fbm_tex_format.samples
	mip_format.usage_bits = fbm_tex_format.usage_bits
	mip_format.array_layers = fbm_tex_format.array_layers
	
	# Creating the source mip level texture on GPU and uploading data from CPU
	var src_mip_compute = local_rd.texture_create(mip_format, RDTextureView.new(), [src_mip_data])
	
	mip_format.width = dst_mip_width
	mip_format.height = dst_mip_width
	
	# Creating target mip level texture to which the compute shader is going to write
	var dst_mip_compute = local_rd.texture_create(mip_format, RDTextureView.new())
	
	# Uniforms
	var uniform_src := RDUniform.new()
	uniform_src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_src.binding = 0
	uniform_src.add_id(src_mip_compute)
	
	var uniform_dst := RDUniform.new()
	uniform_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_dst.binding = 1
	uniform_dst.add_id(dst_mip_compute)

	var maximum_mipmap_fbm_uniform_set = local_rd.uniform_set_create([uniform_src, uniform_dst], maximum_mipmap_compute_shader, 0)
	var maximum_mipmap_fbm_pipeline = local_rd.compute_pipeline_create(maximum_mipmap_compute_shader)
	
	var compute_list := local_rd.compute_list_begin()
	local_rd.compute_list_bind_compute_pipeline(compute_list, maximum_mipmap_fbm_pipeline)
	local_rd.compute_list_bind_uniform_set(compute_list, maximum_mipmap_fbm_uniform_set, 0)
	
	local_rd.compute_list_dispatch(compute_list, max(dst_mip_width / 8, 1), max(dst_mip_width / 8, 1), 1)
	local_rd.compute_list_end()

	local_rd.submit()
	local_rd.sync()
	
	# Reading back target mip level data from GPU
	var dst_mip_data = local_rd.texture_get_data(dst_mip_compute, 0)
	
	# Textures can be freed
	local_rd.free_rid(src_mip_compute)
	local_rd.free_rid(dst_mip_compute)
	
	# Copying into the global image data
	for i in range(dst_mip_data_size):
		fbm_data[dst_mip_offset + i] = dst_mip_data[i]
	
	# Updating the image on CPU
	fbm_image.set_data(fbm_texture_width, fbm_texture_width, true, Image.FORMAT_RGBAH, fbm_data)
	
	# Updating the texture on GPU
	main_rd.texture_update(fbm_render_rdtex, 0, fbm_data)
