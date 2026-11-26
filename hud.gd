extends CanvasLayer
var world: Node3D
var root: Control
var windows := {}
var coins := 100
var potions := 5
var hp := 80
var hp_bar: ProgressBar
var money: Label
var stock: Button
var chat: RichTextLabel
var coords: Label
var theme_rpg := Theme.new()
var attack_button: Button
var jump_button: Button
var layout_cfg := ConfigFile.new()
var layout_drag: Control
var layout_scale := 1.0
var layout_positions := {}
func style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = border
	s.set_corner_radius_all(4)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s
func _ready():
	root = Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_rpg.set_stylebox("panel", "PanelContainer", style(Color("24211def"),Color("b49a62")))
	for state in ["normal","hover","pressed","focus"]:
		theme_rpg.set_stylebox(state,"Button",style(Color("493a2c") if state == "normal" else Color("705536"),Color("ad925e")))
	theme_rpg.set_color("font_color","Button",Color("f4dfb1"))
	theme_rpg.default_font_size = 14
	root.theme = theme_rpg
	var top := panel_at(Vector2(12,12),Vector2(220,100))
	var t := VBoxContainer.new()
	top.add_child(t)
	label(t,"◆  AVENTUREIRO  |  Nv. 1")
	hp_bar = bar(t, hp, Color("a72e32"))
	bar(t,100,Color("346ab5"))
	button(t,"Missões",func(): toggle("Missões"))
	var bottom := panel_at(Vector2.ZERO,Vector2.ZERO)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -60
	var h := HBoxContainer.new()
	bottom.add_child(h)
	for name in ["Poção","Personagem","Inventário","Especial","Habilidades","Emoções","Missões","Amigos","Grupo","Mapa","Loja","Opções"]:
		var n: String = name
		button(h,n,func(): use_potion() if n == "Poção" else toggle(n))
	_load_layout()
	attack_button = _create_control_button("Atacar", "attack", Vector2(0.84,0.70))
	attack_button.pressed.connect(func():
		if not world.control_edit_mode: world.attack())
	jump_button = _create_control_button("Pular", "jump", Vector2(0.84,0.81))
	jump_button.pressed.connect(func():
		if not world.control_edit_mode:
			world.touch_jump = true
			get_tree().create_timer(0.18).timeout.connect(func(): world.touch_jump = false))
	var map := panel_at(Vector2.ZERO,Vector2(170,100))
	map.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	map.offset_left = -185
	map.offset_right = -12
	map.offset_top = 12
	map.offset_bottom = 115
	var mv := VBoxContainer.new()
	map.add_child(mv)
	label(mv,"◇  Campo inicial")
	coords = label(mv,"0, 0")
	button(mv,"Mapa grande",func(): toggle("Mapa"))
	var cp := panel_at(Vector2.ZERO,Vector2(340,110))
	cp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	cp.offset_left = -170
	cp.offset_right = 170
	cp.offset_top = -180
	cp.offset_bottom = -66
	var cv := VBoxContainer.new()
	cp.add_child(cv)
	chat = RichTextLabel.new()
	chat.custom_minimum_size.y = 50
	chat.text = "Sistema: Bem-vindo! (offline)"
	cv.add_child(chat)
	var entry := LineEdit.new()
	entry.placeholder_text = "Chat local"
	cv.add_child(entry)
	entry.text_submitted.connect(func(msg):
		chat.add_text("\nVocê: " + msg)
		entry.clear()
		entry.release_focus()
		cp.hide())
	cp.hide()
	button(h,"Chat",func():
		cp.visible = not cp.visible
		if cp.visible: entry.grab_focus())
	var inv := window("Inventário",Vector2(300,440),true)
	label(inv,"Equipamentos • espaços reservados")
	grid_slots(inv,4,12)
	money = label(inv,"Moedas: 100")
	stock = button(inv,"Poção x5",use_potion)
	pages(inv,5,5,40)
	pages(window("Especial",Vector2(310,410)),8,5,40)
	var c := window("Personagem",Vector2(300,350))
	for line in ["Aventureiro • Nível 1","EXP: 0 / 100","VIT 10   INT 10   STR 10   DEX 10","Ataque 10   Defesa 5","Velocidade: caminhada / corrida","Dano mágico • evasão • bônus: pendentes"]:
		label(c,line)
	for n in ["Habilidades","Emoções"]:
		var v := window(n,Vector2(300,300))
		label(v,"Espaços reservados — ainda sem ações")
		grid_slots(v,6,24)
	label(window("Missões",Vector2(300,220)),"Nenhuma missão disponível.")
	label(window("Amigos",Vector2(300,220)),"Amigos / Guilda / Bloqueados\nServidor online pendente.")
	var g := window("Grupo",Vector2(300,260))
	label(g,"Grupo: 0 / 8 • offline")
	var opt := OptionButton.new()
	opt.add_item("EXP por nível")
	opt.add_item("EXP uniforme")
	g.add_child(opt)
	label(g,"Convites e partilha: requer servidor.")
	label(window("Mapa",Vector2(300,220)),"Campo inicial • mapa gráfico pendente")
	var shop := window("Loja",Vector2(300,260))
	label(shop,"Vendedora de teste • comércio local")
	button(shop,"Comprar poção (10 moedas)",func():
		if coins >= 10:
			coins -= 10
			potions += 1
			refresh())
	button(shop,"Vender poção (5 moedas)",func():
		if potions > 0:
			potions -= 1
			coins += 5
			refresh())
	label(shop,"Loja premium e NPC físico: pendentes")
	var menu := window("Opções",Vector2(300,360))
	label(menu,"Sensibilidade da câmera (Android)")
	var sensitivity := HSlider.new()
	sensitivity.min_value = 1
	sensitivity.max_value = 100
	var settings := ConfigFile.new()
	settings.load("user://settings.cfg")
	sensitivity.value = settings.get_value("controls","sensitivity",50.0)
	world.touch_sensitivity = sensitivity.value
	menu.add_child(sensitivity)
	sensitivity.value_changed.connect(func(value: float):
		world.touch_sensitivity = value
		settings.set_value("controls","sensitivity",value)
		settings.save("user://settings.cfg"))
	button(menu,"Editar posição dos controles",func(): _toggle_layout_edit())
	button(menu,"Aumentar tamanho",func(): _resize_layout(0.1))
	button(menu,"Diminuir tamanho",func(): _resize_layout(-0.1))
	button(menu,"Restaurar padrão",func(): _reset_layout())
	button(menu,"Ajuda / controles",func(): toggle("Ajuda"))
	button(menu,"Tela cheia / janela",func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN))
	button(menu,"Teleportador",func(): toggle("Teleportador"))
	label(menu,"Canal / conta / personagem: offline")
	button(menu,"Sair do jogo",func(): get_tree().quit())
	label(window("Ajuda",Vector2(320,180)),"WASD: mover • Shift: correr\nEspaço: pular • Botão direito: câmera\nScroll: zoom • I: inventário • Esc: opções")
	var tp := window("Teleportador",Vector2(300,200))
	button(tp,"Retornar ao ponto inicial",func():
		world.player.position = Vector3(0,0.1,0)
		world.player.velocity = Vector3.ZERO)
	label(tp,"Outros mapas e NPC físico: pendentes")
