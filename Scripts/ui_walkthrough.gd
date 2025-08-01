extends Node

var camera : Camera3D
var terrain : WorldEnvironment
var terrain_script : CompositorEffect

var step_counter_label : RichTextLabel
var fps_counter_label : RichTextLabel
var tex_rect : TextureRect
var display_shadowmap : bool = false

var title : RichTextLabel
var description : RichTextLabel

var step_specifics_container : VBoxContainer

var previous : Button
var next : Button

var current_step : int = 1
var previous_step : int = 0
var on_enter_step_functions = [
	_step_1, 
	_step_2, 
	_step_3, 
	_step_4, 
	_step_5, 
	_step_6, 
	_step_7, 
	_step_8, 
	_step_9, 
	_step_10, 
	_step_11, 
	_step_12,
	_step_13]
	
enum ShadowTechnique {
	Fragment_Raymarching,
	Shadowmap_Raymarching,
	Shadowmap_Cumulative_Raymarching,
	Shadowmap_Propagation,
	Rotated_Shadowmap_Propagation
}

func _ready():
	var tree := Engine.get_main_loop() as SceneTree
	var root : Node = tree.edited_scene_root if Engine.is_editor_hint() else tree.current_scene
	if root: 
		camera = root.get_node_or_null('Camera3D')
		terrain = root.get_node_or_null('WorldEnvironment')
	
	terrain_script = terrain.compositor.compositor_effects[0]
	
	step_counter_label = get_node("%Step")
	fps_counter_label = get_node("%FPS")
	
	title = get_node("%Title")
	description = get_node("%Description")
	
	step_specifics_container = get_node("%StepSpecificsContainer")
	
	previous = get_node("%Previous")
	next = get_node("%Next")
	
	previous.pressed.connect(_previous)
	next.pressed.connect(_next)

func _process(delta):
	if fps_counter_label:
		fps_counter_label.text = "FPS : %d" % Engine.get_frames_per_second()
		
	if not terrain_script.light: # waiting for setup
		return
		
	if (current_step != previous_step):
		_on_step_changed()
		previous_step = current_step
		
	if display_shadowmap && terrain_script.lighting_changed:
		terrain_script.shadowmap_texture_gpu_readback()
		tex_rect.texture = ImageTexture.create_from_image(terrain_script.shadowmap_image)
	
func _previous():
	current_step = max(1, current_step -1)
	
func _next():
	current_step = min(current_step + 1, on_enter_step_functions.size())

func _on_step_changed():
	if step_counter_label:
		step_counter_label.text = "Step %d / %d" % [current_step, on_enter_step_functions.size()]
		
	for child in step_specifics_container.get_children():
		step_specifics_container.remove_child(child)
		child.queue_free()
		
	if (on_enter_step_functions.size() >= current_step):
		on_enter_step_functions[current_step - 1].call()
	
func _step_1():
	title.text = "Welcome"
	description.text = "This UI is for you to play with the parameters of the stuff implemented. You can stick to this page to experiment on your own, or move to the next steps for a guided walkthrough.
	
