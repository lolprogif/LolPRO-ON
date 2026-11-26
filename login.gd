extends Control
var endpoint: LineEdit
var user: LineEdit
var email: LineEdit
var password: LineEdit
var character: LineEdit
var status: Label
var req := HTTPRequest.new()
var update_req := HTTPRequest.new()
var latest_version := ""
var update_manifest: Dictionary = {}
var action := ""
var token := ""
var settings := ConfigFile.new()
var language: OptionButton
var title_label: Label
var discovery := PacketPeerUDP.new()
var discovery_left := 0.0
func _ready():
	add_child(req)
	req.timeout = 12
	req.request_completed.connect(done)
	add_child(update_req)
	update_req.timeout = 15
	update_req.request_completed.connect(_on_update_manifest)
	var bg := ColorRect.new()
	bg.color = Color("17252e")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440,0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("30271f")
	style.border_color = Color("b69a60")
	style.set_border_width_all(2)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel",style)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation",8)
	panel.add_child(v)
	title_label = Label.new()
	title_label.text = "LolPRO-ON • V0.9"
	title_label.add_theme_font_size_override("font_size",26)
	v.add_child(title_label)
	language = OptionButton.new()
	for s in ["Brasil • Português", "International • English", "España • Español"]: language.add_item(s)
	v.add_child(language)
	endpoint = field(v,"Servidor / Server","http://127.0.0.1:8080" if not OS.has_feature("mobile") else "http://192.168.1.100:8080")
	settings.load("user://login.cfg")
	endpoint.text = str(settings.get_value("login","server",endpoint.text))
	button(v,"Localizar servidor",find_server)
	var channel := Label.new()
	channel.text = "Servidor de teste / Test server • CH1"
	v.add_child(channel)
	user = field(v,"Usuário / Username")
	user.text = str(settings.get_value("login","username",""))
	email = field(v,"E-mail (cadastro / registration)")
	password = field(v,"Senha / Password")
	password.secret = true
	button(v,"Criar conta / Register",func(): send("register",{"username":user.text,"email":email.text,"password":password.text}))
	button(v,"Entrar / Login",func(): send("login",{"username":user.text,"password":password.text}))
	character = field(v,"Nome do personagem / Character name")
	button(v,"Salvar personagem e jogar / Save & play",func():
		if token.is_empty(): status.text = "Entre na conta primeiro / Login first"
		else: send("character",{"token":token,"character":character.text}))
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Teste local • use uma senha exclusiva de teste."
	v.add_child(status)
	button(v,"Verificar atualizações",check_for_updates)
	button(v,"Baixar atualização / Instalar APK",download_update)
	button(v,"Abrir Google Play",func(): OS.shell_open("https://play.google.com/store/apps/details?id=com.rpg.mundointernacional"))
	check_for_updates()
	button(v,"Modo offline / Offline",func():
		get_tree().remove_meta("online_endpoint")
		get_tree().change_scene_to_file("res://World.tscn"))
	if OS.has_feature("mobile"):
		find_server()
func find_server():
	if not OS.has_feature("mobile"):
		endpoint.text = "http://127.0.0.1:8080"
		return
	discovery.close()
	if discovery.bind(0) != OK:
		status.text = "Não foi possível procurar o servidor."
		return
	discovery.set_broadcast_enabled(true)
	discovery.set_dest_address("255.255.255.255",8081)
	discovery.put_packet("LOLPRO_DISCOVER_V1".to_utf8_buffer())
	discovery_left = 4.0
	status.text = "Procurando servidor na rede local..."
func _process(delta):
	if discovery_left <= 0.0: return
	discovery_left -= delta
	while discovery.get_available_packet_count() > 0:
		var packet := discovery.get_packet()
		if packet.get_string_from_utf8() == "LOLPRO_SERVER_V1":
			endpoint.text = "http://" + discovery.get_packet_ip() + ":8080"
			status.text = "Servidor localizado. Confira o endereço antes de entrar."
			discovery_left = 0.0
			discovery.close()
			return
	if discovery_left <= 0.0:
		discovery.close()
		status.text = "Servidor não localizado. Confira o Wi-Fi ou informe o IP manualmente."
func field(v: VBoxContainer,hint: String,value: String = "") -> LineEdit:
	var f := LineEdit.new()
	f.placeholder_text = hint
	f.text = value
	v.add_child(f)
	return f
func button(v: VBoxContainer,label: String,cb: Callable):
	var b := Button.new()
	b.text = label
	v.add_child(b)
	b.pressed.connect(cb)
func send(a: String,data: Dictionary):
	if req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED: return
	action = a
	status.text = "Conectando / Connecting..."
	var err := req.request(endpoint.text.strip_edges().trim_suffix("/")+"/"+a,["Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify(data))
	if err != OK: status.text = "Erro / Request error"
func done(result: int,code: int,_headers: PackedStringArray,body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.text = "Servidor indisponível / Server unavailable"
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary or not d.get("ok",false):
		status.text = str(d.get("error","Error")) if d is Dictionary else "Invalid response"
		return
	if action == "register": status.text = "Conta criada! Faça login / Account created"
	elif action == "login":
		token = d.token
		settings.set_value("login","server",endpoint.text.strip_edges())
		settings.set_value("login","username",user.text)
		settings.save("user://login.cfg")
		character.text = d.character
		password.clear()
		status.text = "Escolha seu personagem / Choose character"
	elif action == "character":
		get_tree().set_meta("online_endpoint",endpoint.text.strip_edges())
		get_tree().change_scene_to_file("res://World.tscn")

const MANIFEST_URL := "https://raw.githubusercontent.com/lolprogif/LolPRO-ON/main/latest.json"
const CURRENT_VERSION := "0.9"

func check_for_updates():
	status.text = "Verificando atualizações..."
	var error := update_req.request(MANIFEST_URL)
	if error != OK:
		status.text = "Não foi possível consultar atualizações. Confira a conexão."

func _on_update_manifest(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status.text = "Não foi possível verificar atualizações. Tente novamente mais tarde."
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.has("version"):
		status.text = "Arquivo de versões inválido."
		return
	update_manifest = parsed
	latest_version = str(parsed.get("version",""))
	if latest_version == CURRENT_VERSION or latest_version.is_empty():
		status.text = "Você já está na versão " + CURRENT_VERSION + "."
	else:
		status.text = "Nova versão disponível: " + latest_version + ". Toque em Baixar atualização."

func download_update():
	if update_manifest.is_empty():
		status.text = "Primeiro toque em Verificar atualizações."
		return
	var url := str(update_manifest.get("android_url","")) if OS.has_feature("mobile") else str(update_manifest.get("windows_url",""))
	if url.is_empty():
		status.text = "Download ainda não publicado para esta plataforma."
		return
	OS.shell_open(url)
	status.text = "Download aberto. Siga a confirmação do sistema para instalar."
