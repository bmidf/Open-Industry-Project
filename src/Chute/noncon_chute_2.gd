@tool
class_name NonConChute2
extends ResizableNode3D

## Funnel-style non-conveyable gravity chute (wide intake -> narrow spout), split into:
##   Chute_Visual (bed/frame/walls), Legs (stretchable support legs, origin at the
##   floor) and Chute (hidden collision proxy).
##
## Carries over ONLY two behaviours from the first chute (NonConChute):
## - Leg adjustment: extends ResizableNode3D so the conveyor gizmo shows a top (+Y)
##   drag handle that drives [member leg_extension]; the legs stretch from the floor
##   and the whole body rises with them.
## - Conveyor snapping: get_snap_features() snaps the WIDE (intake) end to a conveyor
##   at bed height; the conveyor opens its side guard where the chute stands.
##
## [member model_scale] uniformly scales the whole chute, so the SAME model can be
## dropped at several sizes (small / original / 3x) by separate scenes. Uniform scale
## is collision-safe (never non-uniform).

const _CHILD: String = "chute_NON_CON_2"
const _VIS_PATH: String = "chute_NON_CON_2/Chute_Visual"
const _LEGS_PATH: String = "chute_NON_CON_2/Legs"
const _COL_PATH: String = "chute_NON_CON_2/Chute"
## Legs height at zero extension, in (unscaled) meters.
const LEGS_BASE_HEIGHT: float = 0.47
## Overall chute height at zero extension (unscaled meters = CAD height * root_scale).
const BASE_HEIGHT: float = 0.876
const FIXED_LENGTH: float = 1.376
const FIXED_WIDTH: float = 1.664
const MIN_EXTENSION: float = -0.3
const MAX_EXTENSION: float = 5.0

## Uniform size multiplier for the whole chute (1.0 = the model's base import size).
@export_range(0.1, 10.0, 0.01) var model_scale: float = 1.0:
	set(value):
		model_scale = maxf(0.01, value)
		_apply()
		if not _syncing:
			_syncing = true
			size = Vector3(FIXED_LENGTH, BASE_HEIGHT + leg_extension, FIXED_WIDTH) * model_scale
			_syncing = false
		update_gizmos()

## Lengthen (or shorten, negative) the legs; the chute body rises/falls with them (unscaled m).
@export_range(-0.3, 5.0, 0.01, "suffix:m") var leg_extension: float = 0.0:
	set(value):
		leg_extension = clampf(value, MIN_EXTENSION, MAX_EXTENSION)
		_apply()
		if not _syncing:
			_syncing = true
			size = Vector3(FIXED_LENGTH, BASE_HEIGHT + leg_extension, FIXED_WIDTH) * model_scale
			_syncing = false

@export_group("Snapping")
## Half chute length along local X (snap ends), unscaled.
@export var half_length: float = 0.688
## Half intake (wide-end) width along local Z, unscaled.
@export var half_width: float = 0.832
## Bed height (intake end) at zero leg extension, unscaled.
@export var bed_y: float = 0.876
## How far BELOW the conveyor the bed lands on align (unscaled m).
@export_range(0.0, 0.5, 0.005, "suffix:m") var snap_drop: float = 0.07
## Extra world-space lift of the snap connection so the chute sits HIGHER at the
## conveyor (raises the whole chute by this many metres on align).
@export_range(-1.0, 2.0, 0.01, "suffix:m") var snap_lift: float = 0.74

## Intake width (scaled); lets the side-guard opening derivation use the real footprint.
var width: float:
	get:
		return FIXED_WIDTH * model_scale

## Local-space AABB used by snapping/gizmo code (origin at the floor, not centered), scaled.
var local_bbox: AABB:
	get:
		var ms: float = model_scale
		return AABB(
				Vector3(-FIXED_LENGTH * 0.5 * ms, 0.0, -FIXED_WIDTH * 0.5 * ms),
				Vector3(FIXED_LENGTH * ms, (BASE_HEIGHT + leg_extension) * ms, FIXED_WIDTH * ms))

var _syncing: bool = false
var _base_cached: bool = false
var _base_pos: Dictionary = {}
var _legs_base_scale: Vector3 = Vector3.ONE


func _init() -> void:
	size_default = Vector3(FIXED_LENGTH, BASE_HEIGHT, FIXED_WIDTH)
	size_min = Vector3(FIXED_LENGTH * 0.1, (BASE_HEIGHT + MIN_EXTENSION) * 0.1, FIXED_WIDTH * 0.1)


