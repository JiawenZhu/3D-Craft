extends RigidBody3D
const A=preload("res://scripts/assets.gd")
const G=preload("res://scripts/geometry.gd")
var game: Node3D
var adventure: Node3D
var visual: Node3D
var team:=0
var hp:=100.0
var max_hp:=100.0
var touch: Dictionary={}
var spawn_point:=Vector3.ZERO
var flying:=false
var grounded:=false
var fuel:=100.0
var breathing:=false
var recharging:=false
var phase:=0.0
var breath_sound: AudioStreamPlayer3D
var poses: Array[ShaderMaterial]=[]
var flame: CPUParticles3D
var sparks: CPUParticles3D
var jet: MeshInstance3D
var mouth: Node3D
var glow: OmniLight3D

func configure(g: Node3D, level: Node3D) -> void:
	game=g; adventure=level
	mass=45; linear_damp=.3; angular_damp=8
	axis_lock_angular_x=true; axis_lock_angular_y=true; axis_lock_angular_z=true
	continuous_cd=true; contact_monitor=true; max_contacts_reported=8
	var pm:=PhysicsMaterial.new(); pm.friction=.1; physics_material_override=pm
	var shape:=CapsuleShape3D.new(); shape.radius=.65; shape.height=1.9
	var col:=CollisionShape3D.new(); col.shape=shape; add_child(col)
	visual=Node3D.new() if game.custom_asset_enabled else A.model("baby_emerald_dragon",2.7); add_child(visual)
	visual.position.y=-.9; visual.rotation.y=PI
	animate_mesh(visual)
	mouth=Node3D.new(); add_child(mouth); mouth.position=Vector3(0,.45,-.9)
	flame=make_particles(170,.55,29,34,5,.3,.8,false)
	sparks=make_particles(55,.72,25,39,16,.035,.09,true)
	mouth.add_child(flame); mouth.add_child(sparks)
	jet=MeshInstance3D.new(); mouth.add_child(jet)
	var cone:=CylinderMesh.new(); cone.top_radius=.13; cone.bottom_radius=1.3; cone.height=15; cone.radial_segments=24; cone.rings=20
	jet.mesh=cone; jet.rotation.x=PI/2; jet.position.z=-7.5
	var fire_mat:=ShaderMaterial.new(); fire_mat.shader=preload("res://scripts/fire_cone.gdshader"); jet.material_override=fire_mat
	jet.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; jet.visible=false
	glow=OmniLight3D.new(); mouth.add_child(glow); glow.light_color=Color("ff9035"); glow.omni_range=10; glow.light_energy=0
	if DisplayServer.get_name()!="headless":
		breath_sound=AudioStreamPlayer3D.new(); mouth.add_child(breath_sound)
		var sound: AudioStreamWAV=preload("res://assets/fire.wav").duplicate(); sound.loop_mode=AudioStreamWAV.LOOP_FORWARD; sound.loop_end=22050
		breath_sound.stream=sound; breath_sound.volume_db=-12; breath_sound.unit_size=10; breath_sound.max_distance=50
	var fill:=OmniLight3D.new(); add_child(fill); fill.position=Vector3(0,3,2); fill.omni_range=7; fill.light_color=Color("d5ffe2"); fill.light_energy=2.6
	body_entered.connect(func(_b): game.collision_count+=1)

func animate_mesh(node: Node) -> void:
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var old=node.get_active_material(i)
			if old is StandardMaterial3D:
				var mat:=ShaderMaterial.new(); mat.shader=preload("res://scripts/dragon_pose.gdshader")
				mat.set_shader_parameter("skin",old.albedo_texture); mat.set_shader_parameter("tint",old.albedo_color)
				node.set_surface_override_material(i,mat); poses.append(mat)
	for child in node.get_children(): animate_mesh(child)

func make_particles(count: int, life: float, speed_min: float, speed_max: float, spread_angle: float, small: float, large: float, ember: bool) -> CPUParticles3D:
	var p:=CPUParticles3D.new(); p.amount=count; p.lifetime=life; p.emitting=false
	p.local_coords=false; p.direction=Vector3.FORWARD; p.spread=spread_angle
	p.initial_velocity_min=speed_min; p.initial_velocity_max=speed_max
	p.gravity=Vector3(0,1.5,0); p.scale_amount_min=small; p.scale_amount_max=large
	var curve:=Curve.new(); curve.add_point(Vector2(0,.22)); curve.add_point(Vector2(.65,1)); curve.add_point(Vector2(1,.01)); p.scale_amount_curve=curve
	var colors:=Gradient.new(); colors.offsets=PackedFloat32Array([0,.2,.6,1]); colors.colors=PackedColorArray([Color(1,.95,.6,.75),Color(1,.5,.06,.6),Color(.9,.12,.01,.35),Color(.24,.015,.001,0)]); p.color_ramp=colors
	var mesh:=QuadMesh.new(); mesh.size=Vector2(2,2)
	var mat:=ShaderMaterial.new(); mat.shader=preload("res://scripts/flame.gdshader")
	mesh.material=mat; p.mesh=mesh; p.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

