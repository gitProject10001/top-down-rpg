class_name ToolBelt
extends Node3D

signal changed

func active_tool() -> Node:
	return null

func carried() -> Array:
	return []

func use() -> void:
	changed.emit()

func next() -> void:
	changed.emit()
