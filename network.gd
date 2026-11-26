extends Node
var world: Node3D
var status: Label
var address: LineEdit
var remotes := {}
var elapsed := 0.0
const PORT := 7000
func _ready():
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
	if OS.has_feature("mobile"):
		var controls = preload("res://touch.gd").new()
		controls.world = world
		layer.add_child(controls)
func host():
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
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.text.strip_edges(),PORT)
	if err != OK:
		status.text = "Erro ao conectar: %s" % err
		return
	multiplayer.multiplayer_peer = peer
	status.text = "Conectando..."
func leave():
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	for id in remotes.keys():
		remove_remote(id)
	status.text = "Offline"
func remove_remote(id: int):
	if remotes.has(id):
		remotes[id].node.queue_free()
		remotes.erase(id)
func _process(delta):
	for r in remotes.values():
		r.node.position = r.node.position.lerp(r.target, minf(1.0,delta*15.0))
		r.node.rotation.y = lerp_angle(r.node.rotation.y,r.angle,minf(1.0,delta*15.0))
	elapsed += delta
	if elapsed < 0.05: return
	elapsed = 0.0
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
func update_remote(id: int,pos: Vector3,angle: float,state: String):
	if not state in ["Idle","Walking","Running","Jumping"]: return
	if not remotes.has(id):
		var n := Node3D.new()
		world.add_child(n)
		n.position = pos
		var tag := Label3D.new()
		tag.text = "Jogador %d" % id
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
