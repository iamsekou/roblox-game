-- Numbers Assassin Universe: server entry point.
-- Each system is a ModuleScript in Systems/. Init() wires state and remotes without yielding;
-- Start() runs long-lived loops. Order matters: later systems depend on earlier ones.
local Systems = script:WaitForChild("Systems")

local ORDER = {
	"EconomyService",
	"MapService",
	"NumberAssignmentService",
	"PlayerLifeService",
	"RoundManager",
	"EliminationService",
	"AbilityService",
}

local loaded = {}
for _, name in ORDER do
	loaded[name] = require(Systems:WaitForChild(name))
end
for _, name in ORDER do
	if loaded[name].Init then
		loaded[name].Init()
	end
end
for _, name in ORDER do
	if loaded[name].Start then
		task.spawn(loaded[name].Start)
	end
end

print("[NAU] Server started")
