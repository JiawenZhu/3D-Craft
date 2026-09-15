extends Node3D
const G = preload("res://scripts/geometry.gd")
const A = preload("res://scripts/assets.gd")
const Levels = preload("res://scripts/levels.gd")
const Vehicle = preload("res://scripts/vehicle.gd")
const Prop = preload("res://scripts/prop.gd")
const DragonLevel=preload("res://scripts/dragon_level.gd")
var dragon_level: Node3D
const SurvivorLevel=preload("res://scripts/survivor_level.gd")
var survivor_level: Node3D
const CustomAsset=preload("res://scripts/custom_asset.gd")
var custom_asset: Node
var custom_asset_enabled:=false
var custom_frozen_bodies: Dictionary={}
const Bullet = preload("res://scripts/projectile.gd")
var language := "en"
var mode := "arena"
var chosen := "scout"
var status := "playing"
var elapsed := 0.0
var score := 0
var target_count := 0
var collision_count := 0
var explosion_count := 0
var spawned_count := 0
var world: Node3D
var player: RigidBody3D
var camera: Camera3D
var rng := RandomNumberGenerator.new()
var enemies: Array = []
var rivals: Array = []
var checkpoints: Array[Vector3] = []
var checkpoint := 0
var countdown := 0.0
var finish_order: Array = []
var cores: Array[MeshInstance3D] = []
var gate: Node3D
var plate_pos := Vector3.ZERO
var puzzle_crate: RigidBody3D
var gate_open := false
var exit_pos := Vector3.ZERO
var notice := ""
var hud_timer := 0.0
var shake := 0.0
var props: Array = []
var sfx: Dictionary = {}
var mute := false
var started := false
var spawn_cooldown := 0.0
var frozen_input := false

func _ready() -> void:
	add_to_group("forma_game")
	rng.seed=90326
	if OS.has_feature("web"):
		language=str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('lang') || 'en'"))
		mode=str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('mode') || 'arena'"))
		custom_asset_enabled=bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('custom')==='1'"))
		chosen=str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('vehicle') || 'scout'"))
		JavaScriptBridge.eval("window._formaQueue=[];window.addEventListener('message',e=>{if(e.origin===location.origin&&e.source===parent&&e.data&&e.data.channel==='forma-game')window._formaQueue.push(e.data)});window.addEventListener('blur',()=>window._formaQueue.push({action:'release'}));")
	else:
		for arg in OS.get_cmdline_user_args():
			if arg=="custom=1": custom_asset_enabled=true
			if arg.begins_with("lang="): language=arg.trim_prefix("lang=")
			if arg.begins_with("mode="): mode=arg.trim_prefix("mode=")
			if arg.begins_with("vehicle="): chosen=arg.trim_prefix("vehicle=")
	if language not in ["en","zh"]: language="en"
	if mode not in ["arena","race","ruins","dragon","survivor"]: mode="arena"
	if chosen not in ["scout","heavy","cat"]: chosen="scout"
	# Every scene fills the actual phone or desktop viewport, without 16:9 bars.
	get_tree().root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	for name in ["shot","boom","collect"]:
		sfx[name]=load("res://assets/"+name+".wav")
	build_environment()
	world=Node3D.new()
	add_child(world)
	if mode=="dragon":
		dragon_level=DragonLevel.new(); dragon_level.build(self)
	elif mode=="survivor":
		survivor_level=SurvivorLevel.new(); survivor_level.build(self)
	else: Levels.build(self)
	countdown=3.0 if mode=="race" else 0.0
	camera=Camera3D.new()
	add_child(camera)
	camera.current=true
	camera.fov=52 if mode=="survivor" else 58
	camera.far=180
	if mode=="ruins":
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.size=20
	camera.position=player.position+Vector3(0,8,13)
	update_camera(1.0)
	started=true
	if custom_asset_enabled:
		custom_asset=CustomAsset.new(); add_child(custom_asset); custom_asset.configure(self)
		block_custom_world()
	send_state()

