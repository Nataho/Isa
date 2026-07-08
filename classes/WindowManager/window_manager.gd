class_name WindowManager extends Node2D
const FILE = "res://classes/WindowManager/WindowManager.tscn"
static var inst:WindowManager = null

static func spawn():
	var loaded = ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_REPLACE)
	if loaded:
		inst = loaded.instantiate()
		Dummy.add_child(inst)
	else:
		push_error("CRITICAL: Failed to load WindowManager.tscn via Cache Mode Replace!")

static func get_screen_center() -> Vector2: return inst._get_screen_center()
func _get_screen_center() -> Vector2:
	return get_viewport_rect().size/2

static func get_screen_size() -> Vector2: return inst._get_screen_size()
func _get_screen_size() -> Vector2:
	return get_viewport_rect().size
