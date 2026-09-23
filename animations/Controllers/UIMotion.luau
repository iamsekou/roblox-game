-- Small reusable UI motions. Back/Quad easing reads as snappy interface feedback, not physical objects.
local TweenService = game:GetService("TweenService")

local UIMotion = {}

local function scaleOf(gui: GuiObject): UIScale
	local scale = gui:FindFirstChild("NAU_Scale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "NAU_Scale"
		scale.Parent = gui
	end
	return scale :: UIScale
end

-- "Pop in": used when a plate, panel, card or banner appears.
function UIMotion.pop(gui: GuiObject)
	local scale = scaleOf(gui)
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Horizontal "no" shake for rejected input. Debounced so overlapping shakes can't drift the element.
-- The target must not be positioned by a UIListLayout (shake an inner frame instead).
local shaking: { [GuiObject]: boolean } = {}
function UIMotion.shake(gui: GuiObject)
	if shaking[gui] then
		return
	end
	shaking[gui] = true
	local origin = gui.Position
	task.spawn(function()
		for _, dx in { -10, 9, -7, 5, -3, 0 } do
			gui.Position = origin + UDim2.fromOffset(dx, 0)
			task.wait(0.035)
		end
		gui.Position = origin
		shaking[gui] = nil
	end)
end

-- Endless "heartbeat" swell for a call-to-action. Returns a stop function.
function UIMotion.pulse(gui: GuiObject, amount: number?, period: number?): () -> ()
	local scale = scaleOf(gui)
	scale.Scale = 1
	local info = TweenInfo.new((period or 0.9) / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(scale, info, { Scale = 1 + (amount or 0.05) })
	tween:Play()
	return function()
		tween:Cancel()
		scale.Scale = 1
	end
end

-- A quick hit: squash in, overshoot back. For button presses.
function UIMotion.punch(gui: GuiObject)
	local scale = scaleOf(gui)
	scale.Scale = 0.88
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- A light streak that sweeps across `shine` (a thin frame inside a ClipsDescendants parent) every `period`.
-- Returns a stop function.
function UIMotion.sweep(shine: GuiObject, period: number?): () -> ()
	local running = true
	task.spawn(function()
		while running and shine.Parent do
			shine.Position = UDim2.fromScale(-0.3, 0.5)
			local tween = TweenService:Create(shine, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				Position = UDim2.fromScale(1.3, 0.5),
			})
			tween:Play()
			task.wait(period or 2.4)
		end
	end)
	return function()
		running = false
	end
end

-- Background flash that eases back to the element's resting colour.
function UIMotion.flash(gui: GuiObject, color: Color3)
	local base = gui:GetAttribute("NAU_BaseColor")
	if typeof(base) ~= "Color3" then
		base = gui.BackgroundColor3
		gui:SetAttribute("NAU_BaseColor", base)
	end
	gui.BackgroundColor3 = color
	TweenService:Create(gui, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = base,
	}):Play()
end

return UIMotion