func build_environment() -> void:
	var we:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_SKY
	var sky:=Sky.new()
	var sky_mat:=ProceduralSkyMaterial.new()
	# Bright, neutral daylight keeps imported materials legible from every side.
	# Keep each world's palette, but do not hide user assets in a night exposure.
	sky_mat.sky_top_color=Color("78b3d3")
	sky_mat.sky_horizon_color=Color("e1e8df") if mode!="race" else Color("f6d3b5")
	sky_mat.ground_bottom_color=Color("c1cbd0")
	sky_mat.ground_curve=.1
	sky_mat.ground_horizon_color=sky_mat.sky_horizon_color
	sky.sky_material=sky_mat
	env.sky=sky
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("f2f4f7")
	env.ambient_light_energy=.8
	env.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	env.fog_enabled=true
	env.fog_sky_affect=.1
	env.fog_light_color=Color("d4dfe0")
	env.fog_density=.002
	we.environment=env
	add_child(we)
	var sun:=DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees=Vector3(-48,-32,0)
	sun.light_color=Color("fff5e7")
	sun.light_energy=.7
	sun.shadow_enabled=true
	sun.light_angular_distance=.6
	sun.directional_shadow_max_distance=80
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# A shadow-free opposite fill reaches the back of turning characters. It is
	# shared by all players, including runtime GLBs, instead of a front spotlight.
	var bounce:=DirectionalLight3D.new()
	add_child(bounce)
	bounce.rotation_degrees=Vector3(-28,148,0)
	bounce.light_color=Color("e4efff")
	bounce.light_energy=.35
	bounce.shadow_enabled=false

func spawn_player(pos: Vector3, yaw: float) -> void:
	player=Vehicle.new()
	world.add_child(player)
	player.position=pos
	player.rotation.y=yaw
	player.configure(self,chosen,false,mode=="ruins")
	player.spawn_point=pos
	var fill:=OmniLight3D.new()
	player.add_child(fill)
	fill.position=Vector3(0,2.8,2.4)
	fill.light_color=Color("d9e8ef") if mode!="ruins" else Color("ffdea3")
	fill.light_energy=2.0
	fill.omni_range=7.0

func spawn_enemy(pos: Vector3) -> void:
	var enemy:=Vehicle.new()
	world.add_child(enemy)
	enemy.position=pos
	enemy.rotation.y=PI
	enemy.configure(self,"heavy",true)
	enemy.hp=100
	enemy.max_hp=100
	enemies.append(enemy)

func spawn_rival(pos: Vector3) -> void:
	var rival:=Vehicle.new()
	world.add_child(rival)
	rival.position=pos
	rival.rotation.y=-PI/2
	rival.configure(self,"heavy" if rivals.size()==0 else "scout",true)
	rival.team=2
	rival.set_meta("checkpoint",0)
	rivals.append(rival)

func spawn_prop(pos: Vector3, explosive: bool, generated := false) -> RigidBody3D:
	var body:=Prop.new()
	body.game=self
	body.explosive=explosive
	body.mass=18 if explosive else 24
	body.continuous_cd=true
	var pm:=PhysicsMaterial.new()
	pm.friction=.65
	pm.bounce=.18
	body.physics_material_override=pm
	world.add_child(body)
	body.position=pos
	var col:=CollisionShape3D.new()
	if explosive:
		var shape:=CylinderShape3D.new()
		shape.radius=.45
		shape.height=1.8
		col.shape=shape
		G.cylinder(body,Vector3.ZERO,.46,1.8,Color("bd553d"))
		for y in [-.68,.68]: G.cylinder(body,Vector3(0,y,0),.475,.12,Color("e6c699"))
		G.label(body,"!",Vector3(0,.15,-.47),Color("ffe4af"),48)
	else:
		var shape:=BoxShape3D.new()
		shape.size=Vector3.ONE*1.1
		col.shape=shape
		if generated:
			var asset:=A.model("magma_cube",1.1)
			body.add_child(asset)
			asset.position.y=-.5
		else:
			G.box(body,Vector3.ZERO,Vector3.ONE*1.1,Color("bc9368"))
			for x in [-.44,.44]: G.box(body,Vector3(x,0,-.56),Vector3(.11,1.1,.035),Color("715d4b"))
			for y in [-.42,.42]: G.box(body,Vector3(0,y,-.56),Vector3(1.1,.11,.035),Color("715d4b"))
	body.add_child(col)
	props.append(body)
	return body

func shoot(vehicle: RigidBody3D) -> void:
	var bullet:=Bullet.new()
	bullet.game=self
	bullet.shooter=vehicle
	bullet.damage=12 if vehicle.team else 48
	bullet.mass=.3
	bullet.gravity_scale=.12
	world.add_child(bullet)
	bullet.position=vehicle.global_position-vehicle.global_basis.z*2.1+Vector3.UP*1.05
	var col:=CollisionShape3D.new()
	var sphere:=SphereShape3D.new()
	sphere.radius=.2
	col.shape=sphere
	bullet.add_child(col)
	G.orb(bullet,Vector3.ZERO,.19,Color("ffc67e"),2)
	bullet.add_collision_exception_with(vehicle)
	bullet.linear_velocity=-vehicle.global_basis.z*48+vehicle.linear_velocity
	vehicle.apply_central_impulse(vehicle.global_basis.z*vehicle.mass*.12)
	play_sound("shot",bullet.position,-14)

