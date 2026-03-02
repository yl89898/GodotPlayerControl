class_name Player extends Movement

# Player movement configuration parameters
# --------------------------------

@export_group("Movement")
@export var time_to_max_speed: float = 0.5
@export var max_move_speed: float = 300.0
@export var time_to_stop: float = 0.3
@export var move_dust_cd: float = 0.2
@export_group("Jump & Fail")
@export var jump_max_height: float = 150.0
@export var jump_to_max_time: float = 0.4
@export var fail_to_ground_time: float = 0.3
@export var jump_input_buffer_time: float = 0.2
@export var coyote_time: float = 0.15
@export var jump_release_modify_rate: float = 0.5
@export var jump_on_ceil_modify_speed: float = 0.5
@export var max_fail_speed: float = 800.0
@export_group("Dash")
@export var dash_distance: float = 64
@export var dash_duration: float = 0.2
@export var dash_slowdown_time: float = 0.1
@export var dash_cooldown: float = 1.0
@export var basic_dash_amount: int = 1
@export var dash_input_buffer_time: float = 0.15
@export var dash_end_speed_X_rate: float = 0.0
@export var dash_end_speed_Y: float = 0.0
@export var dash_cache_recover_duration: float = 0.1
@export_group("Wall Slide & Jump")
@export var wall_slide_speed: float = 100.0
@export var wall_jump_horizontal_speed: float = 250.0
@export var wall_jump_vertical_speed: float = 300.0
@export var wall_jump_time: float = 0.2
@export var wall_jump_coyote_time: float = 0.1
@export_group("Death")
@export var death_delay_time: float = 1.0
@export var death_move_distance: float = 5
@export var death_move_time: float = 0.15
@export_group("Render Colors")
@export var color_base: Color = Color(1, 1, 1)
@export var color_eye: Color = Color(1, 1, 1)
@export var color_border: Color = Color(1, 1, 1)
@export var color_body_1: Color = Color(1, 1, 1)
@export var color_body_2: Color = Color(1, 1, 1)

# Player state variables
# --------------------------------

var acceleration_move: float = 0.0
var deceleration_move: float = 0.0
var jump_speed: float = 0.0
var jump_buffer_ticks: int = 0
var jump_coyote_ticks: int = 0
var go_up_gravity: float = 1200.0
var go_down_gravity: float = 2000.0
var dash_timer_ticks: int = 0
var dash_cooldown_ticks: int = 0
var dash_amount: int = 0
var dash_buffer_ticks: int = 0
var dash_speed: float = 0.0
var dash_decelerationX: float = 0.0
var dash_decelerationY: float = 0.0
var wall_jump_timer: float = 0
var wall_jump_coyote_tick: int = 0
var wall_normal: Vector2 = Vector2.ZERO
var move_dust_timer: float = -1
var facing: int = 1
var health: int = 1
var is_dead: bool = false
var enable_input: bool = true
var dash_cache_recover_duration_timer: float = 0
var move_input_range = 0.1

signal on_player_dash()

## Node References
@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var head_cast: RayCast2D = $RayCast2D


func _ready() -> void:
	super._ready()
	## calculate derived movement parameters
	acceleration_move = max_move_speed / time_to_max_speed
	deceleration_move = max_move_speed / time_to_stop
	go_up_gravity = 2 * jump_max_height / pow(jump_to_max_time, 2)
	go_down_gravity = 2 * jump_max_height / pow(fail_to_ground_time, 2)
	jump_speed = jump_to_max_time * go_up_gravity
	dash_speed = dash_distance / (dash_duration + dash_slowdown_time * 0.5)
	dash_amount = basic_dash_amount
	head_cast.exclude_parent = true
	await get_tree().create_timer(0.6).timeout
	enable()

func _process(delta: float) -> void:
	if is_dead:
		return
	handle_input()
	process_movement(delta)
	handle_animations()

func enable() -> void:
	sprite.visible = true
	collision_shape.disabled = false
	is_dead = false
	enable_input = true
	facing = 1
	health = 1
	accelerationX = 0.0
	decelerationX = 0.0
	speedX = 0.0
	speedY = 0.0
	dash_amount = basic_dash_amount
	target_speedX = 0.0
	max_velocityY = 0
	speed_scale = 1.0

func disable() -> void:
	sprite.visible = false
	collision_shape.disabled = true


# Player Input
enum ButtonState {
	NONE,
	JUST_PRESSED,
	HOLDING,
	JUST_RELEASED
}

var move_input: Vector2 = Vector2.ZERO
var jump_input_state: ButtonState = ButtonState.NONE
var dash_input_state: ButtonState = ButtonState.NONE

