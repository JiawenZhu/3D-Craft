extends SceneTree
var game: Node3D
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func frames(n: int) -> void:
	for i in n: await physics_frame
func travel(goal: Vector3, tolerance:=1.2) -> bool:
	for i in 2000:
		var p=game.player
		if game.status!="playing": return false
		var delta: Vector3=goal-p.position
		var flat:=Vector2(delta.x,delta.z).length()
		if flat<tolerance and absf(delta.y)<.7:
			p.touch.clear(); await frames(20); return true
		var yaw:=atan2(-delta.x,-delta.z)
		var turn:=wrapf(yaw-p.rotation.y,-PI,PI)
		p.touch={"left":turn>.035,"right":turn<-.035,"forward":flat>tolerance*.7 and absf(turn)<.4,"ascend":delta.y>.45,"descend":delta.y<-.45}
		await physics_frame
	return false
func run() -> void:
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	await frames(60)
	var p=game.player
	check(game.mode=="dragon" and p.grounded,"Dragon starts grounded at its nest")
	var start: Vector3=p.position
	p.touch={"forward":true}; await frames(90); p.touch.clear()
	check(p.position.distance_to(start)>3 and p.position.y<2,"Dragon runs using physical ground movement")
	p.touch={"ascend":true}; await frames(100); p.touch.clear(); await frames(30)
	check(p.flying and p.position.y>8,"Takeoff climbs into the sky")
	var hover: float=p.position.y; await frames(90)
	check(absf(p.position.y-hover)<1,"Released ascent holds altitude")
	for i in 8:
		var arrived:=await travel(game.checkpoints[i])
		check(arrived and game.checkpoint>i,"Flight reaches ring %d through real controls"%(i+1))
	for target in game.dragon_level.targets:
		if target.cleared: continue
		var arrived:=await travel(target.position+Vector3(0,-.6,10))
		check(arrived,"Approached crystal through flight controls")
		for i in 360:
			if target.cleared or game.status!="playing": break
			var delta: Vector3=target.position-p.mouth.global_position
			var turn:=wrapf(atan2(-delta.x,-delta.z)-p.rotation.y,-PI,PI)
			p.touch={"left":turn>.035,"right":turn<-.035,"fire":absf(turn)<.25}
			await physics_frame
		p.touch.clear()
		check(target.cleared,"Mouth flame damages and destroys crystal")
		await frames(80)
	check(game.score==6 and game.explosion_count>=6,"Six targets create actual fire impact explosions")
	await travel(game.dragon_level.nest+Vector3.UP*3)
	p.touch={"descend":true}; await frames(100); p.touch.clear()
	check(game.status=="won","All rings, crystals and physical landing complete the adventure")
	print("RESULT "+JSON.stringify({"failures":failures,"state":game.snapshot()}))
	game.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
