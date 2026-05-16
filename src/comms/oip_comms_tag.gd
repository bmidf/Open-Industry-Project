class_name OIPCommsTag
extends RefCounted

## Process-wide counters incremented on every successful comms call.
## Read by `statistics.gd` (or any other monitor) to compute rate-per-
## second without instrumenting individual parts. Cheap (one int add per
## call); resetting is the caller's responsibility.
static var read_count: int = 0
static var write_count: int = 0

var tag_group_name: String
var tag_name: String
var _register_ok: bool = false
var _group_init: bool = false
# Integer handle into OIPComms.tag_index_. >= 0 = fast path (skip string-
# keyed map lookup on every read/write). -1 = fall back to the legacy
# string-keyed call. register_tag_h returns -1 for protocols where the
# fast path isn't yet wired up (opc_ua/ads/rtde stay on the legacy path).
var _handle: int = -1


func register(group: String, tag: String, count: int = 1) -> void:
	tag_group_name = group
	tag_name = tag
	if OIPComms.has_method(&"register_tag_h"):
		_handle = OIPComms.register_tag_h(tag_group_name, tag_name, count)
		_register_ok = _handle >= 0
		if not _register_ok:
			# register_tag_h returns -1 on validation failure but also when the
			# group doesn't exist. Fall back to the bool API for diagnosis
			# parity with the old wrapper.
			_register_ok = OIPComms.register_tag(tag_group_name, tag_name, count)
	else:
		_register_ok = OIPComms.register_tag(tag_group_name, tag_name, count)


func on_group_initialized(group: String) -> bool:
	if group == tag_group_name:
		_group_init = true
		return _register_ok
	return false


func is_ready() -> bool:
	# When the DLL exposes is_tag_ready_h, ask it directly. This reflects
	# the underlying tag's actual readiness — false during the gap after a
	# sim stop/restart (slots being re-created) and true once libplctag has
	# real PLC data in the cache. Without this, _group_init stays sticky
	# across sim restarts and device scripts read 0 / pop "not initialized"
	# until the scene is reloaded.
	if _handle >= 0 and OIPComms.has_method(&"is_tag_ready_h"):
		return _register_ok and OIPComms.is_tag_ready_h(_handle)
	return _register_ok and _group_init


func matches_group(group: String) -> bool:
	return group == tag_group_name


func read_bit() -> bool:
	read_count += 1
	if _handle >= 0:
		return OIPComms.read_bit_h(_handle)
	return OIPComms.read_bit(tag_group_name, tag_name)


func write_bit(value: bool) -> void:
	write_count += 1
	if _handle >= 0:
		OIPComms.write_bit_h(_handle, value)
	else:
		OIPComms.write_bit(tag_group_name, tag_name, value)


func read_float32() -> float:
	read_count += 1
	if _handle >= 0:
		return OIPComms.read_float32_h(_handle)
	return OIPComms.read_float32(tag_group_name, tag_name)


func write_float32(value: float) -> void:
	write_count += 1
	if _handle >= 0:
		OIPComms.write_float32_h(_handle, value)
	else:
		OIPComms.write_float32(tag_group_name, tag_name, value)


func read_float64() -> float:
	if _handle >= 0:
		return OIPComms.read_float64_h(_handle)
	return OIPComms.read_float64(tag_group_name, tag_name)


func write_float64(value: float) -> void:
	if _handle >= 0:
		OIPComms.write_float64_h(_handle, value)
	else:
		OIPComms.write_float64(tag_group_name, tag_name, value)


func read_int16() -> int:
	read_count += 1
	if _handle >= 0:
		return OIPComms.read_int16_h(_handle)
	return OIPComms.read_int16(tag_group_name, tag_name)


func write_int16(value: int) -> void:
	write_count += 1
	if _handle >= 0:
		OIPComms.write_int16_h(_handle, value)
	else:
		OIPComms.write_int16(tag_group_name, tag_name, value)


func read_int32() -> int:
	read_count += 1
	if _handle >= 0:
		return OIPComms.read_int32_h(_handle)
	return OIPComms.read_int32(tag_group_name, tag_name)


func write_int32(value: int) -> void:
	write_count += 1
	if _handle >= 0:
		OIPComms.write_int32_h(_handle, value)
	else:
		OIPComms.write_int32(tag_group_name, tag_name, value)


func read_uint8() -> int:
	read_count += 1
	if _handle >= 0:
		return OIPComms.read_uint8_h(_handle)
	return OIPComms.read_uint8(tag_group_name, tag_name)


func write_uint8(value: int) -> void:
	write_count += 1
	if _handle >= 0:
		OIPComms.write_uint8_h(_handle, value)
	else:
		OIPComms.write_uint8(tag_group_name, tag_name, value)
