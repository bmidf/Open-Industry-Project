@tool
class_name Pdp
extends Node3D

## Power distribution panel. Two columns of 13 circuit breakers (26 total)
## plus a power-monitoring module.
##
## Each breaker exposes a [code]tripped[/code] checkbox under the "Circuit
## Breakers" inspector group. In pilot mode, looking at a breaker toggle and
## pressing the interact key (E) trips/resets just that breaker via a small
## interaction proxy built at runtime; the editor "Use" shortcut (C) on the
## panel root acts as a master trip/reset for the whole column set.
##
## The monitoring module shows randomly generated Total Power / KWH Consumed /
## Max Power values, regenerated on an interval while the simulation runs (or
## on demand via the inspector button). Ranges and live values are exposed in
## the inspector.
##
## Comms (mirrors `APF`): every breaker publishes a BOOL "tripped" tag, the
## three PMM values publish REAL tags, and the PMM publishes a BOOL comm-fault
## tag. All are device→PLC writes sharing one tag group; `tag_prefix` auto-fills
## every tag name.

## Breaker count must match the GLB: CB_<col>_<row>_tog for col in {0,1},
## row in {0..12}.
const BREAKER_COUNT: int = 26
const TOGGLE_TRIPPED_ANGLE: float = deg_to_rad(22.0)
const TOGGLE_TWEEN_DURATION: float = 0.12
const HANDLE_COLLISION_SIZE: Vector3 = Vector3(0.03, 0.035, 0.05)
## Area layer must intersect the pilot interaction ray mask (layer 2).
const HANDLE_COLLISION_LAYER: int = 2
const BREAKER_PROPERTY_PREFIX: String = "cb_tripped_"
## Dynamic property prefix for the per-breaker comms tag-name fields.
const BREAKER_TAG_PROPERTY_PREFIX: String = "cb_tag_name_"

# Match APF's pilot-lens colors and emission energy exactly.
const PMM_OK_COLOR: Color = Color(0, 1, 0, 1)
const PMM_FAULTED_COLOR: Color = Color(1, 0, 0, 1)
const PMM_LENS_EMISSION_ENERGY: float = 1.0
## Larger box so the pilot can comfortably target the monitor face.
const PMM_COLLISION_SIZE: Vector3 = Vector3(0.1, 0.07, 0.05)


## Panel name shown on the `Name` label.
@export var name_text: String = "PDP":
	set(value):
		name_text = value
		if _name_label:
			_name_label.text = name_text


@export_category("Power Monitor")

## When true, the displayed power values are regenerated on the interval
## below while the simulation is running.
@export var randomize_power: bool = true
## Seconds between automatic power regenerations during simulation.
@export_range(0.1, 60.0, 0.1, "suffix:s") var power_update_interval: float = 2.0
## Total Power random range, in kW (x = min, y = max).
@export var total_power_range: Vector2 = Vector2(80.0, 150.0)
## KWH Consumed random range, in kWh (x = min, y = max).
@export var kwh_consumed_range: Vector2 = Vector2(5000.0, 25000.0)
## Max Power random range, in kW (x = min, y = max).
@export var max_power_range: Vector2 = Vector2(150.0, 220.0)

## Click in the inspector to regenerate the power values immediately.
## Acts as a momentary button (auto-resets next frame).
@export var regenerate_now: bool = false:
	set(value):
		var rising_edge: bool = value and not regenerate_now
		regenerate_now = value
		if rising_edge:
			call_deferred("_handle_regenerate_now")

## Live Total Power (kW). Read-only; written by the generator. Published as
## a REAL tag.
@export var total_power: float = 0.0:
	set(value):
		if _total_power_tag.is_ready() and value != total_power:
			_total_power_tag.write_float32(value)
		total_power = value
## Live KWH Consumed (kWh). Read-only; written by the generator. Published as
## a REAL tag.
@export var kwh_consumed: float = 0.0:
	set(value):
		if _kwh_consumed_tag.is_ready() and value != kwh_consumed:
			_kwh_consumed_tag.write_float32(value)
		kwh_consumed = value
