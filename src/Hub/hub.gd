@tool
class_name Hub
extends Node3D

## Industrial Ethernet / fieldbus hub. Exposes a single BOOL "communication
## fault" tag that auto-faults on a random interval for a random duration
## to simulate a fieldbus blip. While faulted, `HUB_LED_Dome` glows red;
## otherwise it sits green. Mirrors `Fio` / `Dpm`.

const LED_OK_COLOR: Color = Color(0, 1, 0, 1)
const LED_FAULTED_COLOR: Color = Color(1, 0, 0, 1)
const LED_EMISSION_ENERGY: float = 2.0

## Live communication-fault state. true = PLC sees the HUB as missing,
## false = healthy. Driven by the auto-fault timer (or the on-demand
## button below); the setter writes the comms tag.
@export var communication_faulted: bool = false:
	set(value):
		if _comm_fault_tag.is_ready() and value != communication_faulted:
			_comm_fault_tag.write_bit(value)
		communication_faulted = value
		_update_led()


@export_category("Auto-Faults")

## Lower bound on the random wait between auto-fired comms faults.
@export_range(0.1, 600.0, 0.1, "suffix:min") var auto_fault_interval_min_minutes: float = 1.0
## Upper bound on the random wait between auto-fired comms faults. Clamped
## to be >= the min at runtime.
@export_range(0.1, 600.0, 0.1, "suffix:min") var auto_fault_interval_max_minutes: float = 5.0
## Lower bound on the random pulse width (how long the fault stays HIGH).
@export_range(0.1, 600.0, 0.1, "suffix:s") var auto_fault_duration_min_seconds: float = 0.5
## Upper bound on the random pulse width. Clamped to be >= the min.
@export_range(0.1, 600.0, 0.1, "suffix:s") var auto_fault_duration_max_seconds: float = 3.0

## Click in the inspector to fire a fault pulse immediately. Auto-resets
## to false on the next frame (acts as a momentary button). The trip is
## deferred so the inspector's commit cycle finishes before the cascade.
@export var fault_on_demand: bool = false:
	set(value):
		var rising_edge: bool = value and not fault_on_demand
		fault_on_demand = value
		if rising_edge:
			call_deferred("_handle_fault_on_demand")


@export_category("Communications")

## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var tag_group_name: String
## The tag group used by the communication-fault output.
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value

## Communication-fault tag.[br]Datatype: [code]BOOL[/code]
## HIGH while the HUB is auto-faulted, LOW while healthy.
@export var communication_fault_tag_name: String = ""


@onready var _led_dome: MeshInstance3D = find_child("HUB_LED_Dome", true, false) as MeshInstance3D

var _comm_fault_tag := OIPCommsTag.new()
var _led_material_made_unique: bool = false
var _simulating: bool = false
var _fault_elapsed: float = 0.0
## Next fault firing time in seconds, freshly drawn after each pulse so
## the wait between faults is randomised, not just the duration.
var _next_fault_seconds: float = 0.0


func _validate_property(property: Dictionary) -> void:
	OIPCommsSetup.validate_tag_property(property, "tag_group_name",
			"tag_groups", "communication_fault_tag_name")


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
	_update_led()


func _process(delta: float) -> void:
	if not _simulating:
		return
	_fault_elapsed += delta
	if _fault_elapsed >= _next_fault_seconds:
		_fault_elapsed = 0.0
		_next_fault_seconds = _draw_next_fault_seconds()
		_trigger_comm_fault()


func _handle_fault_on_demand() -> void:
	_trigger_comm_fault()
	fault_on_demand = false


## Pulse `communication_faulted` HIGH for a random duration drawn from
## the configured range, then drop it. No-op if already faulted.
func _trigger_comm_fault() -> void:
	if communication_faulted:
		return
	communication_faulted = true
	var dur: float = _draw_fault_duration_seconds()
	await get_tree().create_timer(dur).timeout
	# Scene may have closed during the await; bail if so.
	if is_inside_tree():
		communication_faulted = false


func _draw_next_fault_seconds() -> float:
	var lo: float = auto_fault_interval_min_minutes * 60.0
	var hi: float = maxf(lo, auto_fault_interval_max_minutes * 60.0)
	return randf_range(lo, hi)


func _draw_fault_duration_seconds() -> float:
	var lo: float = auto_fault_duration_min_seconds
	var hi: float = maxf(lo, auto_fault_duration_max_seconds)
	return randf_range(lo, hi)


func _update_led() -> void:
	if not _led_dome:
		return
	_ensure_led_material_unique()
	var mat := _led_dome.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		return
	var color: Color = LED_FAULTED_COLOR if communication_faulted else LED_OK_COLOR
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = LED_EMISSION_ENERGY


func _ensure_led_material_unique() -> void:
	if _led_material_made_unique or not _led_dome:
		return
	var current_override := _led_dome.get_surface_override_material(0)
	if current_override:
		if not current_override.resource_local_to_scene:
			var unique_mat := current_override.duplicate() as Material
			unique_mat.resource_local_to_scene = true
			_led_dome.set_surface_override_material(0, unique_mat)
	else:
		var base_mat := _led_dome.mesh.surface_get_material(0) as StandardMaterial3D
		if base_mat:
			var unique_mat := base_mat.duplicate() as Material
			unique_mat.resource_local_to_scene = true
			_led_dome.set_surface_override_material(0, unique_mat)
		else:
			var fresh := StandardMaterial3D.new()
			fresh.emission_enabled = true
			fresh.resource_local_to_scene = true
			_led_dome.set_surface_override_material(0, fresh)
	_led_material_made_unique = true


func _on_simulation_started() -> void:
	_simulating = true
	_fault_elapsed = 0.0
	_next_fault_seconds = _draw_next_fault_seconds()
	if not enable_comms:
		return
	_comm_fault_tag.register(tag_group_name, communication_fault_tag_name)


func _on_simulation_stopped() -> void:
	_simulating = false


func _tag_group_initialized(group: String) -> void:
	if _comm_fault_tag.on_group_initialized(group):
		_comm_fault_tag.write_bit(communication_faulted)