If you use fragment ray marching along with fbm texture sampling in the fragment shader, the texture will also be sampled for the raymarching (not just for terrain height / normals info), and will produce artifacts."
	
	# Lighting
	terrain_script.rotate_light_source = false
	
	# Normals
	terrain_script.use_original_normals = false
	
	# Texturing
	terrain_script.enable_texturing = true
	
	# Precomputed fbm texture
	terrain_script.vertex_use_fbm = true
	terrain_script.fragment_use_fbm = true
	terrain_script.fragment_enhance_with_noise = true
	
	# Shadows
	terrain_script.cast_shadows = true
	terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Raymarching
	terrain_script.binary_shadows = false
	terrain_script.stop_on_hit = false
	terrain_script.steps_heatmap = false
	
	_roll_terrain_relief()
	_roll_terrain_slopes()
	_roll_terrain_colors()
	
	_terrain_specifics()
	
	_light_specifics()
	
	var toggle_r = create_named_toggle("Rotate light", terrain_script.rotate_light_source, func(value:bool): terrain_script.rotate_light_source = value)
	step_specifics_container.add_child(toggle_r)
	
	var label_n := Label.new()
	label_n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_n.text = "\nNormals"
	step_specifics_container.add_child(label_n)
	var toggle_n = create_named_toggle("Use fixed normals", !terrain_script.use_original_normals, func(value :bool): terrain_script.use_original_normals = !value)
	step_specifics_container.add_child(toggle_n)
	
	var label_t := Label.new()
	label_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_t.text = "\nTexturing"
	step_specifics_container.add_child(label_t)
	var toggle_t = create_named_toggle("Enable texturing", terrain_script.enable_texturing, func(value:bool): terrain_script.enable_texturing = value)
	step_specifics_container.add_child(toggle_t)
	
	var slider_low_x = create_named_slider("Low slope texture scale x", 1, 10, 2, "", func(value:float): terrain_script.low_slope_texture_ST.x = value)
	var slider_low_y = create_named_slider("Low slope texture scale y", 1, 10, 2, "", func(value:float): terrain_script.low_slope_texture_ST.y = value)
	var slider_high_x = create_named_slider("High slope texture scale x", 1, 10, 2, "", func(value:float): terrain_script.high_slope_texture_ST.x = value)
	var slider_high_y = create_named_slider("High slope texture scale y", 1, 10, 2, "", func(value:float): terrain_script.high_slope_texture_ST.y = value)
	step_specifics_container.add_child(slider_low_x)
	step_specifics_container.add_child(slider_low_y)
	step_specifics_container.add_child(slider_high_x)
	step_specifics_container.add_child(slider_high_y)
	
	var label_f := Label.new()
	label_f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_f.text = "\nPrecomputed fbm texture"
	step_specifics_container.add_child(label_f)
	
	var toggle_v = create_named_toggle("Use fbm texture in vertex shader", terrain_script.vertex_use_fbm, func(value:bool): terrain_script.vertex_use_fbm = value)
	step_specifics_container.add_child(toggle_v)
	var toggle_f = create_named_toggle("Use fbm texture in fragment shader", terrain_script.fragment_use_fbm, func(value:bool): terrain_script.fragment_use_fbm = value)
	step_specifics_container.add_child(toggle_f)
	var toggle_e = create_named_toggle("Enhance fragment fbm sampling with noise", terrain_script.fragment_enhance_with_noise, func(value:bool): terrain_script.fragment_enhance_with_noise = value)
	step_specifics_container.add_child(toggle_e)
	
	var label_s := Label.new()
	label_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_s.text = "\nCast shadows"
	step_specifics_container.add_child(label_s)
	
	var toggle_c = create_named_toggle("Enable cast shadows", terrain_script.cast_shadows, func(value:bool): terrain_script.cast_shadows = value)
	step_specifics_container.add_child(toggle_c)
	
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = "Current technique : Shadowmap_Propagation"
	step_specifics_container.add_child(label)
	
	var toggle_fragment = create_named_button("Fragment shader raymarching", func(): 
		terrain_script.shadow_technique = ShadowTechnique.Fragment_Raymarching
		label.text = "Current technique : Fragment_Raymarching")
	step_specifics_container.add_child(toggle_fragment)
	
	var toggle_regular = create_named_button("Shadowmap raymarching", func(): 
		terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Raymarching
		label.text = "Current technique : Shadowmap_Raymarching")
	step_specifics_container.add_child(toggle_regular)
	
	var toggle_cumulative = create_named_button("Shadowmap cumulative raymarching", func(): 
		terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Cumulative_Raymarching
		label.text = "Current technique : Shadowmap_Cumulative_Raymarching")
	step_specifics_container.add_child(toggle_cumulative)
	
	var toggle_p = create_named_button("Shadow propagation", func(): 
		terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Propagation
		label.text = "Current technique : Shadowmap_Propagation")
	step_specifics_container.add_child(toggle_p)
	
	var toggle_rp = create_named_button("Rotated shadowmap propagation", func(): 
		terrain_script.shadow_technique = ShadowTechnique.Rotated_Shadowmap_Propagation
		label.text = "Current technique : Rotated_Shadowmap_Propagation")
	step_specifics_container.add_child(toggle_rp)
	
	var binary_toggle = create_named_toggle("Binary shadows", terrain_script.binary_shadows, func(value:bool): terrain_script.binary_shadows = value)
	step_specifics_container.add_child(binary_toggle)
	
	var slider_soft_shadows = create_named_slider("Soft shadows", 0, 1, terrain_script.soft_shadows, "", func(value : float): terrain_script.soft_shadows = value)
	step_specifics_container.add_child(slider_soft_shadows)
	
	_raymarching_specifics()
	

