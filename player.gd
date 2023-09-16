extends CharacterBody2D

enum State {
	IDLE,
	RUNNING,
	JUMP,
	FALL,
	HIGH_FALL,
	LANDING,
	WALL_SLIDING,
	WALL_JUMP,
	LOOK_UP,
	LOOK_UP_LEFT,
	LOOK_UP_RIGHT,
	LOOK_DOWN,
	LOOK_DOWN_LEFT,
	LOOK_DOWN_RIGHT,
	ATTACK_1,
	ATTACK_2,
	ATTACK_3,
}
const GROUND_STATES      := [State.IDLE, State.RUNNING, State.LANDING,
							State.LOOK_UP, State.LOOK_UP_LEFT, State.LOOK_UP_RIGHT,
							State.LOOK_DOWN, State.LOOK_DOWN_LEFT, State.LOOK_DOWN_RIGHT,
							State.ATTACK_1, State.ATTACK_2, State.ATTACK_3]
const LOOK_UP_STATES     := [State.LOOK_UP, State.LOOK_UP_LEFT, State.LOOK_UP_RIGHT]
const LOOK_DOWN_STATES   := [State.LOOK_DOWN, State.LOOK_DOWN_LEFT, State.LOOK_DOWN_RIGHT]
const RUN_SPEED          := 160.0
const JUMP_VELOCITY      := -320.0
const WALL_JUMP_VELOCITY := Vector2(300, -320)
const LANDING_VELOCITY   := 420
const FLOOR_ACCELERATION := RUN_SPEED / 0.2
const AIR_ACCELERATION   := RUN_SPEED / 0.1
const LANDING_FRICTION   := -RUN_SPEED / 0.3
const LOOK_HRANGE        := 200.0
const LOOK_UP_RANGE      := 90.0
const LOOK_DOWN_RANGE    := 160.0
@export var can_combo   := false

var default_gravity     := ProjectSettings.get("physics/2d/default_gravity") as float
var is_first_tick       := false
var is_combo_request    := false
var old_camara_position := Vector2(0.0, 0.0)
var jump_released       := false

@onready var camera_2d: Camera2D = $Camera2D
@onready var graphics: Node2D = $Graphics
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var jump_request_timer: Timer = $JumpRequestTimer
@onready var foot_checker: RayCast2D = $Graphics/FootChecker
@onready var wall_sliding_foot_checker = $Graphics/WallSlidingFootChecker
@onready var hand_checker: RayCast2D = $Graphics/HandChecker
@onready var state_machine = $StateMachine


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		jump_request_timer.start()
	if event.is_action_released("jump"):
		jump_request_timer.stop()
		jump_released = true

	if event.is_action_pressed("attack") and can_combo:
		is_combo_request = true


func stand(gravity: float, delta: float)->void:
	var acceleration := FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.y += gravity * delta
	move_and_slide()


func look(gravity: float, delta: float) -> void:
	# 看玩家输入左还是右
	var direction := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(direction):
		graphics.scale.x = -1 if direction < 0 else 1
	move_and_slide()


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
		graphics.scale.x = -1 if direction < 0 else 1
	move_and_slide()


func tick_physics(state: State, delta: float)->void:
	var acceleration := FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	match state:
		State.RUNNING, State.IDLE, State.FALL, State.HIGH_FALL:
			move(acceleration, default_gravity, delta)
		State.JUMP:
			if jump_released and velocity.y<JUMP_VELOCITY /2:
				velocity.y = JUMP_VELOCITY/2
				jump_released=false
			move(acceleration, 0.0 if is_first_tick else default_gravity, delta)
		State.WALL_JUMP:
			if jump_released and velocity.y<WALL_JUMP_VELOCITY.y /2:
				velocity.y = WALL_JUMP_VELOCITY.y/2
				velocity.x = WALL_JUMP_VELOCITY.x/2
				jump_released=false
			if state_machine.state_time < 0.1:
				stand(0.0 if is_first_tick else default_gravity, delta)
				graphics.scale.x = get_wall_normal().x
			else:
				move(acceleration, 0.0 if is_first_tick else default_gravity, delta)
		State.LANDING:
			move(LANDING_FRICTION, default_gravity, delta)
		State.WALL_SLIDING:
			move(acceleration, default_gravity*0.3, delta)
			graphics.scale.x = get_wall_normal().x
		State.LOOK_UP, State.LOOK_UP_LEFT, State.LOOK_UP_RIGHT:
			look(default_gravity, delta)
		State.LOOK_DOWN, State.LOOK_DOWN_LEFT, State.LOOK_DOWN_RIGHT:
			look(default_gravity, delta)

	is_first_tick = false


