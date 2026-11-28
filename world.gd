extends Node3D
var free_combat := false
var click_moving := false
var auto_attack := false
var click_destination := Vector3.ZERO
var combat_target: Node3D
var selected_remote_id := ""
var target_marker: MeshInstance3D
var player := CharacterBody3D.new()
var pivot := Node3D.new()
var camera := Camera3D.new()
var models := {}
var brute_motion_paths := {}
var using_brute := false
var using_agent := false
var brute_attack_index := 0
var current := ""
var admin_animation_until: int = 0
var pitch := -0.25
var distance := 4.2
var jump_held := false
var jumping := false
const JUMP_GRAVITY := 10.0
const JUMP_SPEED := 4.0
const JUMP_DURATION := 2.0 * JUMP_SPEED / JUMP_GRAVITY
var yaw := 0.0
var net: Node
var touch_sensitivity := 50.0
var touch_dir := Vector2.ZERO
var touch_run := false
var touch_jump := false
var attack_anim_until: int = 0
var attack_cooldown := 0.0
var portal_guard: Node3D
var boss_return_guard: Node3D
var portal_dialog: ConfirmationDialog
var current_map: String = "valoria"
const BOSS_CENTER := Vector3(1000,0,1000)
const BOSS_HALF := 250.0
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
	sun.shadow_enabled = not OS.has_feature("mobile")
	add_child(sun)
	var ground := StaticBody3D.new()
	add_child(ground)
	create_valoria()
	create_boss_map()
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16,0.19,0.20)
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
	player.position.y = 0.65
	if get_tree().has_meta("online_token") and get_tree().has_meta("saved_world_position"):
		var saved: Array = get_tree().get_meta("saved_world_position")
		if saved.size() == 3:
			player.position = Vector3(float(saved[0]),float(saved[1]),float(saved[2]))
			player.rotation.y = float(get_tree().get_meta("saved_world_angle",0.0))
		get_tree().remove_meta("saved_world_position")
	player.floor_snap_length = 0.45
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	col.shape = capsule
	col.position.y = 0.9
	player.add_child(col)
	if player.position.x > 700.0 and player.position.z > 700.0:
		current_map = "bosses"
	var avatar_id := str(get_tree().get_meta("selected_avatar","whiteclown"))
	if avatar_id == "warrior_m": avatar_id = "sura"
	if avatar_id == "secret_agent" and ResourceLoader.exists("res://assets/The_Secret_Agent.glb"):
		var agent_scene = load("res://assets/The_Secret_Agent.glb")
		if agent_scene is PackedScene:
			var agent: Node3D = agent_scene.instantiate() as Node3D
			if agent != null:
				player.add_child(agent)
				models["Avatar"] = agent
				using_agent = true
	if using_agent:
		pass
	elif avatar_id in ["whiteclown","sura"]:
		# Carrega somente o Idle ao entrar. Caminhada, corrida e ataques são
		# carregados sob demanda para reduzir o pico de memória no Windows.
		using_brute = true
		brute_motion_paths = {
			"Idle":"Idle.fbx",
			"Walking":"Walking.fbx",
			"Running":"Running.fbx",
			"Jumping":"Jumping.fbx",
			"Attack1":"Sword And Shield Slash.fbx",
			"Attack2":"Stable Sword Outward Slash.fbx"
		}
		ensure_brute_motion("Idle")
	else:
		var custom_path: String = "res://assets/Character.fbx"
		var avatar_scene = load(custom_path)
		if avatar_scene is PackedScene:
			var avatar_model: Node3D = avatar_scene.instantiate() as Node3D
			player.add_child(avatar_model)
			models["Avatar"] = avatar_model
		else:
			push_error("Modelo não importado: "+custom_path)
	if models.is_empty():
		push_error("Nenhum modelo FBX importado")
	add_child(pivot)
	pivot.add_child(camera)
	target_marker = MeshInstance3D.new()
	target_marker.name = "SelectedPlayerMarker"
	var marker_mesh := TorusMesh.new()
	marker_mesh.inner_radius = 0.52
	marker_mesh.outer_radius = 0.68
	target_marker.mesh = marker_mesh
	target_marker.rotation.x = PI / 2.0
	target_marker.position.y = 0.045
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color(1.0,0.08,0.08,0.95)
	marker_material.emission_enabled = true
	marker_material.emission = Color(1.0,0.02,0.02)
	target_marker.material_override = marker_material
	target_marker.visible = false
	add_child(target_marker)
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
func ensure_brute_motion(state: String) -> bool:
	if models.has(state):
		return true
	if not brute_motion_paths.has(state):
		return false
	# Mantém o Idle para retarget do pulo e libera a animação anterior.
	# Assim nunca ficam todos os FBX de movimento carregados ao mesmo tempo.
	for existing_state in models.keys().duplicate():
		if existing_state != "Idle" and existing_state != state:
			var previous: Node = models[existing_state]
			if is_instance_valid(previous):
				player.remove_child(previous)
				previous.queue_free()
			models.erase(existing_state)
	var motion_path := "res://assets/" + str(brute_motion_paths[state])
	var motion_scene = load(motion_path)
	if not motion_scene is PackedScene:
		push_warning("Animação não importada: " + motion_path)
		return false
	var motion_model := motion_scene.instantiate() as Node3D
	if motion_model == null:
		push_warning("Não foi possível instanciar a animação: " + motion_path)
		return false
	player.add_child(motion_model)
	motion_model.name = "Brute_" + state
	motion_model.visible = false
	models[state] = motion_model
	return true

func preview_admin_animation(state: String):
	admin_animation_until = 0
	current = ""
	animate(state)
	admin_animation_until = Time.get_ticks_msec() + 2500

