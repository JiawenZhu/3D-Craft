extends RefCounted
## The playable town is level, with wide cross streets and collision proxies matching buildings.
const G = preload("res://scripts/geometry.gd")
var root: Node3D
var blocks: Array[Transform3D] = []
var colors: Array[Color] = []
var tiles: Array[Transform3D] = []
var tile_colors: Array[Color] = []
var glowing: Array[Transform3D] = []
var glow_colors: Array[Color] = []
var lanterns: Array[Transform3D] = []
var lantern_colors: Array[Color] = []
var obstacles: Array[Rect2] = []
var foliage: Array[Transform3D] = []
var foliage_colors: Array[Color] = []
var vessels: Array[Transform3D] = []
var vessel_colors: Array[Color] = []
var rims: Array[Transform3D] = []
var rim_colors: Array[Color] = []

static func build(game: Node3D) -> Array[Rect2]:
	var town = load("res://scripts/survivor_town.gd").new()
	town.root = game.world
	town.construct(game)
	return town.obstacles

func block(pos: Vector3, size: Vector3, color: Color, basis:=Basis.IDENTITY) -> void:
	blocks.append(Transform3D(basis.scaled_local(size),pos))
	colors.append(color)

func beam(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var direction=(b-a).normalized()
	var axis=Vector3.RIGHT if absf(direction.dot(Vector3.UP))>.99 else Vector3.UP
	var side=direction.cross(axis).normalized()
	var basis=Basis(side,direction,side.cross(direction).normalized())
	block((a+b)*.5,Vector3(width,a.distance_to(b),width),color,basis)

func solid(pos: Vector3, size: Vector3, color: Color) -> void:
	G.box(root,pos,size,color,true).visible=false

func construct(game: Node3D) -> void:
	# The shared daylight rig keeps user-created characters readable in this town.
	var floor=G.box(root,Vector3(0,-.3,0),Vector3(72,.6,72),Color.WHITE,true)
	var stone=ShaderMaterial.new()
	stone.shader=preload("res://scripts/survivor_stone.gdshader")
	floor.get_child(0).material_override=stone
	# Thin drain channels and patterned paving frame the central square without movement bumps.
	for side in [-1,1]:
		block(Vector3(side*9.5,.017,0),Vector3(.15,.025,62),Color("101d25"))
		block(Vector3(0,.018,side*9.5),Vector3(62,.025,.15),Color("101d25"))
		for k in range(-30,31,2):
			block(Vector3(side*9.3,.03,k),Vector3(.25,.05,1.88),Color("737a78"))
			block(Vector3(k,.03,side*9.3),Vector3(1.88,.05,.25),Color("737a78"))
	# Dense architecture stays at the perimeter so the horde can flow around every objective.
	building(Vector3(-23,0,-22),8,7,4.1,0,0)
	building(Vector3(23,0,-22),8,7,4.4,0,1)
	building(Vector3(-25,0,19),7,7,2.7,PI,2)
	building(Vector3(25,0,19),7,7,2.7,PI,3)
	building(Vector3(-19,0,-5),7,6,3.4,PI/2,4)
	building(Vector3(19,0,-5),7,6,3.4,-PI/2,5)
	building(Vector3(0,0,-29),10,5,4.8,0,6)
	gate(Vector3(0,0,-22.5))
	skyline()
	for side in [-1,1]:
		lantern_string(Vector3(side*18,4.5,-11),Vector3(side*11.5,4.0,1))
		bamboo(Vector3(side*27,0,-11),side)
		bamboo(Vector3(side*30,0,13),side+2)
		for z in [-27,-17,7,26]:
			tall_tree(Vector3(side*31,0,z),4.6+(z%3)*.45)
			# Irregular moss patches beside garden curbs break up the paving without raising the floor.
			for k in 7:
				var patch=Vector3(side*(29.2+sin(k*2.1)*1.2),.036,z+(k-3)*.7)
				block(patch,Vector3(.7+absf(sin(k)),.012,.4+absf(cos(k*2))*.5),Color("374a3b"),Basis(Vector3.UP,k*.8))
	for side in [-1,1]:
		for z in [-14,4,27]:
			lamp_post(Vector3(side*18,0,z),z==4)
		for z in [-30,30]:
			wall(Vector3(side*21,0,z),17)
		for z in [-27,8,28]:
			G.tree(root,Vector3(side*30,0,z),Color("344c4b"),.95 if z>0 else 1.25)
		# Low garden terraces keep the near camera view clear.
		for x in [12,27]:
			block(Vector3(side*x,.16,29),Vector3(3.5,.3,3),Color("596363"))
			block(Vector3(side*x,.34,29),Vector3(3.1,.12,2.6),Color("263631"))
			for j in 5:
				G.rock(root,Vector3(side*x+(j-2)*.4,.55,29+sin(j)*.6),.4,Color("63716b"))
	# Four substantial perimeter collision walls, lower on the camera-facing edge.
	for x in [-33,33]:
		solid(Vector3(x,1,0),Vector3(.7,3,66),Color.BLACK)
	for z in [-33,33]:
		solid(Vector3(0,1,z),Vector3(66,3,.7),Color.BLACK)
	for i in range(-32,33,4):
		block(Vector3(i,.48,32.5),Vector3(3.96,.96,.7),Color("3e4b50"))
		block(Vector3(i,1.0,32.5),Vector3(4,.12,.9),Color("68716f"))
		block(Vector3(i,2,-33.5),Vector3(3.96,4,.7),Color("263641"))
	# Wind-carried flecks add atmosphere without obscuring combat silhouettes.
	var motes=CPUParticles3D.new()
	root.add_child(motes)
	motes.amount=55
	motes.lifetime=10
	motes.preprocess=8
	motes.position=Vector3(0,3,0)
	motes.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents=Vector3(29,3,29)
	motes.direction=Vector3(1,-.12,.2)
	motes.spread=20
	motes.gravity=Vector3.ZERO
	motes.initial_velocity_min=.3
	motes.initial_velocity_max=.9
	motes.scale_amount_min=.025
	motes.scale_amount_max=.06
	var mote=SphereMesh.new(); mote.radius=.5; mote.height=1; mote.radial_segments=6; mote.rings=3
	mote.material=G.mat(Color("cba86b"),.4)
	motes.mesh=mote
	flush()

func building(center: Vector3, width: float, depth: float, height: float, yaw: float, variant: int) -> void:
	var basis=Basis(Vector3.UP,yaw)
	var extent=Vector2(width,depth) if is_zero_approx(sin(yaw)) else Vector2(depth,width)
	obstacles.append(Rect2(Vector2(center.x,center.z)-extent*.5,extent))
	solid(center+Vector3.UP*height*.5,Vector3(extent.x,height,extent.y),Color.BLACK)
	var wall_color=[Color("8a8171"),Color("697b80"),Color("7b7d6e"),Color("746c64"),Color("83908a"),Color("756d67"),Color("857868")][variant%7]
	block(center+Vector3.UP*height*.5,Vector3(width,height,depth),wall_color,basis)
	block(center+Vector3.UP*.2,Vector3(width+.2,.4,depth+.2),Color("495860"),basis)
	for x in [-width*.5,width*.5]:
		for z in [-depth*.5,depth*.5]:
			block(center+basis*Vector3(x,height*.5,z),Vector3(.24,height+.15,.24),Color("342f30"),basis)
	for y in [.52,height-.22]:
		for z in [-depth*.5-.03,depth*.5+.03]:
			block(center+basis*Vector3(0,y,z),Vector3(width,.18,.16),Color("3d3431"),basis)
	var front=depth*.5+.06
	# Recessed door, structural mullions and warm translucent window panes.
	block(center+basis*Vector3(0,1.1,front),Vector3(1.65,2.15,.09),Color("20292a"),basis)
	for x in [-.85,.85]: block(center+basis*Vector3(x,1.1,front+.06),Vector3(.13,2.3,.16),Color("765647"),basis)
	block(center+basis*Vector3(0,2.27,front+.05),Vector3(1.85,.16,.18),Color("765647"),basis)
	for x in [-.15,.15]: block(center+basis*Vector3(x,1.03,front+.13),Vector3(.065,.28,.05),Color("c4a86c"),basis)
	for side in [-1,1]:
		var win=Vector3(side*width*.31,1.62,front+.05)
		glowing.append(Transform3D(basis.scaled_local(Vector3(1.45,1.35,.06)),center+basis*win)); glow_colors.append(Color("cd9653"))
		for dx in [-.75,-.38,0,.38,.75]:
			block(center+basis*(win+Vector3(dx,0,.06)),Vector3(.07,1.45,.06),Color("3d302b"),basis)
		for dy in [-.7,-.35,0,.35,.7]:
			block(center+basis*(win+Vector3(0,dy,.07)),Vector3(1.5,.06,.06),Color("3d302b"),basis)
		lantern(center+basis*Vector3(side*(width*.5-.55),height-.8,front+.6),.75)
		# Linen shop streamers and a carved timber bracket soften the repetitive frontage.
		var flag=Vector3(side*(width*.5-.3),1.65,front+.17)
		block(center+basis*flag,Vector3(.35,1.55,.03),Color("8d5043") if variant%2 else Color("ab9570"),basis)
		block(center+basis*(flag+Vector3(0,.86,0)),Vector3(.55,.07,.3),Color("463b33"),basis)
		for stripe in [-.45,-.2,.1,.4]:
			block(center+basis*(flag+Vector3(0,stripe,.025)),Vector3(.21,.045,.015),Color("d0b581"),basis)
	# Narrow veranda; visual risers sit inside the building's collision footprint.
	block(center+basis*Vector3(0,.1,depth*.5),Vector3(width+.3,.2,.8),Color("737f80"),basis)
	roof(center+Vector3.UP*height,width+1.35,depth+1.5,basis)
	shop_props(center,basis,width,depth,variant)
	if variant in [0,4,5]: awning(center,basis,depth,height,variant)
	# Blank carved signboard uses a heraldic moon emblem rather than language-specific text.
	block(center+basis*Vector3(0,height-.45,front+.14),Vector3(1.5,.55,.16),Color("302c2a"),basis)
	block(center+basis*Vector3(0,height-.45,front+.24),Vector3(.29,.29,.04),Color("c6a66d"),basis.rotated(Vector3.FORWARD,PI/4))

func roof(center: Vector3, width: float, depth: float, basis: Basis) -> void:
	var profile=[Vector2(0,1.55),Vector2(.25,1.15),Vector2(.52,.62),Vector2(.80,.22),Vector2(1,.38)]
	var mesh=ImmediateMesh.new()
	var material=G.mat(Color("384f5c")).duplicate()
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.roughness=.58
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,material)
	for side in [-1,1]:
		for k in range(profile.size()-1):
			var a=Vector3(-width*.5,profile[k].y,side*profile[k].x*depth*.5)
			var b=Vector3(width*.5,profile[k].y,side*profile[k].x*depth*.5)
			var c=Vector3(-width*.5,profile[k+1].y,side*profile[k+1].x*depth*.5)
			var d=Vector3(width*.5,profile[k+1].y,side*profile[k+1].x*depth*.5)
			var normal=(c-a).cross(b-a).normalized()
			if normal.y<0: normal=-normal
			for point in [a,c,b,b,c,d]:
				mesh.surface_set_normal(basis*normal)
				mesh.surface_add_vertex(center+basis*point)
			# Every ceramic channel follows the curved roof profile in one shared draw call.
			for col in int(width/.26)+1:
				var x=-width*.5+col*.26
				var start=center+basis*Vector3(x,profile[k].y+.025,side*profile[k].x*depth*.5)
				var end=center+basis*Vector3(x,profile[k+1].y+.025,side*profile[k+1].x*depth*.5)
				tile_segment(start,end,.075,Color("576b73") if col%3==0 else Color("425a66"))
			# Horizontal overlap lips give roof courses a readable layered silhouette.
			beam(center+basis*c,center+basis*d,.095,Color("62737a"))
	mesh.surface_end()
	var instance=MeshInstance3D.new(); instance.mesh=mesh; root.add_child(instance)
	beam(center+basis*Vector3(-width*.5,1.58,0),center+basis*Vector3(width*.5,1.58,0),.23,Color("748587"))
	for side in [-1,1]:
		beam(center+basis*Vector3(side*width*.5,1.58,0),center+basis*Vector3(side*(width*.5+.3),1.95,0),.19,Color("71878a"))

