extends Node3D
const G=preload("res://scripts/geometry.gd")
const A=preload("res://scripts/assets.gd")
const Dragon=preload("res://scripts/dragon.gd")
const Target=preload("res://scripts/dragon_target.gd")
const Bullet=preload("res://scripts/projectile.gd")
var game: Node3D
var rings: Array[MeshInstance3D]=[]
var targets: Array[StaticBody3D]=[]
var points:=0
var combo:=0
var combo_time:=0.0
var home_sign: Label3D
var nest:=Vector3(0,1,31)
var last_position:=Vector3.ZERO

func build(g: Node3D) -> void:
	game=g
	game.world.add_child(self)
	var floor:=G.box(game.world,Vector3(0,-.7,0),Vector3(120,1,130),Color("729466"),true)
	floor.get_child(0).material_override=G.surface(Color("597c55"),1.8)
	# A clear meadow runway winds into a valley of towering wooded stone spires.
	var trail:=G.box(self,Vector3(0,-.17,5),Vector3(9,.1,58),Color("b8b28a"))
	trail.get_child(0).material_override=G.surface(Color("b8b28a"),3)
	for i in 22:
		var angle:=TAU*i/22
		var pos:=Vector3(cos(angle)*52,0,sin(angle)*57-3)
		var height:=10.0+(i%5)*4
		var rock:=G.rock(self,pos+Vector3.UP*(height*.27),6,Color("617f77")); rock.scale=Vector3(1,height/7,1.15)
		var top:=G.rock(self,pos+Vector3.UP*(height*.85),5.4,Color("648b66")); top.scale=Vector3(1,.3,1)
		G.tree(self,pos+Vector3.UP*(height*.93),Color("56865d"),1.3)
		G.box(game.world,pos+Vector3.UP*height*.4,Vector3(7,height,7),Color.BLACK,true).visible=false
	for i in 35:
		var x: float=game.rng.randf_range(-44,44); var z: float=game.rng.randf_range(-53,46)
		if absf(x)<10 or (x>14 and x<34): continue
		G.tree(self,Vector3(x,0,z),Color("407e62").lightened((i%4)*.04),.9+(i%3)*.3)
	G.grass(self,game.rng,650,47,Color("6b9a57"),7)
	for pos in [Vector3(-29,0,-15),Vector3(37,0,-32),Vector3(-30,0,29)]:
		var tower:=A.model("castle_tower",8); add_child(tower); tower.position=pos
		G.box(game.world,pos+Vector3.UP*3,Vector3(4,6,4),Color.BLACK,true).visible=false
	var pool:=G.cylinder(self,Vector3(-26,-.1,8),10,.08,Color("55abb0"))
	var water:=ShaderMaterial.new(); water.shader=preload("res://scripts/water.gdshader"); pool.material_override=water
	# Soft cloud clusters keep the elevated route readable against the distant cliffs.
	for i in 13:
		var cloud:=G.orb(self,Vector3(-75+i*13,42+(i%3)*3,-83+(i%4)*3),4,Color("c5e0d1"))
		cloud.scale=Vector3(2.1,.7,1.1)
	G.cylinder(self,Vector3(0,.02,31),4,.25,Color("c4a579"))
	for i in 14:
		var a:=TAU*i/14
		var twig:=G.box(self,Vector3(cos(a)*3.5,.3,31+sin(a)*3.5),Vector3(1.8,.25,.35),Color("92734e")); twig.rotation.y=-a
	home_sign=G.label(self,"HOME",nest+Vector3.UP*2,Color("fff1bd"),26)
	home_sign.visible=false
	game.checkpoints.assign([Vector3(0,3,12),Vector3(0,7,-3),Vector3(-16,12,-20),Vector3(-12,16,-37),Vector3(13,17,-38),Vector3(28,12,-18),Vector3(24,7,6),Vector3(7,3,23)])
	for i in game.checkpoints.size():
		var ring:=MeshInstance3D.new(); var mesh:=TorusMesh.new(); mesh.inner_radius=3.2; mesh.outer_radius=3.5; mesh.rings=40; mesh.ring_segments=8
		ring.mesh=mesh; ring.material_override=G.mat(Color("75d9c0"),.6); add_child(ring); ring.position=game.checkpoints[i]
		var next: Vector3=game.checkpoints[mini(i+1,7)]
		var direction: Vector3=next-ring.position if i<7 else nest-ring.position
		ring.rotation=Vector3(PI/2,atan2(-direction.x,-direction.z),0)
		rings.append(ring)
		G.label(self,"%02d"%(i+1),ring.position+Vector3.UP*4.2,Color("dbffee"),28)
	for pos in [Vector3(0,2,3),Vector3(-18,2,-8),Vector3(18,2,-18),Vector3(-12,12,-34),Vector3(22,15,-35),Vector3(29,7,1)]: create_target(pos)
	game.target_count=targets.size()
	game.player=Dragon.new(); game.world.add_child(game.player)
	game.player.position=nest; game.player.configure(game,self); game.player.spawn_point=nest
	last_position=nest

