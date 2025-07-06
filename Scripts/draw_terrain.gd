@tool
class_name DrawTerrainMesh extends CompositorEffect


## Regenerate mesh data and recompile shaders TODO: Separate mesh generation and shader recompilation
@export var regenerate : bool = true

@export_group("Mesh Settings")
## Number of vertices in the plane mesh, quad count per row is thus  [code]side_length - 1[/code]
@export_range(2, 1000, 1, "or_greater") var side_length : int = 200

## Distance between vertices
@export_range(0.01, 1.0, 0.01, "or_greater") var mesh_scale : float = 1.0

## Render mesh wireframe
@export var wireframe : bool = false

@export_group("Noise Settings")

## Seed for the noise, change for instant gratification
@export var noise_seed : int = 0

## Horizontal scale of the noise
@export_range(0.1, 400, 0.1, "or_greater") var zoom : float = 100.0

## Horizontal scroll through the noise,  [code]y[/code] component adjusts height of plane
@export var offset : Vector3 = Vector3.ZERO

## Rotates the gradient vectors used to calculate perlin noise
@export_range(-180.0, 180.0) var gradient_rotation : float = 0.0

## How many layers of noise to sum. More octaves give more detail with diminishing returns.
@export_range(1, 32) var octave_count : int = 10

@export_subgroup("Octave Settings")
## Amount of rotation (in degrees) to apply each octave iteration
@export_range(-180.0, 180.0) var rotation : float = 30.0

## Random adjustment to rotation per octave, adjustment is generated between this range
@export var angular_variance : Vector2 = Vector2.ZERO

## Amplitude of the first noise octave
@export_range(0.01, 2.0) var initial_amplitude : float = 0.5

## Value to multiply with amplitude each octave iteration, lower values will reduce the impact of each subsequent octave.
@export_range(0.01, 1.0) var amplitude_decay : float = 0.45

## Self similarity of each octave
@export_range(0.01, 3.0) var lacunarity : float = 2.0

## Random adjustment to frequency per octave, adjustment is generated between this range
@export var frequency_variance : Vector2 = Vector2.ZERO

## Multiplies with final noise result to adjust terrain height
@export_range(0.0, 300.0, 0.1, "or_greater") var height_scale : float = 50.0

@export_group("Material Settings")

## Scales the slope to make slope blending easier
@export var slope_damping : float = 0.2

## If the slope is less than the low threshold, outputs  [code]low_slope_color[/code]. If the slope is greater than the upper threshold, outputs  [code]high_slope_color[/code]. If inbetween, blend between the colors.
@export var slope_threshold : Vector2 = Vector2(0.9, 0.98)

## Color of flatter areas of terrain
@export var low_slope_texture : Texture2D
@export var low_slope_texture_ST : Vector4 # ST means scale (xy) translation (zw)

@export var low_slope_color : Color = Color(0.83, 0.88, 0.94)

## Color of steeper areas of terrain
@export var high_slope_texture : Texture2D
@export var high_slope_texture_ST : Vector4

@export var high_slope_color : Color = Color(0.16, 0.1, 0.1)


@export_group("Light Settings")

## Additive light adjustment
@export var ambient_light : Color = Color.DIM_GRAY
@export var rotate_light_source : bool = false
@export_range(0.01, 1.0) var rotation_speed : float = 0.5

@export_group("Fbm Settings")
## Resizing not handled
@export var fbm_texture_width : int = 512 # could use side_length but then we would have to handle recreating the textures when the value changes
## Sample the Fbm instead of computing the noise in the vertex shader
@export var vertex_use_fbm : bool = false # use fbm texture in vertex shader
@export var fragment_use_fbm : bool = false # use fbm texture in fragment shader

@export_subgroup("Save Settings")
## fbm will be saved at 'res://fbm_file_name.png'
@export var fbm_file_name : String = "fbm"
@export var save_fbm : bool = false

