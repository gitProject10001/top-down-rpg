class_name ToolBelt
extends Node3D

signal changed

func use() -> void:
	changed.emit()

func next() -> void:
	changed.emit()
