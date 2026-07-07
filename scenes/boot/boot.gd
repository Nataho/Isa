extends Control

const SIMULATE_OFFLINE = false
const JSON_URL = "https://nataho.github.io/Isa/patches.json"
const BASE_VERSION = "0.1.13"

@onready var blink: Timer = $blink
var _guide_transparent = false

# ─── THE PATIENCE CONFIG ───
const MAX_RETRIES = 3
const RETRY_DELAY_SECONDS = 3.0
var current_retry_count = 0
var download_failed = false
var update_skipped: bool = false

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var status_label: RichTextLabel = $StatusLabel
@onready var version_label: Label = $version_label

var json_http: HTTPRequest
var download_http: HTTPRequest

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
var target_progress: float = 0.0
var current_version: String = ""
var currently_downloading_version: String = ""

func _ready() -> void:
	var acting_singletons := Dummy.get_children()
	for singleton in acting_singletons:
		singleton.free()
		pass
	await get_tree().process_frame
	
	_update_version_info()
	progress_bar.hide()
	blink.timeout.connect(_blink_guide)
	
	if FileAccess.file_exists("user://version.txt"):
		var file = FileAccess.open("user://version.txt", FileAccess.READ)
		current_version = file.get_as_text().strip_edges()
		print("[Boot] Found version.txt. Current version: ", current_version)
	else:
		current_version = BASE_VERSION
		print("[Boot] No version.txt found. Defaulting to base: ", current_version)
	
	_update_version_info()
	json_http = HTTPRequest.new()
	json_http.timeout = 15.0 # Increased timeout to give slow connections more time
	add_child(json_http)
	
	download_http = HTTPRequest.new()
	download_http.timeout = 30.0 # High timeout for large file downloads
	add_child(download_http)
	
	if SIMULATE_OFFLINE:
		status_label.text = _format_message("Offline Mode...")
		_initialize_singletons()
	else:
		status_label.text = _format_message("Checking for updates...")
		await get_tree().process_frame
		_fetch_json()

# ─── SMOOTH LOADING BAR ───
func _process(delta: float) -> void:
	if is_downloading and download_http.get_http_client_status() == HTTPClient.STATUS_BODY:
		var downloaded = download_http.get_downloaded_bytes()
		var total = download_http.get_body_size()
		
		if total > 0:
			target_progress = (float(downloaded) / float(total)) * 100.0
			var current_mb = downloaded / 1048576.0
			var total_mb = total / 1048576.0
			status_label.text = _format_message("Downloading... %.2f MB / %.2f MB" % [current_mb, total_mb])
		
		progress_bar.value = lerpf(progress_bar.value, target_progress, delta * 8.0)

# ─── FETCH THE JSON (WITH RETRY SUPPORT) ───
func _fetch_json() -> void:
	if current_retry_count > 0:
		status_label.text = _format_message("Connection timed out. Retrying (%d/%d)..." % [current_retry_count, MAX_RETRIES])
		print("[Boot] Retrying connection... Attempt ", current_retry_count, " of ", MAX_RETRIES)
	else:
		status_label.text = _format_message("Connecting to update server...")
		print("[Boot] Requesting JSON from: ", JSON_URL)
		
	json_http.request_completed.connect(_on_json_received, CONNECT_ONE_SHOT)
	var error = json_http.request(JSON_URL) 
	if error != OK:
		print("[Boot] Engine level error starting JSON request! Code: ", error)
		_handle_connection_failure()

func _on_json_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	print("[Boot] JSON signal fired! Result Enum: ", result, " | HTTP Code: ", response_code)
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json_string = body.get_string_from_utf8()
		var json = JSON.parse_string(json_string)
		
		if json != null:
			print("[Boot] JSON successfully parsed!")
			_process_patch_list(json)
			return
		else:
			print("[Boot] CRITICAL: JSON file downloaded but corrupted or badly formatted.")
			_handle_connection_failure()
			return
			
	# If we got here, it failed (like HTTP Code 0)
	_handle_connection_failure()

func _handle_connection_failure() -> void:
	if current_retry_count < MAX_RETRIES:
		current_retry_count += 1
		# Wait a few seconds before trying again to let the internet settle down
		await get_tree().create_timer(RETRY_DELAY_SECONDS).timeout
		_fetch_json()
	else:
		print("[Boot] All retries failed. Falling back to offline mode.")
		status_label.text = _format_message("Network Error. Booting offline...")
		_initialize_singletons()