func _step_2():
	title.text = "Starting point"
	description.text = "Setting the compositor effect parameters to the same values as in the original code to start from a familiar place.
Starting from step 5 be sure to check the FPS counter right above this text to see what is the impact on performance of the techniques used. VSync is disabled to free the FPS count."
	terrain_script.zoom = 139.5
	terrain_script.offset = Vector3(-200, 95.655, -326.08)
	terrain_script.gradient_rotation = 68.645
	terrain_script.octave_count = 12
	terrain_script.rotation = -26.99
	terrain_script.angular_variance = Vector2(-15, 15)
	terrain_script.initial_amplitude = 0.739
	terrain_script.amplitude_decay = 0.439
	terrain_script.lacunarity = 1.991
	terrain_script.frequency_variance = Vector2(-0.085, 0.115)
	terrain_script.height_scale = 90.9
	terrain_script.slope_damping = 0.155
	terrain_script.slope_threshold = Vector2(0.84, 0.98)
	terrain_script.low_slope_color = Color(0.366477, 0.373384, 0.0777902, 1)
	terrain_script.high_slope_color = Color(0.1, 0.05835, 0.049, 1)
	terrain_script.ambient_light = Color(0.192, 0.2712, 0.3, 1)
	
	terrain_script.use_original_normals = true
	terrain_script.enable_texturing = false
	terrain_script.vertex_use_fbm = false
	terrain_script.fragment_use_fbm = false
	terrain_script.fragment_enhance_with_noise = false
	terrain_script.cast_shadows = false
	terrain_script.rotate_light_source = false
	
func _step_3():
	title.text = "Fixing normals"
	description.text = "Replacing normal formula :
	vec3 normal = normalize(vec3(-n.y, 1, -n.z));
with :
	vec3 normal = normalize(vec3(-n.y, _Scale, -n.z));
to account for the fact that the coordonates at which the noise is sampled are scaled down by _Scale, thus this factor should also appear in the tangents, multiplying the perlin noise gradient, by use of the chain formula.
The difference is best seen at 90° vertical angle. You may want roll a new terrain to better see the lighting."
	
	var toggle = create_named_toggle("Use original normals", terrain_script.use_original_normals, func(value :bool): terrain_script.use_original_normals = value)
	step_specifics_container.add_child(toggle)
	
	_light_specifics()
	
	_terrain_specifics()
	
func _step_4():
	title.text = "Texturing"
	description.text = "Using triplanar texturing. The vertical (high slopes) texture is samples 2 times (in each vertical plane), the horizontal one (low slopes) just once. The blending coefficients favors the texture which direction is closest to the normal"
	
	terrain_script.enable_texturing = true
	
	var toggle = create_named_toggle("Enable texturing", terrain_script.enable_texturing, func(value:bool): terrain_script.enable_texturing = value)
	step_specifics_container.add_child(toggle)
	
	var slider_low_x = create_named_slider("Low slope texture scale x", 1, 10, 2, "", func(value:float): terrain_script.low_slope_texture_ST.x = value)
	var slider_low_y = create_named_slider("Low slope texture scale y", 1, 10, 2, "", func(value:float): terrain_script.low_slope_texture_ST.y = value)
	var slider_high_x = create_named_slider("High slope texture scale x", 1, 10, 2, "", func(value:float): terrain_script.high_slope_texture_ST.x = value)
	var slider_high_y = create_named_slider("High slope texture scale y", 1, 10, 2, "", func(value:float): terrain_script.high_slope_texture_ST.y = value)
	step_specifics_container.add_child(slider_low_x)
	step_specifics_container.add_child(slider_low_y)
	step_specifics_container.add_child(slider_high_x)
	step_specifics_container.add_child(slider_high_y)
	