func animate(state):
	if Time.get_ticks_msec() < admin_animation_until: return
	if state == current: return
	current = state
	if models.has("Avatar"):
		var actor: Node3D = models["Avatar"]
		actor.show()
		if actor.has_method("set_motion"):
			actor.call("set_motion", state)
			return
		var anim = actor.find_children("*","AnimationPlayer",true,false)
		if not anim.is_empty():
			var ap: AnimationPlayer = anim[0]
			var desired := ""
			if using_agent:
				var wanted: String = str({"Idle":"Idle-loop","Walking":"Walk-loop","Running":"Run-loop","Jumping":"Jump","Attack1":"Sword slash","Attack2":"Sword thrust"}.get(state,"Idle-loop"))
				for clip in ap.get_animation_list():
					if String(clip).get_file().to_lower().replace("_"," ").replace("-"," ") == wanted.to_lower().replace("-"," "):
						desired = String(clip)
						break
				if not desired.is_empty():
					var one_shot: bool = state in ["Jumping","Attack1","Attack2"]
					ap.get_animation(desired).loop_mode = Animation.LOOP_NONE if one_shot else Animation.LOOP_LINEAR
					remove_horizontal_motion(ap, desired, state == "Jumping")
					ap.play(desired, 0.12)
					return
			var candidates := {"Idle":["Intro_wait","onehand_idle","Idle","idle","Standing","FreeRunning"],"Walking":["Walking","Walk","walking","Run","FreeRunning"],"Running":["Running","Run","FreeRunning"],"Jumping":["Jumping","Jump","jump","Idle","idle","Intro_wait"]}
			for candidate in candidates.get(state,["FreeRunning"]):
				if ap.has_animation(candidate):
					desired = candidate
					break
			if desired.is_empty():
				for clip in ap.get_animation_list():
					if clip != "RESET":
						desired = clip
						break
			if not desired.is_empty():
				remove_horizontal_motion(ap, desired, state == "Jumping")
				ap.stop()
				ap.get_animation(desired).loop_mode = Animation.LOOP_NONE if state == "Jumping" else Animation.LOOP_LINEAR
				ap.play(desired)
		return
	if state == "Jumping" and models.has("Idle"):
		if play_jump_on_selected_model():
			return
		state = "Idle"
	if using_brute and not models.has(state):
		if not ensure_brute_motion(state):
			state = "Idle"
	if not models.has(state):
		if state == "Jumping" and models.has("Idle"):
			state = "Idle"
		else:
			return
	for key in models:
		if models[key] is Node3D:
			models[key].visible = key == state
	var model: Node3D = models[state]
	var anim = model.find_children("*","AnimationPlayer",true,false)
	if not anim.is_empty():
		var ap: AnimationPlayer = anim[0]
		for clip in ap.get_animation_list():
			if clip != "RESET" and clip != "jump_transfer/Jump":
				var one_shot: bool = state == "Jumping" or state == "Attack1" or state == "Attack2"
				ap.get_animation(clip).loop_mode = Animation.LOOP_NONE if one_shot else Animation.LOOP_LINEAR
				remove_horizontal_motion(ap, clip, state == "Jumping")
				ap.stop()
				ap.play(clip)
				break
# Copy only compatible skeletal rotation tracks; never display the source mesh.
func play_jump_on_selected_model() -> bool:
	var actor: Node3D = models["Idle"]
	var players := actor.find_children("*", "AnimationPlayer", true, false)
	var skeletons := actor.find_children("*", "Skeleton3D", true, false)
	if players.is_empty() or skeletons.is_empty():
		return false
	var ap: AnimationPlayer = players[0]
	var target: Skeleton3D = skeletons[0]
	var clip_name := "jump_transfer/Jump"
	if not ap.has_animation(clip_name):
		var scene = load("res://assets/Jumping.fbx")
		if not scene is PackedScene:
			return false
		var source: Node = scene.instantiate()
		var source_players := source.find_children("*", "AnimationPlayer", true, false)
		if source_players.is_empty():
			source.free()
			return false
		var source_ap: AnimationPlayer = source_players[0]
		var source_clip: Animation = null
		for name in source_ap.get_animation_list():
			if name != "RESET":
				source_clip = source_ap.get_animation(name)
				break
		if source_clip == null:
			source.free()
			return false
		var root: Node = ap.get_node_or_null(ap.root_node)
		if root == null:
			source.free()
			return false
		var transferred := Animation.new()
		transferred.length = source_clip.length
		transferred.loop_mode = Animation.LOOP_NONE
		for track in range(source_clip.get_track_count()):
			if source_clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var path := source_clip.track_get_path(track)
			if path.get_subname_count() != 1:
				continue
			var bone := String(path.get_subname(0))
			if target.find_bone(bone) == -1:
				continue
			var index := transferred.add_track(Animation.TYPE_ROTATION_3D)
			transferred.track_set_path(index, NodePath(str(root.get_path_to(target)) + ":" + bone))
			for key in range(source_clip.track_get_key_count(track)):
				transferred.track_insert_key(index, source_clip.track_get_key_time(track, key), source_clip.track_get_key_value(track, key))
		source.free()
		if transferred.get_track_count() == 0:
			push_warning("Jump animation has no compatible bones")
			return false
		var library := AnimationLibrary.new()
		library.add_animation("Jump", transferred)
		ap.add_animation_library("jump_transfer", library)
	for key in models:
		if models[key] is Node3D:
			models[key].visible = key == "Idle"
	ap.stop()
	ap.play(clip_name, -1.0, ap.get_animation(clip_name).length / JUMP_DURATION)
	return true

func _notification(what: int):
	# Libera o cursor apenas ao sair da janela; ao voltar, o jogador decide
	# travar/destravar novamente pelo botão direito do mouse.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if select_remote_at(event.position):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if not OS.has_feature("mobile") and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not try_guard_click(event.position):
			click_world(event.position)
	if event is InputEventScreenTouch and event.pressed:
		if not try_guard_click(event.position): click_world(event.position)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.003
		pitch = clamp(pitch-event.relative.y*0.003,-1.2,0.15)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = max(2.0,distance-0.5)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = min(12.0,distance+0.5)