## Live Max Power (kW). Read-only; written by the generator. Published as a
## REAL tag.
@export var max_power: float = 0.0:
	set(value):
		if _max_power_tag.is_ready() and value != max_power:
			_max_power_tag.write_float32(value)
		max_power = value


@export_category("PMM Fault")

## Live power-monitoring-module fault state. true = faulted (lens red),
## false = healthy (lens green). Driven by the auto-fault timer, the
## on-demand button, or pilot interaction.
@export var pmm_faulted: bool = false:
	set(value):
		# Normally closed: tag is HIGH when healthy, LOW when faulted.
		if _pmm_fault_tag.is_ready() and value != pmm_faulted:
			_pmm_fault_tag.write_bit(not value)
		pmm_faulted = value
		_update_pmm_lens()

## When true, the PMM auto-faults on the random interval below while the
## simulation runs, mirroring `Fio`.
@export var pmm_auto_fault: bool = true
## Lower bound on the random wait between auto-fired PMM faults.
@export_range(0.1, 600.0, 0.1, "suffix:min") var pmm_fault_interval_min_minutes: float = 1.0
## Upper bound on the random wait between auto-fired PMM faults. Clamped to
## be >= the min at runtime.
@export_range(0.1, 600.0, 0.1, "suffix:min") var pmm_fault_interval_max_minutes: float = 5.0
## Lower bound on the random pulse width (how long the fault stays HIGH).
@export_range(0.1, 600.0, 0.1, "suffix:s") var pmm_fault_duration_min_seconds: float = 0.5
## Upper bound on the random pulse width. Clamped to be >= the min.
@export_range(0.1, 600.0, 0.1, "suffix:s") var pmm_fault_duration_max_seconds: float = 3.0

## Click in the inspector to fire a PMM fault pulse immediately. Acts as a
## momentary button (auto-resets next frame).
@export var pmm_fault_on_demand: bool = false:
	set(value):
		var rising_edge: bool = value and not pmm_fault_on_demand
		pmm_fault_on_demand = value
		if rising_edge:
			call_deferred("_handle_pmm_fault_on_demand")


@export_category("Communications")

## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var tag_group_name: String
## The tag group shared by every breaker, PMM value and PMM fault tag.
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value

## Device prefix used to auto-fill every tag-name field (e.g. `PDP1` →
## `PDP1:I.CB1`, …, `PDP1:I.TotalPower`, `PDP1:I.PMMCommFault`). Setting this
## overwrites every tag-name field; clearing it blanks them.
@export var tag_prefix: String = "":
	set(value):
		tag_prefix = value
		_apply_tag_prefix(value)
		notify_property_list_changed()

## TotalPower tag.[br]Datatype: [code]REAL[/code]
@export var total_power_tag_name: String = ""
## KWHConsumed tag.[br]Datatype: [code]REAL[/code]
@export var kwh_consumed_tag_name: String = ""
## MaxPower tag.[br]Datatype: [code]REAL[/code]
@export var max_power_tag_name: String = ""
## PMM communication-fault tag.[br]Datatype: [code]BOOL[/code][br]
## Normally closed: HIGH while the PMM is healthy, LOW while faulted.
@export var pmm_fault_tag_name: String = ""


var _model: Node3D
var _name_label: Label3D
var _total_power_label: Label3D
var _kwh_label: Label3D
var _max_power_label: Label3D

var _tripped: Array[bool] = []
var _toggle_meshes: Array[Node3D] = []
var _handles: Array[PdpInteractable] = []

var _pmm_lenses: Array[MeshInstance3D] = []
var _pmm_handle: PdpInteractable
var _pmm_lens_materials_made_unique: bool = false
var _pmm_fault_elapsed: float = 0.0
## Next PMM fault firing time in seconds, redrawn after each pulse.
var _pmm_next_fault_seconds: float = 0.0

var _simulating: bool = false
var _power_elapsed: float = 0.0

# Comms: one BOOL tag per breaker, three REAL tags for the PMM values, and a
# BOOL PMM comm-fault tag. All device→PLC writes sharing `tag_group_name`.
var _cb_tag_names: Array[String] = []
var _cb_tags: Array[OIPCommsTag] = []
var _total_power_tag := OIPCommsTag.new()
var _kwh_consumed_tag := OIPCommsTag.new()
var _max_power_tag := OIPCommsTag.new()
var _pmm_fault_tag := OIPCommsTag.new()