func _step_5():
	title.text = "Precomputed fbm texture"
	description.text = "Evaluating the fbm is computationally expensive. To improve performance we can store the evaluated fbm values in a texture and sample it instead in the vertex and fragment shaders. 
The texture size is fixed to 512 * 512 while the terrain has 400 * 400 vertices. The texture format is R16G16B16A16_SFLOAT. Using a less detailed format would be producing visible height and surface artifacts.
Higher octaves noise details will be filtered out by the low pass filter that represents storing the data in a texture then sampling it back.
To compensate for this we can sample the texture multiple times with scaled up uvs, and apply it with decreasing amplitude, to mimic the fbm. When enabling fbm use in the fragment shader the texture is sampled 3 times.
This produces good results, giving a surface look that has a more 'rocky' aspect compared to the 'organic' aspect of perlin noise.
Yet if we want to keep the original look, it is best to re add some noise sampling (just 3 layers in this case, less than the original 12 octaves). This noise is computed using the perlin_noise2D fucntion but this as well could be stored in a different texture."
	
	var toggle_v = create_named_toggle("Use fbm texture in vertex shader", terrain_script.vertex_use_fbm, func(value:bool): terrain_script.vertex_use_fbm = value)
	step_specifics_container.add_child(toggle_v)
	
	var toggle_f = create_named_toggle("Use fbm texture in fragment shader", terrain_script.fragment_use_fbm, func(value:bool): terrain_script.fragment_use_fbm = value)
	step_specifics_container.add_child(toggle_f)
	
	var toggle_e = create_named_toggle("Enhance fragment fbm sampling with noise", terrain_script.fragment_enhance_with_noise, func(value:bool): terrain_script.fragment_enhance_with_noise = value)
	step_specifics_container.add_child(toggle_e)
	
func _step_6():
	title.text = "Cast shadows"
	description.text = "From now on, focus on cast shadows ! 

Starting with binary shadows computed in the fragment shader.
Binary shadows means each fragment is either in light or in shadow, and if it is in shadow it receives a color intensity decrease uniform across all terrain.
For such shadows, we can stop the ray marching on first hit. 
	
The small change when toggling to stop marching on hit comes from a little edge case in the shadow strength formula, not from the ray marching itself. For the sake of simplicity the same formula is used across all shadow methods."
	
	terrain_script.cast_shadows = true
	terrain_script.shadow_technique = ShadowTechnique.Fragment_Raymarching
	terrain_script.vertex_use_fbm = true
	terrain_script.fragment_use_fbm = true
	terrain_script.fragment_enhance_with_noise = true
	terrain_script.binary_shadows = true
	terrain_script.stop_on_hit = true
	terrain_script.soft_shadows = 0
	terrain_script.steps_heatmap = false
	
	var toggle_c = create_named_toggle("Enable cast shadows", terrain_script.cast_shadows, func(value:bool): terrain_script.cast_shadows = value)
	step_specifics_container.add_child(toggle_c)
	
	var toggle_f = create_named_toggle("Use fbm texture in fragment shader", terrain_script.fragment_use_fbm, func(value:bool): terrain_script.fragment_use_fbm = value)
	step_specifics_container.add_child(toggle_f)
	
	_raymarching_specifics()
	_light_specifics()
	
func _step_7():
	title.text = "Depth shadows"
	description.text = "Depth shadows means each fragment now has a continuous shadow depth value which translates to if you were standing there, how far above your head the closest unblocked ray light would pass.
This value serves two purposes. The first one is applying a stronger shadow the deeper the shadow depth is, giving a more realistic look. The second is identifying the shadow / light frontier, which is where the shadow depth is close to 0, thus being able to modulate between hard and soft shadows.