func tile_segment(start: Vector3, end: Vector3, radius: float, color: Color) -> void:
	var up=(end-start).normalized()
	var right=up.cross(Vector3.RIGHT).normalized()
	var basis=Basis(right,up,right.cross(up).normalized())
	tiles.append(Transform3D(basis.scaled_local(Vector3(radius,start.distance_to(end),radius)),(start+end)*.5))
	tile_colors.append(color)

func lantern(pos: Vector3, size:=1.0) -> void:
	lanterns.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.36,.55,.36)*size),pos))
	lantern_colors.append(Color("edb264"))
	for y in [-.47,.47]: block(pos+Vector3.UP*y*size,Vector3(.42,.06,.42)*size,Color("50352b"))
	block(pos+Vector3(0,-.75*size,0),Vector3(.035,.5,.035)*size,Color("a8613e"))
	for x in [-.23,.23]: block(pos+Vector3(x*size,0,0),Vector3(.026,.83,.36)*size,Color("986641"))

func lamp_post(pos: Vector3, lit: bool) -> void:
	block(pos+Vector3.UP*1.65,Vector3(.18,3.3,.18),Color("3e3531"))
	block(pos+Vector3(.45,3.25,0),Vector3(1.1,.12,.12),Color("645043"))
	block(pos+Vector3.UP*.15,Vector3(.58,.3,.58),Color("687273"))
	lantern(pos+Vector3(.85,2.75,0),1.0)
	if lit:
		var light=OmniLight3D.new(); root.add_child(light)
		light.position=pos+Vector3(.8,2.6,0)
		light.light_color=Color("ffc27c"); light.light_energy=1.6; light.omni_range=10
		light.omni_attenuation=1.4