@export_subgroup("Import Settings")
@export var import_fbm : Texture2D
@export var use_imported_fbm : bool = false

@export_group("Shadows settings")
@export_range(0, 10) var shadow_strength : float = 5
@export_range(0, 1) var soft_shadows : float = 0.5
@export_range(0, 1) var shadow_adaptive_step_size_coeff : float = 0.15
## Compute 'pixel-perfect' shadows in the fragment shader
@export var fragment_shadows : bool = false
## Default technique is ray marching. Shadow propagations is for experimentation purpose and does not work as well
@export var shadow_propagation : bool = false
@export var save_heightmap : bool = false

var transform : Transform3D
var light : DirectionalLight3D

var rd : RenderingDevice
var p_framebuffer : RID
var cached_framebuffer_format : int

var p_render_pipeline : RID
var p_render_pipeline_uniform_set : RID
var p_wire_render_pipeline : RID
var p_vertex_buffer : RID
var vertex_format : int
var p_vertex_array : RID
var p_index_buffer : RID
var p_index_array : RID
var p_wire_index_buffer : RID
var p_wire_index_array : RID
var p_shader : RID
var p_wire_shader : RID
var clear_colors := PackedColorArray([Color.DARK_BLUE])
var p_uniform_buffer : RID

# Texturing
var low_slope_rdtex : RID
var high_slope_rdtex : RID
var low_slope_texture_copied_to_gpu : RID
var high_slope_texture_copied_to_gpu : RID

# Compute render revice
var compute_rd : RenderingDevice
var p_uniform_compute_buffer : RID # compute_rd version of p_uniform_buffer
var geometry_buffer_hash : int = 0 # for detecting value updates affecting geometry
var lighting_buffer_hash : int = 0 # for detecting value updates affecting lighting
var geometry_changed : bool = true
var lighting_changed : bool = true

# Fbmmap
var fbm_render_rdtex : RID # fbm texture in the main rendering device
var fbm_compute_rdtex : RID # fbm texture in the compute rendering device (aliasing the one in the main rendering device)

# Heightmap
var heightmap_render_rdtex : RID # heightmap texture in the main rendering device
var heightmap_compute_rdtex : RID # heightmap texture in the compute rendering device (aliasing the one in the main rendering device)

func init_gpu():
	if rd == null:
		rd = RenderingServer.get_rendering_device()
		
	if compute_rd == null:
		compute_rd = RenderingServer.create_local_rendering_device() # local render device that runs the fbm compute shader
	
	# Creating 2 textures on the gpu for the flat / steep areas
	# Data will be copeid to these textures in _render_callback
	var slope_tex_format = RDTextureFormat.new()
	slope_tex_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	slope_tex_format.width = 1024
	slope_tex_format.height = 1024
	slope_tex_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	slope_tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	
	# Low slope
	low_slope_rdtex = rd.texture_create(slope_tex_format, RDTextureView.new())
	
	# High slope
	high_slope_rdtex = rd.texture_create(slope_tex_format, RDTextureView.new())
	
	# Fbm
	# Texture format
	var fbm_tex_format = RDTextureFormat.new()
	fbm_tex_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	fbm_tex_format.width = fbm_texture_width
	fbm_tex_format.height = fbm_texture_width
	fbm_tex_format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT # DATA_FORMAT_R8G8B8A8_UNORM is not precise enough
	fbm_tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	
	# Creating the textures in the render devices
	# One for the main rendering device (the one rendering the terrain)
	if !fbm_render_rdtex.is_valid():
		fbm_render_rdtex = rd.texture_create(fbm_tex_format, RDTextureView.new())
	
	# One for the compute shader (local) rendering device
	# This one is actually an alias for the one above that can be used in the local render device
	if !fbm_compute_rdtex.is_valid():
		fbm_compute_rdtex = compute_rd.texture_create_from_extension(RenderingDevice.TEXTURE_TYPE_2D,
			fbm_tex_format.format,
			fbm_tex_format.samples,
			fbm_tex_format.usage_bits,
			rd.get_driver_resource(RenderingDevice.DRIVER_RESOURCE_TEXTURE, fbm_render_rdtex, 0),
			fbm_tex_format.width,
			fbm_tex_format.height,
			fbm_tex_format.depth,
			fbm_tex_format.array_layers)
			
	# Heightmap
	# Same as for fbm
	if !heightmap_render_rdtex.is_valid():
		heightmap_render_rdtex = rd.texture_create(fbm_tex_format, RDTextureView.new())
		
	if !heightmap_compute_rdtex.is_valid():
		heightmap_compute_rdtex = compute_rd.texture_create_from_extension(RenderingDevice.TEXTURE_TYPE_2D,
			fbm_tex_format.format,
			fbm_tex_format.samples,
			fbm_tex_format.usage_bits,
			rd.get_driver_resource(RenderingDevice.DRIVER_RESOURCE_TEXTURE, heightmap_render_rdtex, 0),
			fbm_tex_format.width,
			fbm_tex_format.height,
			fbm_tex_format.depth,
			fbm_tex_format.array_layers)

