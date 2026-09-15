extends RigidBody3D

var game: Node3D
var visual: Node3D
var team := 0
var hp := 100.0
var max_hp := 100.0
var kind := "scout"
var explorer := false
var throttle := 0.0
var steer := 0.0
var braking := false
var boosting := false
var grounded := false
var shot_timer := 0.0
var jump_timer := 0.0
var touch: Dictionary = {}
var damage_cooldown := 0.0
var spawn_point := Vector3.ZERO
var wheels: Array[Node3D] = []
var health_bar: MeshInstance3D
const A = preload("res://scripts/assets.gd")
const G = preload("res://scripts/geometry.gd")

func configure(owner_game: Node3D, model_kind: String, enemy := false, walking := false) -> void:
	game = owner_game
	kind = model_kind
	team = 1 if enemy else 0
	explorer = walking
	mass = 65 if walking else (1100 if kind == "heavy" else 720)
	max_hp = 240 if kind == "heavy" else 160
	hp = max_hp
	linear_damp = .12
	angular_damp = 2.5
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	var pm := PhysicsMaterial.new()
	pm.friction = .2 if not walking else .8
	pm.bounce = .05
	physics_material_override = pm
	var col := CollisionShape3D.new()
	if walking:
		var capsule := CapsuleShape3D.new()
		capsule.radius = .42
		capsule.height = 1.5
		col.shape = capsule
		axis_lock_angular_x = true
		axis_lock_angular_z = true
		axis_lock_angular_y = true
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(1.6,.65,2.8)
		col.shape = box
	add_child(col)
	if not walking and game.mode == "arena":
		var turret_col := CollisionShape3D.new()
		var turret_shape := BoxShape3D.new()
		turret_shape.size = Vector3(1.4,1.1,1.6)
		turret_col.shape = turret_shape
		turret_col.position.y = .8
		add_child(turret_col)
	var asset_id := "spherical_robot" if walking else ("retro_camper_van" if kind == "heavy" else "yellow_mini_car")
	if kind == "cat": asset_id = "boba_cat"
	visual = Node3D.new() if game.custom_asset_enabled and not enemy else A.model(asset_id,1.55 if walking else 3.1)
	add_child(visual)
	visual.position.y = -.6 if walking else (-.5 if kind=="cat" else -.82)
	if asset_id == "yellow_mini_car": visual.rotation.y = PI
	if asset_id == "retro_camper_van": visual.rotation.y = PI
	if not walking:
		var accent := Color("fb864e") if enemy else Color("71e7df")
		if game.mode == "arena":
			G.cylinder(self,Vector3(0,.62,.3),.45,.45,Color("283b47"))
			G.box(self,Vector3(0,1.05,.3),Vector3(1.3,.45,1.2),Color("283b47"))
			for x in [-.36,.36]:
				var gun := G.cylinder(self,Vector3(x,1.1,-.7),.13,2.0,Color("263642"))
				gun.rotation.x = PI/2
				G.orb(self,Vector3(x,1.1,-1.72),.13,accent,1.4)
			var pilot := A.model("baby_emerald_dragon" if enemy else "spherical_robot",.7)
			add_child(pilot)
			pilot.position = Vector3(0,1.35,.65)
		if kind=="cat":
			for x in [-.9,.9]:
				for z in [-.95,.95]:
					var wheel := G.cylinder(self,Vector3(x,-.3,z),.36,.22,Color("202a32"))
					wheel.rotation.z = PI/2
					wheels.append(wheel)
	if enemy and game.mode=="arena":
		var background:=MeshInstance3D.new()
		var quad:=QuadMesh.new()
		quad.size=Vector2(2.3,.16)
		background.mesh=quad
		background.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var bg:=G.mat(Color("26373a")).duplicate()
		bg.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		bg.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
		background.material_override=bg
		add_child(background)
		background.position=Vector3(0,3.1,0)
		health_bar=MeshInstance3D.new()
		health_bar.mesh=quad
		health_bar.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var red:=bg.duplicate()
		red.albedo_color=Color("ef9874")
		red.render_priority=1
		red.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		red.no_depth_test=true
		red.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
		health_bar.material_override=red
		add_child(health_bar)
		health_bar.position=Vector3(0,3.1,.01)
		G.label(self,"RAIDER",Vector3(0,3.5,0),Color("ffd9ad"),23)
	body_entered.connect(_impact)

func _impact(other: Node) -> void:
	game.collision_count += 1
	if team == 0 and not explorer and linear_velocity.length() > 9 and damage_cooldown <= 0:
		hp -= maxf(1,(linear_velocity.length()-8)*.55)
		damage_cooldown = .8

