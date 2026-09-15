extends RigidBody3D
var game: Node3D
var shooter: Node
var age := 0.0
var damage := 40.0
var hit := false
func _ready() -> void:
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(impact)
func _physics_process(dt: float) -> void:
	age += dt
	if age > 3: queue_free()
func impact(_other: Node) -> void:
	if hit: return
	hit = true
	game.explode.call_deferred(global_position,4.5,damage,shooter)
	queue_free()