func compute_fbm(buffer : Array):
	# Fbm compute shader
	var shader_path = "res://Scripts/Shaders/compute_fbm.glsl"
	var shader_file = load(shader_path)
	
	if shader_file.get_class() != "RDShaderFile":
		push_error(shader_path + " shader file was imported as text file. This means the shader had an error and could not be compiled at startup. You need to fix the shader and open it in the shader editor window or the error won't go away")

	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	var fbm_compute_shader = compute_rd.shader_create_from_spirv(shader_spirv)
	
	ComputeUtils.ComputeFbmMap(rd, fbm_render_rdtex, compute_rd, fbm_compute_shader, fbm_compute_rdtex, fbm_texture_width, p_uniform_compute_buffer, use_imported_fbm, import_fbm)

func compute_heightmap(buffer : Array):
	# heightmap compute shader
	var shader_path = "res://Scripts/Shaders/compute_heightmap.glsl"
	var shader_file = load(shader_path)
	
	if shader_file.get_class() != "RDShaderFile":
		push_error(shader_path + " shader file was imported as text file. This means the shader had an error and could not be compiled at startup. You need to fix the shader and open it in the shader editor window or the error won't go away")

	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	var heightmap_compute_shader = compute_rd.shader_create_from_spirv(shader_spirv)
	
	ComputeUtils.ComputeHeightMap(compute_rd, heightmap_compute_shader, 
	fbm_compute_rdtex, fbm_texture_width, heightmap_compute_rdtex, fbm_texture_width, p_uniform_compute_buffer)

func _init():
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT

	# Gets whatever light source is in the scene, compositor effects are resources not nodes and so we need to do some jank stuff to get access to the node scene tree
	var tree := Engine.get_main_loop() as SceneTree
	var root : Node = tree.edited_scene_root if Engine.is_editor_hint() else tree.current_scene
	if root: light = root.get_node_or_null('DirectionalLight3D')
	

func rotate_light(light : DirectionalLight3D):
	if rotate_light_source:
		light.rotate_y(rotation_speed / 20)

# Compiles... the shader...?
func compile_shader(vertex_shader : String, fragment_shader : String) -> RID:
	var src := RDShaderSource.new()
	src.source_vertex = vertex_shader
	src.source_fragment = fragment_shader
	
	var shader_spirv : RDShaderSPIRV = rd.shader_compile_spirv_from_source(src)
	
	var err = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_VERTEX)
	if err: push_error(err)
	err = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_FRAGMENT)
	if err: push_error(err)
	
	var shader : RID = rd.shader_create_from_spirv(shader_spirv)
	
	return shader

