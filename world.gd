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
var attack_cooldown := 0.0
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
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	col.shape = capsule
	col.position.y = 0.9
	player.add_child(col)
	var avatar_id := str(get_tree().get_meta("selected_avatar","whiteclown"))
	if avatar_id == "whiteclown":
		# Mantém o conjunto de animações original do personagem masculino.
		for state in ["Idle","Walking","Running","Jumping"]:
			var scene = load("res://assets/"+state+".fbx")
			if scene is PackedScene:
				var model = scene.instantiate()
				player.add_child(model)
				model.hide()
				models[state] = model
	else:
		var avatar_file: String = str({"erika_archer":"erika_archer.fbx","maria":"maria.fbx"}.get(avatar_id,"erika_archer.fbx"))
		var avatar_scene = load("res://assets/"+avatar_file)
		if avatar_scene is PackedScene:
			var avatar_model: Node3D = avatar_scene.instantiate() as Node3D
			player.add_child(avatar_model)
			models["Avatar"] = avatar_model
		else:
			push_error("Modelo não importado: "+avatar_file)
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
	if state == current: return
	current = state
	if models.has("Avatar"):
		var actor: Node3D = models["Avatar"]
		actor.show()
		var anim = actor.find_children("*","AnimationPlayer",true,false)
		if not anim.is_empty():
			var ap: AnimationPlayer = anim[0]
			var desired := ""
			var candidates := {"Idle":["Idle","idle","Standing","FreeRunning"],"Walking":["Walking","Walk","walking","FreeRunning"],"Running":["Running","Run","FreeRunning"],"Jumping":["Jumping","Jump","FreeRunning"]}
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
	if not models.has(state): return
	for key in models:
		models[key].visible = key == state
	var model = models[state]
	var anim = model.find_children("*","AnimationPlayer",true,false)
	if not anim.is_empty():
		var ap = anim[0]
		for clip in ap.get_animation_list():
			if clip != "RESET":
				ap.get_animation(clip).loop_mode = Animation.LOOP_NONE if state == "Jumping" else Animation.LOOP_LINEAR
				remove_horizontal_motion(ap, clip, state == "Jumping")
				ap.stop()
				ap.play(clip)
				break
func _unhandled_input(event):
	if not OS.has_feature("mobile") and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		attack()
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
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if is_instance_valid(net) and net.cloud_active and net.health <= 0:
		player.velocity = Vector3.ZERO
		return
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
	if player.position.y < -10: player.position = Vector3(0,0.65,0)
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

func attack():
	if attack_cooldown > 0.0 or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if is_instance_valid(net) and net.cloud_active and net.health <= 0: return
	attack_cooldown = 0.6
	if is_instance_valid(net): net.request_attack()
	attack_effect(player)
	for target in get_tree().get_nodes_in_group("attackable"):
		if target is Node3D and target.has_method("take_damage"):
			var offset: Vector3 = target.global_position - player.global_position
			if offset.length() <= 2.0 and offset.normalized().dot(player.global_transform.basis.z.normalized()) > 0.3:
				target.take_damage(10)

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
	map_box("Courtyard", Vector3(0,-0.225,0), Vector3(34,0.45,34), stone)
	map_box("TempleRoad", Vector3(0,-0.145,-18), Vector3(12,0.3,24), dark_stone)
	for i in range(6):
		map_box("RoadTile", Vector3(0,0.015,-8.0-float(i)*3.0), Vector3(11,0.02,2.7), stone, false)
	# Entrance stairs.
	# Decorative steps sit over a continuous walkable ramp; they do not block the player.
	for i in range(5):
		map_box("TempleStep", Vector3(0,0.11+float(i)*0.22,-31.9+float(i)*1.0), Vector3(13.0-float(i)*0.8,0.22,1.0), dark_stone, false)
	var ramp_body := StaticBody3D.new()
	ramp_body.name = "TempleAccessRamp"
	ramp_body.position = Vector3(0,0.55,-29.5)
	ramp_body.rotation.x = atan(1.1/6.0)
	var ramp_collision := CollisionShape3D.new()
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(12.0,0.22,6.0)
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
	castle_portal(Vector3(0,3.6,-39.2),Vector3(0,0.2,70))
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

func castle_portal(pos: Vector3, destination: Vector3):
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.15
	torus.outer_radius = 2.65
	torus.rings = 32
	torus.ring_segments = 12
	ring.mesh = torus
	ring.material_override = castle_stone(Color("65717e"))
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
 float wave=sin(a*12.0-r*22.0+TIME*2.0);
 float rim=exp(-pow((r-0.87)*18.0,2.0));
 ALBEDO=vec3(0.015,0.12,0.38)+vec3(0.15,0.65,1.0)*(rim+0.16*wave+0.18);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	disc.material_override = mat
	add_child(disc)
	disc.position = pos + Vector3(0,0,0.08)
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.1,5.2,1.4)
	shape.shape = box
	area.add_child(shape)
	add_child(area)
	area.position = pos
	area.body_entered.connect(func(body: Node3D):
		if body != player or Time.get_ticks_msec() < portal_lock_until:
			return
		portal_lock_until = Time.get_ticks_msec()+2000
		player.set_deferred("position",destination)
		player.velocity = Vector3.ZERO
	)

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
