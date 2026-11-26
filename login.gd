extends Control
var endpoint: LineEdit
var user: LineEdit
var email: LineEdit
var password: LineEdit
var character: LineEdit
var status: Label
var req := HTTPRequest.new()
var update_req := HTTPRequest.new()
var remember_user: CheckBox
var create_window: Window
var register_user: LineEdit
var register_email: LineEdit
var register_password: LineEdit
var register_confirm: LineEdit
const CURRENT_VERSION := "0.9.0"
const UPDATE_MANIFEST := "https://raw.githubusercontent.com/lolprogif/LolPRO-ON/main/latest.json"
var action := ""
var token := ""
var login_center: CenterContainer
var selected_slot := 0
var slot_names := {}
var slot_profiles := {}
var selection: CenterContainer
var loading := false
var progress: ProgressBar
var loading_label: Label
var fade: ColorRect
var preview_stage: Node3D
var preview_actor: Node3D
var preview_camera: Camera3D
var settings := ConfigFile.new()
var language: OptionButton
var title_label: Label
var discovery := PacketPeerUDP.new()
var discovery_left := 0.0
func _ready():
	add_child(req)
	req.timeout = 90
	req.request_completed.connect(done)
	add_child(update_req)
	update_req.timeout = 20
	update_req.request_completed.connect(update_manifest_done)
	var bg := ColorRect.new()
	bg.color = Color("17252e")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	login_center = center
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
	endpoint = LineEdit.new()
	endpoint.text = "https://lolpro-on.onrender.com"
	settings.load("user://login.cfg")
	endpoint.text = "https://lolpro-on.onrender.com"
	user = field(v,"Usuário")
	user.text = str(settings.get_value("login","username",""))
	password = field(v,"Senha")
	password.secret = true
	remember_user = CheckBox.new()
	remember_user.text = "Lembrar meu usuário neste dispositivo"
	remember_user.button_pressed = bool(settings.get_value("login","remember_user",true))
	v.add_child(remember_user)
	button(v,"Entrar",func(): send("login",{"username":user.text,"password":password.text}))
	button(v,"Criar conta",open_register_window)
	status = Label.new()
	status.name = "LoginStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Entre com sua conta ou crie uma nova."
	v.add_child(status)
	button(v,"Atualizar jogo",check_for_updates)
	button(v,"Baixar jogo / Download",func(): OS.shell_open("https://lolprogif.github.io/LolPRO-ON/"))
	button(v,"Modo offline / Offline",func():
		get_tree().remove_meta("online_endpoint")
		get_tree().remove_meta("online_token")
		get_tree().remove_meta("hud_profile")
		get_tree().change_scene_to_file("res://World.tscn"))
	
func open_register_window():
	if is_instance_valid(create_window):
		create_window.popup_centered()
		return
	create_window = Window.new()
	create_window.title = "Criar conta • LolPRO-ON"
	create_window.size = Vector2i(420, 390)
	create_window.transient = true
	create_window.exclusive = true
	add_child(create_window)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	create_window.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "Nova conta"
	heading.add_theme_font_size_override("font_size", 22)
	box.add_child(heading)
	register_email = field(box, "E-mail")
	register_user = field(box, "Usuário (3 a 24 caracteres)")
	register_password = field(box, "Senha (mínimo 8 caracteres)")
	register_password.secret = true
	register_confirm = field(box, "Confirmar senha")
	register_confirm.secret = true
	var create_button := Button.new()
	create_button.text = "Criar conta"
	box.add_child(create_button)
	create_button.pressed.connect(submit_registration)
	var cancel_button := Button.new()
	cancel_button.text = "Cancelar"
	box.add_child(cancel_button)
	cancel_button.pressed.connect(create_window.hide)
	create_window.popup_centered()

func submit_registration():
	if register_password.text != register_confirm.text:
		status.text = "As senhas não conferem."
		return
	if register_email.text.strip_edges().is_empty() or register_user.text.strip_edges().is_empty() or register_password.text.length() < 8:
		status.text = "Preencha e-mail, usuário e senha (mínimo 8 caracteres)."
		return
	user.text = register_user.text.strip_edges()
	password.text = register_password.text
	send("register", {"username":register_user.text, "email":register_email.text, "password":register_password.text})