func explode(pos: Vector3, radius: float, damage: float, shooter: Node) -> void:
	if not is_inside_tree(): return
	explosion_count+=1
	shake=maxf(shake,.3*(1-clampf(pos.distance_to(player.position)/40,0,1)))
	play_sound("boom",pos,-8)
	var fx:=G.orb(world,pos,.3,Color("ffb25d"),3)
	var tween:=fx.create_tween()
	tween.tween_property(fx,"scale",Vector3.ONE*radius*2,.15)
	tween.tween_property(fx,"scale",Vector3.ZERO,.25)
	tween.tween_callback(fx.queue_free)
	for i in 9:
		var shard:=RigidBody3D.new()
		world.add_child(shard)
		shard.position=pos+Vector3(rng.randf_range(-.2,.2),.3,rng.randf_range(-.2,.2))
		G.box(shard,Vector3.ZERO,Vector3.ONE*.17,Color("765f4a"))
		shard.linear_velocity=Vector3(rng.randf_range(-7,7),rng.randf_range(3,10),rng.randf_range(-7,7))
		shard.angular_velocity=Vector3(5,8,3)
		after(2.5,shard.queue_free)
	for body in props+enemies+rivals+[player]:
		if not is_instance_valid(body) or body.is_queued_for_deletion(): continue
		var delta: Vector3=body.global_position-pos
		var distance: float=delta.length()
		if distance>radius: continue
		var strength:=1-distance/radius
		body.apply_central_impulse((delta.normalized()+Vector3.UP*.65)*strength*body.mass*7)
		if body is Prop:
			if body.explosive and not body.detonated:
				after(.12,body.detonate)
		else:
			if not is_instance_valid(shooter) or body.team != shooter.team:
				body.hp-=damage*maxf(.35,strength)

func destroy_vehicle(vehicle: RigidBody3D) -> void:
	if vehicle==player:
		status="lost"
		notice="Vehicle disabled. Retry to return to the field."
		send_state()
		return
	if vehicle.is_queued_for_deletion(): return
	enemies.erase(vehicle)
	rivals.erase(vehicle)
	explode(vehicle.position,5,35,vehicle)
	vehicle.queue_free()
	if mode=="arena":
		score+=1
		if score>=target_count:
			status="won"
			notice="Arena cleared. Your generated assets held the field."

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				if mode!="survivor": recover_player()
			KEY_E:
				if mode!="survivor": interact() if mode=="ruins" else drop_object(true)
			KEY_Q:
				if mode!="survivor": drop_object(false)
			KEY_ESCAPE, KEY_P: pause_game()
			KEY_1, KEY_2, KEY_3:
				if mode=="survivor": survivor_level.choose_upgrade(event.keycode-KEY_1)

func pause_game() -> void:
	if status not in ["playing","paused"]: return
	status="playing" if status=="paused" else "paused"
	for body in world.get_children():
		if body is RigidBody3D:
			body.freeze=status=="paused"
	world.process_mode=Node.PROCESS_MODE_DISABLED if status=="paused" else Node.PROCESS_MODE_INHERIT
	player.touch.clear()
	send_state()

func recover_player() -> void:
	if not is_instance_valid(player) or status!="playing": return
	var pos: Vector3=player.spawn_point
	if mode=="race" and checkpoint>0: pos=checkpoints[checkpoint-1]+Vector3.UP*1.4
	player.linear_velocity=Vector3.ZERO
	player.angular_velocity=Vector3.ZERO
	var yaw: float=0
	if mode=="race":
		var direction: Vector3=checkpoints[mini(checkpoint,7)]-pos
		yaw=atan2(-direction.x,-direction.z)
	player.rotation=Vector3(0,yaw,0)
	player.position=pos
	if mode=="dragon": player.flying=false; dragon_level.last_position=pos
	player.hp=maxf(player.hp-8,10)
	notice="Recovered at the last checkpoint."

func drop_object(explosive: bool) -> void:
	if mode=="survivor" or status!="playing" or spawn_cooldown>0: return
	spawn_cooldown=.5
	props=props.filter(func(p): return is_instance_valid(p))
	if props.size()>65:
		notice="Object limit reached. Restart to clear the playground."
		return
	var prop:=spawn_prop(player.position-player.global_basis.z*5+Vector3.UP*3,explosive,not explosive)
	prop.linear_velocity=player.linear_velocity-player.global_basis.z*2
	spawned_count+=1