# ─── PROCESS PATCHES ───
func _process_patch_list(server_data: Dictionary) -> void:
	var needs_reboot = false
	
	if not server_data.has("patches"):
		print("[Boot] Error: JSON is missing the 'patches' key!")
		_initialize_singletons()
		return
		
	for patch_version in server_data["patches"]:
		print("[Boot] Evaluating server patch: ", patch_version)
		
		if not _is_patch_newer(patch_version, current_version):
			print("[Boot] ---> SKIPPED: ", patch_version, " is NOT newer than our current version (", current_version, ")")
			continue
			
		print("[Boot] ---> APPROVED: ", patch_version, " is newer! Preparing to download.")
		var patch_info = server_data["patches"][patch_version]
		var patch_path = "user://patch_" + patch_version + ".pck"
		
		if not FileAccess.file_exists(patch_path):
			status_label.text = _format_message("Starting download for " + patch_version + "...")
			currently_downloading_version = patch_version
			
			await _download_file(patch_info["url"], patch_path)
			
			if FileAccess.file_exists(patch_path) and patch_info.get("requires_reboot", false):
				needs_reboot = true
		else:
			print("[Boot] ---> File already exists on hard drive: ", patch_path)
		
		if FileAccess.file_exists(patch_path):
			ProjectSettings.load_resource_pack(patch_path)
	
	if needs_reboot:
		status_label.text = _format_message("Applying core update...")
		await get_tree().create_timer(0.5).timeout 
		get_tree().change_scene_to_file("res://scenes/boot/Boot.tscn") 
		return
		
	_initialize_singletons()

# ─── DOWNLOAD FUNCTION ───
func _download_file(url: String, save_path: String) -> void:
	progress_bar.show()
	progress_bar.value = 0
	target_progress = 0
	is_downloading = true
	
	print("[Boot] Starting actual file download from URL: ", url)
	
	download_http.download_file = save_path
	download_http.request_completed.connect(_on_file_downloaded, CONNECT_ONE_SHOT)
	
	var error = download_http.request(url)
	if error != OK:
		print("[Boot] Error starting file download! Code: ", error)
		is_downloading = false
		return
		
	await download_http.request_completed
	
	if update_skipped:
		return

func _on_file_downloaded(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	print("[Boot] Download finished! Result Enum: ", result, " | HTTP Code: ", response_code)
	is_downloading = false
	progress_bar.hide()
	
	if response_code == 200 or response_code == 302:
		print("[Boot] Saving new version ", currently_downloading_version, " to version.txt")
		var file = FileAccess.open("user://version.txt", FileAccess.WRITE)
		file.store_string(currently_downloading_version)
		file.close()
		current_version = currently_downloading_version
	else:
		print("[Boot] WARNING: Download failed or HTTP code was abnormal.")
		download_failed = true
		
# ─── HANDOFF TO GAME ───
func _initialize_singletons() -> void:
	if download_failed:
		status_label.text = _format_message("Download Failed...")
		await get_tree().create_timer(3).timeout
	if update_skipped:
		status_label.text = _format_message("Skipping Search")
		await get_tree().create_timer(3).timeout
	
	status_label.text = _format_message("Loading game...")
	print("[Boot] All patches processed. Loading singletons...")
	for singleton in singletons:
		singleton.spawn()
	GameManager.inst.game_version = current_version
	await get_tree().create_timer(3).timeout
	get_tree().change_scene_to_file("res://scenes/splash/splash.tscn")

# ─── BULLETPROOF VERSION COMPARISON ───
func _is_patch_newer(server_version: String, base_version: String) -> bool:
	var s_parts = server_version.replace("v", "").split(".")
	var b_parts = base_version.replace("v", "").split(".")
	
	for i in range(3):
		var s = s_parts[i].to_int() if i < s_parts.size() else 0
		var b = b_parts[i].to_int() if i < b_parts.size() else 0
		
		if s > b: return true
		if s < b: return false
		
	return false
	
func _format_message(text_to_format: String) -> String:
	return "[center][wave amp=30.0 freq=5.0 connected=1]" + text_to_format + "[/wave][/center]"

func _blink_guide():
	_guide_transparent = !_guide_transparent
	var alpha = 1
	var scalee = Vector2(1.1, 1.1)
	if !_guide_transparent:
		alpha = 0.7
		scalee = Vector2(1,1)
		
	$guide.modulate.a = alpha
	$guide.scale = scalee
	
func _input(event: InputEvent) -> void:
	# If they press Enter/Space and we haven't already skipped or finished
	if event.is_action_pressed("ui_accept") and not update_skipped:
		_skip_and_start_game()

func _skip_and_start_game() -> void:
	update_skipped = true
	is_downloading = false
	print("[Boot] Update bypassed by player.")
	
	# Forcefully stop any active network request (JSON fetch or PCK download)
	json_http.cancel_request()
	download_http.cancel_request()
	
	# Instantly change the UI text and jump straight into loading the game
	status_label.text = "Loading game..."
	_initialize_singletons()
	
func _update_version_info():
	version_label.text = current_version