# --- Dynamic per-breaker bool properties ---

func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	# Own top-level category so the 26 breakers don't nest under another.
	props.append({
		"name": "Circuit Breakers",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_CATEGORY,
	})
	props.append({
		"name": "Tripped",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP,
		"hint_string": BREAKER_PROPERTY_PREFIX,
	})
	for i in BREAKER_COUNT:
		props.append({
			"name": "%s%d" % [BREAKER_PROPERTY_PREFIX, i + 1],
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_DEFAULT,
		})

	# Per-breaker comms tag names. Shown only when comms is enabled globally
	# (mirrors APF gating); always kept as STORAGE so values persist when the
	# Comms dock toggle is off.
	var comms_enabled: bool = OIPComms.get_enable_comms()
	if comms_enabled:
		props.append({
			"name": "Tags",
			"type": TYPE_NIL,
			"usage": PROPERTY_USAGE_GROUP,
			"hint_string": BREAKER_TAG_PROPERTY_PREFIX,
		})
	var tag_usage: int = PROPERTY_USAGE_DEFAULT if comms_enabled else PROPERTY_USAGE_STORAGE
	for i in BREAKER_COUNT:
		props.append({
			"name": "%s%d" % [BREAKER_TAG_PROPERTY_PREFIX, i + 1],
			"type": TYPE_STRING,
			"usage": tag_usage,
		})
	return props


func _get(property: StringName) -> Variant:
	var idx: int = _breaker_index_from_property(property)
	if idx >= 0:
		_ensure_state()
		return _tripped[idx]
	var tag_idx: int = _breaker_tag_index_from_property(property)
	if tag_idx >= 0:
		_ensure_state()
		return _cb_tag_names[tag_idx]
	return null


func _set(property: StringName, value: Variant) -> bool:
	var idx: int = _breaker_index_from_property(property)
	if idx >= 0:
		set_breaker_tripped(idx, bool(value))
		return true
	var tag_idx: int = _breaker_tag_index_from_property(property)
	if tag_idx >= 0:
		_ensure_state()
		_cb_tag_names[tag_idx] = String(value)
		return true
	return false


func _property_can_revert(property: StringName) -> bool:
	return _breaker_index_from_property(property) >= 0 \
			or _breaker_tag_index_from_property(property) >= 0


func _property_get_revert(property: StringName) -> Variant:
	if _breaker_index_from_property(property) >= 0:
		return true
	if _breaker_tag_index_from_property(property) >= 0:
		return ""
	return null


func _breaker_index_from_property(property: StringName) -> int:
	return _indexed_property(property, BREAKER_PROPERTY_PREFIX)


func _breaker_tag_index_from_property(property: StringName) -> int:
	return _indexed_property(property, BREAKER_TAG_PROPERTY_PREFIX)


func _indexed_property(property: StringName, prefix: String) -> int:
	var name_str: String = String(property)
	if not name_str.begins_with(prefix):
		return -1
	var idx: int = name_str.trim_prefix(prefix).to_int() - 1
	if idx < 0 or idx >= BREAKER_COUNT:
		return -1
	return idx


func _validate_property(property: Dictionary) -> void:
	if property.name == "total_power" or property.name == "kwh_consumed" \
			or property.name == "max_power":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
		return
	var tag_fields: PackedStringArray = [
		"total_power_tag_name", "kwh_consumed_tag_name",
		"max_power_tag_name", "pmm_fault_tag_name",
	]
	for field: String in tag_fields:
		if OIPCommsSetup.validate_tag_property(property, "tag_group_name",
				"tag_groups", field):
			return


# --- Lifecycle ---

func _enter_tree() -> void:
	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	EditorInterface.simulation_started.connect(_on_simulation_started)
	EditorInterface.simulation_stopped.connect(_on_simulation_stopped)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized)


func _exit_tree() -> void:
	_simulating = false
	EditorInterface.simulation_started.disconnect(_on_simulation_started)
	EditorInterface.simulation_stopped.disconnect(_on_simulation_stopped)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized)


