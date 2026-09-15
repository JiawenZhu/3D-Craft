extends RefCounted

const SIGN_FONT = preload("res://assets/fonts/forma-game-signs.ttf")
const SIGNS = {"HOME":"家园", "RAIDER":"掠夺者", "FINISH":"终点", "PUSH THE CRATE ONTO THE SEAL":"将箱子推到封印上", "THE SIGNAL":"信号塔"}

static var materials: Dictionary = {}
static var surface_materials: Dictionary = {}
static func surface(color: Color, grain:=1.0) -> ShaderMaterial:
	var key:=str(color)+str(grain)
	if surface_materials.has(key): return surface_materials[key]
	var material:=ShaderMaterial.new()
	material.shader=preload("res://scripts/ground.gdshader")
	material.set_shader_parameter("base_color",color)
	material.set_shader_parameter("grain_scale",grain)
	surface_materials[key]=material
	return material

static func stone_blocks(parent: Node3D, transforms: Array[Transform3D], colors: Array[Color], material: Material=null) -> void:
	var geometry:=BoxMesh.new()
	geometry.size=Vector3.ONE
	mesh_batch(parent,geometry,transforms,colors,material)

static func mesh_batch(parent: Node3D, geometry: Mesh, transforms: Array[Transform3D], colors: Array[Color], override: Material=null) -> void:
	if transforms.is_empty(): return
	var material:=StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.roughness=.95
	geometry.material=override if override else material
	var batch:=MultiMesh.new()
	batch.transform_format=MultiMesh.TRANSFORM_3D
	batch.use_colors=true
	batch.mesh=geometry
	batch.instance_count=transforms.size()
	for i in transforms.size():
		batch.set_instance_transform(i,transforms[i])
		batch.set_instance_color(i,colors[i])
	var instance:=MultiMeshInstance3D.new()
	instance.multimesh=batch
	parent.add_child(instance)

static func fence(parent: Node3D, pos: Vector3, length: float, along_x: bool) -> void:
	var dimensions:=Vector3(length,1.6,.2) if along_x else Vector3(.2,1.6,length)
	box(parent,pos+Vector3.UP*.7,dimensions,Color.BLACK,true).visible=false
	var transforms: Array[Transform3D]=[]
	var colors: Array[Color]=[]
	for y in [.65,1.25]:
		var rail:=Vector3(length,.16,.14) if along_x else Vector3(.14,.16,length)
		transforms.append(Transform3D(Basis.IDENTITY.scaled(rail),pos+Vector3.UP*y))
		colors.append(Color("52696b"))
	for i in int(length/3)+1:
		var offset:=Vector3(i*3-length/2,.7,0) if along_x else Vector3(0,.7,i*3-length/2)
		transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.16,1.6,.16)),pos+offset))
		colors.append(Color("344f55"))
	stone_blocks(parent,transforms,colors)
static func mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var key := str(color) + str(emission)
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	materials[key] = m
	return m

static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid := false) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	parent.add_child(root)
	root.position = pos
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = mat(color)
	root.add_child(mesh)
	if solid:
		var collision := CollisionShape3D.new()
		var collider := BoxShape3D.new()
		collider.size = size
		collision.shape = collider
		root.add_child(collision)
	return root

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top := -1.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius if top < 0 else top
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 12
	mesh.mesh = shape
	mesh.material_override = mat(color)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh

