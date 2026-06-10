@tool
extends CharacterBody3D

@export_category("Default Character")
@export var move_speed: float = 3.5
@export var sprint_multiplier: float = 2.0
@export var mouse_sensitivity: float = 0.1
@export var jump_velocity: float = 4.5
## Box throw speed (m/s) for a quick right-click tap (no charge).
@export var throw_speed_min: float = 8.0
## Box throw speed (m/s) at a fully charged right-click.
@export var throw_speed: float = 25.0
## Seconds of holding right-click to reach a full-power throw.
@export var throw_charge_time: float = 1.0
@export_range(20.0, 85.0, 0.5, "degrees") var floor_max_angle_degrees: float = 58.0
@export_range(0.0, 2.0, 0.01) var floor_snap_distance: float = 0.35

@export_category("Body")
## Total height of the procedurally built humanoid. Should match the collision capsule height.
@export var body_height: float = 2.8
@export var skin_color: Color = Color(0.92, 0.76, 0.62)
@export var shirt_color: Color = Color(0.20, 0.45, 0.80)
@export var pants_color: Color = Color(0.22, 0.24, 0.30)

# The head is on this render layer; the pilot's own camera excludes it (the camera
# sits inside it), while other viewports still show the full head. Everything else
# uses the default layer so the body is visible from every view, including the
# pilot's own first-person camera (so you see your torso/arms/hands/legs).
# Uses the top render layer (20) to avoid colliding with layers the scene already
# uses (e.g. Building walls are on layers 2 and 4).
const _SELF_HIDDEN_LAYER: int = 1 << 19

var _head: Node3D
var _camera: Camera3D
var _interact_text: Label3D
var _hold_point: Marker3D
var _mouse_input: Vector2 = Vector2.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _interact_ray_query: PhysicsRayQueryParameters3D

var held_box = null
var _held_box_rigid: RigidBody3D
## Seconds the right mouse button has been held while charging a throw.
var _throw_charge: float = 0.0
var held_pallet = null
var _held_pallet_rigid: RigidBody3D
var _pallet_offset: Vector3 = Vector3.ZERO
var _interact_key_text: String = "E"

var _body: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _arm_length: float = 1.0
var _walk_phase: float = 0.0
var _walk_amp: float = 0.0
var _reach_active: bool = false
var _reach_point: Vector3 = Vector3.ZERO


func _ready() -> void:
	if get_tree().edited_scene_root == self:
		return

	_head = $Head
	_camera = $Head/Camera3D
	# Eyes sit slightly in front of the body so looking down shows the chest receding
	# toward the legs, instead of staring straight onto the top of the torso.
	_camera.position.z = -0.18
	_head.rotation.y = rotation.y
	_head.rotation.x = clamp(rotation.x, deg_to_rad(-90), deg_to_rad(90))
	rotation = Vector3.ZERO
	floor_max_angle = deg_to_rad(floor_max_angle_degrees)
	floor_snap_length = floor_snap_distance
	floor_stop_on_slope = true

	var editor_settings := EditorInterface.get_editor_settings()
	var interact_sc := editor_settings.get_shortcut("Pilot Mode/Interact")
	if interact_sc and interact_sc.events.size() > 0:
		_interact_key_text = interact_sc.events[0].as_text()

	var crosshair := Label3D.new()
	crosshair.text = "."
	crosshair.font_size = 56
	crosshair.position = Vector3(0, 0, -0.475)
	crosshair.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	crosshair.pixel_size = 0.0005
	crosshair.no_depth_test = true
	_camera.add_child(crosshair)

	_interact_text = Label3D.new()
	_interact_text.font_size = 32
	_interact_text.position = Vector3(0, -0.104, -0.475)
	_interact_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_interact_text.pixel_size = 0.0005
	_interact_text.no_depth_test = true
	_interact_text.visible = false
	_camera.add_child(_interact_text)

	_hold_point = Marker3D.new()
	_hold_point.position = Vector3(0, -0.6, -1.1)
	_camera.add_child(_hold_point)

	_interact_ray_query = PhysicsRayQueryParameters3D.new()
	_interact_ray_query.collision_mask = 10
	_interact_ray_query.collide_with_areas = true

	# Don't render the character's own head/torso in first-person.
	_camera.cull_mask &= ~_SELF_HIDDEN_LAYER
	_build_body()