func _ready() -> void:
	_ensure_state()
	_model = get_node_or_null("PDP") as Node3D
	_collect_power_labels()
	_collect_pmm_lenses()
	_build_breakers()
	_build_pmm_interaction()
	_apply_all_toggle_positions()
	_generate_power()
	_update_pmm_lens()


func _process(delta: float) -> void:
	if not _simulating:
		return
	if randomize_power:
		_power_elapsed += delta
		if _power_elapsed >= power_update_interval:
			_power_elapsed = 0.0
			_generate_power()
	if pmm_auto_fault:
		_pmm_fault_elapsed += delta
		if _pmm_fault_elapsed >= _pmm_next_fault_seconds:
			_pmm_fault_elapsed = 0.0
			_pmm_next_fault_seconds = _draw_pmm_next_fault_seconds()
			_trigger_pmm_fault()


# --- Breaker interaction ---

## Pilot/editor entry point used by a breaker proxy: flips one breaker.
func toggle_breaker(index: int) -> void:
	if index < 0 or index >= BREAKER_COUNT:
		return
	_ensure_state()
	set_breaker_tripped(index, not _tripped[index])
	notify_property_list_changed()


## Set a single breaker's tripped state and animate its toggle.
func set_breaker_tripped(index: int, value: bool) -> void:
	_ensure_state()
	if index < 0 or index >= BREAKER_COUNT:
		return
	if _tripped[index] == value:
		return
	_tripped[index] = value
	if _cb_tags[index].is_ready():
		_cb_tags[index].write_bit(value)
	_animate_toggle(index)


## Editor "Use" shortcut (C) on the panel root: master trip/reset. Trips all
## breakers if any are still closed, otherwise resets them all.
func use() -> void:
	_ensure_state()
	var any_closed: bool = false
	for i in BREAKER_COUNT:
		if not _tripped[i]:
			any_closed = true
			break
	for i in BREAKER_COUNT:
		set_breaker_tripped(i, any_closed)
	notify_property_list_changed()


func _ensure_state() -> void:
	if _tripped.size() != BREAKER_COUNT:
		# Breakers default to tripped (true / On); fill any newly added slots.
		var old_size: int = _tripped.size()
		_tripped.resize(BREAKER_COUNT)
		for i in range(old_size, BREAKER_COUNT):
			_tripped[i] = true
	if _toggle_meshes.size() != BREAKER_COUNT:
		_toggle_meshes.resize(BREAKER_COUNT)
	if _handles.size() != BREAKER_COUNT:
		_handles.resize(BREAKER_COUNT)
	if _cb_tag_names.size() != BREAKER_COUNT:
		_cb_tag_names.resize(BREAKER_COUNT)
	if _cb_tags.size() != BREAKER_COUNT:
		_cb_tags.resize(BREAKER_COUNT)
		for i in BREAKER_COUNT:
			if _cb_tags[i] == null:
				_cb_tags[i] = OIPCommsTag.new()


func _build_breakers() -> void:
	if not _model:
		return
	for i in BREAKER_COUNT:
		var col: int = i & 1
		var row: int = i >> 1
		var tog := _model.find_child("CB_%d_%d_tog" % [col, row], true, false) as Node3D
		_toggle_meshes[i] = tog

		# Task 1: each CB label shows its own node name instead of "CB1".
		var label := _model.get_node_or_null("CB%d" % (i + 1)) as Label3D
		if label:
			label.text = label.name

		if tog == null or (_handles[i] != null and is_instance_valid(_handles[i])):
			continue

		var handle := _make_interaction_proxy("CB%dSwitch" % (i + 1),
				toggle_breaker.bind(i), HANDLE_COLLISION_SIZE, tog.global_position)
		_handles[i] = handle


## Build an [Area3D]-backed interaction proxy at a world position and wire its
## [method PdpInteractable.use] to a callable. Added as a child of the panel.
func _make_interaction_proxy(proxy_name: String, action: Callable,
		box_size: Vector3, world_origin: Vector3) -> PdpInteractable:
	var handle := PdpInteractable.new()
	handle.name = proxy_name
	handle.on_use = action

	var area := Area3D.new()
	area.collision_layer = HANDLE_COLLISION_LAYER
	area.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	area.add_child(shape)
	handle.add_child(area)

	add_child(handle)
	handle.global_position = world_origin
	handle.global_rotation = global_rotation
	return handle