func gate(pos: Vector3) -> void:
	for x in [-4.3,4.3]:
		block(pos+Vector3(x,2.3,0),Vector3(.6,4.6,.6),Color("713f34"))
		block(pos+Vector3(x,.3,0),Vector3(1,.6,1),Color("88918c"))
		lantern(pos+Vector3(x*.7,3.2,.4),1.15)
	beam(pos+Vector3(-5,4,0),pos+Vector3(5,4,0),.4,Color("8f5942"))
	roof(pos+Vector3.UP*4.25,11,2.8,Basis.IDENTITY)
	for x in [-3,3]:
		var light=OmniLight3D.new(); root.add_child(light)
		light.position=pos+Vector3(x,2.8,.5); light.light_color=Color("f8b566")
		light.light_energy=1.8; light.omni_range=9

func wall(pos: Vector3, length: float) -> void:
	block(pos+Vector3.UP*.65,Vector3(length,1.3,.5),Color("737e7c"))
	block(pos+Vector3.UP*1.32,Vector3(length+.2,.16,.72),Color("3c5360"))
	for i in int(length/3)+1:
		block(pos+Vector3(i*3-length*.5,.8,0),Vector3(.5,1.6,.7),Color("596c70"))

func flush() -> void:
	G.stone_blocks(root,blocks,colors)
	var tile=CylinderMesh.new(); tile.height=1; tile.top_radius=1; tile.bottom_radius=1; tile.radial_segments=6
	G.mesh_batch(root,tile,tiles,tile_colors)
	var glow=StandardMaterial3D.new(); glow.vertex_color_use_as_albedo=true
	glow.emission_enabled=true; glow.emission=Color("edb87a"); glow.emission_energy_multiplier=.38
	G.stone_blocks(root,glowing,glow_colors,glow)
	var paper=SphereMesh.new(); paper.radius=1; paper.height=2; paper.radial_segments=12; paper.rings=8
	G.mesh_batch(root,paper,lanterns,lantern_colors,glow)
	var leaf=SphereMesh.new(); leaf.radius=1; leaf.height=2; leaf.radial_segments=10; leaf.rings=5
	G.mesh_batch(root,leaf,foliage,foliage_colors,G.surface(Color.WHITE,3.0))
	var pot=CylinderMesh.new(); pot.height=1; pot.bottom_radius=.42; pot.top_radius=.5; pot.radial_segments=12
	G.mesh_batch(root,pot,vessels,vessel_colors)
	var rim=TorusMesh.new(); rim.inner_radius=.42; rim.outer_radius=.5; rim.rings=12; rim.ring_segments=5
	G.mesh_batch(root,rim,rims,rim_colors)


