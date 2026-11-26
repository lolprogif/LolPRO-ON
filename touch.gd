extends Control
var world: Node3D
var fingers := {}
var defaults := {"move":Vector2(0.15,0.78),"jump":Vector2(0.92,0.78),"attack":Vector2(0.78,0.78),"run":Vector2(0.78,0.56)}
var positions := {}
var radii := {}
var editing := false
var selected := "attack"
var settings := ConfigFile.new()
var toolbar: HBoxContainer
var size_slider: HSlider
var profile := "offline"
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("mobile_hud")
	profile = str(get_tree().get_meta("hud_profile","offline"))
	settings.load("user://mobile_hud.cfg")
	reset_layout()
	for key in defaults:
		var p = settings.get_value(profile,key,defaults[key])
		if p is Vector2: positions[key] = p.clamp(Vector2.ZERO,Vector2.ONE)
		radii[key] = clampf(float(settings.get_value(profile,key+"_radius",radii[key])),24,85)
	toolbar = HBoxContainer.new()
	add_child(toolbar)
	toolbar.position = Vector2(8,8)
	var save := Button.new()
	save.text = "Salvar HUD"
	toolbar.add_child(save)
	save.pressed.connect(save_layout)
	var reset := Button.new()
	reset.text = "Restaurar padrão"
	toolbar.add_child(reset)
	reset.pressed.connect(func(): reset_layout(); size_slider.set_value_no_signal(radii[selected]))
	var cancel := Button.new()
	cancel.text = "Cancelar"
	toolbar.add_child(cancel)
	cancel.pressed.connect(cancel_layout)
	size_slider = HSlider.new()
	size_slider.min_value = 24
	size_slider.max_value = 85
	size_slider.custom_minimum_size.x = 110
	toolbar.add_child(size_slider)
	size_slider.value_changed.connect(func(value: float): radii[selected] = value)
	toolbar.hide()
func reset_layout():
	positions = defaults.duplicate()
	radii = {"move":45.0,"jump":36.0,"attack":36.0,"run":36.0}
func center(key: String) -> Vector2:
	var v := get_viewport_rect().size
	var r := float(radii[key])
	return (positions[key]*v).clamp(Vector2(r,r),Vector2(maxf(r,v.x-r),maxf(r,v.y-r)))
func edit_layout():
	fingers.clear()
	world.touch_dir = Vector2.ZERO
	world.touch_jump = false
	editing = true
	size_slider.set_value_no_signal(radii[selected])
	toolbar.show()
func save_layout():
	for key in defaults:
		settings.set_value(profile,key,positions[key])
		settings.set_value(profile,key+"_radius",radii[key])
	if settings.save("user://mobile_hud.cfg") != OK: return
	finish_edit()
func cancel_layout():
	reset_layout()
	for key in defaults:
		positions[key] = settings.get_value(profile,key,defaults[key])
		radii[key] = clampf(float(settings.get_value(profile,key+"_radius",radii[key])),24,85)
	finish_edit()
func finish_edit():
	editing = false
	fingers.clear()
	toolbar.hide()
func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			if editing and toolbar.get_global_rect().has_point(event.position): return
			var hit := ""
			var nearest := INF
			for key in defaults:
				var d := event.position.distance_to(center(key))
				if d <= float(radii[key]) and d < nearest:
					hit = key
					nearest = d
			if hit.is_empty():
				if editing: get_viewport().set_input_as_handled()
				return
			fingers[event.index] = [hit,event.position]
			if editing:
				selected = hit
				size_slider.set_value_no_signal(radii[hit])
			elif hit == "jump": world.touch_jump = true
			elif hit == "attack": world.attack()
			elif hit == "run": world.touch_run = not world.touch_run
			get_viewport().set_input_as_handled()
		elif fingers.has(event.index):
			var key: String = fingers[event.index][0]
			if key == "move": world.touch_dir = Vector2.ZERO
			if key == "jump": world.touch_jump = false
			fingers.erase(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if fingers.has(event.index):
			var key: String = fingers[event.index][0]
			if editing:
				var v := get_viewport_rect().size
				var r := float(radii[key])
				positions[key] = event.position.clamp(Vector2(r,r),Vector2(maxf(r,v.x-r),maxf(r,v.y-r)))/v
			elif key == "move": world.touch_dir = ((event.position-fingers[event.index][1])/float(radii[key])).limit_length()
			get_viewport().set_input_as_handled()
		elif not editing and event.position.x > get_viewport_rect().size.x*0.5 and event.position.y < get_viewport_rect().size.y*0.6:
			world.yaw -= event.relative.x*0.003*world.touch_sensitivity/50.0
			world.pitch = clampf(world.pitch-event.relative.y*0.003*world.touch_sensitivity/50.0,-1.2,0.15)
func _process(_delta):
	queue_redraw()
func _draw():
	for key in defaults:
		var p := center(key)
		var r := float(radii[key])
		draw_circle(p,r,Color(1,1,1,0.48 if editing and selected==key else 0.25))
		var caption := str({"move":"Mover","jump":"Pular","attack":"Atacar","run":"Caminhar" if world.touch_run else "Correr"}[key])
		var font := ThemeDB.fallback_font
		var fs := int(clampf(r*0.4,12,24))
		draw_string(font,p+Vector2(-font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x/2,fs/3.0),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,fs)
