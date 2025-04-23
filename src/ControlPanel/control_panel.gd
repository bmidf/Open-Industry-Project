@tool
extends Node3D
class_name ControlPanel

@export var button_data: Array[PushButtonData] = []:
	set(value):
		if value.size() > 16:
			value.resize(16)
		_button_data_internal = value
		if Engine.is_editor_hint():
			_update_segments()
	get:
		return _button_data_internal

var _button_data_internal: Array[PushButtonData] = []
var segment_scene: PackedScene = preload("res://parts/PushButton.tscn")
var segments_container: Node3D
var _prev_size := 0

func _ready():
	if Engine.is_editor_hint():
		segments_container = $SegmentsContainer
		_update_segments()

func _process(_delta):
	if Engine.is_editor_hint():
		for i in range(button_data.size()):
			if button_data[i] == null:
				var data = PushButtonData.new()
				data.label = "STOP %d" % i
				button_data[i] = data
		
		if button_data.size() != _prev_size:
			_prev_size = button_data.size()
			_update_segments()

func _update_segments():
	if !is_instance_valid(segments_container):
		return

	for child in segments_container.get_children():
		child.queue_free()

	var buttons_per_row = 4
	var spacing_x = 0.4
	var spacing_y = 0.4
	var total_buttons = button_data.size()
	var total_rows = int(ceil(float(total_buttons) / buttons_per_row))

	for i in range(total_buttons):
		var data = button_data[i]
		if data == null:
			continue

		var btn = segment_scene.instantiate()
		btn.name = "STOP %d" % i
		segments_container.add_child(btn)
		btn.owner = self.get_parent()
		
		var bolts = btn.find_child("Bolts", true, false)
		bolts.visible = false
			
		var row = i / buttons_per_row
		var col = i % buttons_per_row

		var buttons_in_row = buttons_per_row
		if row == total_rows - 1 and total_buttons % buttons_per_row != 0:
			buttons_in_row = total_buttons % buttons_per_row

		var total_width = (buttons_in_row - 1) * spacing_x
		var total_height = (total_rows - 1) * spacing_y

		var x = col * spacing_x - total_width / 2
		var y = -row * spacing_y + total_height / 2

		btn.transform.origin = Vector3(x, y, 0)

		_connect_data_signals(data, btn)
		_update_button_properties(btn, data)

func _update_button_properties(btn, data):
	btn.text = data.label
	btn.button_color = data.color
	btn.toggle = data.toggle
	btn.pushbutton = data.pushbutton
	btn.lamp = data.lamp
	btn.enable_comms = data.enable_comms
	btn.pushbutton_tag_group_name = data.pushbutton_tag_group_name
	btn.pushbutton_tag_name = data.pushbutton_tag_name
	btn.lamp_tag_group_name = data.lamp_tag_group_name
	btn.lamp_tag_name = data.lamp_tag_name

func _on_label_changed(value, button):
	if is_instance_valid(button):
		button.text = value

func _on_color_changed(value, button):
	if is_instance_valid(button):
		button.button_color = value

func _on_toggle_changed(value, button):
	if is_instance_valid(button):
		button.toggle = value

func _on_pushbutton_changed(value, button):
	if is_instance_valid(button):
		button.pushbutton = value

func _on_lamp_changed(value, button):
	if is_instance_valid(button):
		button.lamp = value

func _on_comms_changed(button):
	if is_instance_valid(button):
		button.enable_comms = button_data[button.get_index()].enable_comms
	
func _disconnect_existing_signals(data: PushButtonData):
	if data.label_changed.is_connected(_on_label_changed):
		data.label_changed.disconnect(_on_label_changed)
	if data.color_changed.is_connected(_on_color_changed):
		data.color_changed.disconnect(_on_color_changed)
	if data.toggle_changed.is_connected(_on_toggle_changed):
		data.toggle_changed.disconnect(_on_toggle_changed)
	if data.pushbutton_changed.is_connected(_on_pushbutton_changed):
		data.pushbutton_changed.disconnect(_on_pushbutton_changed)
	if data.lamp_changed.is_connected(_on_lamp_changed):
		data.lamp_changed.disconnect(_on_lamp_changed)
	if data.comms_changed.is_connected(_on_comms_changed):
		data.comms_changed.disconnect(_on_comms_changed)

func _connect_data_signals(data: PushButtonData, button: PushButton):
	_disconnect_existing_signals(data)
	data.label_changed.connect(_on_label_changed.bind(button))
	data.color_changed.connect(_on_color_changed.bind(button))
	data.toggle_changed.connect(_on_toggle_changed.bind(button))
	data.pushbutton_changed.connect(_on_pushbutton_changed.bind(button))
	data.lamp_changed.connect(_on_lamp_changed.bind(button))
	data.comms_changed.connect(_on_comms_changed.bind(button))
