extends RefCounted
const G = preload("res://scripts/geometry.gd")
const A = preload("res://scripts/assets.gd")

static func decorate(root: Node3D, id: String, pos: Vector3, size: float, yaw := 0.0, solid := false) -> Node3D:
	var node := A.model(id,size)
	root.add_child(node)
	node.position = pos
	node.rotation.y = yaw
	if solid:
		var bounds:=A.measure(node,Transform3D.IDENTITY)
		# Normalized visuals are bottom-aligned. A compact proxy preserves navigable edges.
		var body:=StaticBody3D.new()
		node.add_child(body)
		var col:=CollisionShape3D.new()
		var shape:=BoxShape3D.new()
		shape.size=Vector3(bounds.size.x*.65,bounds.size.y,bounds.size.z*.65)
		col.shape=shape
		col.position.y=bounds.size.y/2
		body.add_child(col)
	return node

static func build(game: Node3D) -> void:
	var root: Node3D = game.world
	if game.mode == "arena": arena(game,root)
	elif game.mode == "race": race(game,root)
	else: ruins(game,root)

static func arena(game: Node3D, root: Node3D) -> void:
	var floor:=G.box(root,Vector3(0,-.65,0),Vector3(90,1,90),Color("b28e5b"),true)
	floor.get_child(0).material_override=G.surface(Color("b28e5b"),1.2)
	var lane:=G.box(root,Vector3(0,-.12,0),Vector3(13,.12,64),Color("cda66d"))
	lane.get_child(0).material_override=G.surface(Color("c4a171"),2.0)
	var crossing:=G.box(root,Vector3(0,-.11,0),Vector3(60,.12,12),Color("cda66d"))
	crossing.get_child(0).material_override=G.surface(Color("c4a171"),2.0)
	for i in 24:
		var angle := TAU*i/24
		var pos := Vector3(cos(angle)*38,2,sin(angle)*38)
		var rock := G.rock(root,pos,4.2,Color("ad7055"))
		rock.scale = Vector3(1.3,1.1+(i%3)*.3,.9)
		rock.rotation.y = angle
		var upper := G.rock(root,pos+Vector3(.5,3,0),2.7,Color("b5805c"))
		upper.scale = Vector3(1.3,.5+(i%4)*.12,1.1)
		G.box(root,pos,Vector3(6,8,6),Color("ad7055"),true).visible=false
	for x in [-33,33]:
		G.box(root,Vector3(x,1.5,0),Vector3(1,4,72),Color("9b7557"),true)
	for z in [-33,33]:
		G.box(root,Vector3(0,1.5,z),Vector3(66,4,1),Color("9b7557"),true)
	for x in [-23,23]:
		for z in [-23,23]:
			decorate(root,"castle_tower",Vector3(x,0,z),7.5)
			G.box(root,Vector3(x,2,z),Vector3(4,4,4),Color.BLACK,true).visible=false
	for p in [Vector3(-17,0,1),Vector3(19,0,-9)]:
		decorate(root,"fairytale_cottage",p,6)
		G.box(root,p+Vector3(0,1.6,0),Vector3(4,3.2,4),Color.BLACK,true).visible=false
	for i in 30:
		var rng: RandomNumberGenerator = game.rng
		var x: float = rng.randf_range(-30,30)
		var z: float = rng.randf_range(-30,30)
		if absf(x)<9: continue
		G.tree(root,Vector3(x,0,z),Color("7e994b"),rng.randf_range(.5,.85))
	for p in [Vector3(0,.8,11),Vector3(-4,.8,-4),Vector3(8,.8,-10),Vector3(-14,.8,13),Vector3(16,.8,7)]:
		game.spawn_prop(p,true)
		for k in 3: game.spawn_prop(p+Vector3(2+k%2,k/2*1.1,0),false)
	G.grass(root,game.rng,900,32,Color("7d824c"),9)
	G.label(root,"EMBERFRONT",Vector3(0,5,-31),Color("ffd7a0"),80)
	game.spawn_player(Vector3(0,1.3,24),0)
	for pos in [Vector3(-12,1,-15),Vector3(12,1,-20),Vector3(-22,1,9),Vector3(23,1,15)]:
		game.spawn_enemy(pos)
	game.target_count = 4

static func road(root: Node3D) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,G.surface(Color("394856"),2.5))
	for i in 96:
		var a := TAU*i/96
		var b := TAU*(i+1)/96
		var p := [Vector3(cos(a)*31,.01,sin(a)*23),Vector3(cos(a)*21,.01,sin(a)*13),Vector3(cos(b)*31,.01,sin(b)*23),Vector3(cos(b)*21,.01,sin(b)*13)]
		for idx in [0,2,1,1,2,3]:
			mesh.surface_set_normal(Vector3.UP)
			mesh.surface_add_vertex(p[idx])
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh=mesh
	root.add_child(instance)
	for i in 64:
		var a := TAU*i/64
		var stripe := G.box(root,Vector3(cos(a)*26,.04,sin(a)*18),Vector3(.17,.03,1.15),Color("e1dcc4"))
		stripe.rotation.y=atan2(26*sin(a),18*cos(a))
		for outer in [true,false]:
			var xrad := 31.0 if outer else 21.0
			var zrad := 23.0 if outer else 13.0
			var curb := G.box(root,Vector3(cos(a)*xrad,.08,sin(a)*zrad),Vector3(.6,.18,2.5),Color("eee3d3") if i%2 else Color("e17e66"))
			curb.rotation.y=atan2(xrad*sin(a),zrad*cos(a))

