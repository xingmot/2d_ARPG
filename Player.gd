extends CharacterBody2D

enum State {
	IDLE,
	RUNNING,
	JUMP,
	FALL,
	HIGH_FALL,
	LANDING
}
const GROUND_STATES      := [State.IDLE, State.RUNNING, State.LANDING]
const RUN_SPEED          := 160.0
const JUMP_VELOCITY      := -320.0
const LANDING_VELOCITY   := 420
const FLOOR_ACCELERATION := RUN_SPEED / 0.2
const AIR_ACCELERATION   := RUN_SPEED / 0.02
const LANDING_FRICTION   := -RUN_SPEED / 0.3
var default_gravity      := ProjectSettings.get("physics/2d/default_gravity") as float
var is_first_tick        := false

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var jump_request_timer: Timer = $JumpRequestTimer


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		jump_request_timer.start()
	if event.is_action_released("jump"):
		jump_request_timer.stop()
		if velocity.y < JUMP_VELOCITY / 2:
			velocity.y = JUMP_VELOCITY / 2


func move(acceleration: float, gravity: float, delta: float) -> void:
	# 看玩家输入左还是右
	var direction := Input.get_axis("move_left", "move_right")
	if acceleration < 0 and not is_zero_approx(velocity.x):
		var v = velocity.x + acceleration*delta if velocity.x>0 else velocity.x - acceleration*delta
		if v*velocity.x<0:
			v = 0
		velocity.x = v
	else:
		velocity.x = move_toward(velocity.x, direction * RUN_SPEED, acceleration * delta)
	velocity.y += gravity * delta

	if not is_zero_approx(direction):
		sprite_2d.flip_h = direction < 0
	move_and_slide()


func tick_physics(state: State, delta: float)->void:
	var acceleration := FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	match state:
		State.RUNNING, State.IDLE, State.JUMP:
			move(acceleration, default_gravity, delta)
		State.FALL,State.HIGH_FALL:
			move(acceleration, 0.0 if is_first_tick else default_gravity, delta)
		State.LANDING:
			move(LANDING_FRICTION,default_gravity, delta)

	is_first_tick = false


func get_next_state(state: State) -> State:
	var can_jump := is_on_floor() or coyote_timer.time_left > 0
	var should_jump := can_jump and jump_request_timer.time_left > 0
	if should_jump:
		return State.JUMP

	var direction := Input.get_axis("move_left", "move_right")
	var is_still := is_zero_approx(direction) and is_zero_approx(velocity.x)

	match state:
		State.IDLE:
			if not is_on_floor():
				return State.FALL
			if not is_still:
				return State.RUNNING
		State.RUNNING:
			if not is_on_floor():
				return State.FALL
			if is_still:
				return State.IDLE
		State.FALL:
			if is_on_floor():
				return State.RUNNING
			if velocity.y >= LANDING_VELOCITY:
				return State.HIGH_FALL
		State.HIGH_FALL:
			if is_on_floor():
				return State.LANDING
		State.JUMP:
			if velocity.y >= 0:
				return State.FALL
		State.LANDING:
			if not animation_player.is_playing():
				return State.IDLE

	return state


func transition_state(from: State, to: State) -> void:
	if not from in GROUND_STATES and to in GROUND_STATES:
		coyote_timer.stop()

	match to:
		State.RUNNING:
			animation_player.play("running")
		State.IDLE:
			animation_player.play("idle")
		State.HIGH_FALL:
			animation_player.play("fall")
			if from in GROUND_STATES:
				coyote_timer.start()
		State.FALL:
			animation_player.play("fall")
			if from in GROUND_STATES:
				coyote_timer.start()
		State.JUMP:
			animation_player.play("jump")
			velocity.y = JUMP_VELOCITY
			jump_request_timer.stop()
		State.LANDING:
			animation_player.play("landing")
	is_first_tick = true
