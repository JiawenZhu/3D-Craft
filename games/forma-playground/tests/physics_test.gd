extends SceneTree
var game: Node3D
var failures: Array[String]=[]
func _initialize() -> void:
	run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func verify(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ")+message)
	if not condition: failures.append(message)
func travel(target: Vector3, limit:=600) -> bool:
	for i in limit:
		var delta: Vector3=target-game.player.position
		delta.y=0
		if delta.length()<.7:
			game.player.touch.clear()
			await frames(20)
			return true
		var local: Vector3=delta.rotated(Vector3.UP,-PI/4)
		game.player.touch={"left":local.x<-.18,"right":local.x>.18,"forward":local.z<-.18,"back":local.z>.18}
		await physics_frame
	game.player.touch.clear()
	return false
func run() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	# Isolate component physics here; competition_test keeps every rival active.
	for v in game.enemies+game.rivals: v.set_physics_process(false)
	await frames(120)
	verify(game.player.position.y>0 and game.player.position.y<2,"Player settles on the collision ground")
	var crate: RigidBody3D=game.spawn_prop(Vector3(5,8,11),false)
	await frames(150)
	verify(crate.position.y<2 and crate.position.y>-.1,"Dropped rigid body falls and rests on the floor")
	if game.mode=="ruins":
		verify(await travel(Vector3(-6,0,5.7)),"Physical player pushes the crate forward")
		verify(game.gate_open,"Crate weight opens the gate")
		verify(await travel(Vector3(-6,0,-4)),"Player crosses the opened gate")
		await travel(Vector3(-9,0,-7)); game.interact()
		verify(game.score==1,"First signal collected by proximity interaction")
		await travel(Vector3(7,0,-7)); game.interact()
		verify(game.score==2,"Second signal collected")
		await travel(Vector3(-6,0,-4)); await travel(Vector3(-6,0,6)); await travel(Vector3(8,0,9)); game.interact()
		verify(game.score==3,"Third signal collected")
		await travel(Vector3(-6,0,6)); await travel(Vector3(-6,0,-5)); await travel(Vector3(0,0,-13)); game.interact()
		verify(game.status=="won","Actual movement, puzzle and collection reaches the exit victory")
	else:
		for v in game.enemies+game.rivals: v.set_physics_process(false)
		var start: Vector3=game.player.position
		game.player.touch={"forward":true}
		var distance:=0.0
		for i in 120:
			await physics_frame
			distance=maxf(distance,game.player.position.distance_to(start))
		game.player.touch.clear()
		verify(distance>5,"Suspension vehicle accelerates under engine forces")
		game.pause_game()
		var at_pause: Vector3=game.player.position
		await frames(90)
		verify(game.player.position.distance_to(at_pause)<.05,"Pause freezes physical motion")
		game.pause_game()
		game.recover_player()
		await frames(60)
		var barrel: RigidBody3D=game.spawn_prop(game.player.position-game.player.global_basis.z*8+Vector3.UP*.1,true)
		await frames(60)
		if game.mode=="arena":
			game.player.touch={"fire":true}
			await frames(160)
			game.player.touch.clear()
			verify(not is_instance_valid(barrel),"Real projectile contact detonates the barrel")
			verify(game.explosion_count>0,"Explosion feedback and impulse path executed")
		else:
			game.player.touch={"forward":true}
			await frames(160)
			game.player.touch.clear()
			verify(not is_instance_valid(barrel),"Vehicle impact detonates an explosive barrel")
			verify(game.collision_count>0,"Vehicle and environment collision contacts recorded")
		game.drop_object(false)
		verify(game.spawned_count==1,"Player can spawn a generated asset as a physical object")
	print("RESULT "+JSON.stringify({"mode":game.mode,"failures":failures,"state":game.snapshot()}))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
