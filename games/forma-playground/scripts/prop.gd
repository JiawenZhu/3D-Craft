extends RigidBody3D
var game: Node3D
var explosive := false
var detonated := false
var age := 0.0

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_hit)

func _physics_process(dt: float) -> void:
	age += dt
	if global_position.y < -15: queue_free()

func _hit(body: Node) -> void:
	if not explosive or detonated or age < .4 or not game: return
	var relative_speed := linear_velocity.length()
	if body is RigidBody3D: relative_speed = maxf(relative_speed,body.linear_velocity.length())
	if relative_speed > 5: detonate.call_deferred()

func detonate() -> void:
	if detonated: return
	detonated = true
	game.explode(global_position,7,55,null)
	queue_free()