func initialize_render(framebuffer_format : int):
	load_sharders_from_files()
	
	p_shader = compile_shader(source_vertex, source_fragment)
	p_wire_shader = compile_shader(source_vertex, source_wire_fragment)

	var vertex_buffer := PackedFloat32Array([])
	var half_length = (side_length - 1) / 2.0

	# Generate plane vertices on the xz plane
	for x in side_length:
		for z in side_length:
			var xz : Vector2 = Vector2(x - half_length, z - half_length) * mesh_scale

			var pos : Vector3 = Vector3(xz.x, 0, xz.y)

			# Vertex color is not used but left as a demonstration for adding more vertex attributes
			var color : Vector4 = Vector4(randf(), randf(), randf(), 1)

			# For some reason godot doesn't make it easy to append vectors to arrays
			for i in 3: vertex_buffer.push_back(pos[i])
			for i in 4: vertex_buffer.push_back(color[i])


	var vertex_count = vertex_buffer.size() / 7
	print("Vertex Count: " + str(vertex_count))

	# Dump vertex data, I would delete this but it's probably helpful definitely do not uncomment this if your mesh has more than a couple vertices
	# for i in vertex_count:
	#     var j = i * 7
	#     var pos = Vector3()

	#     pos.x = vertex_buffer[j]
	#     pos.y = vertex_buffer[j + 1]
	#     pos.z = vertex_buffer[j + 2]

	#     var color = Vector4()

	#     color.x = vertex_buffer[j + 3]
	#     color.y = vertex_buffer[j + 4]
	#     color.z = vertex_buffer[j + 5]
	#     color.w = vertex_buffer[j + 6]

	#     print("Vertex " + str(i) + " ---")
	#     print("Position: " + str(pos))
	#     print("Color: " + str(color))



	var index_buffer := PackedInt32Array([])
	var wire_index_buffer := PackedInt32Array([])

	# Appends vertex indices to the index buffer for triangle list and wireframe
	for row in range(0, side_length * side_length - side_length, side_length):
		for i in side_length - 1:
			var v = i + row # shift to row we're actively triangulating

			var v0 = v
			var v1 = v + side_length
			var v2 = v + side_length + 1
			var v3 = v + 1

			index_buffer.append_array([v0, v1, v3, v1, v2, v3])
			wire_index_buffer.append_array([v0, v1, v0, v3, v1, v3, v1, v2, v2, v3])

	print("Triangle Count: " + str(index_buffer.size() / 3))

	
	var vertex_buffer_bytes : PackedByteArray = vertex_buffer.to_byte_array()
	p_vertex_buffer = rd.vertex_buffer_create(vertex_buffer_bytes.size(), vertex_buffer_bytes)
	
	var vertex_buffers := [p_vertex_buffer, p_vertex_buffer]
	
	var sizeof_float := 4
	var stride := 7
	
	# The GPU needs to know the memory layout of the vertex data, in this case each vertex has a position (3 component vector) and a color (4 component vector)
	var vertex_attrs = [RDVertexAttribute.new(), RDVertexAttribute.new()]
	vertex_attrs[0].format = rd.DATA_FORMAT_R32G32B32_SFLOAT
	vertex_attrs[0].location = 0
	vertex_attrs[0].offset = 0
	vertex_attrs[0].stride = stride * sizeof_float

	vertex_attrs[1].format = rd.DATA_FORMAT_R32G32B32A32_SFLOAT
	vertex_attrs[1].location = 1
	vertex_attrs[1].offset = 3 * sizeof_float
	vertex_attrs[1].stride = stride * sizeof_float

	vertex_format = rd.vertex_format_create(vertex_attrs)


	p_vertex_array = rd.vertex_array_create(vertex_buffer.size() / stride, vertex_format, vertex_buffers)

	var index_buffer_bytes : PackedByteArray = index_buffer.to_byte_array()
	p_index_buffer = rd.index_buffer_create(index_buffer.size(), rd.INDEX_BUFFER_FORMAT_UINT32, index_buffer_bytes)
	
	var wire_index_buffer_bytes : PackedByteArray = wire_index_buffer.to_byte_array()
	p_wire_index_buffer = rd.index_buffer_create(wire_index_buffer.size(), rd.INDEX_BUFFER_FORMAT_UINT32, wire_index_buffer_bytes)

	p_index_array = rd.index_array_create(p_index_buffer, 0, index_buffer.size())
	p_wire_index_array = rd.index_array_create(p_wire_index_buffer, 0, wire_index_buffer.size())
	

	initialize_render_pipelines(framebuffer_format)

