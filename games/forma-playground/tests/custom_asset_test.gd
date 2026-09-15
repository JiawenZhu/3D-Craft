extends SceneTree
var game: Node3D
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	print(("PASS " if ok else "FAIL ")+text)
	if not ok: failures.append(text)
func frames(n: int) -> void:
	for i in n: await physics_frame
func wait_for_load() -> void:
	var deadline:=Time.get_ticks_msec()+65000
	while game.custom_asset.state.status=="loading" and Time.get_ticks_msec()<deadline: await process_frame
func run() -> void:
	var cases: Array=[
		["arena","vehicle","yellow_mini_car"],
		["race","vehicle","retro_camper_van"],
		["ruins","character","spherical_robot"],
		["survivor","character","lantern_cat"],
		["dragon","flying","spherical_robot"],
		["ruins","flying","baby_emerald_dragon"],
		["survivor","flying","baby_emerald_dragon"]]
	for data in cases:
		game=load("res://main.tscn").instantiate(); game.mode=data[0]; game.custom_asset_enabled=true; root.add_child(game)
		await frames(12)
		check(game.status=="loading" and game.custom_asset.state.status=="waiting" and game.elapsed==0 and game.player.freeze,"%s waits with the world frozen"%data[0])
		game.pause_game(); check(game.status=="loading","Pause cannot bypass custom loading")
		var original=game.player.visual
		if data[0]=="arena":
			game.custom_asset.load_asset({"id":"retry","name":"Invalid","kind":data[1],"yaw":0,"url":"http://localhost:3000/index.html"})
			await wait_for_load()
			check(game.custom_asset.state.status=="error" and game.status=="loading" and game.player.visual==original and not original.visible,"An invalid HTTP download errors and never plays a default model")
		var request: Dictionary={"id":"retry" if data[0]=="arena" else data[2],"name":data[2],"kind":data[1],"yaw":90 if data[0]=="ruins" else 0,"url":"http://localhost:3000/models/"+data[2]+".glb"}
		game.custom_asset.load_asset(request); game.custom_asset.load_asset(request)
		await wait_for_load()
		check(game.custom_asset.state.status=="ready" and game.status=="playing" and game.player.visual!=original,"%s imports an actual remote GLB and replaces the default"%data[0])
		if game.custom_asset.state.status!="ready":
			print("LOAD ERROR "+str(game.custom_asset.state)); game.queue_free(); await process_frame; continue
		check(game.player.visual.visible and not game.player.freeze,"Imported model is visible and physics resumes")
		if data[0] in ["survivor","dragon"]: check(game.player.poses.is_empty(),"Generic model does not receive bespoke cat or dragon deformation")
		if data[0]=="ruins": check(is_equal_approx(game.player.visual.get_child(0).rotation.y,PI/2),"Facing correction stays inside the steering wrapper")
		await frames(220 if data[0]=="race" else 35)
		var start: Vector3=game.player.position
		game.player.touch={"ascend":true,"forward":true} if data[0]=="dragon" else {"forward":true}
		await frames(75); game.player.touch.clear()
		check(game.player.position.distance_to(start)>1.0,"%s custom asset moves through its existing physics adapter"%data[0])
		if data[0]=="arena":
			game.player.touch={"fire":true}; await frames(25); game.player.touch.clear()
			check(game.player.shot_timer>0,"Custom vehicle retains the arena weapon adapter")
		if data[0]=="dragon": check(is_instance_valid(game.player.mouth) and game.player.flying,"Custom flying asset retains flight and the breath socket")
		game.queue_free(); await process_frame
	print("RESULT "+JSON.stringify({"failures":failures}))
	quit(0 if failures.is_empty() else 1)
