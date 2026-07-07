extends Control

@onready var video: VideoStreamPlayer = $video

func _ready() -> void:
	await get_tree().process_frame
	if GameManager.inst.no_start:
		change_scene()
		return
	
	await video.finished
	change_scene()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		change_scene()
		
func change_scene():
	Transition.change_scene(Transition.Scenes.MAIN, Transition.DISSOLVE)
	#get_tree().change_scene_to_file("res://scenes/Main/Main.tscn")
