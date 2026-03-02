class_name Movement extends CharacterBody2D

## 目标速度
var target_speedX: float = 5.0
## 加速度
var accelerationX: float = 10.0
## 减速度
var decelerationX: float = 10.0
## Y轴加速度（向量 / 有方向数）
var accelerationY: float = 20.0

## 最大速度 有符号向量
var max_velocityY: float = 400.0

## 当前速度 无符号标量
var speedX: float = 0.0
var directionX: int = 1
## 当前速度 有符号向量
var speedY: float = 0.0
var activity: bool = true
var is_grounded_before = true
var speed_scale = 1.0

signal touch_ground()

func _ready() -> void:
	velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
	if not activity:
		return
	delta = delta * speed_scale
	# handle speed x
	if speedX < target_speedX:
		speedX = move_toward(speedX, target_speedX, accelerationX * delta)
	elif speedX > target_speedX:
		speedX = move_toward(speedX, target_speedX, decelerationX * delta)
	# handle speed y
	speedY += accelerationY * delta
	if speedY < 0 and abs(speedY) > max_velocityY:
		speedY = move_toward(abs(speedY), max_velocityY, accelerationY * delta) * sign(speedY)
	# move
	velocity = Vector2(speedX * directionX, speedY)
	move_and_slide()
	if not is_grounded_before and is_on_floor():
		touch_ground.emit()
	is_grounded_before = is_on_floor()