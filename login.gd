extends Control
var endpoint: LineEdit
var user: LineEdit
var email: LineEdit
var password: LineEdit
var character: LineEdit
var status: Label
var req := HTTPRequest.new()
var update_req := HTTPRequest.new()
var update_download_req := HTTPRequest.new()
var update_download_path := ""
var update_latest := ""
var update_download_active := false
var update_progress_box: VBoxContainer
var update_progress_label: Label
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
var login_layout: HBoxContainer
var selected_slot := 0
var slot_names := {}
var slot_profiles := {}
var selection: Control
var loading := false
var progress: ProgressBar
var loading_label: Label
var fade: ColorRect
var preview_class := 0
var preview_gender := 0
var preview_avatar := "whiteclown"
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
	add_child(update_download_req)
	update_download_req.timeout = 300
	update_download_req.request_completed.connect(update_download_done)

	var bg := ColorRect.new()
	bg.color = Color("101b25")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var wallpaper := TextureRect.new()
	wallpaper.name = "LoginWallpaper"
	wallpaper.texture = load("res://assets/login_background.jpg")
	wallpaper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wallpaper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wallpaper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wallpaper)
	if wallpaper.texture != null:
		var source_size := wallpaper.texture.get_size()
		var artwork := AtlasTexture.new()
		artwork.atlas = wallpaper.texture
		artwork.region = Rect2(Vector2.ZERO, Vector2(source_size.x * 0.68, source_size.y))
		wallpaper.texture = artwork
	var layout := HBoxContainer.new()
	login_layout = layout
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_bottom = -64
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var hero := Control.new()
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.size_flags_stretch_ratio = 1.35
	layout.add_child(hero)
	login_center = CenterContainer.new()
	login_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	login_center.size_flags_stretch_ratio = 0.85
	layout.add_child(login_center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.06, 0.11, 0.94)
	style.border_color = Color("b69a60")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	login_center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	title_label = Label.new()
	title_label.text = "Bem-vindo de volta"
	title_label.add_theme_font_size_override("font_size", 27)
	title_label.add_theme_color_override("font_color", Color("f4ead7"))
	v.add_child(title_label)

	var subtitle := Label.new()
	subtitle.text = "Entre para continuar sua aventura."
	subtitle.add_theme_color_override("font_color", Color("bdc8ce"))
	v.add_child(subtitle)

	language = OptionButton.new()
	for item in ["Brasil • Português", "International • English", "España • Español"]:
		language.add_item(item)
	v.add_child(language)

	endpoint = LineEdit.new()
	settings.load("user://login.cfg")
	endpoint.text = "https://lolpro-on.onrender.com"
	user = field(v, "Usuário")
	user.text = str(settings.get_value("login", "username", ""))
	password = field(v, "Senha")
	password.secret = true
	var show_password := CheckBox.new()
	show_password.text = "Mostrar senha"
	show_password.toggled.connect(func(visible_password: bool): password.secret = not visible_password)
	v.add_child(show_password)

	remember_user = CheckBox.new()
	remember_user.text = "Lembrar meu usuário e senha neste dispositivo"
	remember_user.button_pressed = bool(settings.get_value("login", "remember_user", true))
	v.add_child(remember_user)
	if remember_user.button_pressed:
		var saved := ConfigFile.new()
		if saved.load_encrypted_pass("user://login_secret.cfg", login_storage_key()) == OK:
			if str(saved.get_value("login","username","")) == user.text:
				password.text = str(saved.get_value("login","password",""))
	remember_user.toggled.connect(func(enabled: bool):
		if not enabled:
			clear_saved_login()
	)

	var enter_button := Button.new()
	enter_button.text = "ENTRAR"
	enter_button.custom_minimum_size.y = 44
	var blue := StyleBoxFlat.new()
	blue.bg_color = Color("0754ad")
	blue.border_color = Color("e6c478")
	blue.set_border_width_all(2)
	blue.set_corner_radius_all(8)
	enter_button.add_theme_stylebox_override("normal", blue)
	var hover := blue.duplicate() as StyleBoxFlat
	hover.bg_color = Color("087ee5")
	enter_button.add_theme_stylebox_override("hover", hover)
	enter_button.add_theme_stylebox_override("pressed", blue)
	v.add_child(enter_button)
	enter_button.pressed.connect(func(): send("login", {"username": user.text, "password": password.text}))

	var create_button := Button.new()
	create_button.text = "Criar conta"
	create_button.custom_minimum_size.y = 40
	v.add_child(create_button)
	create_button.pressed.connect(open_register_window)

	status = Label.new()
	status.name = "LoginStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Entre com sua conta ou crie uma nova."
	status.add_theme_color_override("font_color", Color("d5c08e"))
	v.add_child(status)

	v.add_child(HSeparator.new())
	var update_button := Button.new()
	update_button.text = "Atualizar jogo"
	update_button.custom_minimum_size.y = 40
	v.add_child(update_button)
	update_button.pressed.connect(check_for_updates)
	update_progress_box = VBoxContainer.new()
	update_progress_box.visible = false
	add_child(update_progress_box)
	update_progress_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	update_progress_box.offset_left = 24
	update_progress_box.offset_right = -24
	update_progress_box.offset_top = -58
	update_progress_box.offset_bottom = -12
	update_progress_label = Label.new()
	update_progress_label.text = "Preparando atualização... 0%"
	update_progress_box.add_child(update_progress_label)
	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = 100
	progress.value = 0
	progress.show_percentage = true
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("00aaff")
	fill.set_corner_radius_all(6)
	progress.add_theme_stylebox_override("fill", fill)
	update_progress_box.add_child(progress)

	var download_button := Button.new()
	download_button.text = "Baixar jogo / Download"
	v.add_child(download_button)
	download_button.pressed.connect(func(): OS.shell_open("https://lolprogif.github.io/LolPRO-ON/"))

	var offline_button := Button.new()
	offline_button.text = "Modo offline / Offline"
	v.add_child(offline_button)
	offline_button.pressed.connect(func():
		get_tree().remove_meta("online_endpoint")
		get_tree().remove_meta("online_token")
		get_tree().remove_meta("hud_profile")
		get_tree().change_scene_to_file("res://World.tscn"))

	get_viewport().size_changed.connect(_adapt_login_layout)
	_adapt_login_layout()

