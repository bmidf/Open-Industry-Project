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
				button_data[i] = data
		
		if button_data.size() != _prev_size:
			_prev_size = button_data.size()
			_update_segments()

func _update_segments():
	if !is_instance_valid(segments_container):
		return

	# Save current states
	var old_states = segments_container.get_children().map(func(child): 
		return {
			"label": child.text,
			"color": child.button_color,
			"toggle": child.toggle,
			"pushbutton": child.pushbutton,
			"lamp": child.lamp,
			"enable_comms": child.enable_comms,
			"pp_tag_group": child.pushbutton_tag_group_name,
			"pp_tag": child.pushbutton_tag_name,
			"lamp_tag_group": child.lamp_tag_group_name,
			"lamp_tag": child.lamp_tag_name
		})

	# Adjust button count
	var total_buttons = button_data.size()
	var existing_buttons = segments_container.get_child_count()

	# Remove excess buttons
	while existing_buttons > total_buttons:
		segments_container.get_child(existing_buttons - 1).queue_free()
		existing_buttons -= 1
		if old_states.size() > 0:
			old_states.pop_back()

	# Add new buttons
	while existing_buttons < total_buttons:
		var new_btn = segment_scene.instantiate()
		new_btn.name = "STOP %d" % existing_buttons
		segments_container.add_child(new_btn)
		new_btn.owner = self.get_parent()
		existing_buttons += 1
		old_states.append({})

	# Layout parameters
	var buttons_per_row = 4
	var spacing = Vector2(0.4, 0.4)
	var total_rows = int(ceil(float(total_buttons) / buttons_per_row))

	# Update all buttons
	for i in range(total_buttons):
		var btn = segments_container.get_child(i)
		var data = button_data[i]
		if data == null:
			continue

		# Position buttons in grid layout
		var row = i / buttons_per_row
		var col = i % buttons_per_row
		var buttons_in_row = min(buttons_per_row, total_buttons - row * buttons_per_row)
		var total_width = (buttons_in_row - 1) * spacing.x
		var total_height = (total_rows - 1) * spacing.y
		btn.transform.origin = Vector3(
			col * spacing.x - total_width / 2,
			-row * spacing.y + total_height / 2,
			0
		)
		
		btn.name = "STOP %d" % i
		
		var bolts = btn.find_child("Bolts", true, false)
		if bolts:
			bolts.visible = false

		# Restore saved state or apply default values
		if i < old_states.size() && !old_states[i].is_empty():
			var old = old_states[i]
			data.label = old["label"]
			data.color = old["color"]
			data.toggle = old["toggle"]
			data.pushbutton = old["pushbutton"]
			data.lamp = old["lamp"]
			data.enable_comms = old["enable_comms"]
			data.pushbutton_tag_group_name = old["pp_tag_group"]
			data.pushbutton_tag_name = old["pp_tag"]
			data.lamp_tag_group_name = old["lamp_tag_group"]
			data.lamp_tag_name = old["lamp_tag"]
		
		_connect_data_signals(data, btn)
		_update_button_properties(btn, data)

func _update_button_properties(btn, data):
	# Update all button properties at once
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

func _connect_data_signals(data: PushButtonData, button: PushButton):
	_disconnect_existing_signals(data)
	
	# Connect property signals
	data.label_changed.connect(_on_property_changed.bind("text", button))
	data.color_changed.connect(_on_property_changed.bind("button_color", button))
	data.toggle_changed.connect(_on_property_changed.bind("toggle", button))
	data.pushbutton_changed.connect(_on_property_changed.bind("pushbutton", button))
	data.lamp_changed.connect(_on_property_changed.bind("lamp", button))
	data.comms_changed.connect(_on_comms_changed.bind(button))

func _disconnect_existing_signals(data: PushButtonData):
	# Disconnect property signals
	var signals = ["label_changed", "color_changed", "toggle_changed", 
				   "pushbutton_changed", "lamp_changed"]
	for signal_name in signals:
		var signal_ref = data.get(signal_name)
		if signal_ref and signal_ref.is_connected(Callable(self, "_on_property_changed")):
			signal_ref.disconnect(Callable(self, "_on_property_changed"))
	if data.comms_changed.is_connected(Callable(self, "_on_comms_changed")):
		data.comms_changed.disconnect(Callable(self, "_on_comms_changed"))

func _on_property_changed(value, property: String, button: PushButton):
	if is_instance_valid(button):
		button.set(property, value)

func _on_comms_changed(button: PushButton):
	if is_instance_valid(button):
		var index = button.get_index()
		if index >= 0 and index < button_data.size():
			button.enable_comms = button_data[index].enable_comms