func _physics_process(delta: float) -> void:
	if get_tree().edited_scene_root == self:
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_pressed("pilot_jump") and is_on_floor():
		velocity.y = jump_velocity

	var current_speed := move_speed
	if held_pallet:
		current_speed = move_speed * 0.6
	if Input.is_action_pressed("pilot_sprint"):
		current_speed *= sprint_multiplier

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("pilot_move_forward"):
		input_dir.y += 1
	if Input.is_action_pressed("pilot_move_back"):
		input_dir.y -= 1
	if Input.is_action_pressed("pilot_move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("pilot_move_right"):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	var forward := -_head.global_transform.basis.z
	var right := _head.global_transform.basis.x
	var direction := (right * input_dir.x + forward * input_dir.y)
	direction.y = 0
	direction = direction.normalized()

	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	move_and_slide()

	_head.rotation_degrees.y -= _mouse_input.x * mouse_sensitivity
	_head.rotation_degrees.x -= _mouse_input.y * mouse_sensitivity
	_head.rotation_degrees.x = clamp(_head.rotation_degrees.x, -90.0, 90.0)
	_mouse_input = Vector2.ZERO

	if held_box:
		_update_held_box(delta)
	elif held_pallet:
		_update_held_pallet(delta)
	else:
		_handle_interaction()

	_update_body(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_input += event.relative


# --- Body construction ---

func _build_body() -> void:
	var h := body_height
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	# Torso: a rounded capsule that spans from the hips (~0.48h) up to the shoulders
	# (~0.82h). Kept visible (default layer) so the arms and legs don't look detached
	# when you look down.
	var torso := CapsuleMesh.new()
	torso.radius = h * 0.105
	torso.height = h * 0.36
	var torso_mi := _make_part(_body, torso, shirt_color)
	torso_mi.position = Vector3(0, h * 0.64, 0)

	# Neck (bridges the torso top to the head so the head isn't floating)
	var neck := CapsuleMesh.new()
	neck.radius = h * 0.045
	neck.height = h * 0.14
	var neck_mi := _make_part(_body, neck, skin_color)
	neck_mi.position = Vector3(0, h * 0.84, 0)

	# Head
	var head := SphereMesh.new()
	head.radius = h * 0.075
	head.height = h * 0.15
	var head_mi := _make_part(_body, head, skin_color)
	head_mi.position = Vector3(0, h * 0.89, 0)
	head_mi.layers = _SELF_HIDDEN_LAYER

	# Legs (point straight down, swing about X while walking)
	var leg_len := h * 0.48
	_left_leg = _make_limb(_body, Vector3(-h * 0.08, leg_len, 0), leg_len, h * 0.05, pants_color)
	_right_leg = _make_limb(_body, Vector3(h * 0.08, leg_len, 0), leg_len, h * 0.05, pants_color)
	_left_leg.rotation.x = deg_to_rad(-90.0)
	_right_leg.rotation.x = deg_to_rad(-90.0)

	# Arms (aimed at a target via look_at, with a hand at the tip). Shoulders sit on
	# the torso's surface near its top so the arms connect to the body.
	_arm_length = h * 0.42
	_left_arm = _make_limb(_body, Vector3(-h * 0.11, h * 0.80, 0), _arm_length, h * 0.035, shirt_color)
	_right_arm = _make_limb(_body, Vector3(h * 0.11, h * 0.80, 0), _arm_length, h * 0.035, shirt_color)
	_make_hand(_left_arm, h)
	_make_hand(_right_arm, h)


func _make_part(parent: Node3D, mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# A limb is a pivot whose visible capsule extends along its local -Z axis,
# so look_at() points the whole limb (and any hand at its tip) at a target.
func _make_limb(parent: Node3D, pos: Vector3, length: float, radius: float, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length
	var mi := _make_part(pivot, cap, color)
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	mi.position = Vector3(0, 0, -length * 0.5)
	return pivot


func _make_hand(arm: Node3D, h: float) -> void:
	var hand := Node3D.new()
	hand.position = Vector3(0, 0, -_arm_length)
	arm.add_child(hand)
	var box := BoxMesh.new()
	box.size = Vector3(h * 0.05, h * 0.05, h * 0.05)
	_make_part(hand, box, skin_color)


# --- Body animation ---

func _update_body(delta: float) -> void:
	if not _body:
		return

	_body.rotation.y = _head.rotation.y

	var planar := Vector2(velocity.x, velocity.z).length()
	_update_legs(delta, planar)
	_update_arms(delta)


func _update_legs(delta: float, planar_speed: float) -> void:
	_walk_amp = clamp(planar_speed * 0.06, 0.0, 0.5)
	_walk_phase += delta * (4.0 + planar_speed)
	var base := deg_to_rad(-90.0)
	_left_leg.rotation.x = base + sin(_walk_phase) * _walk_amp
	_right_leg.rotation.x = base + sin(_walk_phase + PI) * _walk_amp


func _update_arms(delta: float) -> void:
	var body_basis := _body.global_transform.basis
	var down := Vector3.DOWN * (_arm_length * 0.9)
	var fwd := -body_basis.z
	var side := body_basis.x

	# Arms rest angled slightly forward (out of the straight-down view) with a walk swing.
	var rest_fwd := _arm_length * 0.3
	var rest_left := _left_arm.global_position + down + fwd * (rest_fwd + sin(_walk_phase) * _walk_amp * 1.5)
	var rest_right := _right_arm.global_position + down + fwd * (rest_fwd + sin(_walk_phase + PI) * _walk_amp * 1.5)

	var left_target := rest_left
	var right_target := rest_right

	if held_box and is_instance_valid(_held_box_rigid):
		var b := _held_box_rigid.global_position
		left_target = b - side * 0.12
		right_target = b + side * 0.12
	elif held_pallet:
		# Both hands forward on an imaginary pallet-jack handle.
		var handle := _hold_point.global_position
		left_target = handle - side * 0.15
		right_target = handle + side * 0.15
	elif _reach_active:
		right_target = _reach_point

	_aim_limb(_left_arm, left_target, delta)
	_aim_limb(_right_arm, right_target, delta)


func _aim_limb(pivot: Node3D, target: Vector3, delta: float) -> void:
	var dir := target - pivot.global_position
	if dir.length_squared() < 0.0001:
		return
	# Choose an up vector that isn't parallel to the aim direction.
	var up := Vector3.UP
	if absf(dir.normalized().dot(up)) > 0.99:
		up = Vector3.FORWARD
	var t := pivot.global_transform
	var cur_q := t.basis.get_rotation_quaternion()
	var tgt_q := Basis.looking_at(dir, up).get_rotation_quaternion()
	t.basis = Basis(cur_q.slerp(tgt_q, clampf(delta * 12.0, 0.0, 1.0)))
	pivot.global_transform = t


# --- Interaction ---

func _handle_interaction() -> void:
	var start_pos := _camera.global_transform.origin
	var end_pos := start_pos - _camera.global_transform.basis.z * 3.0

	_interact_ray_query.from = start_pos
	_interact_ray_query.to = end_pos

	_reach_active = false

	var result := get_world_3d().direct_space_state.intersect_ray(_interact_ray_query)
	if not result:
		_interact_text.visible = false
		return

	var hit_object = result.collider.get_parent()

	if hit_object is Box:
		_reach_active = true
		_reach_point = result.position
		_interact_text.text = "Press '%s' to pick up!" % _interact_key_text
		_interact_text.visible = true
		if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			_pick_up_box(hit_object)
		return

	if hit_object is Pallet:
		_reach_active = true
		_reach_point = result.position
		_interact_text.text = "Press '%s' to move pallet!" % _interact_key_text
		_interact_text.visible = true
		if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			_pick_up_pallet(hit_object)
		return

	if hit_object.has_method("use"):
		_reach_active = true
		_reach_point = result.position
		_interact_text.text = "Press '%s' to use %s" % [_interact_key_text, hit_object.name]
		_interact_text.visible = true
		if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			hit_object.call("use")
		return

	_interact_text.visible = false


# --- Box carrying ---

func _pick_up_box(box) -> void:
	held_box = box
	_held_box_rigid = box.get_node("RigidBody3D") as RigidBody3D
	# Carry the box kinematically so it follows the hold point exactly instead of
	# fighting the physics solver (which caused jitter and inconsistent lifting).
	_held_box_rigid.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_held_box_rigid.freeze = true


func _update_held_box(delta: float) -> void:
	var rigid := _held_box_rigid
	var weight := clampf(delta * 12.0, 0.0, 1.0)
	var t := rigid.global_transform
	t.origin = t.origin.lerp(_hold_point.global_position, weight)
	t.basis = t.basis.slerp(_hold_point.global_transform.basis, weight)
	rigid.global_transform = t

	_interact_text.visible = false

	# Hold right-click to charge a throw; release to hurl. Longer hold = harder.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_throw_charge = minf(_throw_charge + delta, throw_charge_time)
		var pct := int(_throw_charge / maxf(throw_charge_time, 0.0001) * 100.0)
		_interact_text.text = "Throw power: %d%%" % pct
		_interact_text.visible = true
		return
	elif _throw_charge > 0.0:
		# Right-click released this frame: throw with the charge built up.
		throw_held_box(_throw_charge / maxf(throw_charge_time, 0.0001))
		_throw_charge = 0.0
		return

	# Left-click / interact key drops the box in place.
	var release := InputMap.has_action("interact") and Input.is_action_just_pressed("interact")
	if release or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		release_held_box()


## Launch the held box along the camera's forward axis. [param charge] is the
## 0..1 charge ratio that interpolates between [member throw_speed_min] and
## [member throw_speed].
func throw_held_box(charge: float = 1.0) -> void:
	if not held_box:
		return
	var rigid := _held_box_rigid
	var speed := lerpf(throw_speed_min, throw_speed, clampf(charge, 0.0, 1.0))
	var throw_dir := -_camera.global_transform.basis.z
	rigid.gravity_scale = 1
	rigid.freeze = false
	rigid.angular_velocity = Vector3.ZERO
	rigid.linear_velocity = throw_dir * speed
	held_box = null
	_held_box_rigid = null
	_throw_charge = 0.0


func release_held_box() -> void:
	if held_box:
		_held_box_rigid.gravity_scale = 1
		_held_box_rigid.freeze = false
		_held_box_rigid.linear_velocity = Vector3.ZERO
		_held_box_rigid.angular_velocity = Vector3.ZERO
		held_box = null
		_held_box_rigid = null


# --- Pallet moving ---

func _pick_up_pallet(pallet) -> void:
	held_pallet = pallet
	_held_pallet_rigid = pallet.get_node("RigidBody3D") as RigidBody3D
	var initial_direction: Vector3 = (pallet.global_position - global_position).normalized()
	_pallet_offset = initial_direction * 2.5


func _update_held_pallet(delta: float) -> void:
	var rigid := _held_pallet_rigid
	rigid.gravity_scale = 0.1

	var pallet_jack_length := _pallet_offset.length()
	var forward_direction := -_head.global_transform.basis.z
	var target_pos := global_position + forward_direction * pallet_jack_length
	target_pos.y = global_position.y + 0.05

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("pilot_move_forward"):
		input_dir.y += 1
	if Input.is_action_pressed("pilot_move_back"):
		input_dir.y -= 1
	if Input.is_action_pressed("pilot_move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("pilot_move_right"):
		input_dir.x += 1
	var player_is_moving := input_dir.length() > 0.1

	var position_diff := target_pos - rigid.global_position
	var base_responsiveness := 1.8
	var movement_responsiveness := base_responsiveness if player_is_moving else base_responsiveness * 0.4

	var target_velocity := position_diff * movement_responsiveness
	rigid.linear_velocity.x = lerp(rigid.linear_velocity.x, target_velocity.x, 0.7)
	rigid.linear_velocity.z = lerp(rigid.linear_velocity.z, target_velocity.z, 0.7)
	rigid.linear_velocity.y = target_velocity.y * 2.0

	var target_rotation := _head.global_rotation.y
	var current_rotation := rigid.global_rotation.y
	var rotation_diff := target_rotation - current_rotation

	if rotation_diff > PI:
		rotation_diff -= 2.0 * PI
	elif rotation_diff < -PI:
		rotation_diff += 2.0 * PI

	var steering_responsiveness := 1.0 if player_is_moving else 0.3
	rigid.angular_velocity.y = lerp(rigid.angular_velocity.y, rotation_diff * steering_responsiveness, 0.6)
	rigid.angular_velocity.x = 0.0
	rigid.angular_velocity.z = 0.0

	_interact_text.visible = false

	var release := InputMap.has_action("interact") and Input.is_action_just_pressed("interact")
	if release or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		release_held_pallet()


func release_held_pallet() -> void:
	if held_pallet:
		_held_pallet_rigid.gravity_scale = 1
		_held_pallet_rigid.linear_velocity *= 0.3
		_held_pallet_rigid.angular_velocity *= 0.2
		held_pallet = null
		_held_pallet_rigid = null
		_pallet_offset = Vector3.ZERO