func check_for_updates():
	if update_req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED: return
	status.text = "Verificando atualizações..."
	var err := update_req.request(UPDATE_MANIFEST, ["Cache-Control: no-cache"])
	if err != OK: status.text = "Não foi possível consultar as atualizações."

func update_manifest_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.text = "Não foi possível consultar a versão. Tente novamente."
		return
	var manifest = JSON.parse_string(body.get_string_from_utf8())
	if not manifest is Dictionary:
		status.text = "Manifesto de atualização inválido."
		return
	var latest := str(manifest.get("version", ""))
	if latest.is_empty() or manifest.get("status", "") != "published":
		status.text = "Nenhuma atualização publicada no momento."
		return
	if latest == CURRENT_VERSION:
		status.text = "Seu jogo já está atualizado (v%s)." % CURRENT_VERSION
		return
	var download_url := str(manifest.get("windows_url" if OS.get_name() == "Windows" else "android_url", ""))
	if download_url.is_empty():
		status.text = "Nova versão %s encontrada, mas o pacote ainda não foi publicado." % latest
		return
	if OS.get_name() == "Windows":
		start_windows_update(download_url, latest)
	elif OS.has_feature("android"):
		status.text = "Nova versão %s encontrada. Abrindo o download; confirme a instalação do APK." % latest
		OS.shell_open(download_url)
	else:
		status.text = "Nova versão encontrada: %s. Baixe pelo site oficial." % latest
		OS.shell_open("https://lolprogif.github.io/LolPRO-ON/")

func start_windows_update(download_url: String, latest: String):
	var exe_path := OS.get_executable_path()
	var install_dir := exe_path.get_base_dir()
	var exe_name := exe_path.get_file()
	var updater := install_dir.path_join("update_windows.ps1")
	if not FileAccess.file_exists(updater):
		status.text = "Atualizador não encontrado nesta instalação. Baixe o pacote completo."
		return
	var args := ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", updater, "-ZipUrl", download_url, "-InstallDir", install_dir, "-ExeName", exe_name]
	var pid := OS.create_process("powershell.exe", args)
	if pid <= 0:
		status.text = "Não foi possível iniciar o atualizador."
		return
	status.text = "Atualizando para v%s. O jogo será fechado e reaberto." % latest
	get_tree().quit()
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
	if loading:
		var values := []
		var state := ResourceLoader.load_threaded_get_status("res://World.tscn",values)
		if not values.is_empty(): progress.value = float(values[0])*100.0
		if state == ResourceLoader.THREAD_LOAD_LOADED:
			loading = false
			progress.value = 100
			var scene := ResourceLoader.load_threaded_get("res://World.tscn") as PackedScene
			await get_tree().create_timer(0.5).timeout
			get_tree().change_scene_to_packed(scene)
		elif state == ResourceLoader.THREAD_LOAD_FAILED or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			loading = false
			loading_label.text = "Falha ao carregar. Reinicie o jogo."
		return
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
	if action == "register":
		if is_instance_valid(create_window): create_window.hide()
		status.text = "Conta criada! Agora entre com usuário e senha."
	elif action == "login":
		token = d.token
		settings.set_value("login","server",endpoint.text.strip_edges())
		settings.set_value("login","remember_user",remember_user.button_pressed)
		settings.set_value("login","username",user.text if remember_user.button_pressed else "")
		settings.save("user://login.cfg")
		password.clear()
		show_selection(d.get("characters",[]),str(d.get("character","")))
	elif action == "character":
		get_tree().set_meta("online_endpoint",endpoint.text.strip_edges())
		get_tree().set_meta("online_token",token)
		get_tree().set_meta("hud_profile",user.text.strip_edges().to_lower())
		start_loading()

