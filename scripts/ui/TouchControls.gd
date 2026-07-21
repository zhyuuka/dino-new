class_name TouchControls
extends CanvasLayer
## 触屏操控层：左下虚拟摇杆 + 右下 咬/跳/技能/饮水 按钮
## 信号桥接到玩家：move_input_changed / bite_pressed / jump_pressed / ability_pressed / drink_pressed

signal move_input_changed(vec: Vector2)
signal bite_pressed
signal jump_pressed
signal ability_pressed
signal drink_pressed(held: bool)
signal look_input_changed(delta: Vector2)

const SFX_UI := preload("res://assets/audio/ui.wav")

@onready var joystick: VirtualJoystick = $Control/Joystick
@onready var bite_button: Button = $Control/BiteButton
@onready var jump_button: Button = $Control/JumpButton
@onready var ability_button: Button = $Control/AbilityButton
@onready var drink_button: Button = $Control/DrinkButton
@onready var look_zone: LookControl = $Control/LookZone
var sfx: AudioStreamPlayer


func _ready() -> void:
	sfx = AudioStreamPlayer.new()
	sfx.volume_db = -6.0
	add_child(sfx)
	joystick.input_changed.connect(_on_joystick_input)
	bite_button.pressed.connect(func(): _ui(); bite_pressed.emit())
	jump_button.pressed.connect(func(): _ui(); jump_pressed.emit())
	ability_button.pressed.connect(func(): _ui(); ability_pressed.emit())
	drink_button.button_down.connect(func(): _ui(); drink_pressed.emit(true))
	drink_button.button_up.connect(func(): drink_pressed.emit(false))
	look_zone.look_input_changed.connect(func(d: Vector2): look_input_changed.emit(d))


func _ui() -> void:
	if sfx != null and is_instance_valid(sfx):
		sfx.stream = SFX_UI
		sfx.play()


func _on_joystick_input(vec: Vector2) -> void:
	move_input_changed.emit(vec)