func interact() -> void:
	if status!="playing": return
	for core in cores.duplicate():
		if core.position.distance_to(player.position)<2:
			cores.erase(core)
			core.queue_free()
			score+=1
			play_sound("collect",player.position,-8)
			notice="Signal recovered · %d / 3"%score
			return
	if score==3 and player.position.distance_to(exit_pos)<3:
		status="won"
		notice="The signal is restored. The ruins are awake."

func _physics_process(dt: float) -> void:
	if not started: return
	read_bridge()
	if status=="playing" and countdown>0:
		countdown=maxf(0,countdown-dt)
		update_camera(dt)
		send_state()
		return
	if status=="playing":
		elapsed+=dt
		spawn_cooldown-=dt
		if mode=="race":
			if checkpoint<checkpoints.size() and player.position.distance_to(checkpoints[checkpoint])<5.5:
				checkpoint+=1
				score=checkpoint
				play_sound("collect",player.position,-12)
				if checkpoint==8:
					finish_order.append(player)
					status="won"
					notice="Finish line! All eight checkpoints cleared."
			for rival in rivals:
				var cp: int=rival.get_meta("checkpoint",0)
				if cp<8 and rival.position.distance_to(checkpoints[cp])<6:
					rival.set_meta("checkpoint",cp+1)
					if cp==7: finish_order.append(rival)
			if elapsed>150 and status=="playing":
				status="lost"
				notice="Time is up. Try a faster line through the course."
		elif mode=="ruins":
			if is_instance_valid(puzzle_crate) and Vector2(puzzle_crate.position.x-plate_pos.x,puzzle_crate.position.z-plate_pos.z).length()<1.4:
				gate_open=true
			gate.position.y=lerpf(gate.position.y,5.3 if gate_open else 1.6,dt*3)
			for core in cores: core.rotation.y+=dt
	update_camera(dt)
	hud_timer-=dt
	if hud_timer<=0:
		hud_timer=.2
		send_state()

func update_camera(dt: float) -> void:
	if not camera or not is_instance_valid(player): return
	var offset:=Vector3(14,18,14) if mode=="ruins" else (Vector3(0,8,12) if mode=="race" else Vector3(3.3,3.5,7) if mode=="dragon" else Vector3(0,5.8,8.5))
	if mode=="survivor": offset=Vector3(0,10,11)
	if mode not in ["ruins","survivor"]: offset=player.global_basis.orthonormalized()*offset
	var target: Vector3=player.position+offset
	camera.position=camera.position.lerp(target,1-exp(-dt*5))
	var look: Vector3=player.position+Vector3.UP*.6
	if mode not in ["ruins","survivor"]: look-=player.global_basis.z*(7 if mode=="arena" else 4)
	shake=maxf(0,shake-dt)
	camera.position+=Vector3(rng.randf_range(-shake,shake),rng.randf_range(-shake,shake),0)
	camera.look_at(look)

func set_language(value: String) -> void:
	language="zh" if value=="zh" else "en"
	for sign in get_tree().get_nodes_in_group("localized_signs"):
		sign.text=sign.get_meta(language)

func read_bridge() -> void:
	if not OS.has_feature("web"): return
	var data=JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(window._formaQueue.splice(0))")))
	if not data is Array: return
	for cmd in data:
		match cmd.get("action",""):
			"load_asset":
				if custom_asset_enabled and cmd.get("asset") is Dictionary: custom_asset.load_asset(cmd.asset)
			"input": player.touch[cmd.get("key","")]=cmd.get("down",false)
			"release": player.touch.clear()
			"upgrade":
				if mode=="survivor": survivor_level.choose_upgrade(int(cmd.get("index",-1)))
			"pause": pause_game()
			"recover":
				if mode!="survivor": recover_player()
			"restart": get_tree().reload_current_scene()
			"crate": drop_object(false)
			"barrel": drop_object(true)
			"interact": interact()
			"language": set_language(str(cmd.get("value","en")))
			"mute":
				mute=bool(cmd.get("value",false))
				AudioServer.set_bus_mute(0,mute)