func axis(pos: Key, neg: Key, p: String, n: String) -> float:
	return float(Input.is_key_pressed(pos) or touch.get(p,false))-float(Input.is_key_pressed(neg) or touch.get(n,false))

func _physics_process(dt: float) -> void:
	if not game or game.status!="playing":
		if breath_sound: breath_sound.stop()
		if flame: flame.emitting=false; sparks.emitting=false; glow.light_energy=0; jet.visible=false
		return
	phase+=dt
	var query:=PhysicsRayQueryParameters3D.create(global_position,global_position-Vector3.UP*1.12); query.exclude=[get_rid()]
	grounded=not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	var ascend: bool=Input.is_key_pressed(KEY_SPACE) or touch.get("ascend",false)
	var descend: bool=Input.is_key_pressed(KEY_C) or touch.get("descend",false)
	if ascend: flying=true
	if grounded and descend: flying=false
	var turn:=axis(KEY_A,KEY_D,"left","right")
	rotation.y+=turn*dt*(1.8 if flying else 2.5)
	var throttle:=axis(KEY_W,KEY_S,"forward","back")
	var boost: bool=Input.is_key_pressed(KEY_SHIFT) or touch.get("boost",false)
	var desired: Vector3=-global_basis.z*throttle*(22 if boost and flying else 13 if flying else 10 if boost else 6)
	if flying:
		gravity_scale=0
		desired.y=(float(ascend)-float(descend))*8
		if position.y>29: desired.y=minf(desired.y,-3)
		apply_central_force((desired-linear_velocity)*mass*4)
	else:
		gravity_scale=1
		apply_central_force(Vector3(desired.x-linear_velocity.x,0,desired.z-linear_velocity.z)*mass*9)
	if fuel<=2: recharging=true
	if fuel>=35: recharging=false
	breathing=(Input.is_key_pressed(KEY_F) or touch.get("fire",false)) and not recharging
	fuel=clampf(fuel+(-29 if breathing else 20)*dt,0,100)
	mouth.rotation=Vector3.ZERO
	if breathing:
		var aim: Vector3=adventure.breath_target(mouth.global_position,-global_basis.z)
		mouth.look_at(aim)
		adventure.burn(mouth.global_position,-mouth.global_basis.z,dt)

	if breath_sound:
		if breathing and not breath_sound.playing: breath_sound.play()
		elif not breathing: breath_sound.stop()
	flame.emitting=breathing; sparks.emitting=breathing; jet.visible=breathing
	glow.light_energy=(.85+sin(phase*37)*.2) if breathing else 0
	visual.rotation.z=lerpf(visual.rotation.z,-turn*(.28 if flying else .06),dt*6)
	visual.rotation.x=lerpf(visual.rotation.x,-.23 if flying else 0,dt*5)
	visual.position.y=-.9+sin(phase*(5 if flying else 13))*(.07 if flying else .04*absf(throttle))
	for mat in poses:
		mat.set_shader_parameter("phase",phase); mat.set_shader_parameter("flight",1.0 if flying else .12)
		mat.set_shader_parameter("running",absf(throttle) if not flying else 0.0); mat.set_shader_parameter("breathing",1.0 if breathing else 0.0)
	if position.y < -5 or absf(position.x)>64 or absf(position.z)>70: game.recover_player(); flying=false
	if hp<=0: game.status="lost"; game.notice="Your dragon needs a rest. Try another flight!"

func replace_visual(scene: Node3D, yaw: float) -> void:
	var previous:=visual
	visual=A.normalize_runtime_scene(scene,2.7,yaw)
	add_child(visual); visual.position.y=-.9; visual.rotation.y=PI
	poses.clear()
	if is_instance_valid(previous): remove_child(previous); previous.queue_free()
	# Generic flying assets retain banking and hover motion, never the bespoke
	# dragon wing/jaw deformation. The gameplay muzzle remains an explicit socket.