The counterpart of the improved visuals is that the ray marching cannot be stopped on hit as some terrain causing a greater shadow depth may be found later along the ray direction. Actually most of the time the first terrain hit is found in the immediate neighbourhood of the fragment and not the tall blocking mountains. For the shadow depth information to be accurate the rays will have to climb along the terrain surface, greatly reducing the benefits of the adaptive stepping as the rays will be consistently close to the ground."

	terrain_script.binary_shadows = false
	terrain_script.stop_on_hit = false
	terrain_script.fragment_use_fbm = true
	
	var slider_soft_shadows = create_named_slider("Soft shadows", 0, 1, terrain_script.soft_shadows, "", func(value : float): terrain_script.soft_shadows = value)
	step_specifics_container.add_child(slider_soft_shadows)

	_raymarching_specifics()
	_light_specifics()

func _step_8():
	title.text = "Shadow map"
	description.text = "As for the precomputed fbm texture, the shadow (binary or depth) information can be stored in a texture, and sampled in the fragment shader.
This texture will have to be updated each time the terrain or lighting changes. Shadowmap raymarching marches from each texel towards the light.

When toggling light rotation, the rotation occurs every physics frame (at 60 fps)."

	terrain_script.fragment_shadows = false
	terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Raymarching
	terrain_script.cumulative_shadows = false
	terrain_script.rotate_shadowmap_towards_light = false
	terrain_script.steps_heatmap = false
	terrain_script.shadow_propagation = false
	terrain_script.rotate_light_source = true
	
	var toggle = create_named_toggle("Rotate light", terrain_script.rotate_light_source, func(value:bool): terrain_script.rotate_light_source = value)
	step_specifics_container.add_child(toggle)
	
	var toggle_shadowmap = create_named_toggle("Shadowmap raymarching", !terrain_script.fragment_shadows, func(value:bool): 
		terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Raymarching if value else ShadowTechnique.Fragment_Raymarching)
	step_specifics_container.add_child(toggle_shadowmap)
	
func _step_9():
	title.text = "Cumulative raymarching"
	description.text = "Cumulative raymarching means executing raymarching each frame with a fraction of the maximum steps.
This allows to remove the max step limit without tanking performances. Using the number of steps heatmap shows that the cumulative approach takes way less steps to find the highesh shadow depth because each new raymarching reuses the existing shadowmap information to take bigger steps.
Yet this approach is still not efficient as there is no gpu readback to tell when we don't need to re schedule raymarching anymore, and when the light changes the techniques takes too many frames to accumulate the shadow depth data, producing visible flickering or shadow propagation.
This technique could be viable if we could condense it in a single frame which we will see later."
	
	terrain_script.rotate_light_source = false
	terrain_script.max_step_count = 10
	terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Cumulative_Raymarching
	
	var toggle = create_named_toggle("Rotate light", terrain_script.rotate_light_source, func(value:bool): terrain_script.rotate_light_source = value)
	step_specifics_container.add_child(toggle)
	
	var toggle_cumulative = create_named_toggle("Cumulative raymarching", terrain_script.shadow_technique == ShadowTechnique.Shadowmap_Cumulative_Raymarching, func(value:bool): terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Cumulative_Raymarching if value else ShadowTechnique.Shadowmap_Raymarching)
	step_specifics_container.add_child(toggle_cumulative)
	
	var slider = create_named_slider("Max steps", 0, 100, terrain_script.max_step_count, "", func(value : float): terrain_script.max_step_count = int(value))
	step_specifics_container.add_child(slider)
	
	var slider_f = create_named_slider("Max steps fraction", 0, 1, terrain_script.cumulative_steps_ratio, "", func(value : float): terrain_script.cumulative_steps_ratio = value)
	step_specifics_container.add_child(slider_f)
	
	var heatmap_toggle = create_named_toggle("Raymarching number of steps heatmap", terrain_script.steps_heatmap, func(value:bool): terrain_script.steps_heatmap = value)
	step_specifics_container.add_child(heatmap_toggle)
	