static func race(game: Node3D, root: Node3D) -> void:
	var coast:=G.box(root,Vector3(0,-.6,0),Vector3(105,1,90),Color("d7b67b"),true)
	coast.get_child(0).material_override=G.surface(Color("bfa678"),.8)
	road(root)
	var water := G.cylinder(root,Vector3(0,-.025,0),15,.06,Color("42b1b4"))
	water.scale.z=.65
	var water_material:=ShaderMaterial.new()
	water_material.shader=preload("res://scripts/water.gdshader")
	water.material_override=water_material
	var foam:=G.cylinder(root,Vector3(0,-.055,0),15.2,.05,Color("b7d8c8"))
	foam.scale.z=.65
	var ocean:=G.box(root,Vector3(0,-.7,0),Vector3(450,.1,450),Color("327a87"))
	ocean.get_child(0).material_override=water_material
	for i in 40:
		var rng: RandomNumberGenerator=game.rng
		var a: float=rng.randf()*TAU
		var p:=Vector3(cos(a)*rng.randf_range(34,45),0,sin(a)*rng.randf_range(27,34))
		G.tree(root,p,Color("db9c70") if i%3==0 else Color("7ea279"),rng.randf_range(.9,1.4))
	for p in [Vector3(-12,0,-7),Vector3(12,0,-4)]: decorate(root,"fairytale_cottage",p,5,0,true)
	decorate(root,"castle_tower",Vector3(0,0,-7),7,0,true)
	G.grass(root,game.rng,650,13,Color("73885e"),0,15,9.8)
	for i in 8:
		var angle := PI/2-(i+1)*TAU/8
		var p := Vector3(cos(angle)*26,0,sin(angle)*18)
		game.checkpoints.append(p)
		var gate := Node3D.new()
		root.add_child(gate)
		gate.position=p
		gate.rotation.y=atan2(26*sin(angle),18*cos(angle))
		for side in [-1,1]:
			G.cylinder(gate,Vector3(side*4,2.4,0),.18,4.8,Color("aee9dc"))
		G.box(gate,Vector3(0,4.7,0),Vector3(8.4,.35,.4),Color("3ba69d"))
		G.label(gate,"FINISH" if i==7 else "%02d"%(i+1),Vector3(0,5.5,0),Color("d9fff3"),64)
	for i in [1,3,5]:
		var p: Vector3=game.checkpoints[i]
		game.spawn_prop(p+Vector3(1,1,1),true)
		game.spawn_prop(p+Vector3(-2,1,-1),false)
		game.spawn_prop(p+Vector3(-2,2.2,-1),false)
	var ramp:=G.box(root,Vector3(26,.32,4),Vector3(3,.4,5),Color("cdad7a"),true)
	ramp.rotation.x=.18
	for x in [-46,46]: G.fence(root,Vector3(x,0,0),76,false)
	for z in [-38,38]: G.fence(root,Vector3(0,0,z),92,true)
	game.spawn_player(Vector3(0,1.3,18),-PI/2)
	for i in 3:
		game.spawn_rival(Vector3(-3-i*3,1.3,18+(i%2-0.5)*3))
	game.target_count=8