static func orb(parent: Node3D, pos: Vector3, radius: float, color: Color, emission := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2
	shape.radial_segments = 12
	shape.rings = 6
	mesh.mesh = shape
	mesh.material_override = mat(color, emission)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh

static func label(parent: Node3D, text: String, pos: Vector3, color := Color.WHITE, size := 42) -> Label3D:
	var node := Label3D.new()
	node.text = text
	node.font = SIGN_FONT
	if SIGNS.has(text):
		node.set_meta("en",text)
		node.set_meta("zh",SIGNS[text])
		node.add_to_group("localized_signs")
		var game=parent.get_tree().get_first_node_in_group("forma_game")
		if game and game.language=="zh": node.text=SIGNS[text]
	if text=="FINISH":
		node.visibility_range_begin=12
		node.visibility_range_begin_margin=2
	node.font_size = size
	node.pixel_size = 0.014
	node.modulate = color
	node.outline_modulate = Color("182837")
	node.outline_size = 8
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(node)
	node.position = pos
	return node

static func tree(parent: Node3D, pos: Vector3, hue: Color, scale_factor := 1.0) -> void:
	cylinder(parent,pos+Vector3(0,1.35,0)*scale_factor,.26*scale_factor,2.7*scale_factor,Color("67534a"),.13*scale_factor)
	var branches: Array[Transform3D]=[]
	var leaves: Array[Transform3D]=[]
	var branch_colors: Array[Color]=[]
	var leaf_colors: Array[Color]=[]
	for i in 6:
		var angle:=i*TAU/6+pos.x*.7
		var rotation:=Basis.from_euler(Vector3(sin(angle)*.7,0,-cos(angle)*.7))
		branches.append(Transform3D(rotation.scaled(Vector3(.18,1.6,.18)*scale_factor),pos+Vector3(cos(angle)*.45,2.1,sin(angle)*.45)*scale_factor))
		branch_colors.append(Color("67534a"))
		leaves.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.25,.7875,1.25)*scale_factor),pos+Vector3(cos(angle)*1.05,3.1+(i%3)*.28,sin(angle)*1.05)*scale_factor))
		leaf_colors.append(hue.lightened((i%3)*.025))
	leaves.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.35,.8775,1.35)*scale_factor),pos+Vector3(0,3.7,0)*scale_factor))
	leaf_colors.append(hue.lightened(.04))
	var branch:=CylinderMesh.new()
	branch.height=1; branch.bottom_radius=.5; branch.top_radius=.22; branch.radial_segments=8
	mesh_batch(parent,branch,branches,branch_colors)
	var leaf:=SphereMesh.new()
	leaf.radius=1; leaf.height=2; leaf.radial_segments=12; leaf.rings=6
	mesh_batch(parent,leaf,leaves,leaf_colors,surface(Color.WHITE,3.0))

static func grass(parent: Node3D, rng: RandomNumberGenerator, count: int, extent: float, color: Color, clear: float, exclude_x:=0.0, exclude_z:=0.0) -> void:
	var material := mat(color).duplicate()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,material)
	for i in count:
		var p := Vector3(rng.randf_range(-extent,extent),0.025,rng.randf_range(-extent,extent))
		if exclude_x>0 and pow(p.x/exclude_x,2)+pow(p.z/exclude_z,2)<1: continue
		if clear>0 and (absf(p.x)<clear or absf(p.z)<7): continue
		var height := rng.randf_range(.18,.55)
		var width := rng.randf_range(.08,.16)
		for angle in [0.0,PI/2]:
			var side := Vector3(width,0,0).rotated(Vector3.UP,angle)
			for point in [p-side,p+side,p+Vector3(.12,height,.03)]:
				mesh.surface_set_normal(Vector3.UP)
				mesh.surface_add_vertex(point)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh=mesh
	parent.add_child(instance)

static func rock(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var rock_mesh:=orb(parent,pos,radius,color)
	var arrays:=rock_mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		var p:=vertices[i]/radius
		var distortion:=1+.1*sin(p.x*8+p.z*5)+.06*cos(p.y*12+p.x*3)
		vertices[i]*=distortion
	arrays[Mesh.ARRAY_VERTEX]=vertices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	rock_mesh.mesh=mesh
	var material:=ShaderMaterial.new()
	material.shader=preload("res://scripts/rock.gdshader")
	material.set_shader_parameter("base_color",color)
	rock_mesh.material_override=material
	return rock_mesh
