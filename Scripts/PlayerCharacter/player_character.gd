# PlayerCharacter - first-person CharacterBody3D controller.
#
# Movement model: MovementDirection (Vector3 statistic) holds the normalized
# horizontal wish direction plus an accumulated vertical speed in .y
# Horizontal velocity = direction * MovementSpeed (* SprintMultiplier)
# vertical velocity = direction.y directly. Gravity and jumps modify .y only
#



# State: StateEngine has two sub-engines, NormalStateEngine -> Idle/Walking/Sprinting
# and InAirStateEngine -> Jumped/Falling/Landed The is_in_air setter switches between them
# Head motion is owned entirely by HeadBob states only call jump()/land() on it
# All tuning lives in StatisticList; get_stat_float() provides fallbacks

extends CharacterBody3D
class_name Player

const STAT_PARTNER_HEALTH: StringName = &"partnerhealth"
const STAT_PARTNER_HEALTH_DOT: StringName = &"partnerhealthdot"
const STAT_PARTNER_COMFORT: StringName = &"partnercomfort"
const STAT_PARTNER_COMFORT_DOT: StringName = &"partnercomfortdot"

@onready var statistic_list: StatisticList = $StatisticList
@onready var player_main_state_engine: StateEngine = $StateEngine
@onready var grab_range_ray_cast_3d: RayCast3D = $Neck/Head/Camera3D/GrabRangeRayCast3D
@onready var head: Node3D = $Neck/Head
@onready var camera: Camera3D = $Neck/Head/Camera3D
@onready var head_bob: HeadBob = $HeadBob

static var _instance: Player
static func instance() -> Player:
	assert(_instance != null, "Instance accessed before ready")
	# if this assert fails, access player after _ready(): call_deferred()
	return _instance

#kept as a property because the Riding state reads it too
var mouse_sensitivity: float:
	get:
		return get_stat_float("mousesensitivity", 0.003)

#setter drives the top-level state engine, jumpsTaken is reset on landing
var is_in_air: bool = false:
	set(new_value):
		if new_value:
			player_main_state_engine.transition_to_new_state("inairstateengine")
		else:
			player_main_state_engine.transition_to_new_state("normalstateengine")
			statistic_list.set_value_of("jumpstaken", 0.0)
		is_in_air = new_value

var vehicle: HoverBike = null


#yaw rotates the body, pitch rotates only the camera and pitch is clamped in _physics_process.
func _unhandled_input(event: InputEvent) -> void:
	if vehicle != null:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x -= event.relative.y * mouse_sensitivity


func _ready() -> void:
	if _instance != null:
		push_warning("second Player node instiantiated")
	_instance = self
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_handle_partner_stats(delta)

func _physics_process(delta: float) -> void:
	if vehicle != null:
		return
	# raw WASD vector, y is forward/back in screen terms, negative is forward).
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	statistic_list.set_value_of("inputdirection", input)
	# Preserve vertical speed across frames, but zero it while grounded so walking
	# off a ledge starts a fresh fall instead of reusing the last landing speed
	var falling_speed: float = statistic_list.get_value_of("movementdirection").y
	if is_on_floor() and falling_speed < 0.0:
		falling_speed = 0.0
	#rotate input into world space by the body's basis .y carries the vertical speed
	statistic_list.set_value_of("movementdirection", (transform.basis * Vector3(input.x, 0, input.y)).normalized() + Vector3(0, falling_speed, 0))

	#multi-jump: jumpsTaken's maximum is the jumps that can be taken, jump adds JumpHeight to vertical speed
	if statistic_list.get_value_of("jumpstaken") < statistic_list.get_value_of("jumpstaken", "maximum") and Input.is_action_just_pressed("jump"):
		statistic_list.change_value_of("jumpstaken", 1)
		statistic_list.change_value_of("movementdirection", Vector3(0, statistic_list.get_value_of("jumpheight"), 0))

	#gravity
	if not is_on_floor():
		statistic_list.change_value_of("movementdirection", Vector3(0, -get_stat_float("gravity", 6.0) * delta, 0))
		if is_in_air == false:
			is_in_air = true

	#head pitch clamp, in degrees from the MaxLookAngle statistic
	var max_look := deg_to_rad(get_stat_float("maxlookangle", 89.0))
	camera.rotation.x = clamp(camera.rotation.x, -max_look, max_look)

	# Sprint is decided by the Sprinting state via the IsSprinting statistic
	var speed: float = statistic_list.get_value_of("movementspeed")
	if is_sprinting():
		speed *= get_stat_float("sprintmultiplier", 1.0)

	var movement: Vector3 = statistic_list.get_value_of("movementdirection")
	#actually inputing the velocities to player
	if movement != Vector3.ZERO:
		velocity.x = movement.x * speed
		velocity.y = movement.y
		velocity.z = movement.z * speed
	else:
		# No input and no vertical speed
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()


#single source of truth for sprinting, HeadBob and the speed calculation both use it
func is_riding() -> bool:
	return vehicle != null


func is_sprinting() -> bool:
	return statistic_list.statistics.has("issprinting") and statistic_list.get_value_of("issprinting")

func _handle_partner_stats(delta: float) -> void:
	statistic_list.change_value_of(STAT_PARTNER_HEALTH, -1 * statistic_list.get_value_of(STAT_PARTNER_HEALTH_DOT) * delta)
	statistic_list.change_value_of(STAT_PARTNER_COMFORT, -1 * statistic_list.get_value_of(STAT_PARTNER_COMFORT_DOT) * delta)

func get_statistic_changed_signal(stat_name: StringName) -> Signal:
	return statistic_list.get_changed_signal(stat_name)

# Typed statistic read with a fallback for statistics
func get_stat_float(stat_name: StringName, fallback: float, value_type: String = "current") -> float:
	if statistic_list != null and statistic_list.statistics.has(stat_name):
		return float(statistic_list.get_value_of(stat_name, value_type))
	return fallback