func select_remote_at(screen_pos: Vector2) -> bool:
	if not is_instance_valid(net):
		return false
	var best_id := ""
	var best_node: Node3D = null
	var best_distance := 76.0
	for id in net.remotes:
		var entry: Dictionary = net.remotes[id]
		var node: Node3D = entry.get("node")
		if not is_instance_valid(node):
			continue
		var point := node.global_position + Vector3.UP
		if camera.is_position_behind(point):
			continue
		var d := camera.unproject_position(point).distance_to(screen_pos)
		if d < best_distance:
			best_distance = d
			best_id = str(id)
			best_node = node
	if not is_instance_valid(best_node):
		return false
	selected_remote_id = best_id
	combat_target = best_node
	auto_attack = false
	click_moving = false
	target_marker.visible = true
	target_marker.global_position = best_node.global_position + Vector3(0,0.045,0)
	var hud = get_children().filter(func(n): return n is CanvasLayer)[0]
	if hud.has_method("show_target_menu"):
		hud.show_target_menu(str(net.remotes[best_id].get("name","Jogador")))
	return true
func _physics_process(delta):
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if is_instance_valid(target_marker) and target_marker.visible:
		if is_instance_valid(combat_target):
			target_marker.global_position = combat_target.global_position + Vector3(0,0.045,0)
		else:
			target_marker.visible = false
			selected_remote_id = ""
	if is_instance_valid(net) and net.cloud_active and net.health <= 0:
		player.velocity = Vector3.ZERO
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	direction += Vector3(touch_dir.x,0,touch_dir.y)
	direction = direction.normalized().rotated(Vector3.UP,yaw)
	if direction.length()>0.01:
		click_moving = false
		auto_attack = false
	elif auto_attack and is_instance_valid(combat_target):
		if not target_is_alive(combat_target):
			auto_attack = false
			combat_target = null
			selected_remote_id = ""
			target_marker.visible = false
			click_moving = false
		else:
			click_destination = combat_target.global_position
			var attack_offset := click_destination-player.global_position
			attack_offset.y = 0
			if attack_offset.length() > 1.85:
				direction = attack_offset.normalized()
				click_moving = true
			else:
				click_moving = false
				player.rotation.y = atan2(attack_offset.x,attack_offset.z)
				if attack_cooldown <= 0.0:
					attack()
	elif click_moving:
		var offset := click_destination-player.global_position
		offset.y = 0
		if offset.length() <= 0.3:
			click_moving = false
		else:
			direction = offset.normalized()
	var running: bool = not touch_run # Corrida padrão; botão redondo alterna para caminhada.
	var speed: float = 5.2 if running else 2.8
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
	if current_map == "bosses":
		player.position.x = clampf(player.position.x, BOSS_CENTER.x - BOSS_HALF + 1.0, BOSS_CENTER.x + BOSS_HALF - 1.0)
		player.position.z = clampf(player.position.z, BOSS_CENTER.z - BOSS_HALF + 1.0, BOSS_CENTER.z + BOSS_HALF - 1.0)
	else:
		player.position.x = clampf(player.position.x, -99.0, 99.0)
		player.position.z = clampf(player.position.z, -99.0, 99.0)
	if player.position.y < -10:
		player.position = (BOSS_CENTER if current_map == "bosses" else Vector3.ZERO) + Vector3(0,0.65,0)
		player.velocity = Vector3.ZERO
	if direction.length() > 0.01: player.rotation.y = lerp_angle(player.rotation.y,atan2(direction.x,direction.z),1.0-exp(-12.0*delta))
	if Time.get_ticks_msec() >= attack_anim_until:
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

func acquire_nearby_target(max_distance: float = 7.0) -> Node3D:
	var candidates: Array = get_tree().get_nodes_in_group("attackable")
	if free_combat and is_instance_valid(net):
		for entry in net.remotes.values():
			if entry is Dictionary and is_instance_valid(entry.get("node")):
				candidates.append(entry.node)
	var best: Node3D = null
	var best_distance := max_distance
	for candidate in candidates:
		if not candidate is Node3D or candidate == player or not is_instance_valid(candidate):
			continue
		var offset: Vector3 = candidate.global_position - player.global_position
		offset.y = 0.0
		var distance_to_target := offset.length()
		if distance_to_target < best_distance:
			best_distance = distance_to_target
			best = candidate
	return best

func target_is_alive(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	if target.is_in_group("attackable") and target.get("health") != null:
		return int(target.get("health")) > 0
	if is_instance_valid(net):
		for entry in net.remotes.values():
			if entry.get("node") == target:
				return int(entry.get("hp",100)) > 0
	return true

func attack():
	if attack_cooldown > 0.0 or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if is_instance_valid(net) and net.cloud_active and net.health <= 0:
		return
	# Ataque manual exige um alvo selecionado explicitamente.
	# Nunca procura/adota um alvo automaticamente ao apertar ATACAR.
	if not is_instance_valid(combat_target):
		return
	var target_offset: Vector3 = combat_target.global_position - player.global_position
	target_offset.y = 0.0
	var target_distance := target_offset.length()
	if target_distance > 2.15:
		click_destination = combat_target.global_position
		click_moving = true
		auto_attack = true
		return
	if target_distance > 0.05:
		player.rotation.y = atan2(target_offset.x,target_offset.z)
	attack_cooldown = 0.6
	if is_instance_valid(net) and net.cloud_active:
		var target_id := ""
		for id in net.remotes:
			if net.remotes[id].get("node") == combat_target:
				target_id = str(id)
				break
		if not target_id.is_empty():
			net.request_attack(target_id)
	if using_brute or using_agent:
		brute_attack_index += 1
		var next_attack := "Attack1" if brute_attack_index % 2 == 1 else "Attack2"
		animate(next_attack)
		admin_animation_until = Time.get_ticks_msec() + 580
		attack_anim_until = admin_animation_until
		var attack_state := next_attack
		get_tree().create_timer(0.58).timeout.connect(func():
			admin_animation_until = 0
			if current == attack_state:
				animate("Idle")
		)
	attack_effect(player)
	if combat_target.has_method("take_damage"):
		combat_target.take_damage(10)

func attack_effect(actor: Node3D):
	punch_pose(actor)
	var effect := MeshInstance3D.new()
	var slash := BoxMesh.new()
	slash.size = Vector3(1.6,0.07,0.15)
	effect.mesh = slash
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0,0.8,0.25)
	effect.material_override = material
	actor.add_child(effect)
	effect.position = Vector3(0,1.1,1.0)
	var tween := create_tween()
	tween.tween_property(effect,"rotation:y",1.8,0.18).from(-1.8)
	tween.tween_callback(effect.queue_free)

