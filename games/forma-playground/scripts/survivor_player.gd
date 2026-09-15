extends RigidBody3D
const A=preload("res://scripts/assets.gd")
const G=preload("res://scripts/geometry.gd")
var game: Node3D
var adventure: Node3D
var visual: Node3D
var team:=0
var hp:=120.0
var max_hp:=120.0
var touch: Dictionary={}
var spawn_point:=Vector3.ZERO
var dash_timer:=0.0
var dash_remaining:=0.0
var hit_timer:=0.0
var phase:=0.0
var speed_bonus:=0.0
var facing:=Vector3.FORWARD
var dash_direction:=Vector3.FORWARD
var poses: Array[ShaderMaterial]=[]
var scarf: MeshInstance3D

func configure(g: Node3D, level: Node3D) -> void:
	game=g; adventure=level
	mass=65; linear_damp=.1; angular_damp=10
	axis_lock_angular_x=true; axis_lock_angular_y=true; axis_lock_angular_z=true
	continuous_cd=true
	var pm:=PhysicsMaterial.new(); pm.friction=0; physics_material_override=pm
	var shape:=CapsuleShape3D.new(); shape.radius=.42; shape.height=1.6
	var col:=CollisionShape3D.new(); col.shape=shape; add_child(col)
	visual=Node3D.new() if game.custom_asset_enabled else (A.model("lantern_cat",2.2) if ResourceLoader.exists("res://assets/lantern_cat.glb") else A.model("boba_cat",2.2))
	add_child(visual); visual.position.y=-.8; visual.rotation.y=PI
	# The generated cat's topology is unrigged. A gentle, spatially weighted walk
	# deformation gives the feet and tail motion without claiming a skeletal rig.
	if ResourceLoader.exists("res://assets/lantern_cat.glb"): animate_mesh(visual)
	var ring:=MeshInstance3D.new(); add_child(ring)
	var torus:=TorusMesh.new(); torus.inner_radius=.52; torus.outer_radius=.61; torus.rings=32; torus.ring_segments=8
	ring.mesh=torus; ring.material_override=G.mat(Color("71e4d6"),.45); ring.position.y=-.77
	var fill:=OmniLight3D.new(); add_child(fill); fill.position=Vector3(0,2,1); fill.omni_range=6; fill.light_color=Color("c8e0e9"); fill.light_energy=1.5

func animate_mesh(node: Node) -> void:
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var old=node.get_active_material(i)
			if old is StandardMaterial3D and old.albedo_texture:
				var mat:=ShaderMaterial.new(); mat.shader=preload("res://scripts/survivor_pose.gdshader")
				mat.set_shader_parameter("skin",old.albedo_texture); mat.set_shader_parameter("tint",old.albedo_color)
				mat.set_shader_parameter("roughness_value",old.roughness); mat.set_shader_parameter("metallic_value",old.metallic)
				if old.normal_enabled and old.normal_texture:
					mat.set_shader_parameter("normal_map",old.normal_texture); mat.set_shader_parameter("has_normal",true); mat.set_shader_parameter("normal_strength",old.normal_scale)
				if old.roughness_texture:
					mat.set_shader_parameter("roughness_map",old.roughness_texture); mat.set_shader_parameter("has_roughness",true)
				if old.metallic_texture:
					mat.set_shader_parameter("metallic_map",old.metallic_texture); mat.set_shader_parameter("has_metallic",true)
				node.set_surface_override_material(i,mat); poses.append(mat)
	for child in node.get_children(): animate_mesh(child)

func pressed(letter: Key, arrow: Key, action: String) -> bool:
	return Input.is_key_pressed(letter) or Input.is_key_pressed(arrow) or touch.get(action,false)

func _physics_process(dt: float) -> void:
	if not game or game.status!="playing": return
	phase+=dt; dash_timer=maxf(0,dash_timer-dt); dash_remaining=maxf(0,dash_remaining-dt); hit_timer=maxf(0,hit_timer-dt)
	# Focus moves into the Godot iframe after menus/upgrades. Match the parent
	# page's arrow-key aliases so controls never depend on which frame owns focus.
	var input:=Vector2(
		float(pressed(KEY_D,KEY_RIGHT,"right"))-float(pressed(KEY_A,KEY_LEFT,"left")),
		float(pressed(KEY_S,KEY_DOWN,"back"))-float(pressed(KEY_W,KEY_UP,"forward"))
	).limit_length()
	var direction:=Vector3(input.x,0,input.y)
	if direction.length_squared()>.01: facing=direction.normalized()
	var dash: bool=Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SHIFT) or touch.get("dash",false) or touch.get("boost",false)
	if dash and dash_timer<=0:
		dash_timer=2.8; dash_remaining=.22; dash_direction=facing
		game.play_sound("lantern_dash",position,-16)
		adventure.flash(position-Vector3.UP*.35,Color("83f4df"),1.8)
	var desired:=dash_direction*24 if dash_remaining>0 else direction*(6.3+speed_bonus)
	linear_velocity.x=lerpf(linear_velocity.x,desired.x,minf(1,dt*22)); linear_velocity.z=lerpf(linear_velocity.z,desired.z,minf(1,dt*22))
	var moving:=clampf(Vector2(linear_velocity.x,linear_velocity.z).length()/6,0,1)
	var yaw:=atan2(facing.x,facing.z)
	visual.rotation.y=lerp_angle(visual.rotation.y,yaw,1-exp(-dt*15))
	visual.position.y=-.8+absf(sin(phase*12))*.045*moving
	visual.rotation.z=sin(phase*6)*.035*moving
	for pose in poses:
		pose.set_shader_parameter("phase",phase); pose.set_shader_parameter("running",moving)
	if position.y < -4: game.recover_player()

func take_damage(amount: float, _source: Node=null) -> void:
	if game.status!="playing" or hit_timer>0 or dash_remaining>0: return
	hp=maxf(0,hp-amount); hit_timer=.75; game.shake=.16
	game.play_sound("lantern_hit",position,-17)
	adventure.flash(position,Color("ff6652"),.7)
	if hp<=0:
		game.status="lost"; game.notice="The lanterns faded. Your next run starts with a new build."
		adventure.freeze_world(true); game.send_state()

func replace_visual(scene: Node3D, yaw: float) -> void:
	var previous:=visual
	visual=A.normalize_runtime_scene(scene,2.2,yaw)
	add_child(visual); visual.position.y=-.8; visual.rotation.y=PI
	poses.clear()
	if is_instance_valid(previous): remove_child(previous); previous.queue_free()
