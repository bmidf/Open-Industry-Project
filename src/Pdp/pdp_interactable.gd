@tool
class_name PdpInteractable
extends Node3D

## Lightweight interaction proxy built at runtime by [Pdp]. It carries an
## [Area3D] collider over one interactive feature of the panel (a breaker
## toggle or the power-monitoring module). The pilot character's interaction
## raycast resolves to that area and calls [method use] on its parent (this
## node), which forwards to the [member on_use] callable supplied by the panel.

## Invoked when the pilot uses this proxy. Bound by [Pdp] to the matching
## action, e.g. [code]toggle_breaker.bind(index)[/code] or [code]use_pmm[/code].
var on_use: Callable


func use() -> void:
	if on_use.is_valid():
		on_use.call()
