extends SceneTree
# Drives the production controller with the same held inputs as the web buttons.
# No teleportation, health overrides, disabled enemies or forced finish flags.
var game: Node3D
func _initialize() -> void:
	run.call_deferred()
func drive_to(target: Vector3, desired_speed: float, fire: bool=false) -> void:
	var car: RigidBody3D=game.player
	var delta:=target-car.position
	var local:=car.global_basis.inverse()*delta
	var angle:=atan2(-local.x,-local.z)
	var correction:=angle-car.angular_velocity.y*.32
	var speed: float=car.linear_velocity.dot(-car.global_basis.z)
	var target_speed: float=desired_speed*clampf(1-absf(angle),.08,1)
	car.touch={"forward":speed<target_speed,"brake":speed>target_speed+2,"left":correction>.045,"right":correction<-.045,"fire":fire and absf(angle)<.18}
func run() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	var last_score: int=-1
	for i in 60*145:
		await physics_frame
		if game.status!="playing": break
		if game.mode=="race":
			drive_to(game.checkpoints[mini(game.checkpoint,7)],11)
		else:
			var closest: RigidBody3D=null
			for enemy in game.enemies:
				if closest==null or enemy.position.distance_squared_to(game.player.position)<closest.position.distance_squared_to(game.player.position): closest=enemy
			if closest:
				var distance: float=closest.position.distance_to(game.player.position)
				drive_to(closest.position,8 if distance>14 else 0,true)
		if game.score!=last_score:
			last_score=game.score
			print("PROGRESS "+JSON.stringify(game.snapshot()))
	game.player.touch.clear()
	print("RESULT "+JSON.stringify(game.snapshot()))
	var passed: bool=game.status=="won"
	game.queue_free()
	await process_frame
	quit(0 if passed else 1)
