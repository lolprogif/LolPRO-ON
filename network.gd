extends Node
var world: Node3D
var status: Label
var address: LineEdit
var remotes := {}
var elapsed := 0.0
const PORT := 7000
var cloud_url := ""
var cloud_token := ""
var cloud_request := HTTPRequest.new()
var cloud_active := false
var attack_seq := ""
var attack_target_id := ""
var potion_seq := ""
var item_seq := ""
var item_action := ""
var generation := 0
var health := 100
var remote_attacks := {}
var skill_seq := ""
var skill_index := -1
var skill_events := {}
var skill_buttons: Array[Button] = []
var mana_label: Label
var skill_level := 1
var skill_class := "Guerreiro"
var skill_mana := 100
var skill_cooldowns := [0,0,0,0,0,0]
func _ready():
	add_child(cloud_request)
	cloud_request.timeout = 90
	cloud_request.request_completed.connect(cloud_done)
	multiplayer.peer_disconnected.connect(remove_remote)
	multiplayer.connected_to_server.connect(func(): status.text = "Conectado")
	multiplayer.connection_failed.connect(func(): leave(); status.text = "Falha na conexão")
	multiplayer.server_disconnected.connect(func(): leave(); status.text = "Servidor desconectado")
	var hud = world.get_children().filter(func(n): return n is CanvasLayer)[0]
	var panel: VBoxContainer = hud.window("Rede",Vector2(340,240))
	status = hud.label(panel,"Offline • teste em rede local")
	address = LineEdit.new()
	address.placeholder_text = "IP do computador anfitrião"
	address.text = "127.0.0.1"
	panel.add_child(address)
	if not get_tree().has_meta("online_endpoint"):
		hud.button(panel,"Hospedar (UDP 7000)",host)
	hud.button(panel,"Conectar",join)
	hud.button(panel,"Desconectar",leave)
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	var b := Button.new()
	b.text = "Rede"
	b.position = Vector2(12,125)
	layer.add_child(b)
	b.pressed.connect(func(): hud.toggle("Rede"))
	mana_label = Label.new()
	layer.add_child(mana_label)
	mana_label.hide()
	for i in range(6):
		var skill_button: Button = hud.quick_buttons[i]
		skill_buttons.append(skill_button)
		skill_button.pressed.connect(request_skill.bind(i))
	var admin = preload("res://admin_panel.gd").new()
	admin.net = self
	layer.add_child(admin)
	var voice = preload("res://voice.gd").new()
	voice.net = self
	add_child(voice)
	var controls = preload("res://touch.gd").new()
	controls.world = world
	layer.add_child(controls)
	if get_tree().has_meta("online_endpoint"):
		cloud_url = str(get_tree().get_meta("online_endpoint")).trim_suffix("/")
		cloud_token = str(get_tree().get_meta("online_token",""))
		address.text = cloud_url
		address.editable = false
		if cloud_token.is_empty():
			status.text = "Sessão ausente. Feche o jogo e entre novamente."
			return
		cloud_active = true
		status.text = "Conectando ao mundo online..."

func host():
	if not cloud_url.is_empty():
		status.text = "Use Conectar para o mundo online"
		return
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT,8)
	if err != OK:
		status.text = "Erro ao hospedar: %s" % err
		return
	multiplayer.multiplayer_peer = peer
	status.text = "Hospedando • porta 7000"
func join():
	leave()
	if not cloud_url.is_empty():
		if cloud_token.is_empty():
			status.text = "Sessão ausente. Entre novamente."
			return
		cloud_active = true
		status.text = "Conectando ao mundo online..."
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.text.strip_edges(),PORT)
	if err != OK:
		status.text = "Erro ao conectar: %s" % err
		return
	multiplayer.multiplayer_peer = peer
	status.text = "Conectando..."
func leave():
	cloud_active = false
	cloud_request.cancel_request()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	for id in remotes.keys():
		remove_remote(id)
	status.text = "Offline"
func remove_remote(id):
	if remotes.has(id):
		remotes[id].node.queue_free()
		remotes.erase(id)
