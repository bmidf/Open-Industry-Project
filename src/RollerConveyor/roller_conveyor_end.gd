@tool
extends AbstractRollerContainer
class_name RollerConveyorEnd

const BASE_WIDTH: float = 2.0

@export var flipped: bool = false:
	set(value):
		if flipped != value:
			flipped = value
			roller_rotation_changed.emit(_get_rotation_from_skew_angle(_roller_skew_angle_degrees))

var _roller: Roller

func _init() -> void:
	super()
	width_changed.connect(self._set_ends_separation)

# Overrides virtual method from AbstractRollerContainer
func setup_existing_rollers() -> void:
	_roller = get_node("Roller")
	super.setup_existing_rollers()

# Overrides virtual method from AbstractRollerContainer
func _get_rollers() -> Array[Roller]:
	var rollers: Array[Roller] = [_roller]
	return rollers

func _set_ends_separation(width: float) -> void:
	var end = get_node("ConveyorRollerEnd")
	end.scale = Vector3(1.0, 1.0, width / BASE_WIDTH)
	for end_mesh in end.get_children():
		if end_mesh is MeshInstance3D:
			end_mesh.scale = Vector3(1.0, 1.0, BASE_WIDTH / width)

func _get_rotation_from_skew_angle(angle_degrees: float) -> Vector3:
	var rot = super._get_rotation_from_skew_angle(angle_degrees)
	return rot + Vector3(0, 180, 0) if flipped else rot
