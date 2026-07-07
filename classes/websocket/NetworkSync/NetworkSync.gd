class_name NetworkSync extends Node #NetworkSync.gd
const FILE = "res://classes/websocket/NetworkSync/NetworkSync.tscn"

static var inst:NetworkSync = null

static func spawn():
	var loaded = load(FILE)
	inst = loaded.instantiate()
	Dummy.add_child(inst)

enum NetMode { OFFLINE, LAN_HOST, LAN_CLIENT, ONLINE }
var current_mode: NetMode = NetMode.OFFLINE

## ---------------------------------------------------------
## OUTBOUND ROUTING (Sending data to the opponent)
## ---------------------------------------------------------

static func sync_interaction(action: String, player_id: int, player_name: String):
	inst._sync_interaction(action,player_id,player_name)
func _sync_interaction(action: String, player_id: int, player_name: String):
	match current_mode:
		NetMode.LAN_CLIENT:
			NetworkClient.sync_interaction(action, player_id, player_name)
		NetMode.LAN_HOST:
			var payload = Events.get_base_payload(player_id, player_name)
			payload["action"] = action
			# Host handles it locally, then tells all other clients
			Events.inst.sync_interaction.emit(payload)
			NetworkServer.broadcast_signal("sync_interaction", payload)

static func sync_data(data: Dictionary = {}): inst._sync_data(data)
func _sync_data(data: Dictionary = {}):
	match current_mode:
		NetMode.LAN_CLIENT:
			NetworkClient.sync_data(data)
		NetMode.LAN_HOST:
			Events.inst.sync_data.emit(data)
			NetworkServer.broadcast_signal("sync_data", data)
