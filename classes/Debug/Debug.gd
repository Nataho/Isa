extends Node

var singletons = [
	"res://classes/GameManager/GameManager.gd",
	"res://classes/Transition/Transition.gd",
	"res://classes/Events/Events.gd",
	"res://classes/WindowManager/window_manager.gd",
	"res://classes/websocket/NetworkClient/NetworkClient.gd",
	"res://classes/websocket/NetworkServer/NetworkServer.gd",
	"res://classes/websocket/NetworkSync/NetworkSync.gd",
	"res://classes/Audio/Audio.gd",
]

func _ready() -> void:
	CLA()

func CLA():
	var args = OS.get_cmdline_args()
	if "--debugniowen" in args:
		open_all_singletons()

func open_all_singletons():
	for path in singletons:
		# CACHE_MODE_REPLACE forces Godot to ignore RAM and read the freshly mounted .pck file!
		var script_resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if script_resource and script_resource.has_method("spawn"):
			script_resource.spawn()
	
