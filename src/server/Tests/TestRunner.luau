-- Runs the NAU unit tests. Press Play, switch the command bar to the Server, and run:
--   print(require(game.ServerScriptService.Server.Tests.TestRunner).run())
-- (Running from the Edit-mode command bar can use stale copies of edited modules, because Studio
-- caches modules required there.)
-- Tests tagged [ATn] map to the engineering acceptance scenarios in docs/DESIGN.md.
local TestRunner = {}

local SPECS = { "CodeBook.spec", "MatchCore.spec", "PlateVisibility.spec", "AbilityRules.spec", "AnimTimeline.spec", "ClashRules.spec", "Spring.spec", "ShopRules.spec", "Leaderboard.spec" }

function TestRunner.run(): string
	local lines = {}
	local passed, failed = 0, 0
	for _, specName in SPECS do
		local module = script.Parent:FindFirstChild(specName)
		local ok, cases = pcall(require, module)
		if not ok then
			failed += 1
			table.insert(lines, string.format("FAIL  %s failed to load: %s", specName, tostring(cases)))
			continue
		end
		for _, case in cases do
			local success, err = pcall(case.fn)
			if success then
				passed += 1
				table.insert(lines, "pass  " .. case.name)
			else
				failed += 1
				table.insert(lines, string.format("FAIL  %s\n        %s", case.name, tostring(err)))
			end
		end
	end
	table.insert(lines, 1, string.format("NAU unit tests: %d passed, %d failed", passed, failed))
	return table.concat(lines, "\n")
end

return TestRunner
