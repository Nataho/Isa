class_name GameManager extends Node
const FILE = preload("uid://ps4y6f5ul2l3")

static var inst:GameManager = null

static func spawn():
	inst = FILE.instantiate()
	inst._early_setup()
	Dummy.add_child(inst)

var _is_muted:bool = false
var no_start := false

# ─── FIX 2: Instantiate this inline so it is NEVER Nil ───
var lns : LoadNSave = LoadNSave.new() 

var game_version = "x.x.x"

var player_data = { #is saved
	"name": "player",
}

var settings = {}

var sound_settings = {
	"Master": 0.0,
	"Music": 0.0,
	"Sfx": 0.0,
}

var network_settings = {
	"subnet": "10.147.17.255"
}

var network_data = {
	"is_host": false,
	"is_ready": false,
	"game_status": "inactive",
	"player_list": [],
	"lobby_id": -1,
}

var _save_data := {}

# This runs safely before the node even enters the Scene Tree
func _early_setup() -> void:
	CLA()
	_instantiate_singletons()

func _ready() -> void:
	# ─── FIX 3: REMOVED get_tree().root.add_child(self) ───
	# Keeping this here will cause a hard crash because Boot.gd 
	# is already trying to add this node to the root!
	pass

func _instantiate_singletons():
	lns = LoadNSave.new()

func _update_save_data():
	_save_data = {
		"player_data": player_data,
		"sound_settings": sound_settings,
		"network_settings": network_settings
	}

static func reset_network_data(): inst._reset_network_data()
func _reset_network_data():
	network_data = lns.default_network_data.duplicate()

static func SAVE_GAME(): inst._SAVE_GAME()
func _SAVE_GAME():
	_update_save_data()
	lns.save_file(_save_data)

static func LOAD_GAME() -> bool: return inst._LOAD_GAME()
func _LOAD_GAME() -> bool:
	var data = lns.load_file()
	if data.is_empty():
		return false
	
	player_data.merge(data.get("player_data", {}), true)
	sound_settings.merge(data.get("sound_settings", {}), true)
	network_settings.merge(data.get("network_settings", {}), true)
	
	NetworkServer.inst.custom_subnet = network_settings["subnet"]
	
	_update_save_data()
	_update_sound_volume()
	return true

func _update_sound_volume():
	for bus:String in sound_settings:
		Audio.set_bus_volume(bus, sound_settings[bus])

static func CLA(): inst._CLA()
func _CLA():
	var args = OS.get_cmdline_args()
	if "--mute" in args:
		print("muting")
		_is_muted = true
		AudioServer.set_bus_mute(0,true)
	if "--nostart" in args:
		no_start = true
