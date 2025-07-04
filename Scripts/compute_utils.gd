

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
	buffer : Array,
	# Importing a saved fbm map
	use_imported_fbm : bool = false, 
	imported_fbm : Texture2D = null) -> void:

	if local_rd == null:
		push_error("Local RenderingDevice provided to compute_fbm is null")
		return 
		
	if !local_rd.texture_is_valid(local_rd_texture):
		push_error("RD Texture provided to compute_fbm is invalid for the given RenderingDevice")
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
	var buffer_bytes : PackedByteArray = PackedFloat32Array(buffer).to_byte_array()
	var p_uniform_buffer : RID = local_rd.uniform_buffer_create(buffer_bytes.size(), buffer_bytes)
	
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
	local_rd.sync() # could delay this to avoid freezing the frame