func _apply_all_toggle_positions() -> void:
	for i in BREAKER_COUNT:
		var tog: Node3D = _toggle_meshes[i]
		if tog:
			tog.rotation.x = TOGGLE_TRIPPED_ANGLE if _tripped[i] else 0.0


func _animate_toggle(index: int) -> void:
	var tog: Node3D = _toggle_meshes[index] if index < _toggle_meshes.size() else null
	if not tog:
		return
	var target: float = TOGGLE_TRIPPED_ANGLE if _tripped[index] else 0.0
	var tween := create_tween()
	tween.tween_property(tog, "rotation:x", target, TOGGLE_TWEEN_DURATION)


# --- Power monitor ---

func _collect_power_labels() -> void:
	if not _model:
		return
	_name_label = _model.get_node_or_null("Name") as Label3D
	if _name_label:
		_name_label.text = name_text
	_total_power_label = _model.get_node_or_null("TotalPowerNum") as Label3D
	_kwh_label = _model.get_node_or_null("KWHConsumedNum") as Label3D
	_max_power_label = _model.get_node_or_null("MaxPowerNum") as Label3D


func _generate_power() -> void:
	total_power = randf_range(minf(total_power_range.x, total_power_range.y),
			maxf(total_power_range.x, total_power_range.y))
	kwh_consumed = randf_range(minf(kwh_consumed_range.x, kwh_consumed_range.y),
			maxf(kwh_consumed_range.x, kwh_consumed_range.y))
	max_power = randf_range(minf(max_power_range.x, max_power_range.y),
			maxf(max_power_range.x, max_power_range.y))
	_update_power_labels()


func _update_power_labels() -> void:
	if _total_power_label:
		_total_power_label.text = "%d kW" % int(roundf(total_power))
	if _kwh_label:
		_kwh_label.text = "%d kWh" % int(roundf(kwh_consumed))
	if _max_power_label:
		_max_power_label.text = "%d kW" % int(roundf(max_power))


func _handle_regenerate_now() -> void:
	_generate_power()
	regenerate_now = false


# --- PMM fault ---

## Pilot/editor entry point for the PMM proxy: toggles the fault. Going TRUE
## fires a self-clearing pulse (random duration); clearing is immediate.
## Mirrors `Fio.use`.
func use_pmm() -> void:
	if pmm_faulted:
		pmm_faulted = false
	else:
		_trigger_pmm_fault()


## Pulse the PMM fault HIGH for a random duration, then drop it. No-op if
## already faulted.
func _trigger_pmm_fault() -> void:
	if pmm_faulted:
		return
	pmm_faulted = true
	var dur: float = _draw_pmm_fault_duration_seconds()
	await get_tree().create_timer(dur).timeout
	# Scene may have closed during the await; bail if so.
	if is_inside_tree():
		pmm_faulted = false


func _handle_pmm_fault_on_demand() -> void:
	_trigger_pmm_fault()
	pmm_fault_on_demand = false


func _draw_pmm_next_fault_seconds() -> float:
	var lo: float = pmm_fault_interval_min_minutes * 60.0
	var hi: float = maxf(lo, pmm_fault_interval_max_minutes * 60.0)
	return randf_range(lo, hi)


func _draw_pmm_fault_duration_seconds() -> float:
	var lo: float = pmm_fault_duration_min_seconds
	var hi: float = maxf(lo, pmm_fault_duration_max_seconds)
	return randf_range(lo, hi)


func _collect_pmm_lenses() -> void:
	_pmm_lenses.clear()
	if not _model:
		return
	for node in _model.find_children("PilotLens*", "MeshInstance3D", true, false):
		_pmm_lenses.append(node as MeshInstance3D)
	_pmm_lens_materials_made_unique = false


