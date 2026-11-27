extends Node
var net
var request := HTTPRequest.new()
var panel: VBoxContainer
var entry: LineEdit
var status: Label
var opener: Button
var checked := false
var permissions: Array = []
var animation_button: Button
var animation_panel: VBoxContainer
func _ready():
	add_child(request)
	request.request_completed.connect(done)
	opener = Button.new()
	opener.text = "ADM"
	opener.position = Vector2(12,265)
	opener.hide()
	add_child(opener)
	var hud = net.world.get_children().filter(func(n): return n is CanvasLayer)[0]
	panel = hud.window("Administração",Vector2(380,340))
	opener.pressed.connect(func(): hud.toggle("Administração"))
	entry = LineEdit.new()
	entry.placeholder_text = "/comando"
	panel.add_child(entry)
	entry.text_submitted.connect(send)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status)
	animation_button = Button.new()
	animation_button.text = "Animações"
	animation_button.hide()
	panel.add_child(animation_button)
	animation_panel = hud.window("Animações",Vector2(320,280))
	animation_button.pressed.connect(func(): hud.toggle("Animações"))
	for state in ["Idle","Walking","Running","Jumping"]:
		var test_button := Button.new()
		test_button.text = {"Idle":"Repouso","Walking":"Caminhar","Running":"Correr","Jumping":"Pular"}[state]
		animation_panel.add_child(test_button)
		test_button.pressed.connect(test_animation.bind(state))
func _process(_delta):
	if not checked and net.cloud_active:
		checked = true
		send("")
func send(command: String):
	if not net.cloud_active or request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED: return
	request.request(net.cloud_url+"/admin",["Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify({"token":net.cloud_token,"command":command}))
func done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.text = "Falha de conexão administrativa"
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary: return
	if data.has("permissions"):
		permissions = data.permissions
		opener.visible = not permissions.is_empty()
		animation_button.visible = "owner" in permissions
		for cmd in permissions:
			if cmd == "owner": continue
			var b := Button.new()
			b.text = "/"+str(cmd)
			panel.add_child(b)
			b.pressed.connect(select_command.bind(str(cmd)))
	status.text = str(data.get("message",data.get("error","")))
func select_command(cmd: String):
	entry.text = "/"+cmd+" "
	if cmd == "curar": send(entry.text)
	else: entry.grab_focus()

func test_animation(state: String):
	if not "owner" in permissions: return
	net.world.call("preview_admin_animation",state)
