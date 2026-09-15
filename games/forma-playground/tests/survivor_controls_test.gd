extends SceneTree
var game: Node3D
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func key_event(key: Key, down: bool) -> void:
	var event:=InputEventKey.new(); event.keycode=key; event.physical_keycode=key; event.pressed=down
	Input.parse_input_event(event)
func move_key(key: Key, direction: Vector3, label: String) -> void:
	var start: Vector3=game.player.position
	key_event(key,true); await frames(24); key_event(key,false); await frames(8)
	check((game.player.position-start).dot(direction)>1,label)
func run() -> void:
	game=load("res://main.tscn").instantiate(); root.add_child(game); await frames(30)
	# DOM controls and keys inside the focused Godot iframe must agree.
	await move_key(KEY_UP,Vector3.FORWARD,"Focused game: Up arrow moves forward")
	await move_key(KEY_DOWN,Vector3.BACK,"Focused game: Down arrow moves back")
	await move_key(KEY_LEFT,Vector3.LEFT,"Focused game: Left arrow moves left")
	await move_key(KEY_RIGHT,Vector3.RIGHT,"Focused game: Right arrow moves right")
	game.survivor_level.offer_upgrades(); game.survivor_level.choose_upgrade(0)
	await move_key(KEY_UP,Vector3.FORWARD,"Arrow movement resumes after choosing an upgrade")
	game.pause_game(); await frames(12); game.pause_game()
	await move_key(KEY_DOWN,Vector3.BACK,"Arrow movement resumes after pause")
	await move_key(KEY_W,Vector3.FORWARD,"WASD remains functional")
	# Recreate the south boundary in the user's screenshot using ordinary controls.
	game.player.touch={"back":true}
	for i in 400:
		if game.status=="upgrading": game.survivor_level.choose_upgrade(0)
		await physics_frame
	game.player.touch.clear()
	check(game.player.position.z>31 and game.player.position.z<33,"South wall stops the player inside the map")
	await move_key(KEY_UP,Vector3.FORWARD,"Up arrow escapes the south boundary")
	print("RESULT "+JSON.stringify({"failures":failures}))
	game.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