func shop_props(center: Vector3, basis: Basis, width: float, depth: float, variant: int) -> void:
	for i in 3:
		var p=center+basis*Vector3(width*.5-.55+(i%2)*.55,.34+(i/2)*.55,depth*.5+.46)
		var turn=basis.rotated(Vector3.UP,.08*i)
		block(p,Vector3(.58,.58,.58),Color("785e45"),turn)
		for dx in [-.25,.25]:
			block(p+turn*Vector3(dx,0,.305),Vector3(.06,.59,.04),Color("b29266"),turn)
		for dy in [-.25,.25]:
			block(p+turn*Vector3(0,dy,.305),Vector3(.59,.06,.04),Color("b29266"),turn)
		beam(p+turn*Vector3(-.22,-.22,.33),p+turn*Vector3(.22,.22,.33),.065,Color("ad895a"))
	for i in 2:
		var p=center+basis*Vector3(-width*.5+.5+i*.8,.39,depth*.5+.48)
		vessels.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.72,.78,.72)),p))
		vessel_colors.append(Color("99664a") if variant%2 else Color("4a7270"))
		for y in [-.26,.31]:
			rims.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.73,.73,.73)),p+Vector3.UP*y))
			rim_colors.append(Color("342d2c"))
		block(p+Vector3.UP*.395,Vector3(.48,.025,.48),Color("171e1c"))

