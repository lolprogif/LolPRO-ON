extends Node3D
var player := CharacterBody3D.new()
var pivot := Node3D.new()
var camera := Camera3D.new()
var models := {}
var current := ""
var pitch := -0.25
var distance := 4.2
var jump_held := false
var jumping := false
const JUMP_GRAVITY := 10.0
const JUMP_SPEED := 2.0
const JUMP_DURATION := 2.0 * JUMP_SPEED / JUMP_GRAVITY
var yaw := 0.0
var net: Node
var touch_sensitivity := 50.0
var touch_dir := Vector2.ZERO
var touch_run := false
var touch_jump := false
func _ready():
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.19,0.43,0.72)
	sky_mat.sky_horizon_color = Color(0.77,0.85,0.91)
	sky.sky_material = sky_mat
	env.environment.fog_enabled = true
	env.environment.fog_light_color = Color(0.72,0.82,0.91)
	env.environment.fog_density = 0.003
	env.environment.sky = sky
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-35,0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	add_child(ground)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.37,0.56,0.23)
	var noise := NoiseTexture2D.new()
	noise.width = 512
	noise.height = 512
	noise.seamless = true
	var grass_noise := FastNoiseLite.new()
	grass_noise.frequency = 0.12
	noise.noise = grass_noise
	mat.albedo_texture = noise
	mat.uv1_scale = Vector3(90,90,90)
	mesh.material_override = mat
	ground.add_child(mesh)
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,200)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	ground.add_child(floor_shape)
	add_child(player)
	player.position.y = 0.1
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	col.shape = capsule
	col.position.y = 0.9
	player.add_child(col)
	for state in ["Idle","Walking","Running","Jumping"]:
		var scene = load("res://assets/"+state+".fbx")
		if scene is PackedScene:
			var model = scene.instantiate()
			player.add_child(model)
			model.hide()
			models[state] = model
	if models.is_empty():
		push_error("Nenhum modelo FBX importado")
	add_child(pivot)
	pivot.add_child(camera)
	camera.current = true
	camera.position.z = distance
	var ui = preload("res://hud.gd").new()
	ui.world = self
	add_child(ui)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	animate("Idle")
	net = preload("res://network.gd").new()
	net.world = self
	add_child(net)
func animate(state):
	if state == current or not models.has(state): return
	if models.has(current): models[current].hide()
	current = state
	var model = models[state]
	model.show()
	var anim = model.find_children("*","AnimationPlayer",true,false)
	if not anim.is_empty():
		var ap = anim[0]
		for clip in ap.get_animation_list():
			if clip != "RESET":
				ap.get_animation(clip).loop_mode = Animation.LOOP_NONE if state == "Jumping" else Animation.LOOP_LINEAR
				remove_horizontal_motion(ap, clip, state == "Jumping")
				ap.stop()
				var rate: float = ap.get_animation(clip).length / JUMP_DURATION if state == "Jumping" else 1.0
				ap.play(clip, 0.0, rate)
				ap.advance(0.0)
				break
func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.003
		pitch = clamp(pitch-event.relative.y*0.003,-1.2,0.15)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = max(2.0,distance-0.5)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = min(12.0,distance+0.5)
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
func _physics_process(delta):
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	direction += Vector3(touch_dir.x,0,touch_dir.y)
	direction = direction.normalized().rotated(Vector3.UP,yaw)
	var running := Input.is_physical_key_pressed(KEY_SHIFT) or touch_run
	var speed := 4.6 if running else 1.8
	player.velocity.x = move_toward(player.velocity.x,direction.x*speed,delta*18.0)
	player.velocity.z = move_toward(player.velocity.z,direction.z*speed,delta*18.0)
	var jump_now := Input.is_physical_key_pressed(KEY_SPACE) or touch_jump
	if not player.is_on_floor():
		player.velocity.y -= JUMP_GRAVITY * delta
	elif jump_now and not jump_held:
		player.velocity.y = JUMP_SPEED
		jumping = true
	jump_held = jump_now
	player.move_and_slide()
	if player.is_on_floor():
		jumping = false
	if player.position.y < -10: player.position = Vector3(0,1,0)
	if direction.length() > 0.01: player.rotation.y = lerp_angle(player.rotation.y,atan2(direction.x,direction.z),1.0-exp(-12.0*delta))
	animate("Jumping" if jumping else ("Idle" if direction.length()<0.01 else ("Running" if running else "Walking")))
	pivot.position = pivot.position.lerp(player.position + Vector3(0,1.5,0),1.0-exp(-12.0*delta))
	pivot.rotation = Vector3(pitch,yaw,0)
	camera.position.z = lerpf(camera.position.z,distance,1.0-exp(-12.0*delta))


# Physics owns jump height; remove animated vertical root motion during jumps.
func remove_horizontal_motion(ap: AnimationPlayer, clip: String, lock_vertical: bool):
	var anim := ap.get_animation(clip)
	for track in range(anim.get_track_count()):
		if anim.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(anim.track_get_path(track)).to_lower()
		var bone := path.get_slice(":", 1)
		if not (bone.ends_with("hips") or bone.ends_with("root") or bone.ends_with("pelvis") or bone.is_empty()):
			continue
		if anim.track_get_key_count(track) == 0:
			continue
		var initial: Vector3 = anim.track_get_key_value(track, 0)
		for key in range(anim.track_get_key_count(track)):
			var value: Vector3 = anim.track_get_key_value(track, key)
			value.x = initial.x
			value.z = initial.z
			if lock_vertical:
				value.y = initial.y
			anim.track_set_key_value(track, key, value)