func _build_pmm_interaction() -> void:
	if not _model or (_pmm_handle != null and is_instance_valid(_pmm_handle)):
		return
	var anchor := _model.find_child("PMM_Display", true, false) as Node3D
	if anchor == null:
		anchor = _model.find_child("PMM_Body", true, false) as Node3D
	if anchor == null:
		return
	_pmm_handle = _make_interaction_proxy("PMM", use_pmm, PMM_COLLISION_SIZE,
			anchor.global_position)


func _update_pmm_lens() -> void:
	if _pmm_lenses.is_empty():
		return
	_ensure_pmm_lens_materials_unique()
	var color: Color = PMM_FAULTED_COLOR if pmm_faulted else PMM_OK_COLOR
	for lens in _pmm_lenses:
		if not lens:
			continue
		var mat := lens.get_surface_override_material(0) as StandardMaterial3D
		if not mat:
			continue
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = PMM_LENS_EMISSION_ENERGY


func _ensure_pmm_lens_materials_unique() -> void:
	if _pmm_lens_materials_made_unique or _pmm_lenses.is_empty():
		return
	for lens in _pmm_lenses:
		if not lens:
			continue
		var current := lens.get_surface_override_material(0)
		if current:
			if not current.resource_local_to_scene:
				var unique_mat := current.duplicate() as Material
				unique_mat.resource_local_to_scene = true
				lens.set_surface_override_material(0, unique_mat)
			continue
		var base_mat: StandardMaterial3D = null
		if lens.mesh:
			base_mat = lens.mesh.surface_get_material(0) as StandardMaterial3D
		if base_mat:
			var unique_mat := base_mat.duplicate() as Material
			unique_mat.resource_local_to_scene = true
			lens.set_surface_override_material(0, unique_mat)
		else:
			var fresh := StandardMaterial3D.new()
			fresh.emission_enabled = true
			fresh.resource_local_to_scene = true
			lens.set_surface_override_material(0, fresh)
	_pmm_lens_materials_made_unique = true


func _on_simulation_started() -> void:
	_simulating = true
	_power_elapsed = 0.0
	_pmm_fault_elapsed = 0.0
	_pmm_next_fault_seconds = _draw_pmm_next_fault_seconds()
	if not enable_comms:
		return
	_ensure_state()
	for i in BREAKER_COUNT:
		_cb_tags[i].register(tag_group_name, _cb_tag_names[i])
	_total_power_tag.register(tag_group_name, total_power_tag_name)
	_kwh_consumed_tag.register(tag_group_name, kwh_consumed_tag_name)
	_max_power_tag.register(tag_group_name, max_power_tag_name)
	_pmm_fault_tag.register(tag_group_name, pmm_fault_tag_name)


func _on_simulation_stopped() -> void:
	_simulating = false


# --- Comms ---

func _tag_group_initialized(group: String) -> void:
	_ensure_state()
	for i in BREAKER_COUNT:
		if _cb_tags[i].on_group_initialized(group):
			_cb_tags[i].write_bit(_tripped[i])
	if _total_power_tag.on_group_initialized(group):
		_total_power_tag.write_float32(total_power)
	if _kwh_consumed_tag.on_group_initialized(group):
		_kwh_consumed_tag.write_float32(kwh_consumed)
	if _max_power_tag.on_group_initialized(group):
		_max_power_tag.write_float32(max_power)
	if _pmm_fault_tag.on_group_initialized(group):
		_pmm_fault_tag.write_bit(not pmm_faulted)


# Tag-name suffix templates for `tag_prefix` auto-fill. Device→PLC status uses
# Rockwell `:I.*` semantics, matching APF.
const _PMM_TAG_TEMPLATES: Dictionary = {
	"total_power_tag_name": ":I.TotalPower",
	"kwh_consumed_tag_name": ":I.KWHConsumed",
	"max_power_tag_name": ":I.MaxPower",
	"pmm_fault_tag_name": ":I.PMMCommFault",
}


func _apply_tag_prefix(prefix: String) -> void:
	_ensure_state()
	for property: String in _PMM_TAG_TEMPLATES:
		var suffix: String = _PMM_TAG_TEMPLATES[property]
		set(property, prefix + suffix if prefix != "" else "")
	for i in BREAKER_COUNT:
		_cb_tag_names[i] = "%s_CB%d_OIP" % [prefix, i + 1] if prefix != "" else ""
