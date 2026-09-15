extends SceneTree
var game: Node3D
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	for i in 70: await process_frame
	if game.mode=="dragon":
		game.player.touch={"ascend":true,"forward":true}
		for i in 60: await physics_frame
		game.player.touch={"fire":true}
		for i in 24: await physics_frame
	if game.mode=="survivor":
		for i in 900:
			if game.status=="upgrading": game.survivor_level.choose_upgrade(0)
			game.player.touch={"back":i<12}
			await physics_frame
		game.player.touch.clear()
	game.world.process_mode=Node.PROCESS_MODE_DISABLED
	game.status="paused"
	for body in game.world.get_children():
		if body is RigidBody3D: body.freeze=true
	await RenderingServer.frame_post_draw
	var output: String="/tmp/forma-game-"+game.mode+".png"
	var shot:=root.get_texture().get_image()
	shot.save_png(output)
	shot.save_jpg("/tmp/forma-game-"+game.mode+".jpg",.9)
	print("CAPTURE "+output)
	print("RENDER "+JSON.stringify({"mode":game.mode,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}))
	game.queue_free()
	await process_frame
	quit()