func handle_input() -> void:
	if not enable_input:
		move_input = Vector2.ZERO
		jump_input_state = ButtonState.NONE
		dash_input_state = ButtonState.NONE
		return
	# movement input
	var h = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var v = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	if abs(h) < move_input_range:
		move_input.x = 0
	else:
		move_input.x = sign(h)
	if abs(v) < move_input_range:
		move_input.y = 0
	else:
		move_input.y = sign(v)
	
	# jump input
	if Input.is_action_just_pressed("jump"):
		jump_input_state = ButtonState.JUST_PRESSED
	elif Input.is_action_pressed("jump"):
		if jump_input_state == ButtonState.JUST_PRESSED:
			jump_input_state = ButtonState.HOLDING
	elif Input.is_action_just_released("jump"):
		jump_input_state = ButtonState.JUST_RELEASED
	else:
		jump_input_state = ButtonState.NONE
	# dash input
	if Input.is_action_just_pressed("dash"):
		dash_input_state = ButtonState.JUST_PRESSED
	elif Input.is_action_pressed("dash"):
		if dash_input_state == ButtonState.JUST_PRESSED:
			dash_input_state = ButtonState.HOLDING
	elif Input.is_action_just_released("dash"):
		dash_input_state = ButtonState.JUST_RELEASED
	else:
		dash_input_state = ButtonState.NONE

func process_movement(delta: float) -> void:
	var cur_ticks: int = Time.get_ticks_msec()
	process_verticle(cur_ticks)
	process_horizontal(cur_ticks)
	process_wall_action(cur_ticks, delta)
	process_dashing(cur_ticks, delta)

# base location

func process_verticle(cur_ticks: int) -> void:
	if is_dashing(cur_ticks):
		return
	if is_wall_jumping(cur_ticks):
		return
	# jump input buffering
	if jump_input_state == ButtonState.JUST_PRESSED:
		jump_buffer_ticks = cur_ticks + ceili(jump_input_buffer_time * 1000)
	# jump & fail
	if is_on_floor() and speedY > 0.0:
		accelerationY = 0
		speedY = 0
		jump_coyote_ticks = cur_ticks + ceili(coyote_time * 1000)
		dash_amount = basic_dash_amount
	elif speedY < 0.0:
		accelerationY = go_up_gravity
	else:
		accelerationY = go_down_gravity
	max_velocityY = max_fail_speed
	if jump_buffer_ticks > cur_ticks and jump_coyote_ticks > cur_ticks:
		speedY = - jump_speed
		jump_buffer_ticks = 0
		jump_coyote_ticks = 0
	if jump_input_state == ButtonState.JUST_RELEASED:
		if speedY < 0:
			speedY *= jump_release_modify_rate

func process_horizontal(cur_ticks: int) -> void:
	# horizontal movement
	if is_dashing(cur_ticks):
		return
	if is_wall_jumping(cur_ticks):
		return
	accelerationX = acceleration_move
	decelerationX = deceleration_move
	if move_input.x != 0:
		directionX = sign(move_input.x)
		target_speedX = max_move_speed
	else:
		directionX = 0
		target_speedX = 0.0
	# on ceil
	if is_on_ceiling() and speedY < -jump_on_ceil_modify_speed:
		var collision_info = get_last_slide_collision()
		var cell_normal = collision_info.get_normal()
		if cell_normal.y > 0.98:
			speedY = - jump_on_ceil_modify_speed

# ------

# wall jump & slide
func is_wall_jumping(_cur_ticks: int) -> bool:
	return wall_jump_timer > 0.0

func process_wall_action(cur_ticks: int, delta: float) -> void:
	# wall slide & jump
	if is_on_wall() and not is_on_floor():
		wall_normal = get_wall_normal()
		wall_jump_coyote_tick = cur_ticks + ceili(wall_jump_coyote_time * 1000)
		# wall slide
		if jump_buffer_ticks <= cur_ticks && wall_normal.x * move_input.x < 0 and speedY > 0.0:
			speedY = wall_slide_speed
			accelerationX = 0.0
			decelerationX = 0.0
			accelerationY = 0.0
	# wall jump
	if wall_jump_timer > 0.0:
		wall_jump_timer -= delta
		if wall_jump_timer <= 0.0:
			speedY = 0.0
	else:
		if wall_jump_coyote_tick > cur_ticks && jump_buffer_ticks > cur_ticks:
			speedX = wall_jump_horizontal_speed
			directionX = sign(wall_normal.x)
			speedY = - wall_jump_vertical_speed
			accelerationX = 0.0
			decelerationX = 0.0
			accelerationY = 0.0
			jump_buffer_ticks = 0
			wall_jump_timer = wall_jump_time
			wall_jump_coyote_tick = 0
