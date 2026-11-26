extends Control
var world: Node3D
var joystick_pos := Vector2(0.15,0.78)
var jump_pos := Vector2(0.90,0.78)
var active_finger := -1
var active_control := ""
var settings := ConfigFile.new()

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("touch_controls")
	settings.load("user://controls.cfg")
	joystick_pos = settings.get_value("mobile","joystick",joystick_pos)
	jump_pos = settings.get_value("mobile","touch_jump",jump_pos)

func _input(event):
	var viewport_size := get_viewport_rect().size
	var joystick_center := joystick_pos * viewport_size
	var jump_center := jump_pos * viewport_size
	var radius := 46.0 * world.control_scale
	if event is InputEventScreenTouch:
		if world.control_edit_mode:
			if event.pressed:
				if event.position.distance_to(joystick_center) <= radius:
					active_finger = event.index
					active_control = "joystick"
				elif event.position.distance_to(jump_center) <= radius:
					active_finger = event.index
					active_control = "jump"
			elif event.index == active_finger:
				active_finger = -1
				_save_layout()
			return
		if event.pressed and active_finger == -1:
			if event.position.distance_to(joystick_center) <= radius*1.5:
				active_finger = event.index
				active_control = "move"
				world.touch_dir = Vector2.ZERO
			elif event.position.distance_to(jump_center) <= radius*1.5:
				active_finger = event.index
				active_control = "jump"
				world.touch_jump = true
		elif not event.pressed and event.index == active_finger:
			if active_control == "move": world.touch_dir = Vector2.ZERO
			if active_control == "jump": world.touch_jump = false
			active_finger = -1
			active_control = ""
	elif event is InputEventScreenDrag and event.index == active_finger:
		if world.control_edit_mode:
			var normalized := event.position / viewport_size
			if active_control == "joystick": joystick_pos = normalized
			elif active_control == "jump": jump_pos = normalized
			queue_redraw()
		elif active_control == "move":
			world.touch_dir = ((event.position-joystick_center)/(60.0*world.control_scale)).limit_length()
	queue_redraw()

func _process(_delta):
	queue_redraw()

func _draw():
	var size := get_viewport_rect().size
	var radius := 42.0 * world.control_scale
	var color := Color(1.0,0.82,0.45,0.65) if world.control_edit_mode else Color(1,1,1,0.25)
	draw_circle(joystick_pos*size,radius,color)
	draw_circle(jump_pos*size,radius*0.82,Color(color.r,color.g,color.b,0.75))
	draw_string(ThemeDB.fallback_font,joystick_pos*size+Vector2(-18,5),"Mover")
	draw_string(ThemeDB.fallback_font,jump_pos*size+Vector2(-17,5),"Pular")

func _save_layout():
	settings.set_value("mobile","joystick",joystick_pos)
	settings.set_value("mobile","touch_jump",jump_pos)
	settings.save("user://controls.cfg")

func reset_layout():
	joystick_pos = Vector2(0.15,0.78)
	jump_pos = Vector2(0.90,0.78)
	_save_layout()
	queue_redraw()