static func ruins(game: Node3D, root: Node3D) -> void:
	G.box(root,Vector3(0,-.9,0),Vector3(29,1.6,33),Color("465756"),true)
	var tiles: Array[Transform3D]=[]
	var tile_colors: Array[Color]=[]
	for x in range(-7,8):
		for z in range(-8,9):
			var shade := Color("7b9186") if (x+z)%3 else Color("879b8e")
			tiles.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.8,.16,1.8)),Vector3(x*1.85,-.05,z*1.85)))
			tile_colors.append(shade)
	G.stone_blocks(root,tiles,tile_colors,G.surface(Color.WHITE,3.5))
	for x in [-14,14]: wall(root,Vector3(x,0,0),Vector3(1,3.5,32))
	for z in [-16,16]: wall(root,Vector3(0,0,z),Vector3(28,2.4 if z>0 else 3.5,1))
	wall(root,Vector3(-11,0,2),Vector3(6,3,1))
	wall(root,Vector3(4,0,2),Vector3(18,3,1))
	game.gate=G.box(root,Vector3(-6,1.6,2),Vector3(3,3.4,.55),Color("556962"),true)
	for x in [-1.25,0,1.25]:
		G.box(game.gate,Vector3(x,0,.31),Vector3(.12,3.1,.1),Color("97b8a0"))
	G.orb(game.gate,Vector3(0,.4,.35),.18,Color("77d5bb"),1.3)
	game.plate_pos=Vector3(-6,.1,7)
	G.cylinder(root,game.plate_pos,1.2,.12,Color("50b5b0"))
	game.puzzle_crate=game.spawn_prop(Vector3(-6,.8,10),false)
	G.label(root,"PUSH THE CRATE ONTO THE SEAL",Vector3(-6,2,6),Color("a2f5dd"),28)
	for p in [Vector3(-10,0,-11),Vector3(10,0,-11),Vector3(10,0,12)]:
		decorate(root,"castle_tower",p,5,0,true)
	for p in [Vector3(-9,1,-7),Vector3(7,1,-7),Vector3(8,1,9)]:
		var core:=G.orb(root,p,.35,Color("8affd9"),3)
		game.cores.append(core)
		G.cylinder(root,p-Vector3(0,.65,0),.75,.6,Color("3b6260"))
		var light:=OmniLight3D.new()
		core.add_child(light)
		light.light_color=Color("83ffda")
		light.light_energy=1.5
		light.omni_range=4
	decorate(root,"boba_cat",Vector3(-10,0,12),2.1)
	decorate(root,"baby_emerald_dragon",Vector3(11,0,-2),2.2)
	decorate(root,"fairytale_cottage",Vector3(-9,0,-13),4,0,true)
	for i in 14:
		var p:=Vector3(game.rng.randf_range(-12,12),.5,game.rng.randf_range(-14,-3))
		if p.distance_to(Vector3(-6,.5,-5))>3: game.spawn_prop(p,false)
	for p in [Vector3(-12,0,6),Vector3(12,0,5),Vector3(-12,0,-4),Vector3(12,0,-5)]:
		G.cylinder(root,p+Vector3.UP*1.2,.16,2.4,Color("4a655b"))
		G.orb(root,p+Vector3.UP*2.5,.25,Color("ffcb8d"),2)
		var lamp:=OmniLight3D.new()
		root.add_child(lamp)
		lamp.position=p+Vector3.UP*2.5
		lamp.light_color=Color("ffc18a")
		lamp.omni_range=5
		lamp.light_energy=1.1
	var detail_rng:=RandomNumberGenerator.new()
	detail_rng.seed=482
	G.grass(root,detail_rng,750,13,Color("50766a"),10)
	for x in [-12.8,12.8]:
		for z in [-12,0,12]:
			G.box(root,Vector3(x,.3,z),Vector3(1.35,.6,1.35),Color("405551"))
			G.cylinder(root,Vector3(x,2,z),.44,3.4,Color("59726b"),.37)
			G.box(root,Vector3(x,3.7,z),Vector3(1.15,.35,1.15),Color("84978a"))
			G.box(root,Vector3(x,4,z),Vector3(.8,.25,.8),Color("9dac99"))
	var water:=G.box(root,Vector3(0,-1.6,0),Vector3(90,.1,90),Color("244843"))
	water.get_child(0).material_override=G.surface(Color("294b46"),.5)
	game.exit_pos=Vector3(0,0,-13)
	G.cylinder(root,game.exit_pos+Vector3.UP*.15,1.5,.2,Color("68ad9f"))
	G.label(root,"THE SIGNAL",game.exit_pos+Vector3.UP*3,Color("b8ffe0"),54)
	game.spawn_player(Vector3(-6,1.2,13),0)
	game.target_count=3

static func wall(root: Node3D, pos: Vector3, size: Vector3) -> void:
	G.box(root,pos+Vector3.UP*size.y/2,size,Color("354b46"),true)
	var long_x := size.x>size.z
	var length := size.x if long_x else size.z
	for i in int(length/1.6):
		var offset:=Vector3((i+.5)*1.6-length/2,0,0) if long_x else Vector3(0,0,(i+.5)*1.6-length/2)
		G.box(root,pos+offset+Vector3.UP*(size.y+.25),Vector3(1.0,.6,1.0),Color("8caa90"))
	var transforms: Array[Transform3D]=[]
	var shades: Array[Color]=[]
	var columns:=int(length/1.18)
	var step:=length/columns
	for row in int(size.y/.55):
		for col in columns:
			for side in [-1,1]:
				var along: float=(col+.5)*step-length/2+(.15 if row%2 else -.15)
				var offset:=Vector3(along,row*.55+.28,side*(size.z/2+.015)) if long_x else Vector3(side*(size.x/2+.015),row*.55+.28,along)
				var dimensions:=Vector3(step-.09,.48,.16) if long_x else Vector3(.16,.48,step-.09)
				transforms.append(Transform3D(Basis.IDENTITY.scaled(dimensions),pos+offset))
				shades.append(Color("718a7f").darkened(fposmod(sin(col*12.2+row*3.7+pos.x),1)*.25))
	G.stone_blocks(root,transforms,shades)