# Procedural punch in skeleton space, shared by local and remote actors.
func punch_pose(actor: Node3D):
	for candidate in actor.find_children("*","Skeleton3D",true,false):
		var sk: Skeleton3D = candidate
		var upper := -1
		var fore := -1
		for i in range(sk.get_bone_count()):
			var n := String(sk.get_bone_name(i)).to_lower().replace("_","").replace(".","")
			if n.ends_with("rightarm") or n.ends_with("upperarmr"): upper = i
			if n.ends_with("rightforearm") or n.ends_with("lowerarmr"): fore = i
		if upper < 0 or fore < 0: continue
		var tw := create_tween()
		tw.tween_method(apply_punch.bind(sk,upper,fore),0.0,1.0,0.13)
		tw.tween_method(apply_punch.bind(sk,upper,fore),1.0,0.0,0.22)
		tw.tween_callback(clear_punch.bind(sk,upper,fore))

func apply_punch(amount: float, sk: Skeleton3D, upper: int, fore: int):
	if not is_instance_valid(sk): return
	var shoulder := sk.get_bone_global_pose(upper)
	var elbow := sk.get_bone_global_pose(fore)
	var forward := Vector3.FORWARD
	# The actor faces its local positive Z; use its world direction.
	var actor_node: Node3D = sk
	while actor_node.get_parent() is Node3D and actor_node.get_parent() != self:
		actor_node = actor_node.get_parent()
	forward = (sk.global_transform.basis.inverse() * actor_node.global_transform.basis.z).normalized()
	var arm_dir := (elbow.origin-shoulder.origin).normalized()
	if arm_dir.length_squared() < 0.001: return
	var goal := (forward+Vector3.UP*0.08).normalized()
	var rot := Quaternion(arm_dir,goal)
	var posed := shoulder
	posed.basis = Basis(Quaternion.IDENTITY.slerp(rot,amount))*shoulder.basis
	sk.set_bone_global_pose_override(upper,posed,amount,true)
	var lower := sk.get_bone_global_pose(fore)
	var rest := sk.get_bone_rest(fore)
	lower.origin = posed * rest.origin
	lower.basis = posed.basis * rest.basis
	sk.set_bone_global_pose_override(fore,lower,amount,true)

func clear_punch(sk: Skeleton3D, upper: int, fore: int):
	if not is_instance_valid(sk): return
	sk.set_bone_global_pose_override(upper,Transform3D.IDENTITY,0.0,false)
	sk.set_bone_global_pose_override(fore,Transform3D.IDENTITY,0.0,false)

func show_gear(actor: Node3D, data: Dictionary):
	var flags: Dictionary = data.get("gear",{}).duplicate()
	flags["weapon"] = int(data.get("weapon",0))
	flags["armor"] = int(data.get("armor",0))
	var ranks: Dictionary = data.get("ranks",{})
	var signature := JSON.stringify([flags,ranks])
	if actor.get_meta("gear_signature","") == signature: return
	actor.set_meta("gear_signature",signature)
	var old := actor.get_node_or_null("VisibleGear")
	if old: actor.remove_child(old); old.queue_free()
	var holder := Node3D.new()
	holder.name = "VisibleGear"
	actor.add_child(holder)
	var parts := {
		"weapon":[Vector3(0.43,0.85,0.12),Vector3(0.07,0.85,0.10)],
		"armor":[Vector3(0,1.22,0),Vector3(0.52,0.42,0.28)],
		"helmet":[Vector3(0,1.72,0),Vector3(0.34,0.22,0.34)],
		"boots":[Vector3(0.17,0.13,0),Vector3(0.18,0.24,0.28)],
		"gloves":[Vector3(0.43,0.85,0),Vector3(0.14,0.18,0.14)],
		"necklace":[Vector3(0,1.43,0.17),Vector3(0.16,0.05,0.05)],
		"ring":[Vector3(0.43,0.77,0.07),Vector3(0.06,0.04,0.06)],
		"bracelet":[Vector3(-0.43,0.94,0),Vector3(0.15,0.06,0.15)],
		"shield":[Vector3(-0.48,1.0,0.12),Vector3(0.35,0.55,0.09)]}
	for key in parts:
		if not int(flags.get(key,0)): continue
		var mesh := MeshInstance3D.new()
		mesh.mesh = equipment_mesh(key,parts[key][1])
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("c9a45a") if key in ["ring","necklace","bracelet"] else Color("8b9ba9")
		mat.metallic = 0.65
		mesh.material_override = mat
		holder.add_child(mesh)
		mesh.position = parts[key][0]
		var rank := int(ranks.get(key,1))
		if rank >= 7: refinement_glow(mesh,mat,rank)
		if key == "weapon":
			add_gear_detail(mesh,Vector3(0,-0.39,0),Vector3(0.25,0.045,0.09),Color("c5a052"))
			add_gear_detail(mesh,Vector3(0,-0.49,0),Vector3(0.055,0.18,0.06),Color("493323"))
		if key == "shield":
			add_gear_detail(mesh,Vector3(0,0,0.065),Vector3(0.09,0.09,0.06),Color("c5a052"))
		if key in ["boots","gloves"]:
			var other := mesh.duplicate() as MeshInstance3D
			holder.add_child(other)
			other.position.x *= -1