func create_target(pos: Vector3) -> void:
	var target:=Target.new(); game.world.add_child(target); target.position=pos
	var col:=CollisionShape3D.new(); var shape:=SphereShape3D.new(); shape.radius=1.65; col.shape=shape; target.add_child(col)
	var crystal:=MeshInstance3D.new(); var crystal_mesh:=SphereMesh.new(); crystal_mesh.radius=1.25; crystal_mesh.height=2.5; crystal_mesh.radial_segments=6; crystal_mesh.rings=2
	crystal.mesh=crystal_mesh; crystal.material_override=G.mat(Color("9650bf"),.18); target.add_child(crystal); crystal.scale=Vector3(.75,1.3,.75); target.gem=crystal
	var mesh:=TorusMesh.new(); mesh.inner_radius=1.6; mesh.outer_radius=1.72; mesh.rings=24; mesh.ring_segments=6
	var halo:=MeshInstance3D.new(); halo.mesh=mesh; halo.material_override=G.mat(Color("e79bee"),1); target.add_child(halo); halo.rotation.x=.4; target.halo=halo
	var bar:=G.box(target,Vector3(0,2.2,0),Vector3(2,.12,.1),Color("dfa2ef")); target.bar=bar.get_child(0)
	targets.append(target)

func breath_target(origin: Vector3, forward: Vector3) -> Vector3:
	var best: Vector3=origin+forward*17
	var closest:=18.0
	for target in targets:
		if target.cleared: continue
		var delta: Vector3=target.position-origin
		if delta.length()<closest and delta.normalized().dot(forward)>.88:
			closest=delta.length(); best=target.position
	return best

func burn(origin: Vector3, forward: Vector3, dt: float) -> void:
	for target in targets:
		if target.cleared: continue
		var delta: Vector3=target.position-origin
		if delta.length()>18 or delta.normalized().dot(forward)<.93: continue
		var query:=PhysicsRayQueryParameters3D.create(origin,target.position); query.exclude=[game.player.get_rid()]
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		if hit and hit.collider!=target: continue
		target.health-=65*dt
		target.bar.scale.x=maxf(.01,target.health/100)
		target.gem.scale=Vector3(.75,1.3,.75)*(1+sin(game.elapsed*37)*.06)
		if target.health<=0:
			target.cleared=true; target.visible=false; target.collision_layer=0
			game.score+=1; combo+=1; combo_time=10; points+=100*mini(combo,4)
			game.explode(target.position,4,0,game.player)
			burst(target.position,Color("ffd47b"))
	for prop in game.props:
		if not is_instance_valid(prop) or prop.detonated: continue
		var delta: Vector3=prop.position-origin
		if prop.explosive and delta.length()<16 and delta.normalized().dot(forward)>.95: prop.detonate.call_deferred()

func burst(pos: Vector3, color: Color) -> void:
	var p: CPUParticles3D=game.player.make_particles(60,.8,3,9,180,.035,.13,true)
	game.world.add_child(p); p.position=pos; p.direction=Vector3.UP; p.color=color; p.one_shot=true; p.explosiveness=1; p.emitting=true
	game.after(1.1,p.queue_free)

func _physics_process(dt: float) -> void:
	if not game or not is_instance_valid(game.player) or game.status!="playing": return
	home_sign.visible=game.checkpoint>=8 and game.score>=game.target_count
	combo_time-=dt
	if combo_time<=0: combo=0
	for i in rings.size():
		if i<game.checkpoint: continue
		rings[i].material_override=G.mat(Color("e9b65a") if i==game.checkpoint else Color("70b8b0"),.35 if i==game.checkpoint else .15)
		if i==game.checkpoint:
			var p: Vector3=game.player.position
			var from: Vector3=last_position
			var segment: Vector3=p-from
			var nearest: Vector3=from+segment*clampf((rings[i].position-from).dot(segment)/maxf(.001,segment.length_squared()),0,1)
			if nearest.distance_to(rings[i].position)<3.2:
				game.checkpoint+=1; rings[i].visible=false; points+=50; game.player.hp=minf(100,game.player.hp+12); game.player.fuel=100
				game.play_sound("collect",p,-8); burst(rings[i].position,Color("9bffcd"))
	last_position=game.player.position
	for target in targets:
		if target.cleared: continue
		target.halo.rotate_y(dt); target.gem.rotate_y(dt*.4)
		target.cooldown-=dt
		if target.cooldown<=0 and game.elapsed>10 and game.player.position.distance_to(nest)>6 and target.position.distance_to(game.player.position)<30:
			target.cooldown=5.5
			var bolt:=Bullet.new(); bolt.game=game; bolt.shooter=target; bolt.damage=10; bolt.gravity_scale=0
			game.world.add_child(bolt)
			var dir: Vector3=(game.player.position-target.position).normalized(); bolt.position=target.position+dir*2
			var col:=CollisionShape3D.new(); var shape:=SphereShape3D.new(); shape.radius=.25; col.shape=shape; bolt.add_child(col)
			G.orb(bolt,Vector3.ZERO,.25,Color("cc8cfa"),2); bolt.add_collision_exception_with(target); bolt.linear_velocity=dir*10
	if game.checkpoint>=8 and game.score>=game.target_count and game.player.position.distance_to(nest)<4.5 and game.player.grounded:
		game.status="won"; game.notice="The valley is safe. Your little dragon is a sky guardian!"