func _adapt_login_layout():
	if not is_instance_valid(login_center):
		return
	var width := get_viewport_rect().size.x
	for child in get_children():
		if child is HBoxContainer and child.get_child_count() > 1:
			child.get_child(0).visible = width >= 620

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
	if update_req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED or update_download_active: return
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
	if update_download_active:
		return
	update_latest = latest
	update_download_path = OS.get_user_data_dir().path_join("LolPRO-ON-update.zip")
	update_progress_box.visible = true
	progress.value = 0
	update_progress_label.text = "Baixando v%s... 0%%" % latest
	status.text = "Baixando a atualização. Você pode continuar nesta tela."
	update_download_active = true
	update_download_req.download_file = update_download_path
	var err := update_download_req.request(download_url, ["Cache-Control: no-cache"])
	if err != OK:
		update_download_active = false
		update_progress_label.text = "Falha ao iniciar o download."
		status.text = "Não foi possível iniciar o download. Tente novamente."
		update_download_req.download_file = ""

func update_download_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray):
	update_download_active = false
	update_download_req.download_file = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not FileAccess.file_exists(update_download_path):
		update_progress_label.text = "Falha no download. Tente novamente."
		status.text = "A atualização não foi baixada. O jogo continua aberto."
		return
	var file := FileAccess.open(update_download_path, FileAccess.READ)
	if file == null or file.get_length() < 1024:
		update_progress_label.text = "Pacote inválido."
		status.text = "O arquivo recebido está incompleto. O jogo continua aberto."
		return
	file.close()
	progress.value = 100
	update_progress_label.text = "Download concluído • 100%%. Aplicando atualização..."
	var exe_path := OS.get_executable_path()
	var install_dir := exe_path.get_base_dir()
	var exe_name := exe_path.get_file()
	var updater := install_dir.path_join("update_windows.ps1")
	if not FileAccess.file_exists(updater):
		update_progress_label.text = "Atualizador não encontrado."
		status.text = "Atualizador não encontrado. Baixe o pacote completo."
		return
	var args := ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", updater, "-ZipPath", update_download_path, "-InstallDir", install_dir, "-ExeName", exe_name]
	var pid := OS.create_process("powershell.exe", args)
	if pid <= 0:
		update_progress_label.text = "Não foi possível aplicar."
		status.text = "Falha ao iniciar a instalação. O jogo continua aberto."
		return
	status.text = "Atualização baixada. O jogo será reiniciado automaticamente para substituir os arquivos."
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
	if update_download_active:
		var total := update_download_req.get_body_size()
		var received := update_download_req.get_downloaded_bytes()
		if total > 0:
			progress.value = clampf(float(received) / float(total) * 100.0, 0.0, 99.0)
			update_progress_label.text = "Baixando v%s... %d%%" % [update_latest, int(progress.value)]
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
		var detail := body.get_string_from_utf8().substr(0,180)
		status.text = "Servidor indisponível • conexão %d • HTTP %d\n%s" % [result,code,detail]
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
		if remember_user.button_pressed:
			var saved := ConfigFile.new()
			saved.set_value("login","username",user.text)
			saved.set_value("login","password",password.text)
			if saved.save_encrypted_pass("user://login_secret.cfg",login_storage_key()) != OK:
				push_warning("Não foi possível salvar a senha neste dispositivo.")
		else:
			clear_saved_login()
		show_selection(d.get("characters",[]),str(d.get("character","")))
	elif action == "character":
		get_tree().set_meta("online_endpoint",endpoint.text.strip_edges())
		get_tree().set_meta("online_token",token)
		get_tree().set_meta("hud_profile",user.text.strip_edges().to_lower())
		get_tree().set_meta("selected_avatar",preview_avatar)
		start_loading()