func awning(center: Vector3, basis: Basis, depth: float, height: float, variant: int) -> void:
	var canopy_y=minf(2.9,height-.28)
	var canopy_basis=basis*Basis(Vector3.RIGHT,-.15)
	for i in 10:
		var color=Color("a89b79") if i%2 else (Color("6c4240") if variant%2 else Color("476565"))
		block(center+basis*Vector3((i-4.5)*.37,canopy_y,depth*.5+.8),Vector3(.365,.045,1.8),color,canopy_basis)
		block(center+basis*Vector3((i-4.5)*.37,canopy_y-.2,depth*.5+1.67),Vector3(.36,.22,.035),color,basis)
	for side in [-1,1]:
		beam(center+basis*Vector3(side*1.9,0,depth*.5+1.6),center+basis*Vector3(side*1.9,canopy_y,depth*.5+1.6),.075,Color("594b3c"))
		beam(center+basis*Vector3(side*1.9,canopy_y,depth*.5),center+basis*Vector3(side*1.9,canopy_y-.15,depth*.5+1.65),.08,Color("594b3c"))

func lantern_string(start: Vector3, end: Vector3) -> void:
	for p in [start,end]:
		beam(Vector3(p.x,0,p.z),p+Vector3.UP*.2,.09,Color("655348"))
	var previous=start
	for i in range(1,15):
		var t=i/14.0
		var p=start.lerp(end,t)-Vector3.UP*sin(t*PI)*.7
		beam(previous,p,.025,Color("3f3430"))
		if i%2==1: lantern(p-Vector3.UP*.35,.5)
		previous=p

func tall_tree(pos: Vector3, height: float) -> void:
	tile_segment(pos,pos+Vector3(.25,height*.78,.1),.21,Color("3e4841"))
	for i in 5:
		var angle=i*TAU/5+pos.z*.12
		var tip=pos+Vector3(cos(angle)*1.7,height*.72+sin(i)*.45,sin(angle)*1.7)
		tile_segment(pos+Vector3.UP*height*.48,tip,.09,Color("444a40"))
		foliage.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.7,.7,1.4)),tip))
		foliage_colors.append(Color("354c46").lightened((i%3)*.03))
	foliage.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.25,.85,1.25)),pos+Vector3.UP*height))
	foliage_colors.append(Color("506056"))

func bamboo(pos: Vector3, seed_value: int) -> void:
	for i in 8:
		var p=pos+Vector3(sin(i*2.3)*.7,0,cos(i*1.6)*.7)
		var height=2.8+absf(sin(i+seed_value))*1.5
		tile_segment(p,p+Vector3(.12,height,.05),.048,Color("63795b"))
		for y in range(1,6):
			var origin=p+Vector3(.02,y*.58,0)
			var side=1 if (i+y)%2 else -1
			beam(origin,origin+Vector3(side*.55,.2,.25),.024,Color("6c8060"))
			block(origin+Vector3(side*.4,.23,.2),Vector3(.65,.018,.16),Color("57714e"),Basis.from_euler(Vector3(.15,side*.7,side*.3)))

func skyline() -> void:
	# Fog-separated ridgelines are entirely beyond the collision boundary.
	for i in 9:
		var angle=PI+i*PI/8
		var p=Vector3(cos(angle)*83,7+sin(i*1.4)*4,sin(angle)*65-24)
		foliage.append(Transform3D(Basis(Vector3.UP,i*.4).scaled_local(Vector3(24,12+absf(sin(i))*13,17)),p))
		foliage_colors.append(Color("1b303f").lightened((i%3)*.025))
	for side in [-1,1]:
		for i in 5:
			var p=Vector3(side*(9+i*7),0,-42-absf(sin(i*3))*8)
			var h=3.5+absf(cos(i*1.7))*4
			block(p+Vector3.UP*h*.5,Vector3(5.6,h,5),Color("30434d"))
			roof(p+Vector3.UP*h,6.5,6,Basis(Vector3.UP,i*.06))
			for j in 2:
				glowing.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.55,.7,.04)),p+Vector3((j-.5)*1.7,h*.6,2.54)))
				glow_colors.append(Color("a97c4b"))
