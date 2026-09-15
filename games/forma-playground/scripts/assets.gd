extends RefCounted

static var cache: Dictionary = {}

static func model(id: String, size: float) -> Node3D:
	if not cache.has(id):
		cache[id] = load("res://assets/" + id + ".glb")
	var scene: Node3D = cache[id].instantiate()
	var bounds := measure(scene, Transform3D.IDENTITY)
	var wrapper := Node3D.new()
	wrapper.add_child(scene)
	var factor := size / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	scene.scale = Vector3.ONE * factor
	scene.position = -(bounds.position + Vector3(bounds.size.x / 2, 0, bounds.size.z / 2)) * factor
	return wrapper

static func measure(node: Node, trans: Transform3D) -> AABB:
	var transform := trans
	if node is Node3D:
		transform = trans * node.transform
	var bounds := AABB()
	if node is MeshInstance3D and node.mesh:
		bounds = transform * node.get_aabb()
	for child in node.get_children():
		var other := measure(child, transform)
		if other.size.length() > 0:
			bounds = other if bounds.size.length() == 0 else bounds.merge(other)
	return bounds

# Runtime GLBs share the same ground-centered scale convention as bundled assets.
# Facing correction stays inside the wrapper so character steering remains intact.
static func normalize_runtime_scene(scene: Node3D, size: float, yaw: float) -> Node3D:
	var bounds:=measure(scene,Transform3D.IDENTITY)
	var wrapper:=Node3D.new()
	var pivot:=Node3D.new(); wrapper.add_child(pivot); pivot.rotation.y=deg_to_rad(yaw)
	var normalizer:=Node3D.new(); pivot.add_child(normalizer)
	normalizer.add_child(scene)
	var factor:=size/maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
	# Preserve arbitrary transforms on the GLB root. Normalization belongs to an
	# outer node rather than replacing the imported root's position and scale.
	normalizer.scale=Vector3.ONE*factor
	normalizer.position=-(bounds.position+Vector3(bounds.size.x/2,0,bounds.size.z/2))*factor
	return wrapper
