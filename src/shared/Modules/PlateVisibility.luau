-- Who can read whose number plate (owner rule): the observer must be within range AND in front of
-- the target, i.e. the target is facing them. Pure geometry, shared by the server (which only
-- discloses a code while this holds) and the client (which draws the plate while it holds).
local PlateVisibility = {}

-- targetCFrame: the target's root CFrame (its LookVector is where the target faces).
-- observerPosition: where the observer is.
function PlateVisibility.canRead(targetCFrame: CFrame, observerPosition: Vector3, maxDistance: number, coneDegrees: number): boolean
	local offset = observerPosition - targetCFrame.Position
	if offset.Magnitude > maxDistance then
		return false
	end
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local look = targetCFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatOffset.Magnitude < 0.5 or flatLook.Magnitude < 1e-3 then
		return true -- practically on top of each other
	end
	return flatLook.Unit:Dot(flatOffset.Unit) >= math.cos(math.rad(coneDegrees))
end

-- Approved reading exceptions (Krillin's Tracking Disc, Sasuke's Hunter's Eye, Gojo's Boundless): a grant
-- lets one observer read plates beyond the normal rule, from any angle, up to `range`, until `untilTime`.
-- `targets` limits it to some fighters; nil means every opponent. Line of sight is still required and is
-- checked by the caller (grants never show numbers through walls).
export type Grant = { targets: { [number]: boolean }?, range: number, untilTime: number }

function PlateVisibility.grantAllows(grant: Grant, targetId: number, distance: number, now: number): boolean
	if now >= grant.untilTime or distance > grant.range then
		return false
	end
	return grant.targets == nil or grant.targets[targetId] == true
end

export type PlateMode = "hidden" | "masked" | "revealed"
export type PlateRules = {
	drawDistance: number, -- a blank plate is drawn this close
	viewDistance: number, -- the digits need this close...
	coneDegrees: number, -- ...and the target facing you within this cone
	hideSlackDistance: number, -- once revealed, the digits stay up this far past the rule (no flicker)
	hideSlackDegrees: number,
}

-- What a client draws over one opponent (owner rule, 2026-09-23): a blank plate whenever they're near,
-- the digits only while the reading rule holds AND this client actually holds their code.
function PlateVisibility.plateMode(
	targetCFrame: CFrame,
	observerPosition: Vector3,
	hasCode: boolean,
	wasRevealed: boolean,
	rules: PlateRules
): PlateMode
	if (targetCFrame.Position - observerPosition).Magnitude > rules.drawDistance then
		return "hidden"
	end
	if not hasCode then
		return "masked"
	end
	local distance = rules.viewDistance + (if wasRevealed then rules.hideSlackDistance else 0)
	local cone = rules.coneDegrees + (if wasRevealed then rules.hideSlackDegrees else 0)
	return if PlateVisibility.canRead(targetCFrame, observerPosition, distance, cone) then "revealed" else "masked"
end

return PlateVisibility