func show_selection(items: Array, legacy: String):
	login_layout.hide()
	get_node("LoginWallpaper").show()
	update_progress_box.hide()
	slot_names.clear()
	slot_profiles.clear()
	for item in items:
		slot_names[int(item.get("slot",0))] = str(item.get("name",""))
		slot_profiles[int(item.get("slot",0))] = item
	if slot_names.is_empty() and not legacy.is_empty():
		slot_names[0] = legacy

	selection = Control.new()
	selection.name = "CharacterSelection"
	add_child(selection)
	selection.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	selection.mouse_filter = Control.MOUSE_FILTER_PASS

	# Escurece o cenário existente sem esconder a arte de fundo.
	var shade := ColorRect.new()
	shade.color = Color(0.015,0.025,0.045,0.48)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection.add_child(shade)

	var gold := Color("c9a45f")
	var ivory := Color("f3e5c6")
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035,0.055,0.075,0.91)
	panel_style.border_color = gold
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(5)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 14
	panel_style.content_margin_bottom = 14

	# Faixa superior no estilo de seleção de MMORPG.
	var header := PanelContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 0
	header.offset_right = 0
	header.offset_top = 0
	header.offset_bottom = 62
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0.015,0.025,0.035,0.94)
	header_style.border_color = gold
	header_style.border_width_bottom = 2
	header.add_theme_stylebox_override("panel",header_style)
	selection.add_child(header)
	var heading := Label.new()
	heading.text = "LOLPRO-ON     •     ESCOLHA SEU PERSONAGEM"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size",25)
	heading.add_theme_color_override("font_color",ivory)
	header.add_child(heading)

	# Área principal: ficha à esquerda e personagem 3D em destaque à direita.
	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 22
	content.offset_top = 82
	content.offset_right = -22
	content.offset_bottom = -86
	content.add_theme_constant_override("separation",18)
	selection.add_child(content)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(330,0)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",panel_style)
	content.add_child(card)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation",9)
	card.add_child(details)

	var section_title := Label.new()
	section_title.text = "PERSONAGENS"
	section_title.add_theme_font_size_override("font_size",19)
	section_title.add_theme_color_override("font_color",gold)
	details.add_child(section_title)

	var slots := OptionButton.new()
	slots.custom_minimum_size.y = 38
	for i in range(4):
		slots.add_item("%d   •   %s" % [i+1,slot_names.get(i,"Criar personagem")],i)
	details.add_child(slots)

	var name_title := Label.new()
	name_title.text = "Nome do personagem"
	name_title.add_theme_color_override("font_color",ivory)
	details.add_child(name_title)
	character = field(details,"Digite o nome do aventureiro")
	character.custom_minimum_size.y = 36

	var appearance_title := Label.new()
	appearance_title.text = "Aparência"
	appearance_title.add_theme_color_override("font_color",ivory)
	details.add_child(appearance_title)
	var avatars := OptionButton.new()
	avatars.custom_minimum_size.y = 38
	avatars.add_item("Whiteclown • Masculino",0)
	avatars.add_item("Sura • Masculino",1)
	details.add_child(avatars)

	var separator := HSeparator.new()
	details.add_child(separator)
	var info_title := Label.new()
	info_title.text = "INFORMAÇÕES DO AVENTUREIRO"
	info_title.add_theme_font_size_override("font_size",13)
	info_title.add_theme_color_override("font_color",gold)
	details.add_child(info_title)
	var level_info := Label.new()
	level_info.text = "Nível: 1"
	details.add_child(level_info)
	var class_info := Label.new()
	class_info.text = "Classe: Aventureiro"
	details.add_child(class_info)
	var guild_info := Label.new()
	guild_info.text = "Guilda: Nenhuma"
	details.add_child(guild_info)
	var preview_info := Label.new()
	preview_info.text = "Selecione um espaço para continuar."
	preview_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_info.add_theme_color_override("font_color",Color("d9c89f"))
	details.add_child(preview_info)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(spacer)

	var stage_panel := PanelContainer.new()
	stage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_panel.add_theme_stylebox_override("panel",panel_style)
	content.add_child(stage_panel)
	var stage_box := VBoxContainer.new()
	stage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_panel.add_child(stage_box)
	var stage_caption := Label.new()
	stage_caption.text = "AVENTUREIRO"
	stage_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_caption.add_theme_font_size_override("font_size",16)
	stage_caption.add_theme_color_override("font_color",gold)
	stage_box.add_child(stage_caption)
	build_preview(stage_box)

	var choose := func(index: int):
		selected_slot = index
		character.text = str(slot_names.get(index,""))
		character.editable = not slot_names.has(index)
		var profile: Dictionary = slot_profiles.get(index,{})
		var saved_avatar := str(profile.get("avatar","whiteclown"))
		if saved_avatar == "warrior_m": saved_avatar = "sura"
		var avatar_index: int = int({"whiteclown":0,"sura":1}.get(saved_avatar,0))
		avatars.select(avatar_index)
		avatars.disabled = slot_names.has(index)
		preview_avatar = saved_avatar
		preview_gender = 1 if saved_avatar in ["erika_archer","maria"] else 0
		play_preview("Idle")
		preview_info.text = "Personagem: %s" % character.text if slot_names.has(index) else "Espaço livre • crie seu aventureiro"
		level_info.text = "Nível: %s" % str(profile.get("level",1))
		class_info.text = "Classe: %s" % str(profile.get("class","Aventureiro"))
		guild_info.text = "Guilda: %s" % str(profile.get("guild","Nenhuma"))
	slots.item_selected.connect(choose)
	avatars.item_selected.connect(func(index: int):
		preview_avatar = ["whiteclown","sura"][index]
		preview_gender = 0
		play_preview("Idle")
		preview_info.text = avatars.get_item_text(index))
	choose.call(0)

	# Barra inferior com ações claramente separadas.
	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 22
	footer.offset_right = -22
	footer.offset_top = -70
	footer.offset_bottom = -12
	var footer_style := panel_style.duplicate() as StyleBoxFlat
	footer_style.content_margin_top = 7
	footer_style.content_margin_bottom = 7
	footer.add_theme_stylebox_override("panel",footer_style)
	selection.add_child(footer)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation",14)
	footer.add_child(actions)
	var enter := Button.new()
	enter.text = "⚔  ENTRAR NO MUNDO"
	enter.custom_minimum_size = Vector2(230,42)
	enter.pressed.connect(func():
		if character.text.strip_edges().length()<3:
			status.text = "Digite um nome com pelo menos 3 caracteres."
			return
		var avatar_id: String = str(slot_profiles.get(selected_slot,{}).get("avatar",["whiteclown","sura"][avatars.selected])) if slot_names.has(selected_slot) else ["whiteclown","sura"][avatars.selected]
		if avatar_id == "warrior_m": avatar_id = "sura"
		send("character",{"token":token,"slot":selected_slot,"character":character.text.strip_edges(),"class":"Aventureiro","gender":"Feminino" if avatar_id in ["erika_archer","maria"] else "Masculino","avatar":avatar_id}))
	actions.add_child(enter)
	var back := Button.new()
	back.text = "VOLTAR"
	back.custom_minimum_size = Vector2(150,42)
	back.pressed.connect(func():
		token = ""
		selection.queue_free()
		login_layout.show()
		get_node("LoginWallpaper").show()
		update_progress_box.visible = update_download_active
		status = login_center.find_child("LoginStatus",true,false) as Label
		if status:
			status.text = "Entre com sua conta.")
	actions.add_child(back)

	status = Label.new()
	status.text = ""
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_left = 350
	status.offset_right = -350
	status.offset_top = -108
	status.offset_bottom = -82
	selection.add_child(status)