func get_next_state(state: State) -> State:
	var can_jump := is_on_floor() or coyote_timer.time_left > 0
	var should_jump := can_jump and jump_request_timer.time_left > 0
	var direction := Input.get_axis("move_left", "move_right")
	var v_look_direction := Input.get_axis("look_up", "look_down")
	
	if should_jump:
		return State.JUMP

	var is_still := is_zero_approx(direction) and is_zero_approx(velocity.x)

	if state in GROUND_STATES and not is_on_floor():
		return State.FALL

	match state:
		State.IDLE:
			if Input.is_action_just_pressed("attack"):
				return State.ATTACK_1
			if is_zero_approx(velocity.x) and v_look_direction<0:
				return State.LOOK_UP
			if is_zero_approx(velocity.x) and v_look_direction>0:
				return State.LOOK_DOWN
			if not is_still:
				return State.RUNNING
		State.RUNNING:
			if is_still:
				return State.IDLE
		State.FALL:
			if is_on_floor():
				return State.RUNNING
			if is_on_wall() and hand_checker.is_colliding() and foot_checker.is_colliding():
				return State.WALL_SLIDING
			elif velocity.y >= LANDING_VELOCITY:
				return State.HIGH_FALL
		State.HIGH_FALL:
			if is_on_floor():
				return State.LANDING
			if is_on_wall() and hand_checker.is_colliding() and foot_checker.is_colliding():
				return State.WALL_SLIDING
		State.JUMP:
			if velocity.y >= 0:
				jump_released = false
				return State.FALL
		State.LANDING:
			if not animation_player.is_playing():
				return State.IDLE
		State.WALL_SLIDING:
			if jump_request_timer.time_left>0:
				return State.WALL_JUMP
			if is_on_floor():
				return State.IDLE
			if not is_on_wall() or not wall_sliding_foot_checker.is_colliding() and not foot_checker.is_colliding():
				return State.FALL
		State.WALL_JUMP:
			if velocity.y >= 0:
				return State.FALL
		State.LOOK_UP, State.LOOK_UP_LEFT, State.LOOK_UP_RIGHT:
			if v_look_direction==0:
				return State.IDLE
			if direction > 0:
				return State.LOOK_UP_RIGHT
			elif direction < 0:
				return State.LOOK_UP_LEFT
		State.LOOK_DOWN, State.LOOK_DOWN_LEFT, State.LOOK_DOWN_RIGHT:
			if v_look_direction==0:
				return State.IDLE
			if direction > 0:
				return State.LOOK_DOWN_RIGHT
			elif direction < 0:
				return State.LOOK_DOWN_LEFT
		State.ATTACK_1:
			if not animation_player.is_playing():
					return State.ATTACK_2 if is_combo_request else State.IDLE
		State.ATTACK_2:
			if not animation_player.is_playing():
				return State.ATTACK_3 if is_combo_request else State.IDLE
		State.ATTACK_3:
			return State.IDLE


	return state


func transition_state(from: State, to: State) -> void:
	print("[%s] %s => %s"% [
		Engine.get_physics_frames(),
		State.keys()[from] if from != -1 else "<START>",
		State.keys()[to]
	])
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
			coyote_timer.stop()
			jump_request_timer.stop()
		State.LANDING:
			animation_player.play("landing")
		State.WALL_SLIDING:
			animation_player.play("wall_sliding")
		State.WALL_JUMP:
			animation_player.play("jump")
			velocity = WALL_JUMP_VELOCITY
			velocity.x *= get_wall_normal().x
			jump_request_timer.stop()
		State.LOOK_UP:
			animation_player.play("idle")
			old_camara_position = camera_2d.position
			camera_2d.position.y -= LOOK_UP_RANGE
		State.LOOK_UP_LEFT, State.LOOK_DOWN_LEFT:
			animation_player.play("idle")
			camera_2d.position.x -= LOOK_HRANGE
			if from == State.LOOK_DOWN_RIGHT or from == State.LOOK_UP_RIGHT:
				camera_2d.position.x -= LOOK_HRANGE
		State.LOOK_UP_RIGHT, State.LOOK_DOWN_RIGHT:
			animation_player.play("idle")
			camera_2d.position.x += LOOK_HRANGE
			if from == State.LOOK_DOWN_LEFT or from == State.LOOK_UP_LEFT:
				camera_2d.position.x += LOOK_HRANGE
		State.LOOK_DOWN:
			animation_player.play("idle")
			old_camara_position = camera_2d.position
			camera_2d.position.y += LOOK_DOWN_RANGE
	if to == State.WALL_JUMP:
		Engine.time_scale = 0.8
	if from == State.WALL_JUMP:
		Engine.time_scale = 1.0
	if ((from in LOOK_UP_STATES and not to in LOOK_UP_STATES)
	or (from in LOOK_DOWN_STATES and not to in LOOK_DOWN_STATES)):
		camera_2d.position = old_camara_position

	if from == State.FALL and to == State.WALL_SLIDING:
		velocity.y *= 0.3
	if not to == State.FALL and not to == State.HIGH_FALL:
		jump_released=false
	is_first_tick = true