# Initialization of the render pipeline objects is separated from the above code so that we don't have to regenerate everything when the framebuffer format changes
# otherwise the game would freeze to regenerate the entire terrain every time the window size changes by 1 pixel
# ideally shader recompilation is separated from the above function too, and generation of the vertex and index buffers also should be separated since that is what causes the stall
func initialize_render_pipelines(framebuffer_format : int) -> void:
	# The rest of this is setting up the render pipeline object, you can read the godot docs to see different settings here but they are largely irrelevant to this project
	var raster_state = RDPipelineRasterizationState.new()
	
	raster_state.cull_mode = RenderingDevice.POLYGON_CULL_BACK
	
	var depth_state = RDPipelineDepthStencilState.new()
	
	depth_state.enable_depth_write = true
	depth_state.enable_depth_test = true
	depth_state.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER
	
	var blend = RDPipelineColorBlendState.new()
	
	blend.attachments.push_back(RDPipelineColorBlendStateAttachment.new())

	p_render_pipeline = rd.render_pipeline_create(p_shader, framebuffer_format, vertex_format, rd.RENDER_PRIMITIVE_TRIANGLES, raster_state, RDPipelineMultisampleState.new(), depth_state, blend)
	p_wire_render_pipeline = rd.render_pipeline_create(p_wire_shader, framebuffer_format, vertex_format, rd.RENDER_PRIMITIVE_LINES, raster_state, RDPipelineMultisampleState.new(), depth_state, blend)



