extends Node3D
const G=preload("res://scripts/geometry.gd")
const Player=preload("res://scripts/survivor_player.gd")
const Enemy=preload("res://scripts/survivor_enemy.gd")
const Town=preload("res://scripts/survivor_town.gd")
const UPGRADES={
	"bolt":["Spirit bolts","Faster bolts, more damage, another target."],
	"orbit":["Moon blades","Orbiting blades cut through nearby spirits."],
	"pulse":["Lantern burst","A powerful pulse clears space around you."],
	"vitality":["Nine lives","Restore 40 health and gain 20 maximum health."],
	"haste":["Silk steps","Run faster and draw in distant spirit shards."]
}
var game: Node3D
var foes: Array=[]
var bolts: Array=[]
var shards: Array=[]
var shrines: Array=[]
var choices: Array=[]
var obstacles: Array[Rect2]=[]
var level:=1
var xp:=0
var next_xp:=8
var kills:=0
var coins:=0
var shrine_count:=0
var ranks: Dictionary={"bolt":1,"orbit":0,"pulse":0,"vitality":0,"haste":0}
var spawn_timer:=1.8
var bolt_timer:=.4
var pulse_timer:=4.0
var orbit_timer:=.3
var orbit_phase:=0.0
var blades: Array[Node3D]=[]
var boss: CharacterBody3D
var boss_spawned:=false
var boss_defeated:=false
var total_damage:=0.0
var upgrades_chosen:=0

func build(g: Node3D) -> void:
	game=g; game.world.add_child(self)
	obstacles=Town.build(game)
	for id in ["lantern_cast","lantern_dash","lantern_hit"]: game.sfx[id]=load("res://assets/"+id+".wav")
	if DisplayServer.get_name()!="headless":
		var music:=AudioStreamPlayer.new(); add_child(music)
		var stream: AudioStreamWAV=load("res://assets/lantern_music.wav").duplicate()
		stream.loop_end=int(stream.get_length()*stream.mix_rate); stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		music.stream=stream; music.volume_db=-17; music.play()
	game.player=Player.new(); game.world.add_child(game.player)
	game.player.position=Vector3(0,1,10); game.player.configure(game,self); game.player.spawn_point=game.player.position
	game.target_count=3
	for point in [Vector3(-15,0,-12),Vector3(15,0,-12),Vector3(0,0,24)]:
		var root:=Node3D.new(); add_child(root); root.position=point
		G.cylinder(root,Vector3(0,.22,0),1.3,.4,Color("455351"))
		G.cylinder(root,Vector3(0,.6,0),.75,.5,Color("343f41"))
		G.box(root,Vector3(0,1.15,0),Vector3(.8,.85,.8),Color("8b493c"))
		G.cylinder(root,Vector3(0,1.7,0),.9,.4,Color("29383b"),.08)
		var core:=G.orb(root,Vector3(0,1.25,-.43),.2,Color("97dacc"),.3)
		var ring:=ring_mesh(root,2.4,Color("83e2c5")); ring.position.y=.08
		shrines.append({"node":root,"point":point,"active":false,"core":core,"ring":ring})
	game.notice="Ignite three lantern shrines. Survive until the Midnight Warden arrives."

func _physics_process(dt: float) -> void:
	if game.status!="playing": return
	var p=game.player
	foes=foes.filter(func(f): return is_instance_valid(f) and not f.dead)
	spawn_timer-=dt; bolt_timer-=dt; pulse_timer-=dt; orbit_timer-=dt; orbit_phase+=dt*2.8
	if spawn_timer<=0 and foes.size()<55:
		spawn_timer=maxf(.5,1.65-game.elapsed*.007)
		spawn_enemy()
		if game.elapsed>15 and foes.size()<55: spawn_enemy()
	if bolt_timer<=0:
		bolt_timer=maxf(.22,.76-int(ranks.bolt)*.065)
		var nearest:=nearest_foes(p.position,10.5)
		for i in mini(nearest.size(),1+int(ranks.bolt)/3): fire_bolt(nearest[i])
	if int(ranks.pulse)>0 and pulse_timer<=0:
		pulse_timer=maxf(2.2,5.0-int(ranks.pulse)*.35)
		var radius:=4.3+int(ranks.pulse)*.45
		flash(p.position-Vector3.UP*.6,Color("ffc777"),radius)
		for foe in foes.duplicate():
			if foe.position.distance_to(p.position)<radius: hurt(foe,35+int(ranks.pulse)*16)
		game.play_sound("boom",p.position,-24)
	for i in blades.size():
		var angle:=orbit_phase+TAU*i/blades.size()
		blades[i].position=p.position+Vector3(cos(angle)*2.5,.1,sin(angle)*2.5)
		blades[i].rotation=Vector3(.25,angle,PI*.25)
	if orbit_timer<=0:
		orbit_timer=.35
		for foe in foes.duplicate():
			for blade in blades:
				if is_instance_valid(foe) and not foe.dead and foe.position.distance_to(blade.position)<1.65:
					hurt(foe,14+int(ranks.orbit)*8); break
	if game.status!="playing": return
	update_bolts(dt)
	if game.status!="playing": return
	update_shards(dt)
	for shrine in shrines:
		if not shrine.active and p.position.distance_to(shrine.point+Vector3.UP)<2.7:
			shrine.active=true; shrine_count+=1; game.score=shrine_count
			shrine.core.material_override=G.mat(Color("ffcc6c"),.6)
			shrine.ring.material_override=G.mat(Color("ffc66b"),.35)
			var light:=OmniLight3D.new(); shrine.node.add_child(light); light.position.y=2; light.light_color=Color("ffb55c"); light.light_energy=2; light.omni_range=7
			p.hp=minf(p.max_hp,p.hp+25); xp+=8; coins+=15
			flash(shrine.point,Color("ffc66b"),4); game.play_sound("collect",p.position,-10)
			game.notice="Lantern shrine ignited. Health restored."
	if game.elapsed>=120 and shrine_count==3 and not boss_spawned: spawn_boss()
	if game.elapsed>=240:
		game.status="lost"; game.notice="Midnight swallowed the town. Find the shrines and defeat the Warden sooner."
		freeze_world(true); game.send_state(); return
	if xp>=next_xp: offer_upgrades()