func show_selection(items: Array, legacy: String):
	login_center.hide()
	slot_names.clear()
	slot_profiles.clear()
	for item in items:
		slot_names[int(item.get("slot",0))] = str(item.get("name",""))
		slot_profiles[int(item.get("slot",0))] = item
	if slot_names.is_empty() and not legacy.is_empty(): slot_names[0] = legacy
	selection = CenterContainer.new()
	add_child(selection)
	selection.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480,0)
	selection.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var heading := Label.new()
	heading.text = "LolPRO-ON  |  Escolha seu personagem"
	heading.add_theme_font_size_override("font_size",26)
	v.add_child(heading)
	build_preview(v)
	var slots := OptionButton.new()
	for i in range(4):
		slots.add_item("%d  •  %s" % [i+1,slot_names.get(i,"Criar personagem")],i)
	v.add_child(slots)
	character = field(v,"Nome do novo personagem")
	var classes := OptionButton.new()
	for cl in ["Guerreiro","Shura","Ninja","Xamã"]: classes.add_item(cl)
	v.add_child(classes)
	var genders := OptionButton.new()
	genders.add_item("Masculino")
	genders.add_item("Feminino")
	v.add_child(genders)
	var preview := Label.new()
	preview.text = "Aventureiro • Campo inicial"
	v.add_child(preview)
	var choose := func(index: int):
		selected_slot = index
		character.text = str(slot_names.get(index,""))
		character.editable = not slot_names.has(index)
		var profile: Dictionary = slot_profiles.get(index,{})
		classes.select(maxi(0,["Guerreiro","Shura","Ninja","Xamã"].find(profile.get("class","Guerreiro"))))
		genders.select(1 if profile.get("gender","Masculino") == "Feminino" else 0)
		classes.disabled = slot_names.has(index)
		genders.disabled = slot_names.has(index)
		preview.text = "Aventureiro • "+character.text if slot_names.has(index) else "Novo aventureiro"
	slots.item_selected.connect(choose)
	choose.call(0)
	button(v,"Entrar no mundo",func():
		if character.text.strip_edges().length()<3:
			status.text = "Digite um nome com pelo menos 3 caracteres."
			return
		send("character",{"token":token,"slot":selected_slot,"character":character.text.strip_edges(),"class":classes.get_item_text(classes.selected),"gender":genders.get_item_text(genders.selected)}))
	button(v,"Voltar",func():
		token = ""
		selection.queue_free()
		login_center.show()
		status = login_center.find_child("LoginStatus",true,false) as Label
		if status: status.text = "Entre com sua conta.")
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status)
func start_loading():
	if is_instance_valid(preview_actor):
		play_preview("Walking")
		var cinematic := create_tween().set_parallel(true)
		cinematic.tween_property(preview_actor,"position:z",1.1,1.2)
		cinematic.tween_property(preview_camera,"position",Vector3(0.7,1.5,3.0),1.2)
		await cinematic.finished
	selection.hide()
	fade = ColorRect.new()
	fade.color = Color("101b29")
	add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var c := CenterContainer.new()
	fade.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(400,0)
	c.add_child(v)
	loading_label = Label.new()
	loading_label.text = "A jornada de "+character.text+" começa..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(loading_label)
	progress = ProgressBar.new()
	v.add_child(progress)
	fade.modulate.a = 0.0
	create_tween().tween_property(fade,"modulate:a",1.0,0.7)
	await get_tree().create_timer(0.8).timeout
	if ResourceLoader.load_threaded_request("res://World.tscn") == OK:
		loading = true
	else:
		loading_label.text = "Não foi possível iniciar o carregamento."

func build_preview(parent: VBoxContainer):
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(440,260)
	container.stretch = true
	parent.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	preview_stage = Node3D.new()
	viewport.add_child(preview_stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("182332")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("aabbdc")
	env.environment.ambient_light_energy = 0.7
	preview_stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-35,0)
	preview_stage.add_child(light)
	var pedestal := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.15
	cylinder.height = 0.2
	pedestal.mesh = cylinder
	pedestal.position.y = -0.1
	preview_stage.add_child(pedestal)
	preview_camera = Camera3D.new()
	preview_stage.add_child(preview_camera)
	preview_camera.position = Vector3(0,1.35,4.2)
	preview_camera.look_at(Vector3(0,0.95,0))
	preview_camera.current = true
	play_preview("Idle")
func play_preview(state: String):
	var scene = load("res://assets/"+state+".fbx")
	if not scene is PackedScene: return
	if is_instance_valid(preview_actor): preview_actor.queue_free()
	preview_actor = scene.instantiate() as Node3D
	preview_stage.add_child(preview_actor)
	for node in preview_actor.find_children("*","AnimationPlayer",true,false):
		var ap: AnimationPlayer = node
		for clip in ap.get_animation_list():
			if clip == "RESET": continue
			ap.play(clip)
			break