func _step_10():
	title.text = "Shadow propagation"
	description.text = "Before coding raymarching which I had never done before I wanted a simpler method. I came up with shadow propagation, which seemed promising in my mind but with no mention of it online I suspected it was bad, but still wanted to try.
	Shadow propagation consists in looping a number of time over each texel of the shadowmap. Each loop, the shadow height of the current texel becomes the maximum between the terrain height at that texel obtained by sampling the fbm texture at the same uv, and the interpolated shadow height of the neighbor shadowmap texel towards the light.
	Enabling shadow propagation schedules a shader that does this once per frame."
	
	terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Propagation
	display_shadowmap = false
	
	var toggle = create_named_toggle("Rotate light", terrain_script.rotate_light_source, func(value:bool): terrain_script.rotate_light_source = value)
	step_specifics_container.add_child(toggle)
	
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = "Current technique : Shadowmap_Propagation"
	step_specifics_container.add_child(label)
	
	var toggle_p = create_named_button("Shadow propagation", func(): 
		terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Propagation
		label.text = "Current technique : Shadowmap_Propagation")
	step_specifics_container.add_child(toggle_p)
	
	var toggle_cumulative = create_named_button("Shadowmap cumulative raymarching", func(): 
		terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Cumulative_Raymarching
		label.text = "Current technique : Shadowmap_Cumulative_Raymarching")
	step_specifics_container.add_child(toggle_cumulative)
	
	var toggle_regular = create_named_button("Shadowmap raymarching", func(): 
		terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Raymarching
		label.text = "Current technique : Shadowmap_Raymarching")
	step_specifics_container.add_child(toggle_regular)
	
	var heatmap_toggle = create_named_toggle("Raymarching number of steps heatmap", terrain_script.steps_heatmap, func(value:bool): terrain_script.steps_heatmap = value)
	step_specifics_container.add_child(heatmap_toggle)
	
	
func _step_11():
	title.text = "Rotated shadow propagation"
	description.text = "As we have seen, cumulative ray marching and shadowmap propagation are the worst techniques, mainly because they span over multiple frames.
Spanning them over multiple frames is essentially motivated by the fact that if we do multiple steps in a single frame we will have texture read / write concurrent access, producing shadow artifacts.
We can only synchronize the access inside thread groups, but as the light direction may take any direction in the xz plane there is no way of defining exclusive thread groups alignes with the light direction, unless we rotate the shadow map towards the light.

The current method used is the shadowmap ray marching technique. It does not benefit nor is degraded by the rotation.
The combination of shadowmap raymarching and rotation isn't relevant in term of rendering, but allows us to visualize the rotation which we will use later."

	terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Raymarching
	
	_light_specifics()

	var toggle = create_named_toggle("Rotate shadowmap towards light", terrain_script.rotate_shadowmap_towards_light, func(value:bool): terrain_script.rotate_shadowmap_towards_light = value)
	step_specifics_container.add_child(toggle)
	
	_shadowmap_container()
	
func _step_12():
	title.text = "Rotated shadowmap propagation"
	description.text = "Now we are going to actually make use of that rotation. We can see that the texture y axis is aligned with the light direction. 
	Each ray comes from the top row and goes along a single column. Which means that we can schedule thread groups that span over an etiere column and sync their read and writes, allowing us to perform in a single frame what we were doing over multiple ones previously.
	The ray alignment with the texture y also trivializes the major part of formulas so that we can arrive to a version which is closest to the propagation technique than the raymarching technique. 
	Though in practice, the default propagation does not take bigger steps each loop while this technique does (like the cumulative raymarching technique).
	Yet these times the steps can be even more agressive thanks to the per-groups sync, doubling in size each loop, so that the maximum number of steps any texel may require is log2(texture height) = log2(512) = 9 in our case.
	Regular shadowmap propagation is scheduled each frame while rotated shadowmap completes in a single frame."
	
	terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Propagation
	terrain_script.rotate_shadowmap_towards_light = false
	terrain_script.max_step_count = 20
	
	_light_specifics()
	
	var toggle_l = create_named_toggle("Rotate light", terrain_script.rotate_light_source, func(value:bool): terrain_script.rotate_light_source = value)
	step_specifics_container.add_child(toggle_l)
	
	var toggle = create_named_toggle("Rotate shadowmap towards light", terrain_script.rotate_shadowmap_towards_light, func(value:bool): terrain_script.shadow_technique = ShadowTechnique.Rotated_Shadowmap_Propagation if value else ShadowTechnique.Shadowmap_Propagation)
	step_specifics_container.add_child(toggle)
	
	var heatmap_toggle = create_named_toggle("Raymarching number of steps heatmap", terrain_script.steps_heatmap, func(value:bool): terrain_script.steps_heatmap = value)
	step_specifics_container.add_child(heatmap_toggle)
	
	_shadowmap_container()
	