func nearest_foes(pos: Vector3, radius: float) -> Array:
	var nearby:=foes.filter(func(f): return is_instance_valid(f) and not f.dead and f.position.distance_squared_to(pos)<radius*radius)
	nearby.sort_custom(func(a,b): return a.position.distance_squared_to(pos)<b.position.distance_squared_to(pos))
	return nearby

func spawn_enemy() -> void:
	var pos:=Vector3.ZERO
	var found:=false
	for attempt in 24:
		var angle: float=game.rng.randf()*TAU
		pos=game.player.position+Vector3(cos(angle),0,sin(angle))*game.rng.randf_range(10,16)
		pos.y=.1
		if absf(pos.x)>30 or absf(pos.z)>30: continue
		var blocked:=false
		for rect in obstacles:
			if rect.grow(1).has_point(Vector2(pos.x,pos.z)): blocked=true; break
		if not blocked: found=true; break
	if not found: return
	var type:=0
	if game.elapsed>25 and game.rng.randf()<.28: type=1
	if game.elapsed>55 and game.rng.randf()<.2: type=2
	var foe:=Enemy.new(); add_child(foe); foe.position=pos; foe.configure(self,type); foes.append(foe)

func spawn_boss() -> void:
	boss_spawned=true
	boss=Enemy.new(); add_child(boss); boss.position=Vector3(0,.1,-13); boss.configure(self,3); foes.append(boss)
	game.notice="The Midnight Warden has arrived. Break its mask!"
	flash(boss.position,Color("f0745b"),7); game.shake=.35; game.send_state()

func fire_bolt(target: Node3D) -> void:
	var root:=Node3D.new(); add_child(root); root.position=game.player.position+Vector3.UP*.5
	var orb:=G.orb(root,Vector3.ZERO,.13,Color("78eddd"),.6)
	var tail:=G.box(root,Vector3(0,0,.3),Vector3(.08,.08,.55),Color("b6ffe5")); tail.get_child(0).material_override=G.mat(Color("9affdf"),.5)
	orb.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolts.append({"node":root,"target":target,"life":1.7,"damage":25+int(ranks.bolt)*9})
	game.play_sound("lantern_cast",root.position,-23)

func update_bolts(dt: float) -> void:
	for data in bolts.duplicate():
		var node: Node3D=data.node
		data.life-=dt
		if not is_instance_valid(data.target) or data.target.dead:
			var candidates:=nearest_foes(node.position,10)
			if candidates.is_empty(): data.life=0
			else: data.target=candidates[0]
		if data.life<=0:
			bolts.erase(data); node.queue_free(); continue
		var target_pos: Vector3=data.target.position+Vector3.UP*(1.8 if data.target.kind==3 else .9)
		var delta:=target_pos-node.position
		if delta.length()<dt*23+.5:
			hurt(data.target,data.damage); flash(target_pos,Color("79efdc"),.55)
			bolts.erase(data); node.queue_free()
		else:
			node.position+=delta.normalized()*dt*23
			node.look_at(target_pos)

func hurt(foe: Node3D, amount: float) -> void:
	if not is_instance_valid(foe) or foe.dead: return
	total_damage+=amount; foe.take_damage(amount)

