class_name NetworkServer extends Node #NetworkServer.gd
const FILE = preload("uid://bchcvd6uawwo5")
static var inst:NetworkServer = null

static func spawn():
	inst = FILE.instantiate()
	Dummy.add_child(inst)

var active_players: Array[Dictionary] = []

@export var listen_port: int = 42069 
@export var broadcast_port: int = 4242

var server_active := false
var tcp_server := TCPServer.new()
var connected_clients: Array[WebSocketPeer] = [] 

var udp_broadcaster := PacketPeerUDP.new()
var broadcast_timer := 0.0

var local_subnet := "255.255.255.255"
var custom_subnet := "10.147.17.255"

var client_last_seen: Dictionary = {}

static func start() -> void: inst._start()
func _start() -> void:
	if server_active: return
	NetworkSync.inst.current_mode = NetworkSync.NetMode.LAN_HOST
	active_players.clear()
	
	var err = tcp_server.listen(listen_port)
	if err != OK: return

	udp_broadcaster.set_broadcast_enabled(true)
	# I REMOVED the set_dest_address line that was here!
	server_active = true

static func stop() -> void: inst._stop()
func _stop() -> void:
	if not server_active: return
	server_active = false
	udp_broadcaster.close()
	broadcast_timer = 0.0
	for ws in connected_clients:
		if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			ws.close(1001, "Server shutting down")
	connected_clients.clear()
	active_players.clear()
	client_last_seen.clear()
	tcp_server.stop()
	NetworkSync.inst.current_mode = NetworkSync.NetMode.OFFLINE

func _process(delta: float) -> void:
	if not server_active: return
	_handle_udp_broadcast(delta)
	_check_for_new_connections()
	_process_client_messages()
	
#region Discovery & Polling
func _handle_udp_broadcast(delta: float) -> void:
	broadcast_timer += delta
	if broadcast_timer > 2.0:
		broadcast_timer = 0.0
		
		# Pulling live data directly from your GameManager!
		var broadcast_data := {
			"identifier": "nataho_server",
			"host_name": GameManager.inst.player_data.get("name", "Host"),
			"status": GameManager.inst.network_data.get("game_status", "inactive"), 
			"player_count": active_players.size() + 1, 
			"max_players": 8
		}
		
		var json_payload = JSON.stringify(broadcast_data)
		var packet_buffer = json_payload.to_utf8_buffer()
		
		# ─── THE DYNAMIC SUBNET LOOP ───
		var target_subnets = [local_subnet, custom_subnet]
		
		for subnet in target_subnets:
			udp_broadcaster.set_dest_address(subnet, broadcast_port)
			udp_broadcaster.put_packet(packet_buffer)

func _check_for_new_connections() -> void:
	while tcp_server.is_connection_available():
		var conn = tcp_server.take_connection()
		var ws = WebSocketPeer.new()
		ws.accept_stream(conn)
		ws.set_meta("welcomed", false)
		connected_clients.append(ws)
		client_last_seen[ws] = Time.get_ticks_msec()
		
func _process_client_messages() -> void:
	var current_time = Time.get_ticks_msec()
	for i in range(connected_clients.size() - 1, -1, -1):
		var ws = connected_clients[i]
		ws.poll()
		var state = ws.get_ready_state()
		
		if state == WebSocketPeer.STATE_OPEN:
			if not ws.get_meta("welcomed"):
				_send_welcome(ws)
				ws.set_meta("welcomed", true)
			_read_packets(ws)
			if current_time - client_last_seen.get(ws, current_time) > 15000:
				print("Server: Client timed out (No pings for 15s). Dropping connection!")
				
				ws.close(1008, "Ping Timeout")
		elif state == WebSocketPeer.STATE_CLOSED:
			client_last_seen.erase(ws)
			for p in range(active_players.size() - 1, -1, -1):
				if active_players[p].get("socket") == ws:
					var leaving_player = active_players[p]
					active_players.remove_at(p)
					Events.inst.client_left_lobby.emit(leaving_player)
			connected_clients.remove_at(i)
#endregion

#region Server Signals & Authentication
func _read_packets(ws: WebSocketPeer) -> void:
	while ws.get_available_packet_count() > 0:
		var packet = ws.get_packet()
		client_last_seen[ws] = Time.get_ticks_msec()
		var msg = packet.get_string_from_utf8()
		var parsed_msg = JSON.parse_string(msg)
		
		if typeof(parsed_msg) != TYPE_DICTIONARY or not parsed_msg.has("signal"): continue
		
		if parsed_msg["signal"] == "ping":
			send_to_client(ws, "pong")
			continue
		
		_handle_signal(ws, parsed_msg)

func _handle_signal(ws: WebSocketPeer, data: Dictionary) -> void:
	match data["signal"]:
		"request_join":
			# Pushing the decision out to your Lobby!
			var client_info = data.get("data", {})
			Events.inst.join_requested.emit(ws, client_info)
		"sync_data":
			Events.inst.sync_data.emit(data["data"])
			broadcast_signal("sync_data", data["data"])
		"sync_interaction":
			Events.inst.sync_interaction.emit(data["data"])
			broadcast_signal("sync_interaction", data["data"])
		_:
			print("unknown signal: ", data)

# ─── CALL THESE FROM YOUR LOBBY SCRIPT ───
static func approve_join(ws: WebSocketPeer, player_data: Dictionary) -> void:
	inst._approve_join(ws, player_data)
func _approve_join(ws: WebSocketPeer, player_data: Dictionary) -> void:
	var profile = player_data.duplicate()
	profile["socket"] = ws
	active_players.append(profile)
	send_to_client(ws, "join_accepted", {"total_players": active_players.size()})

static func reject_join(ws: WebSocketPeer, reason: String) -> void:
	inst._reject_join(ws, reason)
func _reject_join(ws: WebSocketPeer, reason: String) -> void:
	send_to_client(ws, "join_rejected", {"reason": reason})
	ws.close(1008, "Rejected by Lobby")

# ─── UTILS ───
func _send_welcome(ws: WebSocketPeer) -> void:
	send_to_client(ws, "server_connected")

static func send_to_client(ws: WebSocketPeer, signal_name: String, extra_data: Dictionary = {}) -> void:
	inst._send_to_client(ws, signal_name, extra_data)
func _send_to_client(ws: WebSocketPeer, signal_name: String, extra_data: Dictionary = {}) -> void:
	var payload = {"signal": signal_name, "data": extra_data}
	ws.send_text(JSON.stringify(payload))

static func broadcast_signal(signal_name: String, extra_data: Dictionary = {}) -> void:
	inst._broadcast_signal(signal_name, extra_data)
func _broadcast_signal(signal_name: String, extra_data: Dictionary = {}) -> void:
	for ws in connected_clients:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			# Only broadcast to fully authenticated players
			var is_validated = false
			for p in active_players:
				if p["socket"] == ws:
					is_validated = true
					break
			if is_validated:
				send_to_client(ws, signal_name, extra_data)
#endregion1
