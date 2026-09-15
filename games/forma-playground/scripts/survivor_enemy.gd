extends CharacterBody3D
const G=preload("res://scripts/geometry.gd")
var adventure: Node3D
var hp:=40.0
var max_hp:=40.0
var kind:=0
var speed:=2.0
var phase:=0.0
var hit_flash:=0.0
var visual: Node3D
var limbs: Array[Node3D]=[]
var pulse_timer:=5.0
var dead:=false

func configure(level: Node3D, type: int) -> void:
	adventure=level; kind=type
	hp=1100 if kind==3 else 90 if kind==2 else 28 if kind==1 else 42
	max_hp=hp; speed=1.8 if kind==3 else 1.5 if kind==2 else 3.0 if kind==1 else 2.0
	collision_layer=2; collision_mask=1
	var shape:=CapsuleShape3D.new(); shape.radius=1.5 if kind==3 else .4; shape.height=3.6 if kind==3 else 1.7
	var col:=CollisionShape3D.new(); col.shape=shape; col.position.y=1.8 if kind==3 else .85; add_child(col)
	visual=Node3D.new(); add_child(visual)
	if kind==3:
		G.orb(visual,Vector3(0,2,0),1.65,Color("253d42"))
		G.cylinder(visual,Vector3(0,3.4,0),1.2,.18,Color("b38653"),.9)
		G.box(visual,Vector3(0,4,0),Vector3(1.5,1.1,1.3),Color("602e2e"))
		G.cylinder(visual,Vector3(0,4.7,0),1.4,.55,Color("243235"),.05)
		face(Vector3(0,2,-1.52),1.5)
		for side in [-1,1]:
			for i in 4:
				var leg:=G.box(visual,Vector3(side*1.85,1.1,(i-1.5)*.75),Vector3(2.1,.18,.2),Color("67746c")); leg.rotation.z=side*.4; limbs.append(leg)
	else:
		var robe:=Color("20343a") if kind==0 else Color("354745") if kind==1 else Color("3b2c38")
		G.cylinder(visual,Vector3(0,.72,0),.48,1.3,robe,.3)
		face(Vector3(0,1.58,-.15),.64)
		for side in [-1,1]:
			var arm:=G.box(visual,Vector3(side*.4,1.05,-.05),Vector3(.2,.7,.22),robe); arm.rotation.z=side*.18; limbs.append(arm)
		for x in [-.14,.14]: G.box(visual,Vector3(x,1.01,-.36),Vector3(.08,.35,.035),Color("c0a77d"))
		if kind==2:
			visual.scale=Vector3.ONE*1.45
			G.box(visual,Vector3(0,1.1,.28),Vector3(.8,1.8,.23),Color("5a6260"))

func face(pos: Vector3, size: float) -> void:
	var mask:=G.orb(visual,pos,size*.38,Color("d4d4be")); mask.scale=Vector3(.86,1.13,.45)
	for side in [-1,1]: G.box(visual,pos+Vector3(side*size*.12,size*.03,-size*.16),Vector3(size*.1,size*.045,.035),Color("162324"))
	G.box(visual,pos+Vector3(0,-size*.13,-size*.18),Vector3(size*.24,size*.045,.035),Color("8f483b"))

func _physics_process(dt: float) -> void:
	if dead or adventure.game.status!="playing": return
	phase+=dt
	var player=adventure.game.player
	var delta: Vector3=player.position-global_position; delta.y=0
	var direction:=delta.normalized()
	# Collision-respecting steering keeps the swarm flowing around street corners.
	var probe:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*.6,global_position+Vector3.UP*.6+direction*1.8,1)
	var wall:=get_world_3d().direct_space_state.intersect_ray(probe)
	if wall:
		var normal: Vector3=wall.normal
		direction=(direction-normal*direction.dot(normal)).normalized()
		if direction.length_squared()<.1: direction=Vector3(-normal.z,0,normal.x)
	var separation:=Vector3.ZERO
	for other in adventure.foes:
		if other==self or not is_instance_valid(other) or other.dead: continue
		var away: Vector3=position-other.position; away.y=0
		var length:=away.length()
		if length>0 and length<1.0: separation+=away/length*(1-length)*1.7
	velocity=(direction+separation).limit_length()*speed
	velocity.y=-3
	move_and_slide()
	if delta.length_squared()>.01: visual.rotation.y=lerp_angle(visual.rotation.y,atan2(-delta.x,-delta.z),dt*6)
	visual.position.y=sin(phase*5)*.045
	for i in limbs.size(): limbs[i].rotation.x=sin(phase*6+i*PI)*.18
	var reach:=2.2 if kind==3 else 1.0
	if delta.length()<reach: player.take_damage(22 if kind==3 else 10)
	if kind==3:
		pulse_timer-=dt
		if pulse_timer<=0:
			pulse_timer=6; adventure.boss_attack(position)

func take_damage(amount: float) -> void:
	if dead: return
	hp-=amount
	if hp<=0:
		dead=true; adventure.enemy_down(self); queue_free()
