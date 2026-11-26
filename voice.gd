extends Node
var net: Node
var mic := AudioStreamPlayer.new()
var capture := AudioEffectCapture.new()
var req := HTTPRequest.new()
var enabled := false
var listening := false
var busy := false
var elapsed := 0.0
var label_status: Label
var mic_button: Button
var quick_mic: Button
var muted := {}
var speakers := {}
var volume := 0.7
var bus_index := -1
var phase := 0.0
const RATE := 16000
func _ready():
	add_to_group("voice_controls")
	add_child(req)
	req.timeout = 5
	req.request_completed.connect(received)
	var hud = net.world.get_children().filter(func(n): return n is CanvasLayer)[0]
	var panel: VBoxContainer = hud.window("Voz",Vector2(320,310))
	label_status = hud.label(panel,"Voz desligada")
	mic_button = hud.button(panel,"Ligar microfone",toggle_mic)
	var listen := CheckButton.new()
	listen.text = "Ouvir jogadores próximos"
	panel.add_child(listen)
	listen.toggled.connect(func(on: bool):
		listening = on
		if not on:
			for speaker in speakers.values(): speaker.stop()
			for speaker in speakers.values(): speaker.queue_free()
			speakers.clear())
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = volume
	panel.add_child(slider)
	slider.value_changed.connect(func(v: float): volume = v)
	var mute_name := LineEdit.new()
	mute_name.placeholder_text = "Nome do personagem"
	panel.add_child(mute_name)
	hud.button(panel,"Alternar silêncio",func():
		var key := mute_name.text.strip_edges().to_lower()
		if not key.is_empty():
			muted[key] = not muted.get(key,false)
			label_status.text = key + (" silenciado" if muted[key] else " liberado"))
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.layer = 4
	var button := Button.new()
	button.text = "Voz"
	button.position = Vector2(12,165)
	layer.add_child(button)
	button.pressed.connect(func(): hud.toggle("Voz"))
	quick_mic = Button.new()
	quick_mic.position = Vector2(12,205)
	quick_mic.custom_minimum_size = Vector2(52,52)
	quick_mic.focus_mode = Control.FOCUS_NONE
	layer.add_child(quick_mic)
	quick_mic.pressed.connect(toggle_mic)
	refresh_mic_icon()
	if OS.has_feature("mobile"): quick_mic.hide()
	AudioServer.add_bus()
	bus_index = AudioServer.bus_count-1
	AudioServer.set_bus_name(bus_index,"VoiceCapture")
	AudioServer.add_bus_effect(bus_index,capture)
	AudioServer.set_bus_mute(bus_index,true)
	mic.bus = "VoiceCapture"
	mic.stream = AudioStreamMicrophone.new()
	add_child(mic)
func refresh_mic_icon():
	if not is_instance_valid(quick_mic): return
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><g fill="none" stroke="%s" stroke-width="2.5" stroke-linecap="round"><rect x="12" y="3" width="8" height="17" rx="4"/><path d="M8 15v2a8 8 0 0 0 16 0v-2M16 25v4M11 29h10"/>%s</g></svg>' % ["#55dd88" if enabled else "#ff6666", "" if enabled else '<path d="M4 4l24 24"/>']
	var img := Image.new()
	if img.load_svg_from_string(svg) == OK: quick_mic.icon = ImageTexture.create_from_image(img)
	quick_mic.tooltip_text = "Desligar microfone" if enabled else "Ligar microfone"
func toggle_mic():
	if enabled:
		stop_mic()
		return
	if not net.cloud_active:
		label_status.text = "Entre no mundo online"
		return
	if OS.has_feature("android") and not OS.get_granted_permissions().has("android.permission.RECORD_AUDIO"):
		OS.request_permission("android.permission.RECORD_AUDIO")
		label_status.text = "Autorize o microfone e toque novamente"
		return
	capture.clear_buffer()
	phase = 0.0
	enabled = true
	refresh_mic_icon()
	mic.play()
	mic_button.text = "Desligar microfone"
	label_status.text = "Microfone ligado • alcance 20 m"
func stop_mic():
	enabled = false
	refresh_mic_icon()
	mic.stop()
	capture.clear_buffer()
	mic_button.text = "Ligar microfone"
	label_status.text = "Microfone desligado"
func _process(delta):
	if not net.cloud_active:
		if enabled: stop_mic()
		return
	if not enabled and not listening: return
	elapsed += delta
	if elapsed < 0.2 or busy: return
	elapsed = 0.0
	var bytes := PackedByteArray()
	if enabled:
		var available := capture.get_frames_available()
		var frames := capture.get_buffer(available) if available > 0 else PackedVector2Array()
		var ratio := float(AudioServer.get_mix_rate())/RATE
		var start := maxi(0,frames.size()-int(AudioServer.get_mix_rate()*0.35))
		var i := float(start)
		while int(i)<frames.size():
			var sample := frames[int(i)]
			var val := int(clampf((sample.x+sample.y)*0.5,-1.0,1.0)*32767)
			bytes.append(val & 255)
			bytes.append((val >> 8) & 255)
			i += ratio
	var payload := {"token":net.cloud_token,"audio":Marshalls.raw_to_base64(bytes) if not bytes.is_empty() else ""}
	busy = req.request(net.cloud_url+"/voice",["Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify(payload)) == OK
func received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	busy = false
	if not listening or not net.cloud_active or result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("ok",false): return
	for packet in data.get("packets",[]):
		var name_text := str(packet.get("name",""))
		if muted.get(name_text.to_lower(),false): continue
		var id := str(packet.get("id",""))
		if not speakers.has(id):
			var player := AudioStreamPlayer.new()
			var stream := AudioStreamGenerator.new()
			stream.mix_rate = RATE
			stream.buffer_length = 0.8
			player.stream = stream
			add_child(player)
			player.play()
			speakers[id] = player
		var speaker: AudioStreamPlayer = speakers[id]
		speaker.volume_db = linear_to_db(maxf(volume,0.0001))
		var playback := speaker.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback == null: continue
		var raw := Marshalls.base64_to_raw(str(packet.get("audio","")))
		for i in range(0,mini(raw.size()/2,playback.get_frames_available())):
			var sample := float(raw.decode_s16(i*2))/32768.0
			playback.push_frame(Vector2(sample,sample))
		label_status.text = "Falando: "+name_text
func _exit_tree():
	mic.stop()
	if bus_index >= 0 and bus_index < AudioServer.bus_count:
		AudioServer.remove_bus(bus_index)
