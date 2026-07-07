extends Node

var singletons = [
	GameManager,
	Transition,
	Events,
	WindowManager,
	NetworkSync,
	NetworkServer,
	NetworkClient,
]

func _ready() -> void:
	CLA()

func CLA():
	var args = OS.get_cmdline_args()
	if "--debugniowen" in args:
		open_all_singletons()

func open_all_singletons():
	for singleton in singletons:
		singleton.spawn()
	pass
	