# ------

# dashing
func is_dashing(cur_ticks: int) -> bool:
	return cur_ticks < dash_timer_ticks

func is_dashing_cooldown(cur_ticks: int) -> bool:
	return cur_ticks < dash_cooldown_ticks

func process_dashing(cur_ticks: int, delta: float) -> void:
	if dash_cache_recover_duration_timer > 0:
		dash_cache_recover_duration_timer -= delta
		if dash_cache_recover_duration_timer <= 0.0 && dash_amount > basic_dash_amount:
			dash_amount = basic_dash_amount
	if not is_dashing_cooldown(cur_ticks):
		if dash_input_state == ButtonState.JUST_PRESSED:
			dash_buffer_ticks = cur_ticks + ceili(dash_input_buffer_time * 1000)
	if is_dashing(cur_ticks):
		var last_dash_ticks: float = (dash_timer_ticks - cur_ticks) / 1000.0
		if last_dash_ticks < dash_slowdown_time:
			decelerationX = dash_decelerationX
			accelerationY = dash_decelerationY
	if dash_amount > 0 && dash_buffer_ticks > cur_ticks:
		dash_timer_ticks = cur_ticks + ceili((dash_duration + dash_slowdown_time + 0.08) * 1000)
		dash_cooldown_ticks = cur_ticks + ceili((dash_cooldown + 0.08) * 1000)
		dash_amount -= 1
		accelerationX = 0.0
		decelerationX = 0.0
		accelerationY = 0.0
		speedX = 0
		speedY = 0
		dash_buffer_ticks = 0
		await get_tree().create_timer(0.08).timeout
		var dash_dir = move_input
		var camera = get_tree().root.get_node("GameManager/Camera2D")
		if camera != null:
			camera.shake()
		if dash_dir.y > 0 && is_on_floor():
			dash_dir.y = 0
		if dash_dir.length_squared() == 0:
			dash_dir = Vector2(facing, 0)
		dash_dir = dash_dir.normalized()
		var dash_velocity = dash_dir * dash_speed
		if dash_velocity.x != 0:
			speedX = abs(dash_velocity.x)
			directionX = sign(dash_velocity.x)
		speedY = dash_velocity.y
		max_velocityY = dash_end_speed_Y * sign(speedY)
		target_speedX = max_move_speed * dash_end_speed_X_rate
		if sign(speedX) != 0:
			dash_decelerationX = (speedX - target_speedX) / dash_slowdown_time
		else:
			dash_decelerationX = 0.0
		if sign(speedY) != 0:
			dash_decelerationY = - (speedY - max_velocityY) / dash_slowdown_time
		else:
			dash_decelerationY = 0.0
		on_player_dash.emit(self)

func stop_dash() -> void:
	dash_timer_ticks = 0
	dash_cooldown_ticks = 0

func set_dash_amount(amount: int) -> void:
	dash_amount = amount
	dash_cache_recover_duration_timer = dash_cache_recover_duration
	dash_cooldown_ticks -= ceili(dash_cooldown * 500)

func reset_dash_amount() -> void:
	if dash_amount < basic_dash_amount:
		dash_amount = basic_dash_amount
# ------

# animation
func handle_animations() -> void:
	if directionX != 0:
		sprite.flip_h = directionX < 0
		facing = directionX
		head_cast.target_position = Vector2(facing * 8, 0)

	if is_on_wall() and not is_on_floor() and wall_normal.x * move_input.x < 0 and speedY > 0.0:
		# wall slide
		play_animation("wall")
		sprite.flip_h = directionX > 0
	elif not is_on_floor():
		if speedY < 0:
			# jump
			play_animation("jump")
		else:
			# fall
			play_animation("fall")
	else:
		if abs(speedX) > 0.1:
			# run
			play_animation("run")
		else:
			# idle
			play_animation("idle")

func play_animation(animation_name: String) -> void:
	if animation_player.current_animation == animation_name:
		return
	animation_player.play(animation_name)

# hurt
func get_hurt(hurt_normal: Vector2) -> void:
	# print(str(hurt_normal))
	if not enable_input:
		return
	if is_dead:
		return
	health -= 1
	if health < 1:
		#print("Player is dead")
		animation_player.play("hurt")
		activity = false
		is_dead = true
		var death_tween: Tween = create_tween()
		death_tween.tween_property(self, "global_position", global_position - death_move_distance * hurt_normal, death_move_time).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT).from_current()
		await death_tween.finished
		disable()
		await get_tree().create_timer(death_delay_time).timeout
		#level_fail()
	else:
		print("Player got hurt! Health remaining: ", health)


func set_speed(speed: float) -> void:
	speed_scale = speed