func equipment_mesh(kind: String, dimensions: Vector3) -> Mesh:
	if kind in ["ring","bracelet","necklace"]:
		var torus := TorusMesh.new()
		torus.inner_radius = dimensions.x*0.30
		torus.outer_radius = dimensions.x*0.50
		return torus
	if kind in ["helmet","armor","gloves","boots","shield"]:
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		var arrays := sphere.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(vertices.size()): vertices[i] *= dimensions
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var result := ArrayMesh.new()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		return result
	var blade := PrismMesh.new()
	blade.size = dimensions
	return blade
func add_gear_detail(parent: Node3D, offset: Vector3, dimensions: Vector3, color: Color):
	var detail := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = dimensions
	detail.mesh = shape
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.5
	detail.material_override = mat
	parent.add_child(detail)
	detail.position = offset

func refinement_glow(mesh: MeshInstance3D, mat: StandardMaterial3D, rank: int):
	mat.emission_enabled = true
	mat.emission = Color("ffd36a")
	mat.emission_energy_multiplier = 0.22 if rank == 7 else (0.55 if rank == 8 else 1.15)
	var sparks := GPUParticles3D.new()
	sparks.amount = 6 if rank == 7 else (14 if rank == 8 else 32)
	sparks.lifetime = 0.65
	sparks.local_coords = true
	sparks.visibility_aabb = AABB(Vector3(-2,-2,-2),Vector3(4,4,4))
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = mesh.mesh.get_aabb().size * 0.5
	motion.direction = Vector3.UP
	motion.spread = 85.0
	motion.initial_velocity_min = 0.12
	motion.initial_velocity_max = 0.45 if rank < 9 else 0.85
	motion.gravity = Vector3(0,-0.35,0)
	motion.scale_min = 0.45
	motion.scale_max = 1.0
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1,0.95,0.55,1),Color(1,0.55,0.08,0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	sparks.process_material = motion
	var dot := QuadMesh.new()
	dot.size = Vector2(0.025,0.025) if rank < 9 else Vector2(0.045,0.045)
	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gold.vertex_color_use_as_albedo = true
	gold.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gold.emission_enabled = true
	gold.emission = Color("ffce55")
	dot.material = gold
	sparks.draw_pass_1 = dot
	mesh.add_child(sparks)
	sparks.emitting = true


# Valoria: procedural oriental-fantasy starter town.
func create_valoria():
	var stone := Color("343b43")
	var dark_stone := Color("202832")
	var roof := Color("171f2b")
	var gold := Color("a77b3e")
	var wood := Color("493329")
	var red := Color("6e2028")
	# Main raised courtyard and the road leading to the temple.
	map_box("Courtyard", Vector3(0,-0.195,0), Vector3(34,0.45,34), stone)
	map_box("TempleRoad", Vector3(0,-0.09,-18), Vector3(12,0.3,24), dark_stone)
	for i in range(6):
		map_box("RoadTile", Vector3(0,0.075,-8.0-float(i)*3.0), Vector3(11,0.02,2.7), stone, false)
	# Entrance stairs.
	# Decorative steps sit over a continuous walkable ramp; they do not block the player.
	for i in range(5):
		map_box("TempleStep", Vector3(0,0.99-float(i)*0.22,-26.0+float(i)*1.0), Vector3(12.0,0.22,1.0), dark_stone, false)
	var ramp_body := StaticBody3D.new()
	ramp_body.name = "TempleAccessRamp"
	ramp_body.position = Vector3(0,0.43,-23.5)
	ramp_body.rotation.x = atan(1.1/6.0)
	var ramp_collision := CollisionShape3D.new()
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(12.0,0.22,6.2)
	ramp_collision.shape = ramp_shape
	ramp_body.add_child(ramp_collision)
	add_child(ramp_body)
	# Main temple platform, columns and walls.
	map_box("TempleFoundation", Vector3(0,0.55,-34), Vector3(22,1.1,15), dark_stone)
	map_box("TempleBackWall", Vector3(0,5.1,-40.5), Vector3(19,7.0,1.0), wood)
	map_box("TempleLeftWall", Vector3(-9.5,4.0,-34), Vector3(1.0,5.5,13), wood)
	map_box("TempleRightWall", Vector3(9.5,4.0,-34), Vector3(1.0,5.5,13), wood)
	for x in [-8.0,-4.0,4.0,8.0]:
		map_box("TempleColumn", Vector3(x,4.0,-28.2), Vector3(0.9,6.2,0.9), red)
		map_box("ColumnBase", Vector3(x,1.1,-28.2), Vector3(1.5,0.8,1.5), gold)
	# Blue walk-through portal in the original temple.
	castle_portal(Vector3(0,3.6,-30.5),Vector3(0,0.2,70))
	create_portal_guard()
	create_test_monster()
	for x in [-8.0,-4.0,4.0,8.0]:
		temple_lantern(Vector3(x,3.1,-27.5))
	for x in [-5.0,5.0]:
		temple_lantern(Vector3(x,1.8,-26.5))
	temple_light(Vector3(0,5,-34),Color("ffd08a"),2.0,15.0)
	temple_light(Vector3(0,4,-37),Color("399dff"),1.5,9.0)
	# Three-tier oriental roof with raised eaves and gold ridge.
	for tier in range(3):
		var y := 8.0+float(tier)*2.0
		var width := 23.0-float(tier)*3.3
		var depth := 16.0-float(tier)*2.4
		map_box("PagodaRoof", Vector3(0,y,-34), Vector3(width,0.55,depth), roof, false)
		map_box("RoofGoldRidge", Vector3(0,y+0.35,-34), Vector3(width*0.52,0.12,0.22), gold, false)
		for side in [-1.0,1.0]:
			var eave := map_box("RaisedEave", Vector3(side*(width*0.5-0.4),y+0.45,-34), Vector3(0.65,0.7,depth), roof, false)
			eave.rotation.z = -side*0.10
	# Separate interior on the same map, preserving network coordinates.
	map_box("HallFloor",Vector3(0,0.1,70),Vector3(24,0.2,24),stone)
	for x in [-12.0,12.0]:
		map_box("HallWall",Vector3(x,4,70),Vector3(1,8,24),dark_stone)
	for z in [58.0,82.0]:
		map_box("HallWall",Vector3(0,4,z),Vector3(24,8,1),dark_stone)
	for x in [-8.0,8.0]:
		for z in [62.0,70.0,78.0]:
			map_box("HallColumn",Vector3(x,4,z),Vector3(1.2,8,1.2),stone)
	map_box("HallCeiling",Vector3(0,8,70),Vector3(24,0.5,24),dark_stone)
	castle_portal(Vector3(0,2.6,80),Vector3(0,1.2,-35))
	# Entrance gate in front of the courtyard.
	for x in [-7.0,7.0]:
		map_box("GatePost", Vector3(x,3.3,12.0), Vector3(1.25,6.5,1.25), red)
		map_box("GateFoot", Vector3(x,0.55,12.0), Vector3(2.0,1.0,2.0), gold)
	map_box("GateBeam", Vector3(0,6.5,12.0), Vector3(17,1.0,1.8), wood)
	map_box("GateRoof", Vector3(0,7.25,12.0), Vector3(20,0.45,3.2), roof, false)
	# Side buildings: market stalls and small houses.
	for side in [-1.0,1.0]:
		for i in range(3):
			var z := 5.0-float(i)*10.0
			var x: float = float(side) * 19.0
			map_box("TownHouse", Vector3(x,2.0,z), Vector3(7,4,7), wood)
			map_box("HouseRoof", Vector3(x,4.5,z), Vector3(8.5,0.55,8.5), roof, false)
			map_box("HouseDoor", Vector3(x,1.1,z+3.56), Vector3(1.6,2.2,0.18), dark_stone, false)
			map_box("HouseTrim", Vector3(x,3.25,z+3.7), Vector3(2.0,0.18,0.25), gold, false)
	# Courtyard lanterns and braziers.
	for x in [-12.0,12.0]:
		for z in [-12.0,2.0,15.0]:
			map_box("LanternStand", Vector3(x,1.5,z), Vector3(0.65,3.0,0.65), dark_stone)
			map_box("LanternCap", Vector3(x,3.15,z), Vector3(1.4,0.35,1.4), gold, false)
			map_fire(Vector3(x,3.65,z))
	# Low boundary walls and decorative corner towers.
	for x in [-17.0,17.0]:
		map_box("CourtyardWall", Vector3(x,1.0,0), Vector3(0.8,2.0,33), dark_stone)
	for z in [-16.0,16.0]:
		for side in [-1.0,1.0]:
			map_box("CourtyardWall", Vector3(float(side)*10.5,1.0,z), Vector3(13,2.0,0.8), dark_stone)
	# Distant silhouettes make the playable area feel like a larger region.
	for i in range(9):
		var x := -48.0+float(i)*12.0
		map_box("DistantRock", Vector3(x,3.0,-61.0), Vector3(8,6+float(i%3)*2.0,7), Color("242d37"), false)
	# Spawn point and a short sign at the town entrance.
	map_box("WelcomeSign", Vector3(0,1.5,17.0), Vector3(4.5,2.8,0.35), wood, false)
	map_box("WelcomePlaque", Vector3(0,2.0,16.78), Vector3(3.6,0.8,0.12), gold, false)

var castle_materials := {}
var portal_lock_until := 0

func castle_stone(color: Color) -> StandardMaterial3D:
	if castle_materials.has(color):
		return castle_materials[color]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.lightened(0.25)
	mat.roughness = 0.95
	var img := Image.create(256,256,false,Image.FORMAT_RGB8)
	for y in range(256):
		for x in range(256):
			var row := y / 32
			var bx := (x + (int(row) % 2)*32) % 64
			var by := y % 32
			var grain := float((x*17+y*31+x*y*3)%23)/100.0
			var shade := 0.32 if bx < 2 or by < 2 else 0.64+grain
			img.set_pixel(x,y,Color(shade,shade,shade))
	img.generate_mipmaps()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.65,0.65,0.65)
	castle_materials[color] = mat
	return mat