func start_loading():
	if is_instance_valid(preview_actor):
		if play_preview("Walking"):
			var cinematic := create_tween().set_parallel(true)
			cinematic.tween_property(preview_actor,"position:z",1.1,2.0)
			cinematic.tween_property(preview_camera,"position",Vector3(0.7,1.5,3.0),2.0)
			await cinematic.finished
		else:
			play_preview("Idle")
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
	var brand := Label.new()
	brand.text = "LolPRO-ON"
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_theme_font_size_override("font_size",42)
	brand.add_theme_color_override("font_color",Color("e6c478"))
	v.add_child(brand)
	var slogan := Label.new()
	slogan.text = "Sua jornada começa aqui • Evolua até o nível 99"
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(slogan)
	var promo := Label.new()
	promo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	promo.add_theme_font_size_override("font_size",22)
	v.add_child(promo)
	var promo_tween := create_tween().set_loops()
	for phrase in ["QUATRO CLASSES • UM DESTINO","EVOLUA SEU DRAGÃO ATÉ O NÍVEL 99","EXPLORE • EVOLUA • CONQUISTE"]:
		promo_tween.tween_callback(func(): promo.text = phrase)
		promo_tween.tween_property(promo,"modulate:a",1.0,0.35).from(0.0)
		promo_tween.tween_interval(1.0)
		promo_tween.tween_property(promo,"modulate:a",0.0,0.3)
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
	container.custom_minimum_size = Vector2(0,180)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.stretch = true
	parent.add_child(container)
	container.gui_input.connect(rotate_preview_input)
	var rotation_controls := HBoxContainer.new()
	rotation_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(rotation_controls)
	for step in [-45.0,45.0]:
		var rotate_button := Button.new()
		rotate_button.text = "Girar esquerda" if step < 0 else "Girar direita"
		rotation_controls.add_child(rotate_button)
		rotate_button.pressed.connect(rotate_preview.bind(step))
	var reset_button := Button.new()
	reset_button.text = "Frente"
	rotation_controls.add_child(reset_button)
	reset_button.pressed.connect(func():
		if is_instance_valid(preview_actor): preview_actor.rotation.y = 0.0)
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
	env.environment.ambient_light_energy = 1.0
	preview_stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-35,0)
	preview_stage.add_child(light)
	preview_camera = Camera3D.new()
	preview_stage.add_child(preview_camera)
	preview_camera.position = Vector3(0,1.2,2.7)
	preview_camera.fov = 48.0
	preview_camera.look_at(Vector3(0,0.95,0))
	preview_camera.current = true
	play_preview("Idle")
