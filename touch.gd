extends Control
var world: Node3D
var fingers := {}
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _input(event):
	if event is InputEventScreenTouch:
		var size_v := get_viewport_rect().size
		if event.pressed and event.position.y > size_v.y * 0.62:
			if event.position.x < size_v.x * 0.35: fingers[event.index] = ["move",event.position]
			elif event.position.distance_to(Vector2(size_v.x*0.922,size_v.y*0.78)) <= 36:
				fingers[event.index] = ["jump",event.position]
				world.touch_jump = true
			else: return
			get_viewport().set_input_as_handled()
		elif not event.pressed and fingers.has(event.index):
			if fingers[event.index][0] == "move": world.touch_dir = Vector2.ZERO
			else: world.touch_jump = false
			fingers.erase(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if fingers.has(event.index):
			if fingers[event.index][0] == "move": world.touch_dir = ((event.position-fingers[event.index][1])/60.0).limit_length()
			get_viewport().set_input_as_handled()
		elif event.position.x > get_viewport_rect().size.x*0.5 and event.position.y < get_viewport_rect().size.y*0.6:
			world.yaw -= event.relative.x*0.003*world.touch_sensitivity/50.0
			world.pitch = clampf(world.pitch-event.relative.y*0.003*world.touch_sensitivity/50.0,-1.2,0.15)
func _process(_delta):
	queue_redraw()
func _draw():
	var v := get_viewport_rect().size
	draw_circle(Vector2(v.x*0.15,v.y*0.78),45,Color(1,1,1,0.25))
	draw_circle(Vector2(v.x*0.92,v.y*0.78),36,Color(1,1,1,0.3))
	draw_string(ThemeDB.fallback_font,Vector2(v.x*0.92-18,v.y*0.78+5),"Pular")