func _step_13():
	title.text = "And the winner is..."
	description.text = "Using the parameters available for this terrain, the shadowmap ray marching technique may require up to around 50 steps to compute accurate shadow depths.
The oriented shadowmap propagation techniques takes log2(shadowmap size) = 8 steps.
In these conditions, the oriented shadowmap propagation technique is the most performant. In mor favorable conditions for the raymarching technique, the oriented shadowmap propagation still performs comparably.

The oriented shadowmap propagation technique is thus the most efficient shadow casting technique.

Yet this technique is optimized for the current project and is probably less scalable and easy to integrate into another project than the fragment shader raymarching technique."
	
	display_shadowmap = false
	terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Raymarching
	
	_light_specifics()
	
	var toggle_l = create_named_toggle("Rotate light", terrain_script.rotate_light_source, func(value:bool): terrain_script.rotate_light_source = value)
	step_specifics_container.add_child(toggle_l)
	
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = "Current technique : Shadowmap_Raymarching"
	step_specifics_container.add_child(label)
	
	var toggle_p = create_named_button("Rotated shadowmap propagation", func(): 
		terrain_script.shadow_technique = ShadowTechnique.Rotated_Shadowmap_Propagation
		label.text = "Current technique : Rotated_Shadowmap_Propagation")
	step_specifics_container.add_child(toggle_p)
	
	var toggle_regular = create_named_button("Shadowmap raymarching", func(): 
		terrain_script.shadow_technique = ShadowTechnique.Shadowmap_Raymarching
		label.text = "Current technique : Shadowmap_Raymarching")
	step_specifics_container.add_child(toggle_regular)
	
	_raymarching_specifics()

func _light_specifics():
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = "\nLighting"
	step_specifics_container.add_child(label)
	
	var slider_h = create_named_slider("Horizontal rotation", -180, 180, rad_to_deg(terrain_script.light.rotation.y), "", func(value : float): terrain_script.light.rotation.y = deg_to_rad(value))
	step_specifics_container.add_child(slider_h)
	
	var slider_v = create_named_slider("Angle with Y axis", 0, 90, rad_to_deg(terrain_script.light.rotation.x) + 90, "", func(value : float): terrain_script.light.rotation.x = deg_to_rad(value - 90))
	step_specifics_container.add_child(slider_v)
	
func create_named_toggle(ui_name : String, initial_value : bool, on_toggle : Callable) -> CheckBox:
	var toggle := CheckBox.new()
	toggle.text = ui_name
	toggle.toggle_mode = true
	toggle.button_pressed = initial_value
	toggle.toggled.connect(func(value:bool):
		on_toggle.call(value))
		
	return toggle
	
func create_named_button(ui_name : String, on_toggle : Callable) -> Button:
	var toggle := Button.new()
	toggle.text = ui_name
	toggle.toggle_mode = false
	toggle.pressed.connect(func():
		on_toggle.call())
		
	return toggle
	
func create_named_slider(ui_name : String, smin : float, smax : float, initial_value : float, unit : String, on_value_change : Callable)-> HBoxContainer:
	var hbox := HBoxContainer.new()
	
	var label := Label.new()
	label.text = ui_name
	
	var lvalue := Label.new()
	
	var slider := HSlider.new()
	slider.min_value = smin
	slider.max_value = smax
	slider.step = (smax - smin) / 1000.0
	slider.value = initial_value
	
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float): 
		on_value_change.call(value) 
		lvalue.text = "%.2f %s" % [value, unit])
		
	lvalue.text = "%.2f %s" % [initial_value, unit]
	
	hbox.add_child(label)
	hbox.add_child(slider)
	hbox.add_child(lvalue)
	
	return hbox

