-- Numbers Assassin Universe: server entry point.
-- Each system is a ModuleScript in Systems/. Init() wires state and remotes without yielding;
-- Start() runs long-lived loops. Order matters: later systems depend on earlier ones.
local Systems = script:WaitForChild("Systems")

local ORDER = {
	"EconomyService",
	"MapService",
	"NumberAssignmentService",
	"MovementGuard",
	"PlayerLifeService",
	"RoundManager",
	"EliminationService",
	"ClashDuelService", -- clash duels; AbilityService starts them
	"AbilityService",
	"MeleeService", -- M1 punches; clashes go through AbilityService
	"ShopService",
	"LeaderboardService",
	"ProfileService",
	"RobuxService", -- after ProfileService: bundle receipts are saved through it
	"StressTestService", -- Studio only
}

-- Each system is isolated (audit fix, 2026-09-28): one that fails to load or to Init is reported and skipped,
-- and the rest still start (before, the first error stopped every later system, RobuxService's receipts last).
-- A Start loop that dies is reported too.
local loaded = {}
for _, name in ORDER do
	local ok, system = pcall(require, Systems:WaitForChild(name))
	if ok then
		loaded[name] = system
	else
		warn(string.format("[NAU] %s failed to load: %s", name, tostring(system)))
	end
end
for _, name in ORDER do
	local system = loaded[name]
	if system and system.Init then
		local ok, err = pcall(system.Init)
		if not ok then
			warn(string.format("[NAU] %s.Init failed: %s", name, tostring(err)))
		end
	end
end
for _, name in ORDER do
	local system = loaded[name]
	if system and system.Start then
		task.spawn(function()
			local ok, err = pcall(system.Start)
			if not ok then
				warn(string.format("[NAU] %s stopped: %s", name, tostring(err)))
			end
		end)
	end
end

print("[NAU] Server started")
