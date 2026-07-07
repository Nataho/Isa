extends Control

const SIMULATE_OFFLINE = true
const JSON_URL = "https://your-server.com/patches.json"

@onready var http_request: HTTPRequest = $UpdaterHTTP
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var status_label: Label = $StatusLabel

var singletons = [
	GameManager,
	Transition,
	Events,
	WindowManager,
	NetworkSync,
	NetworkServer,
	NetworkClient,
]

var is_downloading: bool = false

func _ready() -> void:
	progress_bar.hide()
	
	if SIMULATE_OFFLINE:
		status_label.text = "Offline Mode: Checking local files..."
		# Mocking the JSON data so you can test it without a server
		var mock_json = {
			"patches": {
				"0.1": {
					"url": "fake_url", 
					"requires_reboot": true # Try setting this to false later!
				}
			}
		}
		_process_patch_list(mock_json)
	else:
		status_label.text = "Checking for updates..."
		_fetch_json()

# ─── 1. THE LOADING BAR MAGIC ───
func _process(_delta: float) -> void:
	if is_downloading:
		var downloaded = http_request.get_downloaded_bytes()
		var total = http_request.get_body_size()
		
		if total > 0:
			var percent = (float(downloaded) / float(total)) * 100.0
			progress_bar.value = percent
			status_label.text = "Downloading... %d%%" % percent

# ─── 2. FETCH THE JSON ───
func _fetch_json() -> void:
	http_request.request_completed.connect(_on_json_received, CONNECT_ONE_SHOT)
	http_request.request(JSON_URL)

func _on_json_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json:
			_process_patch_list(json)
			return
			
	status_label.text = "Network Error. Booting offline..."
	_initialize_singletons()

func _process_patch_list(server_data: Dictionary) -> void:
	var needs_reboot = false
	
	for patch_version in server_data["patches"]:
		var patch_info = server_data["patches"][patch_version]
		var patch_path = "user://patch_" + patch_version + ".pck"
		
		# If we DON'T have it, download it
		if not FileAccess.file_exists(patch_path):
			status_label.text = "Downloading patch " + patch_version + "..."
			
			if SIMULATE_OFFLINE:
				# FAKE DOWNLOAD: Create a dummy file on the hard drive 
				# so the game knows we "downloaded" it and breaks the loop!
				var dummy_file = FileAccess.open(patch_path, FileAccess.WRITE)
				dummy_file.store_string("dummy")
				dummy_file.close()
			else:
				# REAL DOWNLOAD: Pause and wait for the real file
				await _download_file(patch_info["url"], patch_path)
			
			# SAFETY CHECK: Only reboot if the file actually exists on the drive now
			if FileAccess.file_exists(patch_path):
				if patch_info.get("requires_reboot", false):
					needs_reboot = true
		
		# Mount the patch into the engine's memory
		if FileAccess.file_exists(patch_path):
			ProjectSettings.load_resource_pack(patch_path)
	
	if needs_reboot:
		status_label.text = "Applying core update..."
		await get_tree().create_timer(0.5).timeout 
		get_tree().change_scene_to_file("res://scenes/boot/Boot.tscn") 
		return
		
	_initialize_singletons()

# ─── 4. DOWNLOAD FUNCTION ───
func _download_file(url: String, save_path: String) -> void:
	progress_bar.show()
	progress_bar.value = 0
	is_downloading = true
	
	http_request.download_file = save_path
	http_request.request_completed.connect(_on_file_downloaded, CONNECT_ONE_SHOT)
	
	var error = http_request.request(url)
	if error != OK:
		is_downloading = false
		return
		
	# Wait here until the signal fires
	await http_request.request_completed

func _on_file_downloaded(_res, _code, _headers, _body) -> void:
	is_downloading = false
	progress_bar.hide()

# ─── 5. HANDOFF TO GAME ───
func _initialize_singletons() -> void:
	status_label.text = "Loading game..."
	
	for singleton in singletons:
		singleton.spawn()
		
	get_tree().change_scene_to_file("res://scenes/splash/splash.tscn")
