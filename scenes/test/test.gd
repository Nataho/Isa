extends Control
#
#func _ready() -> void:
	#print("hello world")
	#Events.inst.discovered_servers_updated.connect(func(servers_list:Array[Dictionary]):
		#print(servers_list)
		#)
#
#func host():
	#NetworkServer.start()
#
#func join():
	#NetworkClient.start()
#
#func communicate():
	#if NetworkClient.client_active:
		#NetworkClient.send_signal("test", {})