func panel_at(pos: Vector2, sz: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	root.add_child(p)
	p.position = pos
	p.size = sz
	return p
func label(parent: Node, value: String) -> Label:
	var l := Label.new()
	l.text = value
	parent.add_child(l)
	return l
func button(parent: Node, value: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = value
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	b.pressed.connect(action)
	return b
func bar(parent: Node, value: int, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(150,12)
	b.show_percentage = false
	b.value = value
	b.add_theme_stylebox_override("fill",style(color,color))
	parent.add_child(b)
	return b
func window(n: String, sz: Vector2, right := false) -> VBoxContainer:
	var p := panel_at(Vector2(240,110),sz)
	if right:
		p.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		p.offset_left = -sz.x - 12
		p.offset_right = -12
		p.offset_top = 120
		p.offset_bottom = 120 + sz.y
	var v := VBoxContainer.new()
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var l := label(h,n)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(h,"×",func(): p.hide())
	windows[n] = p
	p.hide()
	return v
func grid_slots(parent: Node, columns: int, count: int):
	var grid := GridContainer.new()
	grid.columns = columns
	parent.add_child(grid)
	for i in range(count):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(32,25)
		grid.add_child(slot)
func pages(parent: Node, count: int, columns: int, slots: int):
	var tabs := TabContainer.new()
	parent.add_child(tabs)
	for i in range(count):
		var v := VBoxContainer.new()
		v.name = str(i+1)
		tabs.add_child(v)
		grid_slots(v,columns,slots)
func toggle(n: String):
	if windows.has(n):
		windows[n].visible = not windows[n].visible
func refresh():
	money.text = "Moedas: %d" % coins
	stock.text = "Poção x%d" % potions
	hp_bar.value = hp
func use_potion():
	if potions > 0 and hp < 100:
		potions -= 1
		hp = mini(100,hp+20)
		refresh()
func _process(_delta):
	if is_instance_valid(coords):
		coords.text = "X: %.0f  Z: %.0f" % [world.player.position.x,world.player.position.z]
func _unhandled_key_input(event):
	if event.pressed and not event.echo:
		if event.keycode == KEY_I: toggle("Inventário")
		if event.keycode == KEY_ESCAPE: toggle("Opções")


func _layout_profile() -> String:
	return "mobile" if OS.has_feature("mobile") else "pc"

func _load_layout():
	layout_cfg.load("user://controls.cfg")
	var profile := _layout_profile()
	layout_scale = clampf(float(layout_cfg.get_value(profile,"scale",1.0)),0.7,1.5)
	layout_positions["attack"] = layout_cfg.get_value(profile,"attack",Vector2(0.84,0.70))
	layout_positions["jump"] = layout_cfg.get_value(profile,"jump",Vector2(0.84,0.81))
	world.control_scale = layout_scale

func _create_control_button(caption: String, key: String, fallback: Vector2) -> Button:
	var b := Button.new()
	b.text = caption
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(100,50) * layout_scale
	b.size = b.custom_minimum_size
	root.add_child(b)
	b.position = layout_positions.get(key,fallback) * get_viewport().get_visible_rect().size
	b.gui_input.connect(func(event): _layout_button_input(event,b,key))
	return b

func _layout_button_input(event: InputEvent, target: Control, key: String):
	if not world.control_edit_mode: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: layout_drag = target
		elif layout_drag == target:
			layout_drag = null
			_save_layout()
	elif event is InputEventMouseMotion and layout_drag == target:
		target.position += event.relative
		_clamp_layout_button(target)
	elif event is InputEventScreenTouch:
		if event.pressed: layout_drag = target
		elif layout_drag == target:
			layout_drag = null
			_save_layout()
	elif event is InputEventScreenDrag and layout_drag == target:
		target.position += event.relative
		_clamp_layout_button(target)
	if layout_drag == target:
		var size := get_viewport().get_visible_rect().size
		layout_positions[key] = Vector2(target.position.x/maxf(1.0,size.x),target.position.y/maxf(1.0,size.y))

func _clamp_layout_button(target: Control):
	var size := get_viewport().get_visible_rect().size
	target.position.x = clampf(target.position.x,0.0,maxf(0.0,size.x-target.size.x))
	target.position.y = clampf(target.position.y,0.0,maxf(0.0,size.y-target.size.y))

func _toggle_layout_edit():
	world.control_edit_mode = not world.control_edit_mode
	attack_button.text = "Mover Atacar" if world.control_edit_mode else "Atacar"
	jump_button.text = "Mover Pular" if world.control_edit_mode else "Pular"
	attack_button.modulate = Color(1.0,0.82,0.5) if world.control_edit_mode else Color.WHITE
	jump_button.modulate = Color(1.0,0.82,0.5) if world.control_edit_mode else Color.WHITE
	if not world.control_edit_mode: _save_layout()

func _resize_layout(amount: float):
	layout_scale = clampf(layout_scale+amount,0.7,1.5)
	world.control_scale = layout_scale
	for b in [attack_button,jump_button]:
		b.custom_minimum_size = Vector2(100,50)*layout_scale
		b.size = b.custom_minimum_size
		_clamp_layout_button(b)
	_save_layout()

func _reset_layout():
	layout_scale = 1.0
	world.control_scale = 1.0
	layout_positions["attack"] = Vector2(0.84,0.70)
	layout_positions["jump"] = Vector2(0.84,0.81)
	for pair in [[attack_button,"attack"],[jump_button,"jump"]]:
		var b: Control = pair[0]
		b.position = layout_positions[pair[1]]*get_viewport().get_visible_rect().size
		b.custom_minimum_size = Vector2(100,50)
		b.size = b.custom_minimum_size
	if world.has_node("Network/TouchControls"):
		world.get_node("Network/TouchControls").reset_layout()
	_save_layout()

func _save_layout():
	var profile := _layout_profile()
	layout_cfg.set_value(profile,"scale",layout_scale)
	layout_cfg.set_value(profile,"attack",layout_positions.get("attack",Vector2(0.84,0.70)))
	layout_cfg.set_value(profile,"jump",layout_positions.get("jump",Vector2(0.84,0.81)))
	layout_cfg.save("user://controls.cfg")
