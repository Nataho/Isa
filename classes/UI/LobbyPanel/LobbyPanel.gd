class_name LobbyPanel extends Panel
const FILE = preload("uid://dgibny0cjx21y")

signal pressed

var host:String = "username"
var status:String = "in lobby"
var players:int = 0
var ip:String = "127.0.0.1"
var port:int = 11111

@onready var host_label: Label = $username
@onready var players_label: Label = $players
@onready var status_label: Label = $status
@onready var button: Button = $button

var labels:Array[Label] = []


static func create(network_info:Dictionary) -> LobbyPanel:
	var obj:LobbyPanel = FILE.instantiate()
	obj.ip = network_info["ip"]
	obj.port = network_info["last_seen"]
	obj.host = network_info["host_name"]
	obj.status = network_info["status"]
	obj.players = network_info["player_count"]
	
	return obj


func _ready():
	_connect_signals()
	labels = [host_label, players_label, status_label]
	
	# Make sure EVERY label gets a unique copy of its OWN specific settings
	for label: Label in labels:
		if label.label_settings:
			label.label_settings = label.label_settings.duplicate()
	
	var unique_stylebox = button.get_theme_stylebox("normal") as StyleBoxFlat
	if unique_stylebox:
		button.add_theme_stylebox_override("normal",unique_stylebox.duplicate())
		#unique_stylebox.bg_color = new_color
	#button.
	
	_update_contents()

func _connect_signals():
	button.mouse_entered.connect(_mouse_entered)
	button.mouse_exited.connect(_mouse_exited)
	button.pressed.connect(_pressed)

func _update_contents():
	host_label.text = host.to_upper()
	players_label.text = "PLAYERS\n\n" + str(players) + str("/4")
	status_label.text = "STATUS\n\n" + status
	if status == "in game":
		var unique_stylebox = button.get_theme_stylebox("normal") as StyleBoxFlat
		unique_stylebox.bg_color = Palette.Isa.YELLOW
		pass

func _pressed():
	NetworkClient.connect_to_server(ip, GameManager.inst.player_data)
	pressed.emit()

func _mouse_entered():
	Audio.play_sound("hover")
	# Update the color on each label's unique settings
	for label: Label in labels:
		if label.label_settings:
			label.label_settings.font_color = Palette.Space.VIOLET

func _mouse_exited():
	# Revert the color on each label's unique settings
	for label: Label in labels:
		if label.label_settings:
			label.label_settings.font_color = Palette.Space.BLACK