func temple_light(pos: Vector3, tint: Color, energy: float, reach: float):
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	add_child(light)
	light.position = pos

func temple_lantern(pos: Vector3):
	var lamp := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = Vector3(0.35,0.55,0.35)
	lamp.mesh = shape
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ffd080")
	lamp.material_override = mat
	add_child(lamp)
	lamp.position = pos
	if not OS.has_feature("mobile"):
		temple_light(pos,Color("ffc16b"),0.65,5.0)

func castle_tower(pos: Vector3, h: float, radius: float):
	var shaft := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = h
	cylinder.radial_segments = 20
	shaft.mesh = cylinder
	shaft.material_override = castle_stone(Color("65717e"))
	add_child(shaft)
	shaft.position = pos + Vector3(0,h*0.5,0)
	var roof := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.04
	cone.bottom_radius = radius*1.25
	cone.height = radius*3.0
	cone.radial_segments = 20
	roof.mesh = cone
	roof.material_override = castle_stone(Color("273e59"))
	add_child(roof)
	roof.position = pos + Vector3(0,h+radius*1.5,0)
	for i in range(6):
		var angle := TAU*float(i)/6.0
		map_box("TowerTrim",pos+Vector3(cos(angle)*radius,h-0.5,sin(angle)*radius),Vector3(0.6,1.2,0.6),Color("9b9383"),false)

