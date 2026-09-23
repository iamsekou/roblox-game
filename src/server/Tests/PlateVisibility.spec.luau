-- Unit tests for Shared/Modules/PlateVisibility (range + facing rule for reading a number plate).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlateVisibility = require(ReplicatedStorage.Shared.Modules.PlateVisibility)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)
local T = require(script.Parent.TestUtil)

local RANGE = Constants.PLATE_VIEW_DISTANCE
local CONE = Constants.PLATE_VIEW_CONE_DEGREES

-- Target at the origin facing -Z (Roblox's default forward).
local TARGET = CFrame.new(0, 3, 0)

local function observerAt(distance: number, degreesOffFront: number): Vector3
	local r = math.rad(degreesOffFront)
	return Vector3.new(math.sin(r) * distance, 3, -math.cos(r) * distance)
end

local tests = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("[PLATE] readable straight in front, within range", function()
	T.eq(PlateVisibility.canRead(TARGET, observerAt(RANGE - 1, 0), RANGE, CONE), true)
end)

test("[PLATE] not readable beyond reading range, even straight in front", function()
	T.eq(PlateVisibility.canRead(TARGET, observerAt(RANGE + 0.5, 0), RANGE, CONE), false)
	T.eq(PlateVisibility.canRead(TARGET, observerAt(40, 0), RANGE, CONE), false)
end)

test("[PLATE] not readable from behind or from the side when they face away", function()
	T.eq(PlateVisibility.canRead(TARGET, observerAt(3, 180), RANGE, CONE), false, "directly behind")
	T.eq(PlateVisibility.canRead(TARGET, observerAt(3, 90), RANGE, CONE), false, "square to the side")
	T.eq(PlateVisibility.canRead(TARGET, observerAt(3, CONE + 5), RANGE, CONE), false, "just outside the cone")
end)

test("[PLATE] readable at an angle inside the facing cone", function()
	T.eq(PlateVisibility.canRead(TARGET, observerAt(3, CONE - 5), RANGE, CONE), true)
	T.eq(PlateVisibility.canRead(TARGET, observerAt(3, -(CONE - 5)), RANGE, CONE), true)
end)

test("[PLATE] turning around hides your number from someone in front of you", function()
	local observer = observerAt(3, 0)
	T.eq(PlateVisibility.canRead(TARGET, observer, RANGE, CONE), true)
	local turned = TARGET * CFrame.Angles(0, math.pi, 0)
	T.eq(PlateVisibility.canRead(turned, observer, RANGE, CONE), false)
end)

-- Blank plates: an opponent's plate is always visible nearby, the digits only when faced.
local RULES = {
	drawDistance = Constants.PLATE_BLANK_DRAW_DISTANCE,
	viewDistance = RANGE,
	coneDegrees = CONE,
	hideSlackDistance = Constants.PLATE_HIDE_SLACK_DISTANCE,
	hideSlackDegrees = Constants.PLATE_HIDE_SLACK_DEGREES,
}
local function mode(observer: Vector3, hasCode: boolean, wasRevealed: boolean?): string
	return PlateVisibility.plateMode(TARGET, observer, hasCode, wasRevealed == true, RULES)
end

test("[PLATE] a blank plate shows from behind and the side; the digits don't", function()
	T.eq(mode(observerAt(3, 180), true), "masked", "directly behind")
	T.eq(mode(observerAt(3, 90), true), "masked", "square to the side")
	T.eq(mode(observerAt(3, 0), true), "revealed", "faced, within range")
end)

test("[PLATE] a blank plate shows beyond reading range, up to the draw distance", function()
	T.eq(mode(observerAt(RANGE + 5, 0), true), "masked", "faced but too far to read")
	T.eq(mode(observerAt(Constants.PLATE_BLANK_DRAW_DISTANCE - 1, 180), true), "masked")
	T.eq(mode(observerAt(Constants.PLATE_BLANK_DRAW_DISTANCE + 1, 0), true), "hidden", "past the draw distance")
end)

test("[PLATE] without a disclosed code the plate stays masked even when faced", function()
	T.eq(mode(observerAt(3, 0), false), "masked")
end)

test("[PLATE] a revealed number holds just past the edge, then masks", function()
	local edge = observerAt(3, CONE + Constants.PLATE_HIDE_SLACK_DEGREES / 2)
	T.eq(mode(edge, true, false), "masked", "not yet revealed: the plain rule applies")
	T.eq(mode(edge, true, true), "revealed", "already revealed: no flicker at the edge")
	T.eq(mode(observerAt(3, CONE + Constants.PLATE_HIDE_SLACK_DEGREES + 5), true, true), "masked")
	T.eq(mode(observerAt(RANGE + Constants.PLATE_HIDE_SLACK_DISTANCE + 0.5, 0), true, true), "masked")
end)

return tests
