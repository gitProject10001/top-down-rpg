@tool
extends Resource
## All 24 game hours advance uniformly. Sun's summer arc lasts 16 hours.
@export_range(1, 180, 1) var real_minutes := 30.0
@export_range(0, 24, .05) var initial_hour := 10.0
@export var sunrise := 5.0
@export var sunset := 21.0
@export var day_sun := Color(1.0, .94, .79)
@export var dusk_sun := Color(1.0, .48, .23)
@export var night_ambient := Color(.24, .34, .55)
@export var day_ambient := Color(.53, .72, .77)
@export_range(0, 2, .01) var night_energy := .22
@export_range(0, 2, .01) var day_energy := .40
@export var sun_energy := 1.2
@export var moon_energy := .24