func _render_callback(_effect_callback_type : int, render_data : RenderData):
	if not enabled: return
	if _effect_callback_type != effect_callback_type: return
	
	if rd == null:
		init_gpu()
	
	var render_scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var render_scene_data : RenderSceneData = render_data.get_render_scene_data()
	
	if not render_scene_buffers: return

	if regenerate or not p_render_pipeline.is_valid():
		_notification(NOTIFICATION_PREDELETE)
		p_framebuffer = FramebufferCacheRD.get_cache_multipass([render_scene_buffers.get_color_texture(), render_scene_buffers.get_depth_texture()], [], 1)
		initialize_render(rd.framebuffer_get_format(p_framebuffer))
		regenerate = false

	var current_framebuffer = FramebufferCacheRD.get_cache_multipass([render_scene_buffers.get_color_texture(), render_scene_buffers.get_depth_texture()], [], 1)

	# If the framebuffer has changed then we need to reinitialize the render pipeline objects, this happens when the editor window changes or the game window changes
	if p_framebuffer != current_framebuffer:
		p_framebuffer = current_framebuffer
		initialize_render_pipelines(rd.framebuffer_get_format(p_framebuffer))

	var buffer = Array()

	# Assemble the model, view, and projection matrices for vertex world space -> clip space conversion (watch PS1 video if you care about how this works but otherwise it just works(tm))
	var model = transform
	var view = render_scene_data.get_cam_transform().inverse()
	var projection = render_scene_data.get_view_projection(0)

	var model_view = Projection(view * model)
	var MVP = projection * model_view;
	
	# Store MVP matrix in gpu data buffer
	for i in range(0,16):
		buffer.push_back(MVP[i / 4][i % 4])

	# Default light direction if no light source is found
	var light_direction = Vector3(0, 1, 0)

	# Attempt to find a light source if no light source was found earlier
	if not light:
		var tree := Engine.get_main_loop() as SceneTree
		var root : Node = tree.edited_scene_root if Engine.is_editor_hint() else tree.current_scene
		light = root.get_node_or_null('DirectionalLight3D')
		if not light:
			push_error("No light source detected please put a DirectionalLight3D into the scene thank you")
	else:
		light_direction = light.transform.basis.z.normalized()

	# Store all shader uniforms in a gpu data buffer, this isn't exactly the optimal data layout, each 1.0 push back is wasted space
	buffer.push_back(light_direction.x)
	buffer.push_back(light_direction.y)
	buffer.push_back(light_direction.z)
	buffer.push_back(gradient_rotation)
	buffer.push_back(rotation)
	buffer.push_back(height_scale)
	buffer.push_back(angular_variance.x)
	buffer.push_back(angular_variance.y)
	buffer.push_back(zoom)
	buffer.push_back(octave_count)
	buffer.push_back(amplitude_decay)
	buffer.push_back(1.0)
	buffer.push_back(offset.x)
	buffer.push_back(offset.y)
	buffer.push_back(offset.z)
	buffer.push_back(noise_seed)
	buffer.push_back(initial_amplitude)
	buffer.push_back(lacunarity)
	buffer.push_back(slope_threshold.x)
	buffer.push_back(slope_threshold.y)
	buffer.push_back(low_slope_color.r)
	buffer.push_back(low_slope_color.g)
	buffer.push_back(low_slope_color.b)
	buffer.push_back(1.0)
	buffer.push_back(low_slope_texture_ST.x)
	buffer.push_back(low_slope_texture_ST.y)
	buffer.push_back(low_slope_texture_ST.z)
	buffer.push_back(low_slope_texture_ST.w)
	buffer.push_back(high_slope_color.r)
	buffer.push_back(high_slope_color.g)
	buffer.push_back(high_slope_color.b)
	buffer.push_back(1.0)
	buffer.push_back(high_slope_texture_ST.x)
	buffer.push_back(high_slope_texture_ST.y)
	buffer.push_back(high_slope_texture_ST.z)
	buffer.push_back(high_slope_texture_ST.w)
	buffer.push_back(frequency_variance.x)
	buffer.push_back(frequency_variance.y)
	buffer.push_back(slope_damping)
	buffer.push_back(1.0)
	buffer.push_back(ambient_light.r)
	buffer.push_back(ambient_light.g)
	buffer.push_back(ambient_light.b)
	buffer.push_back(1.0)
	buffer.push_back(vertex_use_fbm)
	buffer.push_back(fragment_use_fbm)
	buffer.push_back(side_length * mesh_scale) # num of vertices * distance between each = mesh size
	buffer.push_back(shadow_strength)
	buffer.push_back(soft_shadows)
	buffer.push_back(shadow_adaptive_step_size_coeff)
	buffer.push_back(fragment_shadows)
	buffer.push_back(shadow_propagation)

	var values_affecting_geometry : Array = [gradient_rotation, rotation, height_scale, angular_variance, zoom, octave_count, amplitude_decay, noise_seed, initial_amplitude, frequency_variance, side_length * mesh_scale]
	var values_affecting_lighting : Array = [light_direction, shadow_propagation, shadow_adaptive_step_size_coeff]
	var geometry_hash = values_affecting_geometry.hash()
	var lighting_hash = values_affecting_lighting.hash()
	
	geometry_changed = geometry_buffer_hash != geometry_hash
	geometry_buffer_hash = geometry_hash
	lighting_changed = lighting_buffer_hash != lighting_hash || geometry_changed
	lighting_buffer_hash = lighting_hash

	
	# All of our settings are stored in a single uniform buffer, certainly not the best decision, but it's easy to work with
	var buffer_bytes : PackedByteArray = PackedFloat32Array(buffer).to_byte_array()
	if !p_uniform_buffer.is_valid():
		p_uniform_buffer = rd.uniform_buffer_create(buffer_bytes.size(), buffer_bytes)
	else:
		rd.buffer_update(p_uniform_buffer, 0, buffer_bytes.size(), buffer_bytes)
	
	if !p_uniform_compute_buffer.is_valid():
		p_uniform_compute_buffer = compute_rd.uniform_buffer_create(buffer_bytes.size(), buffer_bytes)
	else:
		compute_rd.buffer_update(p_uniform_compute_buffer, 0, buffer_bytes.size(), buffer_bytes)
	
	var uniforms = []
	var uniform := RDUniform.new()
	
	# The gpu needs to know the layout of the uniform variables, even though we have many variables here on the cpu, they're all in one uniform buffer, and so there is technically only one shader uniform
	uniform.binding = 0
	uniform.uniform_type = rd.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.add_id(p_uniform_buffer)
	uniforms.push_back(uniform)
	
	# Texturing
	if not low_slope_texture or not high_slope_texture:
		push_error("Unassigned textures")
		return
	
	# Sampler object for both textures
	var slope_tex_sampler_state := RDSamplerState.new()
	slope_tex_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	slope_tex_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	var slope_tex_sampler = rd.sampler_create(slope_tex_sampler_state)
	
	# Binding the textures created on the gpu in init_gpu() to the shader
	var low_slope_tex_uniform := RDUniform.new()
	low_slope_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	low_slope_tex_uniform.binding = 1
	low_slope_tex_uniform.add_id(slope_tex_sampler)
	low_slope_tex_uniform.add_id(low_slope_rdtex)
	uniforms.push_back(low_slope_tex_uniform)
	
	var high_slope_tex_uniform := RDUniform.new()
	high_slope_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	high_slope_tex_uniform.binding = 2
	high_slope_tex_uniform.add_id(slope_tex_sampler)
	high_slope_tex_uniform.add_id(high_slope_rdtex)
	uniforms.push_back(high_slope_tex_uniform)
	
	# Updating texture data when a change is made in the editor
	if low_slope_texture_copied_to_gpu != low_slope_texture.get_rid() and low_slope_rdtex.is_valid():
		var image = low_slope_texture.get_image()
		image.convert(Image.FORMAT_RGBA8)
		rd.texture_update(low_slope_rdtex, 0, image.get_data())
		low_slope_texture_copied_to_gpu = low_slope_texture.get_rid()
		
	if high_slope_texture_copied_to_gpu != high_slope_texture.get_rid() and high_slope_rdtex.is_valid():
		var image = high_slope_texture.get_image()
		image.convert(Image.FORMAT_RGBA8)
		rd.texture_update(high_slope_rdtex, 0, image.get_data())
		high_slope_texture_copied_to_gpu = high_slope_texture.get_rid()
	
	# Fbm
	var fbm_sampler_state := RDSamplerState.new()
	fbm_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	fbm_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	fbm_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	var fbm_sampler = rd.sampler_create(fbm_sampler_state)
	
	var fbm_uniform := RDUniform.new()
	fbm_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	fbm_uniform.binding = 3
	fbm_uniform.add_id(fbm_sampler)
	fbm_uniform.add_id(fbm_render_rdtex)
	uniforms.push_back(fbm_uniform)
	
	# Heightmap
	var heightmap_uniform := RDUniform.new()
	heightmap_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	heightmap_uniform.binding = 4
	heightmap_uniform.add_id(fbm_sampler)
	heightmap_uniform.add_id(heightmap_render_rdtex)
	uniforms.push_back(heightmap_uniform)
	
	# Currently we just free the previously instantiated uniform set and then make a new one, ideally this is only done when the uniform variables change
	if p_render_pipeline_uniform_set.is_valid():
		rd.free_rid(p_render_pipeline_uniform_set)
	
	p_render_pipeline_uniform_set = rd.uniform_set_create(uniforms, p_shader, 0)

	# If you frame capture the program with something like NVIDIA NSight you will see this label show up so you can easily see the render time of the terrain
	rd.draw_command_begin_label("Terrain Mesh", Color(1.0, 1.0, 1.0, 1.0))

	# The rest of this code is the creation of the draw call command list whether we are doing wireframe mode or not
	var draw_list = rd.draw_list_begin(p_framebuffer, rd.DRAW_IGNORE_ALL, clear_colors, 1.0,  0,  Rect2(), 0)

	if wireframe:
		rd.draw_list_bind_render_pipeline(draw_list, p_wire_render_pipeline)
	else:
		rd.draw_list_bind_render_pipeline(draw_list, p_render_pipeline)
		
	rd.draw_list_bind_vertex_array(draw_list, p_vertex_array)

	if wireframe:
		rd.draw_list_bind_index_array(draw_list, p_wire_index_array)
	else:
		rd.draw_list_bind_index_array(draw_list, p_index_array)

	rd.draw_list_bind_uniform_set(draw_list, p_render_pipeline_uniform_set, 0)
	rd.draw_list_draw(draw_list, true, 1)
	rd.draw_list_end()

	rd.draw_command_end_label()
	
	rotate_light(light)
	light.position = side_length * mesh_scale * light_direction
	light.position.y = -light.position.y
	
	if fragment_shadows: # cannot have both enabled
		shadow_propagation = false
	
	if geometry_changed:
		compute_fbm(buffer)
		
	if lighting_changed || shadow_propagation && !fragment_shadows:
		compute_heightmap(buffer)
	
	# Saving the fbm
	if save_fbm:
		save_fbm = false
		var output_bytes = rd.texture_get_data(fbm_render_rdtex, 0) # even though we have an alias for the local rendering device we can only get back data from the 'main' declaration
		var fbm_image = Image.create_from_data(fbm_texture_width, fbm_texture_width, false, Image.FORMAT_RGBAH, output_bytes)
		fbm_image.save_png("res://" + fbm_file_name + ".png")
		
	# Saving the heightmap
	if save_heightmap:
		save_heightmap = false
		var output_bytes = rd.texture_get_data(heightmap_render_rdtex, 0) # even though we have an alias for the local rendering device we can only get back data from the 'main' declaration
		var heightmap_image = Image.create_from_data(fbm_texture_width, fbm_texture_width, false, Image.FORMAT_RGBAH, output_bytes)
		heightmap_image.save_png("res://heightmap.png")


