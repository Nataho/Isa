class_name WindowManager extends Node2D
const FILE = "uid://cyamgc7dktii8"
static var inst:WindowManager = null

static func spawn():
	var loaded = load(FILE)
	inst = loaded.instantiate()
	Dummy.add_child(inst)

static func get_screen_center() -> Vector2: return inst._get_screen_center()
func _get_screen_center() -> Vector2:
	return get_viewport_rect().size/2

static func get_screen_size() -> Vector2: return inst._get_screen_size()
func _get_screen_size() -> Vector2:
	return get_viewport_rect().size
