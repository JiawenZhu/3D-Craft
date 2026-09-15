extends SceneTree
var game: Node3D
var failures: Array[String]=[]
var checked_upgrade:=false
var checked_dash:=false
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func frames(n: int) -> void:
	for i in n: await physics_frame
func select_upgrade() -> void:
	var level=game.survivor_level
	if not checked_upgrade:
		var elapsed: float=game.elapsed; var pos: Vector3=game.player.position
		game.pause_game(); await frames(12)
		check(game.status=="upgrading" and game.elapsed==elapsed and pos.distance_to(game.player.position)<.01,"Level up freezes time and movement; Pause cannot bypass choices")
		level.choose_upgrade(-1); check(game.status=="upgrading","Invalid upgrade index leaves choice pending")
		checked_upgrade=true
	var best:=0; var value:=-1.0
	for i in level.choices.size():
		var id: String=level.choices[i].id
		var score:=4.0 if id=="bolt" else 3.0 if id=="orbit" else 2.0 if id=="pulse" else 1.0
		if id=="vitality" and game.player.hp<80: score=8
		if score>value: best=i; value=score
	level.choose_upgrade(best)
func steer(goal: Vector3, dash:=false) -> void:
	var delta: Vector3=goal-game.player.position
	game.player.touch={"left":delta.x<-.4,"right":delta.x>.4,"forward":delta.z<-.4,"back":delta.z>.4,"dash":dash}
func run() -> void:
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	await frames(30)
	check(game.mode=="survivor" and game.player.position.y<1,"Cat starts on town collision floor")
	var start: Vector3=game.player.position
	game.player.touch={"forward":true,"dash":true}; await frames(12)
	check(game.player.dash_timer>2 and game.player.position.distance_to(start)>2,"Dash uses physical movement and consumes cooldown")
	game.player.touch.clear()
	var route: Array[Vector3]=[Vector3(0,0,24),Vector3(0,0,0),Vector3(-15,0,-12),Vector3(0,0,-12),Vector3(15,0,-12),Vector3(0,0,0)]
	var waypoint:=0
	for i in 16000:
		if game.status=="upgrading": await select_upgrade()
		if game.status!="playing": break
		if waypoint<route.size():
			if Vector2(game.player.position.x-route[waypoint].x,game.player.position.z-route[waypoint].z).length()<1.4: waypoint+=1
			if waypoint<route.size(): steer(route[waypoint])
		else:
			# An ordinary kite route through the open plaza keeps attacks and resource
			# collection active; it never moves bodies or changes combat statistics.
			var angle: float=game.elapsed*.27
			steer(Vector3(cos(angle)*10,0,sin(angle)*10),game.player.hp<50)
		await physics_frame
	check(game.survivor_level.shrine_count==3,"Real movement ignites all three shrine objectives")
	check(game.survivor_level.kills>15 and game.survivor_level.total_damage>1000,"Automatic weapons damage and defeat the horde")
	check(game.survivor_level.upgrades_chosen>=3,"Collected spirit shards create a multi-upgrade build")
	check(game.survivor_level.boss_spawned,"Warden arrives after 120 seconds and all shrines")
	check(game.status=="won" and game.survivor_level.boss_defeated,"Player defeats the Warden through normal movement and auto combat")
	print("RESULT "+JSON.stringify({"failures":failures,"state":game.snapshot()}))
	game.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
