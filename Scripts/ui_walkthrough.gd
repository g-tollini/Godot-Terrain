extends Node

var camera : Camera3D
var terrain : WorldEnvironment
var terrain_script : CompositorEffect

var step_counter_label : RichTextLabel
var fps_counter_label : RichTextLabel

var title : RichTextLabel
var description : RichTextLabel

var step_specifics_container : VBoxContainer

var previous : Button
var next : Button

var current_step : int = 1
var previous_step : int = 0
var last_step : int = 10
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
	_step_10]

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
		
	if (current_step != previous_step):
		_on_step_changed()
		previous_step = current_step
	
func _previous():
	current_step = max(1, current_step -1)
	
func _next():
	current_step = min(current_step + 1, last_step)

func _on_step_changed():
	if step_counter_label:
		step_counter_label.text = "Step %d / %d" % [current_step, last_step]
		
	for child in step_specifics_container.get_children():
		step_specifics_container.remove_child(child)
		child.queue_free()
		
	if (on_enter_step_functions.size() >= current_step):
		on_enter_step_functions[current_step - 1].call()
	
func _step_1():
	title.text = "Configuration"
	description.text = "Choose your settings"
	
func _step_2():
	title.text = "Starting point"
	description.text = "Setting the compositor effect parameters to the same values as in the original code to start from a familiar place"
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
	terrain_script.cast_shadows = false
	
func _step_3():
	title.text = "Fixing normals"
	description.text = "Replacing normal formula :
	vec3 normal = normalize(vec3(-n.y, 1, -n.z));
with :
	vec3 normal = normalize(vec3(-n.y, _Scale, -n.z));
to account for the fact that the coordonates at which the noise is sampled are scaled down by _Scale, thus this factor should also appear in the tangents, multiplying the perlin noise gradient, by use of the chain formula.
The difference is best seen at 90° vertical angle"
	
	var toggle := CheckBox.new()
	toggle.text = "Use original normals"
	toggle.toggle_mode = true
	toggle.button_pressed = terrain_script.use_original_normals
	toggle.toggled.connect(func(value:bool):
		terrain_script.use_original_normals = value)
	step_specifics_container.add_child(toggle)
	
	_light_specifics()
	
func _step_4():
	title.text = "Texturing"
	description.text = "Using triplanar texturing. The vertical (high slopes) texture is samples 2 times (in each vertical plane), the horizontal one (low slopes) just once. The blending coefficients favors the texture which direction is closest to the normal"
	
	terrain_script.enable_texturing = true
	
	var toggle := CheckBox.new()
	toggle.text = "Enable texturing"
	toggle.toggle_mode = true
	toggle.button_pressed = terrain_script.enable_texturing
	toggle.toggled.connect(func(value:bool):
		terrain_script.enable_texturing = value)
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
	title.text = "Shadow Jam"
	description.text = "Will we eventually see the light ?"
	
func _step_6():
	description.text = "Fixing normals"
	
func _step_7():
	description.text = "Fixing normals"
	
func _step_8():
	description.text = "Fixing normals"
	
func _step_9():
	description.text = "Fixing normals"
	
func _step_10():
	description.text = "Fixing normals"

func _light_specifics():
	var hbox_h := HBoxContainer.new()
	
	var label_h := Label.new()
	label_h.text = "Horizontal rotation"
	
	var value_h := Label.new()
	
	var slider_h := HSlider.new()
	slider_h.min_value = -180
	slider_h.max_value = 180
	slider_h.value = rad_to_deg(terrain_script.light.rotation.y)
	slider_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_h.value_changed.connect(func(value: float):
		terrain_script.light.rotation.y = deg_to_rad(value)
		value_h.text = "%d °" % value
	)
	
	value_h.text = "%d °" % slider_h.value
	
	hbox_h.add_child(label_h)
	hbox_h.add_child(slider_h)
	hbox_h.add_child(value_h)

	step_specifics_container.add_child(hbox_h)
	
	var hbox_v := HBoxContainer.new()
	
	var label_v := Label.new()
	label_v.text = "Vertical angle"
	
	var value_v := Label.new()
	
	var slider_v := HSlider.new()
	slider_v.min_value = 0
	slider_v.max_value = 180
	slider_v.value = -rad_to_deg(terrain_script.light.rotation.x)
	
	slider_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_v.value_changed.connect(func(value: float):
		terrain_script.light.rotation.x = -deg_to_rad(value)
		value_v.text = "%d °" % value
	)
	
	value_v.text = "%d °" % slider_v.value
	
	hbox_v.add_child(label_v)
	hbox_v.add_child(slider_v)
	hbox_v.add_child(value_v)

	step_specifics_container.add_child(hbox_v)
	
func create_named_slider(ui_name : String, smin : float, smax : float, initial_value : float, unit : String, on_value_change : Callable)-> HBoxContainer:
	var hbox := HBoxContainer.new()
	
	var label := Label.new()
	label.text = ui_name
	
	var value := Label.new()
	
	var slider := HSlider.new()
	slider.min_value = smin
	slider.max_value = smax
	slider.step = (smax - smin) / 100.0
	slider.value = initial_value
	
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float): on_value_change.call(value))
	
	value.text = "%d %s" % [slider.value, unit]
	
	hbox.add_child(label)
	hbox.add_child(slider)
	hbox.add_child(value)
	
	return hbox
