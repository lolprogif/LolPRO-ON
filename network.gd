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
var potion_seq := ""
var generation := 0
var health := 100
var remote_attacks := {}
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
	var voice = preload("res://voice.gd").new()
	voice.net = self
	add_child(voice)
	if OS.has_feature("mobile"):
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
			var payload := {"token":cloud_token,"pos":[p.x,p.y,p.z],"angle":world.player.rotation.y,"state":world.current,"attack":attack_seq,"potion":potion_seq,"generation":generation}
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
func update_remote(id,pos: Vector3,angle: float,state: String,display_name: String = ""):
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
	if r.state == state: return
	if is_instance_valid(r.model): r.model.queue_free()
	var model = load("res://assets/"+state+".fbx").instantiate()
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
		status.text = "HTTPS: erro %d / HTTP %d. Reconectando..." % [result,code]
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("ok",false):
		status.text = "Falha no mundo online"
		return
	var own: Dictionary = data.get("self",{})
	if not own.is_empty():
		health = int(own.get("hp",100))
		var hud = world.get_children().filter(func(n): return n is CanvasLayer)[0]
		hud.hp = health
		hud.potions = int(own.get("potions",5))
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
		update_remote(id,Vector3(float(p[0]),float(p[1]),float(p[2])),float(item["angle"]),str(item["state"]),str(item["name"])+" • "+str(item.get("hp",100))+" HP")
		if remotes.has(id):
			var node: Node3D = remotes[id].node
			for child in node.get_children():
				if child is Label3D: child.text = str(item["name"])+" • "+str(item.get("hp",100))+" HP"
			var seq := str(item.get("attack_seq",""))
			if remote_attacks.has(id) and remote_attacks[id] != seq and not seq.is_empty(): world.attack_effect(node)
			remote_attacks[id] = seq
	for id in remotes.keys():
		if not seen.has(id): remove_remote(id)
	status.text = "Online HTTPS • %d jogador(es)" % (seen.size()+1)

func request_attack():
	if cloud_active and health > 0: attack_seq = str(Time.get_ticks_usec())+"-"+str(randi())
func request_potion():
	if cloud_active: potion_seq = str(Time.get_ticks_usec())+"-"+str(randi())
