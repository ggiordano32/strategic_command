extends Node

# Networking constants
const DEFAULT_PORT = 28960
const MAX_PLAYERS = 8

# Connection variables
var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var player_info = {}
var my_info = {
	"name": "Player",
	"faction": "coalition",
	"team": 1,
	"color": Color(0.0, 0.5, 1.0)
}

# Signals
signal player_connected(id, info)
signal player_disconnected(id)
signal server_disconnected
signal connection_failed
signal connection_succeeded
signal match_started
signal player_info_updated(id, info)
signal server_created

# Game state
var game_started: bool = false
var players_ready: Dictionary = {}

func _ready():
	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_player_connected)
	multiplayer.peer_disconnected.connect(_player_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)

# Create a server (become host)
func create_server(player_name: String, faction: String = "coalition"):
	is_host = true
	my_info.name = player_name
	my_info.faction = faction
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	
	if error != OK:
		print("Error creating server: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	
	# Add ourselves (host) to player_info
	var my_id = multiplayer.get_unique_id()
	player_info[my_id] = my_info.duplicate()
	
	emit_signal("server_created")
	return OK

# Join an existing server
func join_server(ip: String, player_name: String, faction: String = "collective"):
	is_host = false
	my_info.name = player_name
	my_info.faction = faction
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, DEFAULT_PORT)
	
	if error != OK:
		print("Error joining server: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	return OK

# Disconnect from the server or shut down the server
func disconnect_from_server():
	if peer:
		peer.close()
		peer = null
	
	multiplayer.multiplayer_peer = null
	player_info.clear()
	players_ready.clear()
	game_started = false
	is_host = false

# Mark this player as ready to start
func set_player_ready(is_ready: bool = true):
	if multiplayer.multiplayer_peer:
		var my_id = multiplayer.get_unique_id()
		rpc("_player_ready", my_id, is_ready)

# Update player information
func update_player_info(new_info: Dictionary):
	my_info.merge(new_info)
	
	if multiplayer.multiplayer_peer:
		var my_id = multiplayer.get_unique_id()
		rpc("_update_player_info", my_id, my_info)

# Start the match (host only)
func start_match():
	if is_host and multiplayer.multiplayer_peer:
		rpc("_start_match")

# Get the faction for a player ID
func get_player_faction(id: int) -> String:
	if player_info.has(id):
		return player_info[id].faction
	return "coalition"  # Default

# Get the team for a player ID
func get_player_team(id: int) -> int:
	if player_info.has(id):
		return player_info[id].team
	return 1  # Default

# Check if two players are allies
func are_allies(id1: int, id2: int) -> bool:
	return get_player_team(id1) == get_player_team(id2)

# Multiplayer callbacks
func _player_connected(id):
	# Someone connected, request their info
	if is_host:
		# Send existing players to the new player
		for pid in player_info:
			rpc_id(id, "_register_player", pid, player_info[pid])
			
		# Tell the new player to register themselves
		rpc_id(id, "_request_player_info", id)

func _player_disconnected(id):
	if player_info.has(id):
		player_info.erase(id)
		
	if players_ready.has(id):
		players_ready.erase(id)
		
	emit_signal("player_disconnected", id)

func _connected_to_server():
	var my_id = multiplayer.get_unique_id()
	rpc_id(1, "_register_player", my_id, my_info)
	emit_signal("connection_succeeded")

func _server_disconnected():
	disconnect_from_server()
	emit_signal("server_disconnected")

func _connection_failed():
	disconnect_from_server()
	emit_signal("connection_failed")

# RPCs
@rpc("any_peer", "reliable")
func _register_player(id, info):
	player_info[id] = info
	emit_signal("player_connected", id, info)

@rpc("any_peer", "reliable")
func _request_player_info(id):
	if multiplayer.get_unique_id() == id:
		rpc_id(1, "_register_player", id, my_info)

@rpc("any_peer", "reliable")
func _update_player_info(id, info):
	if player_info.has(id):
		player_info[id] = info
		emit_signal("player_info_updated", id, info)

@rpc("any_peer", "reliable")
func _player_ready(id, is_ready):
	players_ready[id] = is_ready
	
	# If host, check if all players are ready to start
	if is_host:
		var all_ready = true
		for player_id in player_info:
			if not players_ready.has(player_id) or not players_ready[player_id]:
				all_ready = false
				break
		
		if all_ready and player_info.size() > 1:
			# Auto-start when all players are ready
			start_match()

@rpc("authority", "reliable")
func _start_match():
	game_started = true
	emit_signal("match_started")
