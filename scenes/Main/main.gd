extends Control
@onready var join_button: Button = $buttons/join
@onready var host_button: Button = $buttons/host
@onready var settings_button: Button = $buttons/settings
@onready var quit_button: Button = $buttons/quit
@onready var card: Card = $Card
@onready var placeholder: Control = $placeholder
@onready var version_label: Label = $Version


# ─── OSCILLATION CONFIGURATION ───
var time: float = 0.0
var base_y: float = 0.0

# Vertical (Up/Down) settings
@export var vertical_amplitude: float = 15.0  # How many pixels it moves up/down
@export var vertical_speed: float = 1      # How fast it moves up/down

# Rotational settings
@export var rotation_amplitude: float = 3  # 5 degrees each way = 10 degrees total swing
@export var rotation_speed: float = 1.5      # Unsynced speed (not a multiple of vertical_speed)

func _ready() -> void:
	GameManager.LOAD_GAME()
	GameManager.SAVE_GAME()
	GameManager.inst.reset_network_data()
	
	version_label.text = GameManager.inst.game_version
	
	if NetworkClient.inst.has_method("stop"):
		NetworkClient.stop()
	if NetworkServer.inst.has_method("stop"):
		NetworkServer.stop()
	
	
	Audio.play_music("main")
	
	join_button.pressed.connect(join)
	host_button.pressed.connect(host)
	settings_button.pressed.connect(settings)
	quit_button.pressed.connect(quit)
	if card:
		base_y = placeholder.position.y
	
	for button:Button in $buttons.get_children():
		button.mouse_entered.connect(hovered)
	
	await get_tree().create_timer(1).timeout
	card.set_placeholder(placeholder)

func join():
	Transition.change_scene(Transition.Scenes.SEARCH, Transition.DISSOLVE)
	Audio.play_sound("confirm3")
	GameManager.inst.network_data["is_host"] = false
	
func host():
	Transition.change_scene(Transition.Scenes.LOBBY, Transition.DISSOLVE)
	Audio.play_sound("confirm3")
	GameManager.inst.network_data["is_host"] = true
	
func settings():
	Transition.change_scene(Transition.Scenes.SETTINGS, Transition.DISSOLVE)
	Audio.play_sound("confirm1")
	
func quit(): 
	Transition.quit()
	Audio.play_sound("confirm2")

func hovered():
	Audio.play_sound("hover")

func _process(delta: float) -> void:
	if not card or card.discarded: return

	time += delta
	
	placeholder.position.y = base_y + (sin(time * vertical_speed) * vertical_amplitude)
	var target_rotation_degrees = sin(time * rotation_speed) * rotation_amplitude
	card.initial_rotation = deg_to_rad(target_rotation_degrees)

func _physics_process(delta: float) -> void:
	pass
