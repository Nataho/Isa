class_name Events extends Node
const FILE = preload("uid://cvcn4ghnbbfy0")
static var inst: Events = null

static func spawn():
	inst = FILE.instantiate()
	Dummy.add_child(inst)
	
### ─── LAN CONNECTION & LOBBY SIGNALS (From your network code) ───
signal client_searching
signal connection_timeout
signal client_connected_to_server
signal failed_to_connect_to_server
signal client_disconnected
signal server_rejected_join
signal server_accepted_join(server_data: Dictionary)
signal join_requested(ws_peer: WebSocketPeer, player_data: Dictionary)
signal client_left_lobby(player_data: Dictionary)
signal discovered_servers_updated(servers_list: Array[Dictionary])

### ─── CORE NETWORK DATA SYNC SIGNALS (From your network code) ───
signal sync_data(data: Dictionary)
signal sync_interaction(data: Dictionary)

### ─── MULTIPLAYER UNO GAMEPLAY SIGNALS (From our previous step) ───
signal card_played(payload: Dictionary)
signal card_drawn(payload: Dictionary)
signal deck_reshuffled(payload: Dictionary)
signal turn_changed(payload: Dictionary)
signal game_over(payload: Dictionary)

### ─── REQUIRED PLAYER PAYLOAD HELPER ───
# Generates the standard player identification data required for your payloads
static func get_base_payload(player_id: int, player_name: String) -> Dictionary: 
	return inst._get_base_payload(player_id, player_name)
	
func _get_base_payload(player_id: int, player_name: String) -> Dictionary:
	return {
		"player_id": player_id,
		"player_name": player_name
	}
