class_name Transition extends CanvasLayer
const FILE = "res://classes/Transition/Transition.tscn"
static var inst: Transition = null

static func spawn():
	var loaded = load(FILE)
	inst = loaded.instantiate()
	Dummy.add_child(inst)

enum { DISSOLVE }
enum Scenes { 
	SPLASH , MAIN , SETTINGS, QUIT,
	SEARCH, LOBBY,
	DUMMY
	}

signal screen_obscured

@onready var anim: AnimationPlayer = $anim

var animations:Dictionary = {
	DISSOLVE: "dissolve"
}

var scenes:Dictionary = {
	Scenes.SPLASH: "uid://sxodp55gia30",
	Scenes.MAIN: "uid://cekq182icrfya",
	Scenes.SETTINGS: "uid://bv3h36ydpflj",
	Scenes.SEARCH: "uid://b7pgaw88m4b6r",
	Scenes.LOBBY: "uid://dabv2ovv6ckqo",
	
}

static func quit(): inst._quit()
func _quit():
	change_scene(Scenes.QUIT, DISSOLVE)

static func change_scene(scene:int, animation:int): inst._change_scene(scene,animation)
func _change_scene(scene:int, animation:int):
	anim.play(animations[animation])
	await anim.animation_finished
	screen_obscured.emit()
	
	if scene == Scenes.QUIT:
		get_tree().quit()
		return
	if scene == Scenes.DUMMY:
		anim.play_backwards(animations[animation])
		return
	
	get_tree().change_scene_to_file(scenes[scene])
	anim.play_backwards(animations[animation])