func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if p_render_pipeline.is_valid():
			rd.free_rid(p_render_pipeline)
		if p_wire_render_pipeline.is_valid():
			rd.free_rid(p_wire_render_pipeline)
		if p_vertex_array.is_valid():
			rd.free_rid(p_vertex_array)
		if p_vertex_buffer.is_valid():
			rd.free_rid(p_vertex_buffer)
		if p_index_array.is_valid():
			rd.free_rid(p_index_array)
		if p_index_buffer.is_valid():
			rd.free_rid(p_index_buffer)
		if p_wire_index_array.is_valid():
			rd.free_rid(p_wire_index_array)
		if p_wire_index_buffer.is_valid():
			rd.free_rid(p_wire_index_buffer)

var source_vertex : String
var source_fragment : String
var source_wire_fragment : String # I am not going to explain the wireframe shader it's pretty straight forward okay thanks

func load_sharders_from_files():
	source_vertex = ShaderUtils.LoadWithIncludes("res://Scripts/Shaders/vertex.gdshaderinc")
	source_fragment = ShaderUtils.LoadWithIncludes("res://Scripts/Shaders/fragment.gdshaderinc")
	source_wire_fragment = ShaderUtils.LoadWithIncludes("res://Scripts/Shaders/wire_fragment.gdshaderinc")