func enemy_down(foe: Node3D) -> void:
	kills+=1; coins+=3 if foe.kind==2 else 1
	if foe.kind==3:
		boss_defeated=true; game.status="won"; game.notice="Dawn belongs to you. The town's lanterns burn again."
		game.shake=.5; flash(foe.position,Color("ffd27d"),8); freeze_world(true); game.send_state(); return
	var gem:=G.orb(self,foe.position+Vector3.UP*.4,.14 if foe.kind!=2 else .22,Color("69dec1"),.4)
	gem.mesh=PrismMesh.new(); gem.mesh.size=Vector3(.24,.36,.24)
	gem.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shards.append({"node":gem,"value":5 if foe.kind==2 else 3,"age":0.0})
	# Dropped resources are bounded even when a player stays far away.
	if shards.size()>130:
		var old: Dictionary=shards.pop_front(); old.node.queue_free()

func update_shards(dt: float) -> void:
	for shard in shards.duplicate():
		shard.age+=dt
		var node: Node3D=shard.node
		var delta: Vector3=game.player.position-node.position
		var distance:=delta.length()
		node.rotation.y+=dt*2
		if distance<4.5+int(ranks.haste)*1.2:
			node.position+=delta.normalized()*minf(distance,dt*(8+8/maxf(distance,.3)))
		if distance<.8:
			xp+=shard.value; shards.erase(shard); node.queue_free()

func offer_upgrades() -> void:
	if game.status!="playing": return
	xp-=next_xp; level+=1; next_xp=8+level*5
	choices.clear()
	var available: Array=["bolt","orbit","pulse","vitality","haste"]
	# Three distinct choices. Rotate the random pool with the seeded game RNG.
	while choices.size()<3:
		var index: int=game.rng.randi_range(0,available.size()-1)
		var id: String=available.pop_at(index)
		choices.append({"id":id,"name":UPGRADES[id][0],"description":UPGRADES[id][1],"rank":int(ranks[id])+1})
	game.status="upgrading"; game.player.touch.clear(); freeze_world(true); game.send_state()

func choose_upgrade(index: int) -> void:
	if game.status!="upgrading" or index<0 or index>=choices.size(): return
	var id: String=choices[index].id
	ranks[id]=int(ranks[id])+1; upgrades_chosen+=1
	if id=="vitality":
		game.player.max_hp+=20; game.player.hp=minf(game.player.max_hp,game.player.hp+40)
	elif id=="haste": game.player.speed_bonus+=.5
	elif id=="orbit":
		for blade in blades: blade.queue_free()
		blades.clear()
		for i in mini(5,1+int(ranks.orbit)):
			var blade:=G.box(self,Vector3.ZERO,Vector3(.12,.2,1.1),Color("e7deba")); blade.get_child(0).material_override=G.mat(Color("e6e8c7"),.3); blades.append(blade)
	choices.clear(); game.player.touch.clear(); game.status="playing"; freeze_world(false); game.send_state()

func freeze_world(frozen: bool) -> void:
	game.player.freeze=frozen
	game.world.process_mode=Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT

func ring_mesh(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var mesh:=MeshInstance3D.new(); parent.add_child(mesh)
	var torus:=TorusMesh.new(); torus.inner_radius=radius-.06; torus.outer_radius=radius+.06; torus.rings=48; torus.ring_segments=6
	mesh.mesh=torus; mesh.material_override=G.mat(color,.35); mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh

func flash(pos: Vector3, color: Color, radius: float) -> void:
	var ring:=ring_mesh(self,1,color); ring.position=pos+Vector3.UP*.1; ring.scale=Vector3.ONE*.15
	var tween:=ring.create_tween()
	tween.tween_property(ring,"scale",Vector3.ONE*radius,.18)
	tween.tween_property(ring,"scale",Vector3.ONE*.01,.22)
	tween.tween_callback(ring.queue_free)

func boss_attack(pos: Vector3) -> void:
	var warning:=ring_mesh(self,5.5,Color("fc6f54")); warning.position=pos+Vector3.UP*.13
	var tween:=warning.create_tween()
	tween.tween_property(warning,"scale",Vector3.ONE*.85,1.1)
	tween.tween_callback(func():
		if game.status=="playing":
			flash(pos,Color("ff9970"),5.5)
			if game.player.position.distance_to(pos)<5.5: game.player.take_damage(24)
		warning.queue_free())

func snapshot() -> Dictionary:
	return {"level":level,"xp":xp,"nextXp":next_xp,"kills":kills,"coins":coins,"dash":clampf(1-game.player.dash_timer/2.8,0,1),"choices":choices,"weapons":{"bolt":ranks.bolt,"orbit":ranks.orbit,"pulse":ranks.pulse},"shrines":shrine_count,"bossHealth":maxf(0,boss.hp) if is_instance_valid(boss) else 0,"bossMaxHealth":1100,"bossSpawned":boss_spawned,"bossDefeated":boss_defeated}
