class_name WindowManager extends Node2D
const FILE = preload("uid://cyamgc7dktii8")
static var inst:WindowManager = null

static func spawn():
	inst = FILE.instantiate()
	Dummy.add_child(inst)

static func get_screen_center() -> Vector2: return inst._get_screen_center()
func _get_screen_center() -> Vector2:
	return get_viewport_rect().size/2

static func get_screen_size() -> Vector2: return inst._get_screen_size()
func _get_screen_size() -> Vector2:
	return get_viewport_rect().size
