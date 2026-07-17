--[[
StateMachine.lua - Controller state machine.

The reactor controller operates in distinct states to make behavior predictable and tunable.

States:
- STABLE: Shield and field are healthy, output can increase
- RECOVERING: Field below target, attempting to recover it
- LIMITED: Output has hit an upper limit (saturation or request)
- SATURATED: Input is saturated; cannot achieve requested output
- EMERGENCY: Shutdown condition triggered (field too low, temp too high)
]]

local StateMachine = {}

local STATES = {
	STABLE = "STABLE",
	RECOVERING = "RECOVERING",
	LIMITED = "LIMITED",
	SATURATED = "SATURATED",
	EMERGENCY = "EMERGENCY",
}

--[[
Creates a new state machine.
]]
function StateMachine.new()
	local sm = {
		state = STATES.STABLE,
		stateTimer = 0,
		lastState = nil,
	}
	return sm
end

--[[
Transitions to a new state if conditions are met.

Only allows transition after stateChangeDelay updates in the new state,
to prevent rapid flickering.

delay: number of updates to wait before confirming the transition
]]
function StateMachine.tryTransition(sm, newState, delay)
	if newState == sm.state then
		sm.stateTimer = 0
		return false
	end

	sm.stateTimer = sm.stateTimer + 1
	if sm.stateTimer >= delay then
		sm.lastState = sm.state
		sm.state = newState
		sm.stateTimer = 0
		return true
	end

	return false
end

--[[
Forcefully transitions to a new state immediately.
Used for emergency shutdown and other urgent transitions.
]]
function StateMachine.forceTransition(sm, newState)
	sm.lastState = sm.state
	sm.state = newState
	sm.stateTimer = 0
end

--[[
Returns the current state.
]]
function StateMachine.getState(sm)
	return sm.state
end

--[[
Returns true if currently in the given state.
]]
function StateMachine.isState(sm, state)
	return sm.state == state
end

--[[
Returns the state enum for reference.
]]
function StateMachine.getStates()
	return STATES
end

return StateMachine