func _process(delta):
	for r in remotes.values():
		r.node.position = r.node.position.lerp(r.target, minf(1.0,delta*15.0))
		r.node.rotation.y = lerp_angle(r.node.rotation.y,r.angle,minf(1.0,delta*15.0))
	elapsed += delta
	if elapsed < (0.25 if cloud_active else 0.05): return
	elapsed = 0.0
	if cloud_active:
		if cloud_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
			var p: Vector3 = world.player.position
			var payload := {"token":cloud_token,"map_id":world.current_map,"pos":[p.x,p.y,p.z],"angle":world.player.rotation.y,"state":world.current,"attack":attack_seq,"target_id":attack_target_id,"free_combat":world.free_combat,"potion":potion_seq,"generation":generation,"item":item_seq,"item_action":item_action,"skill_seq":skill_seq,"skill_index":skill_index}
			var err := cloud_request.request(cloud_url+"/world",["Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify(payload))
			if err != OK: status.text = "Falha na conexão online"
		return
	if not multiplayer.has_multiplayer_peer(): return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return
	if multiplayer.is_server():
		broadcast.rpc(1,world.player.position,world.player.rotation.y,world.current)
	else:
		submit.rpc_id(1,world.player.position,world.player.rotation.y,world.current)
@rpc("any_peer","call_remote","unreliable_ordered")
func submit(pos: Vector3, angle: float, state: String):
	if not multiplayer.is_server(): return
	var id := multiplayer.get_remote_sender_id()
	if not pos.is_finite() or not is_finite(angle) or pos.length() > 150.0: return
	update_remote(id,pos,angle,state)
	broadcast.rpc(id,pos,angle,state)
@rpc("authority","call_remote","unreliable_ordered")
func broadcast(id: int,pos: Vector3,angle: float,state: String):
	if id != multiplayer.get_unique_id(): update_remote(id,pos,angle,state)
func update_remote(id,pos: Vector3,angle: float,state: String,display_name: String = "", avatar: String = "whiteclown"):
	if not state in ["Idle","Walking","Running","Jumping"]: return
	if not remotes.has(id):
		var n := Node3D.new()
		world.add_child(n)
		n.position = pos
		var tag := Label3D.new()
		tag.text = display_name if not display_name.is_empty() else "Jogador %s" % str(id)
		tag.position.y = 2.1
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		n.add_child(tag)
		remotes[id] = {"node":n,"target":pos,"angle":angle,"state":"","model":null}
	var r: Dictionary = remotes[id]
	r.target = pos
	r.angle = angle
	if not display_name.is_empty():
		r.name = display_name.split(" • ")[0]
		var hp_text := display_name.get_slice(" • ",1).replace(" HP","")
		if hp_text.is_valid_int():
			r.hp = int(hp_text)
	if r.state == state and r.get("avatar","") == avatar: return
	if is_instance_valid(r.model): r.model.queue_free()
	var model_path: String = str({"sura":"res://sura_male_novice.glb","warrior_m":"res://warrior_m_4-1.glb","erika_archer":"res://assets/erika_archer.fbx","maria":"res://assets/maria.fbx"}.get(avatar,"res://assets/"+state+".fbx"))
	var model = load(model_path).instantiate()
	r.avatar = avatar
	r.node.add_child(model)
	r.model = model
	r.state = state
	var aps = model.find_children("*","AnimationPlayer",true,false)
	if not aps.is_empty():
		var ap: AnimationPlayer = aps[0]
		for clip in ap.get_animation_list():
			if clip == "RESET": continue
			world.remove_horizontal_motion(ap,clip,state == "Jumping")
			ap.get_animation(clip).loop_mode = Animation.LOOP_NONE if state == "Jumping" else Animation.LOOP_LINEAR
			ap.play(clip)
			break

func cloud_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	if not cloud_active: return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		var detail := body.get_string_from_utf8().substr(0,180)
		status.text = "Falha no mundo • conexão %d • HTTP %d • %s" % [result,code,detail]
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("ok",false):
		status.text = "Falha no mundo online: " + str(data.get("error","resposta inválida")) if data is Dictionary else "Resposta inválida do servidor"
		return
	var own: Dictionary = data.get("self",{})
	if not own.is_empty():
		health = int(own.get("hp",100))
		skill_level = int(own.get("level",1))
		skill_class = str(own.get("class","Guerreiro"))
		skill_mana = int(own.get("mana",100))
		skill_cooldowns = own.get("cooldowns",[0,0,0,0,0,0])
		mana_label.text = "MP %d/100" % skill_mana
		world.get_children().filter(func(n): return n is CanvasLayer)[0].mana_bar.value = skill_mana
		var catalog: Array = preload("res://class_skills.gd").skills_for(skill_class)
		for i in range(6):
			skill_buttons[i].disabled = skill_level < [5,8,10,12,15,20][i] or float(skill_cooldowns[i]) > 0 or skill_mana < 10+i*3
			skill_buttons[i].tooltip_text = str(catalog[i][0]) if catalog.size()>i else ""
			skill_buttons[i].text = str(i+1) if float(skill_cooldowns[i]) <= 0 else str(ceili(float(skill_cooldowns[i])))
		if own.get("skill_ack","") == skill_seq: skill_seq = ""
		show_skill_event("self",world.player,own,skill_class)
		var hud = world.get_children().filter(func(n): return n is CanvasLayer)[0]
		hud.hp = health
		hud.potions = int(own.get("potions",5))
		world.show_gear(world.player,own)
		hud.apply_progress(own)
		if str(own.get("item_seq","")) == item_seq: item_seq = ""; item_action = ""
		hud.refresh()
		var next_generation := int(own.get("generation",0))
		if next_generation != generation:
			generation = next_generation
			world.player.position = Vector3(0,0.1,0)
			world.player.velocity = Vector3.ZERO
	var seen := {}
	for item in data.get("players",[]):
		var id := str(item["id"])
		var p: Array = item["pos"]
		seen[id] = true
		update_remote(id,Vector3(float(p[0]),float(p[1]),float(p[2])),float(item["angle"]),str(item["state"]),str(item["name"])+" • "+str(item.get("hp",100))+" HP",str(item.get("avatar","whiteclown")))
		if remotes.has(id):
			var node: Node3D = remotes[id].node
			world.show_gear(node,item)
			show_remote_pet(node,item.get("pet",{}))
			show_skill_event(id,node,item,str(item.get("class_name","Guerreiro")))
			for child in node.get_children():
				if child is Label3D: child.text = str(item["name"])+" • "+str(item.get("hp",100))+" HP"
			var seq := str(item.get("attack_seq",""))
			if remote_attacks.has(id) and remote_attacks[id] != seq and not seq.is_empty(): world.attack_effect(node)
			remote_attacks[id] = seq
	for id in remotes.keys():
		if not seen.has(id): remove_remote(id)
	status.text = "Online HTTPS • %d jogador(es)" % (seen.size()+1)

func map_changed() -> void:
	elapsed = 1.0
	for id in remotes.keys():
		remove_remote(id)

func request_attack(target_id: String = ""):
	if cloud_active and health > 0:
		attack_target_id = target_id
		attack_seq = str(Time.get_ticks_usec())+"-"+str(randi())
func request_potion():
	if cloud_active: potion_seq = str(Time.get_ticks_usec())+"-"+str(randi())

func request_item(cmd: String):
	if cloud_active and item_seq.is_empty():
		item_action = cmd
		item_seq = str(Time.get_ticks_usec())+"-"+str(randi())

func request_skill(index: int):
	if cloud_active and health > 0 and skill_seq.is_empty() and not skill_buttons[index].disabled:
		skill_index = index
		skill_seq = str(Time.get_ticks_usec())+"-"+str(randi())

func _unhandled_key_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_6:
		request_skill(event.keycode-KEY_1)

func show_skill_event(id: String, actor: Node3D, data: Dictionary, cl: String):
	var seq := str(data.get("skill_event",""))
	if seq.is_empty() or skill_events.get(id,"") == seq: return
	skill_events[id] = seq
	world.attack_effect(actor)
	var effect := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.8
	ring.outer_radius = 1.0
	effect.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = {"Guerreiro":Color.ORANGE_RED,"Shura":Color.MEDIUM_PURPLE,"Ninja":Color.SEA_GREEN,"Xamã":Color.GOLD}.get(cl,Color.WHITE)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	effect.material_override = mat
	actor.add_child(effect)
	effect.position.y = 0.3
	var tween := create_tween()
	tween.tween_property(effect,"scale",Vector3(3,1,3),0.55)
	tween.tween_callback(effect.queue_free)

func show_remote_pet(actor: Node3D, data: Dictionary):
	var pet := actor.get_node_or_null("StarterPet") as Node3D
	if not bool(data.get("summoned",false)):
		if is_instance_valid(pet): pet.hide()
		return
	if not is_instance_valid(pet):
		pet = Node3D.new()
		pet.name = "StarterPet"
		actor.add_child(pet)
		pet.position = Vector3(1.2,0.6,1.0)
		for i in range(5):
			var part := MeshInstance3D.new()
			part.mesh = SphereMesh.new()
			part.position = [Vector3.ZERO,Vector3(0,0.2,-0.25),Vector3(-0.32,0.12,0),Vector3(0.32,0.12,0),Vector3(0,0,0.38)][i]
			part.scale = [Vector3(0.64,0.48,0.9),Vector3(0.44,0.44,0.44),Vector3(0.6,0.12,0.48),Vector3(0.6,0.12,0.48),Vector3(0.18,0.18,0.7)][i]
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("d9a344")
			part.material_override = mat
			pet.add_child(part)
	pet.show()
	pet.scale = Vector3.ONE * (1.0+float(int(data.get("level",1))-1)/100.0)