func _raymarching_specifics():
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = "\nRaymarching parameters"
	step_specifics_container.add_child(label)
	
	var slider_shadow_strength = create_named_slider("Shadow stength", 0, 10, terrain_script.shadow_strength, "", func(value : float): terrain_script.shadow_strength = value)
	step_specifics_container.add_child(slider_shadow_strength)
	
	var stop_toggle = create_named_toggle("Stop raymarching on hit", terrain_script.stop_on_hit, func(value:bool): terrain_script.stop_on_hit = value)
	step_specifics_container.add_child(stop_toggle)
	
	var slider_max_steps = create_named_slider("Raymarching max steps", 0, 100, terrain_script.max_step_count, "", func(value : float): terrain_script.max_step_count = int(value))
	step_specifics_container.add_child(slider_max_steps)
	
	var slider_f = create_named_slider("Cumulative max steps fraction", 0, 1, terrain_script.cumulative_steps_ratio, "", func(value : float): terrain_script.cumulative_steps_ratio = value)
	step_specifics_container.add_child(slider_f)
	
	var slider_min_step_size = create_named_slider("Raymarching min step size", 0, 10, terrain_script.min_step_size, "", func(value : float): terrain_script.min_step_size = value)
	step_specifics_container.add_child(slider_min_step_size)
	
	var slider_adaptive_coeff = create_named_slider("Raymarching adaptive step size", 0, 10, terrain_script.adaptive_step_size_coeff, "", func(value : float): terrain_script.adaptive_step_size_coeff = value)
	step_specifics_container.add_child(slider_adaptive_coeff)
	
	var heatmap_toggle = create_named_toggle("Raymarching number of steps heatmap", terrain_script.steps_heatmap, func(value:bool): terrain_script.steps_heatmap = value)
	step_specifics_container.add_child(heatmap_toggle)

func _shadowmap_container():
	tex_rect = TextureRect.new()
	step_specifics_container.add_child(tex_rect)
	display_shadowmap = true
	terrain_script.lighting_changed = true
	
func _terrain_specifics():
	var label_e := Label.new()
	label_e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_e.text = "\nTerrain"
	step_specifics_container.add_child(label_e)
	
	var button_t = create_named_button("Roll terrain relief", func(): _roll_terrain_relief())
	step_specifics_container.add_child(button_t)
	
	var button_s = create_named_button("Roll terrain slopes", func(): _roll_terrain_slopes())
	step_specifics_container.add_child(button_s)
	
	var button_c = create_named_button("Roll terrain colors", func(): _roll_terrain_colors())
	step_specifics_container.add_child(button_c)
	
func _roll_terrain_relief():
	terrain_script.zoom = 120 + 30 * randf()
	terrain_script.offset = Vector3(-200 + 300 * randf(), 95.655, -326.08 + 300 * randf())
	terrain_script.gradient_rotation = 60 + 10 * randf()
	terrain_script.octave_count = 12
	terrain_script.rotation = -30 + 10 * randf()
	terrain_script.angular_variance = Vector2(-15, 15)
	terrain_script.initial_amplitude = 0.739
	terrain_script.amplitude_decay = 0.439
	terrain_script.lacunarity = 1.991
	terrain_script.frequency_variance = Vector2(-0.085, 0.115)
	terrain_script.height_scale = 50 + randf() * 50

func _roll_terrain_slopes():
	terrain_script.slope_damping = 0.12 + 0.3 * randf()
	terrain_script.slope_threshold.x = lerp(0.7, 1.0, randf())
	terrain_script.slope_threshold.y = lerp(terrain_script.slope_threshold.x, 1.0, randf())
	
	
func _roll_terrain_colors():
	terrain_script.low_slope_color = rand_color(Color.MEDIUM_SEA_GREEN, 0.2)
	terrain_script.high_slope_color = rand_color(Color(0.809404, 0.581583, 0.415475, 1), 0.1)
	terrain_script.ambient_light = rand_color(Color(0.192, 0.2712, 0.3, 1), 0.1)

func rand_color(center : Color, around : float) -> Color:
	return Color(clamp(center.r + around * (randf() - 1), 0, 1), clamp(center.g + around * (randf() - 1), 0, 1) , clamp(center.b + around * (randf() - 1), 0, 1), 1)