func castle_portal(pos: Vector3, _destination: Vector3):
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.15
	torus.outer_radius = 2.65
	torus.rings = 32
	torus.ring_segments = 12
	ring.mesh = torus
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color("58cfff")
	rim_mat.emission_enabled = true
	rim_mat.emission = Color("249dff")
	rim_mat.emission_energy_multiplier = 2.5
	ring.material_override = rim_mat
	add_child(ring)
	ring.position = pos
	ring.rotation_degrees.x = 90
	var disc := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4.3,4.3)
	disc.mesh = quad
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment(){
 vec2 p=UV*2.0-1.0;
 float r=length(p);
 if(r>1.0){discard;}
 float a=atan(p.y,p.x);
 float spiral=pow(0.5+0.5*sin(a*5.0-r*19.0+TIME*3.0),4.0);
 float rim=exp(-pow((r-0.94)*24.0,2.0));
 float pulse=0.8+0.2*sin(TIME*3.0);
 float core=exp(-r*r*8.0);
 vec3 glow=vec3(0.04,0.22,0.65)+vec3(0.15,0.65,1.0)*(spiral*0.9+core*0.65)+vec3(0.65,0.9,1.0)*rim;
 ALBEDO=glow;
 EMISSION=glow*pulse*1.5;
}"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	disc.material_override = mat
	add_child(disc)
	disc.position = pos + Vector3(0,0,0.08)
	temple_light(pos + Vector3(0,0,1.5),Color("37baff"),2.0,9.0)
	var arcs := MeshInstance3D.new()
	var arc_quad := QuadMesh.new()
	arc_quad.size = Vector2(7.5,7.5)
	arcs.mesh = arc_quad
	var arc_shader := Shader.new()
	arc_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
