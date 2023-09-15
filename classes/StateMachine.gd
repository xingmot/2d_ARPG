class_name StateMachine
extends Node

# 要求owner实现3个方法，
# transition_state：表示初次进入状态
# get_next_state：获取当前状态下的下一个状态，里面写各种逻辑
# tick_physics：每一帧做的事情


var current_state: int = -1:
	set(v):
		owner.transition_state(current_state, v)
		current_state = v


func _ready() -> void:
	await owner.ready
	current_state = 0


func _physics_process( delta: float, ) -> void:
	while true:
		var next := owner.get_next_state(current_state) as int
		if current_state == next:
			break
		current_state = next

	owner.tick_physics(current_state,delta)
