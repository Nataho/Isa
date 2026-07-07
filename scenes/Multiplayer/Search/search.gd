extends Control

@onready var hosts: VBoxContainer = %hosts
var panels:Array[PanelContainer] = []

@onready var lan_button: Button = %LANButton
@onready var direct_button: Button = %DirectButton

@onready var ip_field: LineEdit = %ip_field
@onready var connect_to_ip_button: Button = %connect

var manual_ip_address:String = ""

func _ready() -> void:
	panels = [%hostsPanel, %directPanel]
	
	# ─── THE IDENTITY FIX: Client generates THEIR OWN unique ID ───
	if GameManager.inst.network_data.get("lobby_id", -1) == -1:
		var my_new_id = randi_range(10000, 99999)
		GameManager.inst.network_data["lobby_id"] = my_new_id
		
		# IMPORTANT: If your Network wrapper sends GameManager.inst.player_data 
		# when joining, we must inject the ID there too so the Host sees it!
		GameManager.inst.player_data["lobby_id"] = my_new_id
		
	_connect_signals()
	NetworkClient.start()
	
func _connect_signals():
	Events.inst.discovered_servers_updated.connect(update_list)
	Events.inst.server_accepted_join.connect(_on_accepted)
	
	lan_button.pressed.connect(show_panel.bind(panels[0]))
	direct_button.pressed.connect(show_panel.bind(panels[1]))
	
	ip_field.text_changed.connect(_ip_address_changed)
	connect_to_ip_button.pressed.connect(_connect_to_server)

func _on_accepted(server_data: Dictionary):
	print("server has accepted: ", server_data)
	
	# Keep the client strictly as a client
	GameManager.inst.network_data["is_host"] = false
	Transition.change_scene(Transition.Scenes.LOBBY, Transition.DISSOLVE)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		print("cancelled")
		Transition.change_scene(Transition.Scenes.MAIN, Transition.DISSOLVE)

func update_list(servers_list: Array[Dictionary]):
	for child in hosts.get_children():
		child.queue_free()
	
	for host: Dictionary in servers_list:
		var lobby_panel := LobbyPanel.create(host)
		lobby_panel.pressed.connect(_connecting_to_server)
		hosts.add_child(lobby_panel)

func _connecting_to_server():
	var loading_panel = LoadingPanel.create("Connecting To Server")
	add_child(loading_panel)
	Events.inst.failed_to_connect_to_server.connect(func():
		print("connection_timeout?")
		loading_panel.queue_free()
		)

func _ip_address_changed(text:String):
	manual_ip_address = text

func _connect_to_server():
	NetworkClient.connect_to_server(manual_ip_address, GameManager.inst.player_data)
	_connecting_to_server()

func show_panel(panel_to_show:PanelContainer):
	for panel in panels:
		panel.hide()
	
	panel_to_show.show()