func _physics_process(dt: float) -> void:
	if not game or game.status != "playing": return
	shot_timer -= dt
	jump_timer -= dt
	damage_cooldown -= dt
	if global_position.y < -8:
		if team == 0: game.recover_player()
		else: game.destroy_vehicle(self)
		return
	if hp <= 0:
		game.destroy_vehicle(self)
		return
	if health_bar: health_bar.scale.x=clampf(hp/max_hp,0,1)
	if explorer:
		walk(dt)
		return
	if team == 0:
		throttle = axis(KEY_W,KEY_S,"forward","back")
		steer = axis(KEY_A,KEY_D,"left","right")
		braking = Input.is_key_pressed(KEY_SPACE) or touch.get("brake",false)
		boosting = Input.is_key_pressed(KEY_SHIFT) or touch.get("boost",false)
		if game.mode == "arena" and (Input.is_key_pressed(KEY_SPACE) or touch.get("fire",false)):
			fire()
			braking = false
	else:
		var aim: Vector3 = game.player.global_position
		if game.mode == "race":
			var cp: int = mini(int(get_meta("checkpoint",0)),7)
			aim = game.checkpoints[cp]
		var offset: Vector3 = aim-global_position
		var local_target := global_basis.inverse() * offset
		steer = clampf(atan2(-local_target.x,-local_target.z)*1.8,-1,1)
		throttle = .8 if game.mode == "race" else (.65 if offset.length() > 10 else .05)
		if game.mode == "arena" and game.elapsed>6 and absf(steer)<.35 and offset.length()<40: fire()
	if game.countdown>0 or (team==2 and int(get_meta("checkpoint",0))>=8):
		throttle=0
		steer=0
		braking=true
	grounded = false
	for x in [-.72,.72]:
		for z in [-1.0,1.0]:
			var anchor := global_transform * Vector3(x,0,z)
			var query := PhysicsRayQueryParameters3D.create(anchor,anchor-global_basis.y*1.25)
			query.exclude = [get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit and hit.normal.y > .3:
				grounded = true
				var length: float = anchor.distance_to(hit.position)
				var arm := anchor-global_position
				var velocity_at := linear_velocity + angular_velocity.cross(arm)
				var force := maxf(0,(.9-length)*mass*35-velocity_at.dot(global_basis.y)*mass*3.1)
				apply_force(global_basis.y*minf(force,mass*45),arm)
	if grounded:
		var forward := -global_basis.z
		var speed := linear_velocity.dot(forward)
		var top := 23.0 if kind == "heavy" else 30.0
		if boosting: top *= 1.45
		if absf(speed)<top or signf(throttle)!=signf(speed):
			apply_central_force(forward*throttle*mass*(13 if boosting else 9))
		apply_central_force(-global_basis.x*linear_velocity.dot(global_basis.x)*mass*(2 if braking else 7))
		if braking: apply_central_force(-linear_velocity*mass*4)
		var turn_factor := clampf(absf(speed)/5,.2,1)
		apply_torque(Vector3.UP*steer*mass*4.5*turn_factor*(1 if speed>=-1 else -1))
		apply_torque(global_basis.y.cross(Vector3.UP)*mass*12)
		apply_torque(Vector3(-angular_velocity.x,0,-angular_velocity.z)*mass*1.7)
	for wheel in wheels:
		wheel.rotate_y(linear_velocity.length()*dt*1.8)

func axis(positive: Key, negative: Key, p: String, n: String) -> float:
	return float(Input.is_key_pressed(positive) or touch.get(p,false))-float(Input.is_key_pressed(negative) or touch.get(n,false))

func walk(dt: float) -> void:
	var wish := Vector3(axis(KEY_D,KEY_A,"right","left"),0,axis(KEY_S,KEY_W,"back","forward"))
	wish = wish.rotated(Vector3.UP,PI/4).normalized()
	var target := wish * (8 if Input.is_key_pressed(KEY_SHIFT) or touch.get("boost",false) else 5)
	apply_central_force(Vector3(target.x-linear_velocity.x,0,target.z-linear_velocity.z)*mass*10)
	var query := PhysicsRayQueryParameters3D.create(global_position,global_position-Vector3.UP*.95)
	query.exclude = [get_rid()]
	grounded = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	if grounded and jump_timer<=0 and (Input.is_key_pressed(KEY_SPACE) or touch.get("jump",false)):
		apply_central_impulse(Vector3.UP*mass*6)
		jump_timer = .5
	if wish.length()>.1:
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(wish.x,wish.z),dt*10)
		visual.position.y = -.6+sin(game.elapsed*12)*.035

func fire() -> void:
	if shot_timer>0: return
	shot_timer = 2.8 if team else (.55 if kind=="heavy" else .28)
	game.shoot(self)

func replace_visual(scene: Node3D, yaw: float) -> void:
	var previous:=visual
	visual=A.normalize_runtime_scene(scene,1.55 if explorer else 3.1,yaw)
	add_child(visual); visual.position.y=-.6 if explorer else -.82
	visual.rotation.y=0 if explorer else PI
	if is_instance_valid(previous): remove_child(previous); previous.queue_free()
	# The chosen GLB supplies its own body and wheels. Existing arena weapon
	# mounts are siblings, so muzzle positions and projectile physics stay intact.
	for wheel in wheels:
		if is_instance_valid(wheel): wheel.queue_free()
	wheels.clear()
