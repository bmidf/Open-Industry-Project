@tool
extends Resource
class_name PushButtonData

signal label_changed(value)
signal color_changed(value)
signal toggle_changed(value)
signal pushbutton_changed(value)
signal lamp_changed(value)
signal comms_changed()

@export var label: String = "STOP":
	set(value):
		label = value
		emit_signal("label_changed", value)

@export var color: Color = Color.RED:
	set(value):
		color = value
		emit_signal("color_changed", value)

@export var toggle: bool = false:
	set(value):
		toggle = value
		emit_signal("toggle_changed", value)

@export var pushbutton: bool = false:
	set(value):
		pushbutton = value
		emit_signal("pushbutton_changed", value)

@export var lamp: bool = false:
	set(value):
		lamp = value
		emit_signal("lamp_changed", value)

@export var enable_comms: bool = false:
	set(value):
		enable_comms = value
		emit_signal("comms_changed")

@export var pushbutton_tag_group_name: String = ""
@export var pushbutton_tag_name: String = ""
@export var lamp_tag_group_name: String = ""
@export var lamp_tag_name: String = ""
