extends Node
## A custom game remains blocked until an actual, self-contained GLB has loaded.
const A=preload("res://scripts/assets.gd")
const LIMIT=100*1024*1024
var game: Node3D
var request: HTTPRequest
var state: Dictionary={"status":"waiting","id":"","name":"","error":""}
var pending: Dictionary={}

func configure(owner_game: Node3D) -> void:
	game=owner_game
	request=HTTPRequest.new(); add_child(request)
	request.body_size_limit=LIMIT; request.timeout=60; request.max_redirects=3
	request.request_completed.connect(_completed)

func load_asset(asset: Dictionary) -> void:
	var id: String=str(asset.get("id",""))
	if state.status in ["loading","ready"]: return
	pending=asset.duplicate()
	state={"status":"loading","id":id.left(160),"name":str(asset.get("name","Asset")).left(160),"error":""}
	game.block_custom_world()
	game.send_state()
	var allowed: Array=["vehicle"] if game.mode in ["arena","race"] else ["flying"] if game.mode=="dragon" else ["character","flying"]
	if id.is_empty() or str(asset.get("kind","")) not in allowed:
		fail("This asset does not match the selected game's movement type."); return
	var yaw=asset.get("yaw",0)
	if not yaw is float and not yaw is int:
		fail("The asset facing angle is invalid."); return
	if int(yaw) not in [0,90,180,270] or float(yaw)!=float(int(yaw)):
		fail("The asset facing angle is invalid."); return
	var url: String=str(asset.get("url",""))
	if not (url.begins_with("https://") or url.begins_with("http://")) or url.contains("\n") or url.contains("\r") or url.length()>8192:
		fail("The model download URL is invalid."); return
	var error:=request.request(url)
	if error!=OK: fail("The model download could not start (%d)."%error)

func _completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if state.status!="loading": return
	if result!=HTTPRequest.RESULT_SUCCESS or response_code<200 or response_code>=300:
		fail("The model download failed (HTTP %d, result %d)."%[response_code,result]); return
	accept_bytes(body)

func accept_bytes(bytes: PackedByteArray) -> void:
	if state.status!="loading": return
	var reason:=validate_glb(bytes)
	if not reason.is_empty(): fail(reason); return
	var document:=GLTFDocument.new()
	var gltf:=GLTFState.new()
	var error:=document.append_from_buffer(bytes,"",gltf)
	if error!=OK: fail("This GLB could not be imported (%d)."%error); return
	var scene:=document.generate_scene(gltf)
	if not scene is Node3D:
		if scene: scene.free()
		fail("This model has no usable 3D scene."); return
	var bounds:=A.measure(scene,Transform3D.IDENTITY)
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.length()<.00001:
		scene.free(); fail("This model has no visible mesh geometry."); return
	# GLB cameras, lights and animations never take control of the game scene.
	sanitize_scene(scene)
	game.player.replace_visual(scene,int(pending.get("yaw",0)))
	state.status="ready"; state.error=""
	game.release_custom_world()
	game.send_state()

func sanitize_scene(node: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is Light3D or child is AudioStreamPlayer3D or child is CollisionObject3D:
			child.free()
		else: sanitize_scene(child)
	node.process_mode=Node.PROCESS_MODE_DISABLED

func validate_glb(bytes: PackedByteArray) -> String:
	if bytes.size()<20 or bytes.size()>LIMIT: return "The GLB is empty or exceeds the 100 MB limit."
	if bytes.decode_u32(0)!=0x46546c67 or bytes.decode_u32(4)!=2 or bytes.decode_u32(8)!=bytes.size(): return "The downloaded file is not a valid GLB 2.0 model."
	var length:=bytes.decode_u32(12)
	if bytes.decode_u32(16)!=0x4e4f534a or length==0 or length>bytes.size()-20: return "The GLB scene data is invalid."
	var json=JSON.parse_string(bytes.slice(20,20+length).get_string_from_utf8())
	if not json is Dictionary or not json.get("meshes",[]) is Array or json.get("meshes",[]).is_empty(): return "This model has no visible mesh geometry."
	# Runtime assets must carry all their resources in the GLB. This also stops
	# an imported document from resolving local paths or unrelated remote files.
	for section in ["buffers","images"]:
		if not json.get(section,[]) is Array: return "The GLB resource table is invalid."
		for resource in json.get(section,[]):
			if not resource is Dictionary or resource.has("uri"): return "Use a self-contained GLB with embedded textures and geometry."
	return ""

func fail(reason: String) -> void:
	state.status="error"; state.error=reason
	game.block_custom_world(); game.send_state()