void fragment(){
 vec2 p=UV*2.0-1.0;
 float r=length(p);
 float a=atan(p.y,p.x);
 float t=floor(TIME*12.0);
 float sector=floor((a+3.14159)*1.27324);
 float seed=fract(sin(sector*73.13+t*17.71)*43758.5453);
 float angle=(sector+0.5)*0.785398-3.14159;
 float zig=sin(r*65.0+seed*20.0)*0.035+sin(r*112.0+t)*0.015;
 float dist=abs(a-angle-zig);
 float arc=exp(-dist*180.0)*step(0.68,r)*step(r,0.76+seed*0.22)*step(0.35,seed);
 float sparks=pow(max(0.0,sin(a*43.0+t*2.0)*sin(r*93.0-t)),24.0)*step(0.69,r)*step(r,0.98);
 ALBEDO=vec3(0.25,0.7,1.0);
 EMISSION=vec3(0.55,0.85,1.0)*(arc*2.0+sparks);
 ALPHA=clamp(arc+sparks,0.0,1.0);
}"""
	var arc_mat := ShaderMaterial.new()
	arc_mat.shader = arc_shader
	arcs.material_override = arc_mat
	add_child(arcs)
	arcs.position = pos + Vector3(0,0,0.15)
	# Portal surfaces are traversable; map transition is handled by proximity trigger.
func map_box(label: String, pos: Vector3, size: Vector3, color: Color, solid: bool = true) -> MeshInstance3D:
	var body: Node3D = StaticBody3D.new() if solid else Node3D.new()
	body.name = label
	body.position = pos
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	mesh.material_override = castle_stone(color) if label.begins_with("Castle") or label.begins_with("Hall") or label == "Battlement" else material
	body.add_child(mesh)
	if solid:
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		collision.shape = box
		body.add_child(collision)
	add_child(body)
	return mesh

func map_fire(pos: Vector3):
	var flame := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.75
	flame.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ff7a19")
	material.emission_enabled = true
	material.emission = Color("ff4a08")
	material.emission_energy_multiplier = 2.0
	flame.material_override = material
	flame.position = pos
	add_child(flame)
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = Color("ff762a")
	light.light_energy = 1.5
	light.omni_range = 8.0
	add_child(light)

func create_portal_guard():
	var path := "res://assets/portal_guard.fbx"
	if not ResourceLoader.exists(path):
		return
	var scene = load(path)
	if not scene is PackedScene:
		return
	var guard := scene.instantiate() as Node3D
	if guard == null:
		return
	add_child(guard)
	portal_guard = guard
	guard.position = Vector3(0.0,1.1,-28.0)
	guard.rotation.y = 0.0
	# Relax the Mixamo T-pose using local upper-arm bone rotations.
	for node in guard.find_children("*","Skeleton3D",true,false):
		var skeleton := node as Skeleton3D
		for i in range(skeleton.get_bone_count()):
			var bone_name := skeleton.get_bone_name(i).to_lower().replace("_","")
			if not (bone_name.ends_with("leftarm") or bone_name.ends_with("rightarm")):
				continue
			var rest := skeleton.get_bone_global_rest(i)
			var direction := rest.basis.y.normalized()
			for child in skeleton.get_bone_children(i):
				var offset := skeleton.get_bone_global_rest(child).origin - rest.origin
				if offset.length() > 0.001:
					direction = offset.normalized()
					break
			var target := Vector3(direction.x * 0.15,-1.0,0.0).normalized()
			var delta := Quaternion(direction,target)
			var local_delta := rest.basis.orthonormalized().inverse() * Basis(delta) * rest.basis.orthonormalized()
			skeleton.set_bone_pose_rotation(i,skeleton.get_bone_pose_rotation(i) * local_delta.get_rotation_quaternion())
	var tag := Label3D.new()
	tag.text = "Guardião do Portal"
	tag.position.y = 2.2
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	guard.add_child(tag)

func create_test_monster() -> void:
	var path := "res://assets/portal_guard.fbx"
	if not ResourceLoader.exists(path):
		push_warning("Modelo do monstro de teste não encontrado.")
		return
	var scene = load(path)
	if not scene is PackedScene:
		push_warning("Não foi possível importar o modelo do monstro de teste.")
		return
	var monster := scene.instantiate() as Node3D
	if monster == null:
		return
	monster.set_script(load("res://test_monster.gd"))
	add_child(monster)
	monster.position = Vector3(2.5, 1.0, -5.0)
	monster.rotation.y = PI
	monster.scale = Vector3.ONE * 0.9
	# Baixa levemente os braços do modelo de teste para não deixá-lo em T-pose.
	for node in monster.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		for i in range(skeleton.get_bone_count()):
			var bone_name := skeleton.get_bone_name(i).to_lower().replace("_", "")
			if not (bone_name.ends_with("leftarm") or bone_name.ends_with("rightarm")):
				continue
			var rest := skeleton.get_bone_global_rest(i)
			var direction := rest.basis.y.normalized()
			for child in skeleton.get_bone_children(i):
				var offset := skeleton.get_bone_global_rest(child).origin - rest.origin
				if offset.length() > 0.001:
					direction = offset.normalized()
					break
			var target := Vector3(direction.x * 0.15, -1.0, 0.0).normalized()
			var delta := Quaternion(direction, target)
			var local_delta := rest.basis.orthonormalized().inverse() * Basis(delta) * rest.basis.orthonormalized()
			skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i) * local_delta.get_rotation_quaternion())

func create_boss_map() -> void:
	# Novo mapa aberto, com a mesma área útil (48 x 48), sem construções,
	# paredes ou pilares. Mantém somente o portal e o NPC de retorno.
	map_box("BossMapFloor",BOSS_CENTER + Vector3(0,-0.25,0),Vector3(500,0.5,500),Color("34313d"))
	castle_portal(BOSS_CENTER + Vector3(0,2.6,-12),Vector3(0,0.2,0))
	create_boss_return_guard()

func create_boss_return_guard() -> void:
	var path := "res://assets/portal_guard.fbx"
	if not ResourceLoader.exists(path):
		push_warning("Modelo do teleportador de retorno não encontrado.")
		return
	var scene = load(path)
	if not scene is PackedScene:
		return
	boss_return_guard = scene.instantiate() as Node3D
	if boss_return_guard == null:
		return
	add_child(boss_return_guard)
	boss_return_guard.position = BOSS_CENTER + Vector3(0,1.0,-9)
	boss_return_guard.rotation.y = PI
	var tag := Label3D.new()
	tag.text = "Teleportador • Voltar para Valoria"
	tag.position.y = 2.2
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	boss_return_guard.add_child(tag)

func try_guard_click(screen_pos: Vector2) -> bool:
	var chosen: Node3D = null
	var destination := ""
	var best_distance := 105.0
	for entry in [{"node":portal_guard,"destination":"bosses"},{"node":boss_return_guard,"destination":"valoria"}]:
		var guard: Node3D = entry.node
		if not is_instance_valid(guard):
			continue
		if player.global_position.distance_to(guard.global_position) > 12.0:
			continue
		var target := guard.global_position + Vector3(0,0.9,0)
		if camera.is_position_behind(target):
			continue
		var screen_distance := camera.unproject_position(target).distance_to(screen_pos)
		if screen_distance < best_distance:
			best_distance = screen_distance
			chosen = guard
			destination = str(entry.destination)
	if not is_instance_valid(chosen):
		return false
	if is_instance_valid(portal_dialog):
		portal_dialog.queue_free()
	portal_dialog = ConfirmationDialog.new()
	portal_dialog.title = "Teleportador"
	portal_dialog.dialog_text = "Viajar para o Mapa dos Bosses?" if destination == "bosses" else "Voltar para Valoria?"
	portal_dialog.ok_button_text = "Viajar" if destination == "bosses" else "Voltar"
	portal_dialog.cancel_button_text = "Cancelar"
	add_child(portal_dialog)
	portal_dialog.confirmed.connect(func(): travel_to_map(destination))
	portal_dialog.popup_centered(Vector2i(340,160))
	return true

func travel_to_map(destination: String) -> void:
	var next_map := "bosses" if destination == "bosses" else "valoria"
	if next_map == current_map:
		return
	current_map = next_map
	player.velocity = Vector3.ZERO
	click_moving = false
	auto_attack = false
	combat_target = null
	selected_remote_id = ""
	if current_map == "bosses":
		player.global_position = BOSS_CENTER + Vector3(0,0.75,0)
		# Spawn voltado para o portal/NPC de retorno.
		player.rotation.y = PI
	else:
		player.global_position = Vector3(0,0.75,0)
		player.rotation.y = 0.0
	pivot.position = player.position + Vector3(0,1.5,0)
	portal_lock_until = Time.get_ticks_msec()+2500
	if is_instance_valid(target_marker):
		target_marker.visible = false
	if net != null and net.has_method("map_changed"):
		net.map_changed()

func click_world(screen_pos: Vector2):
	var origin := camera.project_ray_origin(screen_pos)
	var end := origin+camera.project_ray_normal(screen_pos)*300.0
	var query := PhysicsRayQueryParameters3D.create(origin,end)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	combat_target = null
	var candidates := get_tree().get_nodes_in_group("attackable")
	if free_combat and is_instance_valid(net):
		for entry in net.remotes.values(): candidates.append(entry.node)
	var nearest := 45.0
	for candidate in candidates:
		if not candidate is Node3D or candidate == player: continue
		var point: Vector3 = candidate.global_position+Vector3.UP
		if camera.is_position_behind(point): continue
		var d := camera.unproject_position(point).distance_to(screen_pos)
		if d<nearest:
			nearest = d
			combat_target = candidate
	if is_instance_valid(combat_target):
		click_destination = combat_target.global_position
		click_moving = true
		auto_attack = true
	elif not hit.is_empty():
		auto_attack = false
		click_destination = hit.position
		click_moving = true
