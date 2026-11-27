extends Node3D

var max_health: int = 120
var health: int = 120
var health_label: Label3D

func _ready() -> void:
	add_to_group("attackable")
	name = "TemporaryTestMonster"
	health_label = Label3D.new()
	health_label.name = "TestMonsterHealth"
	health_label.text = "MONSTRO DE TESTE\nHP: %d / %d" % [health, max_health]
	health_label.position = Vector3(0, 2.5, 0)
	health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_label.font_size = 48
	health_label.outline_size = 8
	add_child(health_label)
	_play_idle()

func take_damage(amount: int) -> void:
	if health <= 0:
		return
	health = maxi(0, health - maxi(1, amount))
	if is_instance_valid(health_label):
		health_label.text = "MONSTRO DE TESTE\nHP: %d / %d" % [health, max_health]
	if health == 0:
		defeated()

func defeated() -> void:
	remove_from_group("attackable")
	visible = false
	if is_instance_valid(health_label):
		health_label.text = "DERROTADO!"
	await get_tree().create_timer(4.0).timeout
	if not is_inside_tree():
		return
	health = max_health
	visible = true
	add_to_group("attackable")
	if is_instance_valid(health_label):
		health_label.text = "MONSTRO DE TESTE\nHP: %d / %d" % [health, max_health]

func _play_idle() -> void:
	for node in find_children("*", "AnimationPlayer", true, false):
		var ap := node as AnimationPlayer
		for clip in ap.get_animation_list():
			var lower := String(clip).to_lower()
			if "idle" in lower or "stand" in lower:
				ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				ap.play(clip)
				return
