class_name NetworkClient extends Node #Networkclient.gd
const FILE = "res://classes/websocket/NetworkClient/NetworkClient.tscn"

static var inst:NetworkClient = null

static func spawn():
	var loaded = ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_REPLACE)
	if loaded:
		inst = loaded.instantiate()
		Dummy.add_child(inst)
	else:
		push_error("CRITICAL: Failed to load NetworkClient.tscn via Cache Mode Replace!")

@export var listen_port: int = 4242
@export var server_port: int = 42069

@onready var timer: Timer = $Timer

var client := WebSocketPeer.new()
var udp_listener := PacketPeerUDP.new()

var client_active: bool = false
var found_server_ip: String = ""
var is_connecting: bool = false

# ─── UPDATED: LOCALLY CACHE THE FULL PLAYER DATA DICTIONARY ───
var local_player_data: Dictionary = {}

var is_discovering: bool = false
var discovered_servers: Array[Dictionary] = [] 
var prune_timer: float = 0.0

var heartbeat_timer: float = 0.0
var last_ping_time: int = 0

const CONNECTION_TIMEOUT: float = 15.0

func _ready() -> void:
	timer.timeout.connect(_on_timeout)
	timer.one_shot = true 

static func start() -> void: inst._start()
func _start() -> void:
	if client_active or is_connecting or is_discovering: return
	
	discovered_servers.clear()
	found_server_ip = ""
	
	if udp_listener.bind(listen_port) == OK:
		is_discovering = true
		Events.inst.client_searching.emit() 
	else:
		stop()

# ─── UPDATED: ACCEPTS A DICTIONARY ───
static func connect_to_server(ip: String, player_data: Dictionary) -> void:
	inst._connect_to_server(ip, player_data)
func _connect_to_server(ip: String, player_data: Dictionary) -> void:
	if client_active or is_connecting: return
		
	local_player_data = player_data
		
	is_discovering = false
	if udp_listener.is_bound():
		udp_listener.close()
		
	client_active = true
	is_connecting = true
	found_server_ip = ip
	
	timer.start(CONNECTION_TIMEOUT)
	var url = "ws://" + found_server_ip + ":" + str(server_port)
	client.connect_to_url(url)

static func stop() -> void: inst._stop()
func _stop() -> void:
	timer.stop() 
	if udp_listener.is_bound():
		udp_listener.close()
	if client.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		client.close()
		
	client_active = false
	is_connecting = false
	is_discovering = false
	found_server_ip = ""
	discovered_servers.clear()
	
	
func _on_timeout() -> void:
	if client_active and (found_server_ip == "" or is_connecting):
		stop()
		Events.inst.connection_timeout.emit()
		return
	Events.inst.failed_to_connect_to_server.emit()
	
func _process(delta: float) -> void:
	if is_discovering:
		_search_for_servers()
		_prune_stale_servers(delta)

	if not client_active: return

	client.poll() 
	var state = client.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if is_connecting:
			is_connecting = false 
			timer.stop() 
			
		_handle_server_messages()
		
		heartbeat_timer += delta
		if heartbeat_timer > 1.0:
			last_ping_time = Time.get_ticks_msec()
			send_signal("ping") 
			heartbeat_timer = 0.0
		
	elif state == WebSocketPeer.STATE_CLOSED:
		Events.inst.client_disconnected.emit()
		_handle_disconnection()
		
#region Network Logic
func _search_for_servers() -> void:
	var current_time = Time.get_ticks_msec()
	var list_changed = false
	
	while udp_listener.get_available_packet_count() > 0:
		var packet_msg = udp_listener.get_packet().get_string_from_utf8()
		var parsed = JSON.parse_string(packet_msg)
		
		if typeof(parsed) == TYPE_DICTIONARY and parsed.get("identifier") == "nataho_server":
			var server_ip = udp_listener.get_packet_ip()
			
			# Map the keys straight from the server's broadcast payload
			var server_info := {
				"ip": server_ip,
				"last_seen": current_time,
				"host_name": parsed.get("host_name", "Unknown"),
				"status": parsed.get("status", "inactive"),
				"player_count": parsed.get("player_count", 1),
				"max_players": parsed.get("max_players", 8)
			}
			
			var existing_index: int = -1
			for i in range(discovered_servers.size()):
				if discovered_servers[i]["ip"] == server_ip:
					existing_index = i
					break
			
			if existing_index != -1:
				discovered_servers[existing_index] = server_info
				list_changed = true 
			else:
				discovered_servers.append(server_info)
				list_changed = true
				
	if list_changed and Events.inst.has_signal("discovered_servers_updated"):
		Events.inst.discovered_servers_updated.emit(discovered_servers)

func _prune_stale_servers(delta: float) -> void:
	prune_timer += delta
	if prune_timer < 1.0: return
	prune_timer = 0.0
	var current_time = Time.get_ticks_msec()
	var list_changed = false
	for i in range(discovered_servers.size() - 1, -1, -1):
		if current_time - discovered_servers[i]["last_seen"] > 6000:
			discovered_servers.remove_at(i)
			list_changed = true
	if list_changed and Events.inst.has_signal("discovered_servers_updated"):
		Events.inst.discovered_servers_updated.emit(discovered_servers)

func _handle_disconnection() -> void:
	found_server_ip = "" 
	client.close() 
	client_active = false
	Events.inst.client_disconnected.emit()
	start() 

func _handle_server_messages() -> void:
	while client.get_available_packet_count() > 0:
		var packet = client.get_packet()
		var raw_data = packet.get_string_from_utf8()
		if raw_data.is_empty(): continue
		var parsed_msg = JSON.parse_string(raw_data)
		if typeof(parsed_msg) != TYPE_DICTIONARY: continue
		_process_server_signal(parsed_msg)

func _process_server_signal(data: Dictionary) -> void:
	var signal_name = data.get("signal", "")
	if signal_name == "": return

	match signal_name:
		"server_connected":
			Events.inst.client_connected_to_server.emit()
			# Socket is open, send the full player dictionary to the server!
			send_signal("request_join", local_player_data)
			
		"join_accepted":
			NetworkSync.inst.current_mode = NetworkSync.NetMode.LAN_CLIENT
			Events.inst.server_accepted_join.emit(data.get("data", {}))
			
		"join_rejected":
			Events.inst.server_rejected_join.emit()
			stop()
			
		"sync_interaction":
			Events.inst.sync_interaction.emit(data.get("data", {}))
		"sync_data":
			Events.inst.sync_data.emit(data.get("data", {}))
		"pong":
			var current_ping = Time.get_ticks_msec() - last_ping_time
#endregion

#region Outbound Communication
static func sync_interaction(action: String, player_id: int, player_name: String) -> void:
	inst._sync_interaction(action, player_id, player_name)
func _sync_interaction(action: String, player_id: int, player_name: String) -> void:
	var payload = Events.get_base_payload(player_id, player_name)
	payload["action"] = action
	send_signal("sync_interaction", payload)

static func sync_data(data: Dictionary) -> void:
	inst._sync_data(data)
func _sync_data(data: Dictionary) -> void:
	send_signal("sync_data", data)

func send_signal(signal_name: String, extra_data: Dictionary = {}) -> void:
	inst._send_signal(signal_name, extra_data)
func _send_signal(signal_name: String, extra_data: Dictionary = {}) -> void:
	var payload = {"signal": signal_name, "data": extra_data}
	_send_json(payload)

func _send_json(payload: Dictionary) -> void:
	if client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		client.send_text(JSON.stringify(payload))
#endregion
