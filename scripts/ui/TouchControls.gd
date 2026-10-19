class_name TouchControls
extends CanvasLayer
## 触屏操控层：左下虚拟摇杆 + 右下 咬/跳/技能/饮水 按钮 + 左中「视角」按钮
## 信号桥接到玩家：move_input_changed / bite_pressed / jump_pressed / ability_pressed / drink_pressed / camera_pressed

signal move_input_changed(vec: Vector2)
signal bite_pressed
signal bite_hold_changed(holding: bool)   # 咬键长按电平(button_down/up 驱动),供玩家叼尸拖拽
signal jump_pressed
signal ability_pressed
signal drink_pressed(held: bool)
signal look_input_changed(delta: Vector2)
signal camera_pressed

const SFX_UI := preload("res://assets/audio/ui.wav")

@onready var joystick: VirtualJoystick = $Control/Joystick
@onready var bite_button: Button = $Control/BiteButton
@onready var jump_button: Button = $Control/JumpButton
@onready var ability_button: Button = $Control/AbilityButton
@onready var drink_button: Button = $Control/DrinkButton
@onready var camera_button: Button = $Control/CameraButton
@onready var look_zone: LookControl = $Control/LookZone
var sfx: AudioStreamPlayer


func _ready() -> void:
	sfx = AudioStreamPlayer.new()
	sfx.volume_db = -6.0
	add_child(sfx)
	joystick.input_changed.connect(_on_joystick_input)
	bite_button.pressed.connect(func(): _ui(); bite_pressed.emit())
	# 咬键补长按语义:与饮水键同款 button_down/up 电平驱动,供"按住叼尸拖拽"
	bite_button.button_down.connect(func(): _ui(); bite_hold_changed.emit(true))
	bite_button.button_up.connect(func(): bite_hold_changed.emit(false))
	# 长按电平反向接线:Main 编排器只桥接离散动作信号(bite_pressed 等),
	# 电平信号由控件侧直连玩家——玩家先于触屏层入树,此处必能找到;
	# 死亡重开时两者一同重建,连接随之刷新,不会残留旧引用
	var p := get_tree().get_first_node_in_group(Groups.PLAYER) as PlayerDino
	if p != null:
		bite_hold_changed.connect(p.set_bite_hold)
	jump_button.pressed.connect(func(): _ui(); jump_pressed.emit())
	ability_button.pressed.connect(func(): _ui(); ability_pressed.emit())
	drink_button.button_down.connect(func(): _ui(); drink_pressed.emit(true))
	drink_button.button_up.connect(func(): drink_pressed.emit(false))
	camera_button.pressed.connect(func(): _ui(); camera_pressed.emit())
	look_zone.look_input_changed.connect(func(d: Vector2): look_input_changed.emit(d))


func _ui() -> void:
	if sfx != null and is_instance_valid(sfx):
		sfx.stream = SFX_UI
		sfx.play()


func _on_joystick_input(vec: Vector2) -> void:
	move_input_changed.emit(vec)


## 仅拥有冲锋技能的物种显示技能按钮
func set_ability_visible(v: bool) -> void:
	ability_button.visible = v


## 显示冲锋冷却：冷却中显示剩余秒数并半透明，就绪恢复「技能」
func set_ability_cooldown(remaining: float, total: float) -> void:
	if not ability_button.visible:
		return
	if remaining > 0.05:
		ability_button.text = "%.1f" % remaining
		ability_button.modulate.a = 0.55
	else:
		ability_button.text = "技能"
		ability_button.modulate.a = 1.0