func play_preview(state: String) -> bool:
	var model_file: String = str({"whiteclown":("Walking.fbx" if state == "Walking" else "Idle.fbx"),"erika_archer":"erika_archer.fbx","maria":"maria.fbx"}.get(preview_avatar,"Character.fbx"))
	var custom_path: String = str({"sura":"res://sura_male_novice.glb"}.get(preview_avatar,"res://assets/"+model_file))
	var scene = load(custom_path)
	if not scene is PackedScene:
		push_warning("Modelo de personagem não importado: "+model_file)
		return false
	if is_instance_valid(preview_actor): preview_actor.queue_free()
	preview_actor = scene.instantiate() as Node3D
	preview_stage.add_child(preview_actor)
	for node in preview_actor.find_children("*","AnimationPlayer",true,false):
		var ap: AnimationPlayer = node
		for clip in ap.get_animation_list():
			if clip == "RESET": continue
			var clip_name := String(clip).to_lower()
			if state == "Walking" and preview_avatar != "whiteclown" and not ("walk" in clip_name or "walking" in clip_name):
				continue
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			ap.play(clip)
			return true
	return false

func rotate_preview(degrees: float):
	if is_instance_valid(preview_actor):
		preview_actor.rotate_y(deg_to_rad(degrees))

func rotate_preview_input(event: InputEvent):
	if event is InputEventScreenDrag:
		rotate_preview(event.relative.x * 0.5)
	elif event is InputEventMouseMotion and not OS.has_feature("mobile") and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		rotate_preview(event.relative.x * 0.5)

func login_storage_key() -> String:
	return ("LolPRO-ON:local-login:v1:" + OS.get_unique_id()).sha256_text()

func clear_saved_login():
	if FileAccess.file_exists("user://login_secret.cfg"):
		DirAccess.remove_absolute("user://login_secret.cfg")
	settings.set_value("login","remember_user",false)
	settings.set_value("login","username","")
	settings.save("user://login.cfg")
