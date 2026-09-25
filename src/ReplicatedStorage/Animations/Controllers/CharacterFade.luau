-- Fades a character in or out for this client only (LocalTransparencyModifier), frame by frame.
local RunService = game:GetService("RunService")

local CharacterFade = {}

function CharacterFade.run(character: Model, from: number, to: number, duration: number)
	local parts = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			table.insert(parts, descendant)
			descendant.LocalTransparencyModifier = from
		end
	end
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
		local value = from + (to - from) * alpha
		for _, part in parts do
			if part.Parent then
				part.LocalTransparencyModifier = value
			end
		end
		if alpha >= 1 or not character.Parent then
			connection:Disconnect()
		end
	end)
end

return CharacterFade
