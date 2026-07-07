class_name LoadNSave extends Node

const default_network_data = {
	"is_host": false,
	"is_ready": false,
	"game_status": "inactive",
	"player_list": [],
	"lobby_id": -1,
}

func save_file(data: Dictionary) -> void:
	var saved_file = FileAccess.open("user://Save.save", FileAccess.WRITE)
	var json_string = JSON.stringify(data, "\t", false, true)
	saved_file.store_line(json_string)
	print("sucessfully saved game")

func load_file() -> Dictionary:
	if not FileAccess.file_exists("user://Save.save"):
		return {}

	var saved_file = FileAccess.open("user://Save.save", FileAccess.READ)
	var data = JSON.parse_string(saved_file.get_as_text())
	saved_file.close()

	if data == null:
		return {}

	return data
