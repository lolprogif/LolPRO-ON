extends RefCounted

static func attach(parent: Node3D) -> void:
	var scene := load("res://bone-dragon.glb") as PackedScene
	if scene == null:
		return
	var model := scene.instantiate() as Node3D
	if model == null:
		return
	parent.add_child(model)
	model.scale = Vector3.ONE * 0.18
	var players := model.find_children("*", "AnimationPlayer", true, false)
	for node in players:
		var anim := node as AnimationPlayer
		for clip in anim.get_animation_list():
			if String(clip).to_lower().contains("fly"):
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				anim.play(clip)
				break