func snapshot() -> Dictionary:
	var hint := ""
	if mode=="ruins":
		for core in cores:
			if core.position.distance_to(player.position)<2: hint="E · Recover signal"
		if score==3: hint="Return to THE SIGNAL and press E"
	var place:=1
	for rival in rivals:
		var other_cp: int=rival.get_meta("checkpoint",0)
		if other_cp>checkpoint or (other_cp==checkpoint and checkpoint<8 and rival.position.distance_squared_to(checkpoints[checkpoint])<player.position.distance_squared_to(checkpoints[checkpoint])): place+=1
	if player in finish_order: place=finish_order.find(player)+1
	var aim:=Vector2(.5,.5)
	if mode in ["arena","dragon"] and camera:
		var muzzle:=player.position-player.global_basis.z*2.1+Vector3.UP*1.05
		var far_point:=muzzle-player.global_basis.z*45
		if mode=="dragon":
			muzzle=player.mouth.global_position
			far_point=dragon_level.breath_target(muzzle,-player.global_basis.z)
		var query:=PhysicsRayQueryParameters3D.create(muzzle,far_point)
		query.exclude=[player.get_rid()]
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		if hit: far_point=hit.position
		aim=camera.unproject_position(far_point)/get_viewport().get_visible_rect().size
	var actors: Array=[]
	for other in enemies+rivals:
		if is_instance_valid(other): actors.append([other.position.x,other.position.z])
	var objectives: Array=[]
	if mode=="ruins":
		for core in cores: objectives.append([core.position.x,core.position.z])
	elif mode in ["race","dragon"]:
		for point in checkpoints: objectives.append([point.x,point.z])
	if mode=="survivor":
		for foe in survivor_level.foes:
			if is_instance_valid(foe) and not foe.dead: actors.append([foe.position.x,foe.position.z])
		for shrine in survivor_level.shrines:
			if not shrine.active: objectives.append([shrine.point.x,shrine.point.z])
	var dragon_data: Dictionary={}
	if mode=="dragon":
		dragon_data={"flying":player.flying,"fuel":roundi(player.fuel),"recharging":player.recharging,"points":dragon_level.points,"combo":dragon_level.combo,"targets":[]}
		for target in dragon_level.targets:
			if not target.cleared: dragon_data.targets.append([target.position.x,target.position.z])
	return {"customAsset":custom_asset.state.duplicate() if custom_asset_enabled and custom_asset else {},"survivor":survivor_level.snapshot() if mode=="survivor" else {},"dragon":dragon_data,"aim":[aim.x,aim.y],"heading":player.visual.rotation.y+PI if mode in ["ruins","survivor"] else player.rotation.y,"actors":actors,"objectives":objectives,"countdown":ceilf(countdown),"channel":"forma-state","mode":mode,"status":status,"elapsed":snappedf(elapsed,.1),"speed":roundi(player.linear_velocity.length()*3.6),"health":maxi(0,roundi(player.hp/player.max_hp*100)),"score":score,"target":target_count,"checkpoint":checkpoint,"place":place,"notice":notice,"hint":hint,"gateOpen":gate_open,"collisions":collision_count,"explosions":explosion_count,"spawned":spawned_count,"fps":Engine.get_frames_per_second(),"position":[snappedf(player.position.x,.01),snappedf(player.position.y,.01),snappedf(player.position.z,.01)]}

func send_state() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("parent.postMessage("+JSON.stringify(snapshot())+",location.origin)")

func play_sound(id: String, pos: Vector3, volume: float) -> void:
	if not sfx.has(id) or DisplayServer.get_name()=="headless": return
	var sound:=AudioStreamPlayer3D.new()
	world.add_child(sound)
	sound.position=pos
	sound.stream=sfx[id]
	sound.volume_db=volume
	sound.max_distance=70
	sound.unit_size=12
	sound.play()
	sound.finished.connect(sound.queue_free)

# Scene-owned timers stop with the world and are freed with the level.
func after(seconds: float, callback: Callable) -> void:
	var timer:=Timer.new()
	timer.one_shot=true
	timer.wait_time=seconds
	world.add_child(timer)
	timer.timeout.connect(callback)
	timer.timeout.connect(timer.queue_free)
	timer.start()


func block_custom_world() -> void:
	status="loading"
	player.touch.clear()
	player.visual.visible=false
	freeze_custom_bodies(world)
	world.process_mode=Node.PROCESS_MODE_DISABLED

func freeze_custom_bodies(node: Node) -> void:
	if node is RigidBody3D:
		if not custom_frozen_bodies.has(node.get_instance_id()): custom_frozen_bodies[node.get_instance_id()]=node.freeze
		node.freeze=true
	for child in node.get_children(): freeze_custom_bodies(child)

func release_custom_world() -> void:
	for id in custom_frozen_bodies:
		var body=instance_from_id(id)
		if is_instance_valid(body): body.freeze=custom_frozen_bodies[id]
	custom_frozen_bodies.clear()
	world.process_mode=Node.PROCESS_MODE_INHERIT
	player.visual.visible=true
	player.touch.clear()
	elapsed=0
	status="playing"
