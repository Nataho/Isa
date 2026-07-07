class_name Settings extends Control
const FILE = preload("uid://bv3h36ydpflj")

var panels:Array[PanelContainer] = []

signal panel_closed

@onready var bg: ColorRect = $bg

@onready var audio_button: Button = %AudioButton
@onready var graphics_button: Button = %GraphicsButton
@onready var network_button: Button = %NetworkButton
@onready var user_button: Button = %UserButton
@onready var player_username: LineEdit = %player_username
@onready var subnet_field: LineEdit = %subnet_field

var _is_created := false

static func create() -> Settings:
	var obj: Settings = FILE.instantiate()
	obj._is_created = true
	return obj

func _ready() -> void:
		
		
	setup_button_sfx()
	setup_panels()
	setup_loaded_info()
	
	if _is_created:
		_setup_created_settings()
	

func _setup_created_settings():
	bg.hide()
	user_button.hide()
	for panel:PanelContainer in panels:
		panel.self_modulate.a = 0.5
	pass

func setup_loaded_info():
	GameManager.LOAD_GAME()
	player_username.text = GameManager.inst.player_data["name"]
	subnet_field.text = GameManager.inst.network_settings["subnet"]
	%master_slider.value = GameManager.inst.sound_settings["Master"]
	%music_slider.value = GameManager.inst.sound_settings["Music"]
	%sfx_slider.value = GameManager.inst.sound_settings["Sfx"]

func setup_panels():
	panels = [ %AudioPanel, %GraphicsPanel, %NetworkPanel, %UserPanel ]
	
	audio_button.pressed.connect(show_panel.bind(panels[0]))
	graphics_button.pressed.connect(show_panel.bind(panels[1]))
	network_button.pressed.connect(show_panel.bind(panels[2]))
	user_button.pressed.connect(show_panel.bind(panels[3]))
	
	player_username.text_changed.connect(username_changed)
	subnet_field.text_changed.connect(subnet_changed)
	
	%master_slider.value_changed.connect(func(value:float): 
		Audio.set_bus_volume(Audio.MASTER_BUS, value)
		print("updated volume: ", value)
		)
	%music_slider.value_changed.connect(func(value:float): 
		Audio.set_bus_volume(Audio.MUSIC_BUS, value)
		print("updated volume: ", value)
		)
	%sfx_slider.value_changed.connect(func(value:float): Audio.set_bus_volume(Audio.SFX_BUS, value))
	
	show_panel(panels[0])

func setup_button_sfx():
	var main_buttons := $PanelManager/HBoxContainer/Buttons.get_children()
	for button:Button in main_buttons:
		button.mouse_entered.connect(func():
			Audio.play_sound("hover")
			)
		button.pressed.connect(func():
			Audio.play_sound("confirm2")
			)

func show_panel(panel_to_show:PanelContainer):
	for panel in panels:
		panel.hide()
	
	panel_to_show.show()

func username_changed(text:String):
	GameManager.inst.player_data["name"] = text
	GameManager.SAVE_GAME()

func subnet_changed(text:String):
	GameManager.inst.network_settings["subnet"] = text
	GameManager.SAVE_GAME()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _is_created:
			get_viewport().set_input_as_handled()
			panel_closed.emit()
			queue_free()
			return
		Transition.change_scene(Transition.Scenes.MAIN, Transition.DISSOLVE)
