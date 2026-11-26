extends CanvasLayer
var world: Node3D
var root: Control
var windows := {}
var coins := 100
var level := 1
var xp := 0
var weapon := 0
var armor := 0
var level_label: Label
var stats_label: Label
var weapon_button: Button
var armor_button: Button
var gear_buttons := {}
var upgrade_buttons := {}
var inventory_items := {}
var gear_names := {"helmet":"Capacete","boots":"Botas","gloves":"Luvas","necklace":"Colar","ring":"Anel","bracelet":"Pulseira","shield":"Escudo"}
var potions := 5
var hp := 80
var hp_bar: ProgressBar
var money: Label
var stock: Button
var chat: RichTextLabel
var coords: Label
var theme_rpg := Theme.new()
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
	level_label = label(t,"◆  AVENTUREIRO  |  Nv. 1")
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
	var attack_button := Button.new()
	attack_button.text = "Atacar" if OS.has_feature("mobile") else "Atacar (Mouse esq.)"
	attack_button.focus_mode = Control.FOCUS_NONE
	root.add_child(attack_button)
	attack_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	attack_button.offset_left = -300
	attack_button.offset_right = -200
	attack_button.offset_top = -220
	attack_button.offset_bottom = -170
	attack_button.pressed.connect(func(): world.attack())
	if OS.has_feature("mobile"): attack_button.hide()

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
	label(inv,"Equipamentos iniciais")
	weapon_button = button(inv,"Equipar espada",func(): item_action("weapon"))
	armor_button = button(inv,"Equipar armadura",func(): item_action("armor"))
	var equipment := GridContainer.new()
	equipment.columns = 2
	inv.add_child(equipment)
	for key in gear_names:
		var kind: String = key
		gear_buttons[kind] = button(equipment,gear_names[kind],func(): item_action(kind))
	money = label(inv,"Moedas: 100")
	stock = button(inv,"Poção x5",use_potion)
	build_item_inventory(inv)
	pages(window("Especial",Vector2(310,410)),8,5,40)
	var c := window("Personagem",Vector2(300,350))
	stats_label = label(c,"Nível 1 • EXP 0 / 100")
	for line in ["VIT 10   INT 10   STR 10   DEX 10","Ataque 10   Defesa 5","Velocidade: caminhada / corrida","Dano mágico • evasão • bônus: pendentes"]:
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
		if is_instance_valid(world.net) and world.net.cloud_active:
			world.net.request_item("buy_potion")
			return
		if coins >= 10:
			coins -= 10
			potions += 1
			refresh())
	button(shop,"Vender poção (5 moedas)",func():
		if is_instance_valid(world.net) and world.net.cloud_active:
			world.net.request_item("sell_potion")
			return
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
	if OS.has_feature("mobile"):
		button(menu,"Personalizar HUD",func():
			windows["Opções"].hide()
			get_tree().call_group("mobile_hud","edit_layout"))
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
func apply_progress(data: Dictionary):
	var ranks: Dictionary = data.get("ranks",{})
	for key in upgrade_buttons:
		var rank := int(ranks.get(key,0))
		var rarity := "Comum" if rank<3 else ("Raro" if rank<6 else ("Épico" if rank<9 else "Lendário"))
		upgrade_buttons[key].text = "%s +%d • %s" % [inventory_items[key],rank,rarity]
		upgrade_buttons[key].tooltip_text = "Melhorar: %d moedas" % (25*(rank+1))
		upgrade_buttons[key].disabled = rank>=9
	level = int(data.get("level",1))
	xp = int(data.get("xp",0))
	coins = int(data.get("coins",100))
	weapon = int(data.get("weapon",0))
	armor = int(data.get("armor",0))
	var gear: Dictionary = data.get("gear",{})
	for key in gear_buttons:
		gear_buttons[key].text = gear_names[key]+(" ✓" if int(gear.get(key,0)) else " +")
func item_action(cmd: String):
	if is_instance_valid(world.net) and world.net.cloud_active: world.net.request_item(cmd)
	else:
		if cmd == "weapon": weapon = 1-weapon
		if cmd == "armor": armor = 1-armor
		refresh()
func refresh():
	level_label.text = "◆ AVENTUREIRO | Nv. %d" % level
	stats_label.text = "Nível %d • EXP %d / 100" % [level,xp]
	weapon_button.text = "Desequipar espada" if weapon else "Equipar espada"
	armor_button.text = "Desequipar armadura" if armor else "Equipar armadura"
	money.text = "Moedas: %d" % coins
	stock.text = "Poção x%d" % potions
	hp_bar.value = hp
func use_potion():
	if is_instance_valid(world.net) and world.net.cloud_active:
		world.net.request_potion()
		return
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

func build_item_inventory(parent: Node):
	inventory_items = gear_names.duplicate()
	inventory_items["weapon"] = "Espada"
	inventory_items["armor"] = "Armadura"
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.y = 180
	parent.add_child(tabs)
	for category in ["Armas","Proteção","Acessórios"]:
		var scroll := ScrollContainer.new()
		scroll.name = category
		tabs.add_child(scroll)
		var list := VBoxContainer.new()
		scroll.add_child(list)
		for key in inventory_items:
			if category == "Armas" and key != "weapon": continue
			if category == "Proteção" and not key in ["armor","helmet","boots","gloves","shield"]: continue
			if category == "Acessórios" and not key in ["ring","necklace","bracelet"]: continue
			var kind: String = key
			var item = preload("res://inventory_item.gd").new()
			item.kind = kind
			item.text = inventory_items[kind]
			item.pressed.connect(func(): item_action(kind))
			list.add_child(item)
			upgrade_buttons[kind] = button(list,"Melhorar "+inventory_items[kind],func(): item_action("upgrade:"+kind))
	var target = preload("res://inventory_item.gd").new()
	target.text = "Arraste um item aqui para equipar / desequipar"
	target.drop_target = true
	target.equip_requested.connect(item_action)
	parent.add_child(target)