func _ready() -> void:
	_apply()
	if not _syncing:
		_syncing = true
		size = Vector3(FIXED_LENGTH, BASE_HEIGHT + leg_extension, FIXED_WIDTH) * model_scale
		_syncing = false
	ConveyorSnapping.notify_contacts_rebuild(self)


func _exit_tree() -> void:
	super._exit_tree()
	ConveyorSnapping.notify_contacts_rebuild(self)


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		ConveyorSnapping.notify_contacts_rebuild(self)


#region ResizableNode3D integration (gizmo handle drives leg_extension)

func _on_size_changed() -> void:
	if _syncing:
		return
	_syncing = true
	leg_extension = size.y / maxf(0.01, model_scale) - BASE_HEIGHT
	_syncing = false


func _get_constrained_size(new_size: Vector3) -> Vector3:
	var ms: float = model_scale
	return Vector3(
			FIXED_LENGTH * ms,
			clampf(new_size.y, (BASE_HEIGHT + MIN_EXTENSION) * ms, (BASE_HEIGHT + MAX_EXTENSION) * ms),
			FIXED_WIDTH * ms)


func _get_resize_local_bounds(for_size: Vector3) -> AABB:
	return AABB(Vector3(-for_size.x * 0.5, 0.0, -for_size.z * 0.5), for_size)


func _get_active_resize_handle_ids() -> PackedInt32Array:
	return PackedInt32Array([2])


func _get_scale_warning_text() -> String:
	return "Use the top handle (or 'size' Y) to adjust the chute legs."

#endregion


func _node(path: String) -> Node3D:
	return get_node_or_null(NodePath(path)) as Node3D


func _cache_base() -> void:
	if _base_cached:
		return
	var vis: Node3D = _node(_VIS_PATH)
	var legs: Node3D = _node(_LEGS_PATH)
	var col: Node3D = _node(_COL_PATH)
	if vis == null or legs == null or col == null:
		return
	_base_pos.clear()
	for path: String in [_VIS_PATH, _COL_PATH, _LEGS_PATH]:
		var n: Node3D = _node(path)
		if n != null:
			_base_pos[path] = n.position
	_legs_base_scale = legs.scale
	_base_cached = true


func _apply() -> void:
	_cache_base()
	if not _base_cached:
		return
	# Uniform scale on the imported model root (collision-safe).
	var child: Node3D = _node(_CHILD)
	if child != null and not child.scale.is_equal_approx(Vector3.ONE * model_scale):
		child.scale = Vector3.ONE * model_scale
	var rise: Vector3 = Vector3(0.0, leg_extension, 0.0)
	for path: String in _base_pos.keys():
		var n: Node3D = _node(path)
		if n == null:
			continue
		if path == _LEGS_PATH:
			n.position = _base_pos[path]
			var k: float = (LEGS_BASE_HEIGHT + leg_extension) / LEGS_BASE_HEIGHT
			n.scale = Vector3(_legs_base_scale.x, _legs_base_scale.y * k, _legs_base_scale.z)
		else:
			n.position = (_base_pos[path] as Vector3) + rise


func get_snap_features() -> Array:
	var ms: float = model_scale
	# Features sit snap_drop ABOVE the bed so the align lands the bed that much
	# below the conveyor's contact line. snap_lift (world m) then raises the whole
	# chute so it sits exactly at the conveyor. Intake = wide end at local +X.
	var by: float = (bed_y + leg_extension + snap_drop) * ms - snap_lift
	var hl: float = half_length * ms
	var hw: float = half_width * ms
	return [
		{"shape": 0, "kind": &"straight_end_front", "local_pos": Vector3(hl, by, 0.0),
			"local_outward": Vector3(1, 0, 0), "end_name": &"front"},
		{"shape": 0, "kind": &"straight_end_back", "local_pos": Vector3(-hl, by, 0.0),
			"local_outward": Vector3(-1, 0, 0), "end_name": &"back"},
		{"shape": 1, "kind": &"straight_sideguard_left",
			"seg_start": Vector3(-hl, by, -hw), "seg_end": Vector3(hl, by, -hw),
			"seg_outward_local": Vector3(0, 0, -1)},
		{"shape": 1, "kind": &"straight_sideguard_right",
			"seg_start": Vector3(-hl, by, hw), "seg_end": Vector3(hl, by, hw),
			"seg_outward_local": Vector3(0, 0, 1)},
	]
