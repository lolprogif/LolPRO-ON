extends Button
signal equip_requested(kind: String)
var kind := ""
var drop_target := false
func _get_drag_data(_at_position: Vector2):
	if drop_target or kind.is_empty(): return null
	var preview := Label.new()
	preview.text = text
	set_drag_preview(preview)
	return {"gear_kind":kind}
func _can_drop_data(_at_position: Vector2,data):
	return drop_target and data is Dictionary and data.has("gear_kind")
func _drop_data(_at_position: Vector2,data):
	equip_requested.emit(str(data["gear_kind"]))
