-- Edit-mode preview of the graybox builders. Paste this into Studio's command bar (View > Command Bar):
--   require(game.ServerStorage.Assets.Init.BuildPreview)()
-- Pressing Play builds these automatically; delete Workspace.NAU_Preview before publishing.
return function()
	local Builders = game:GetService("ServerStorage").Assets.Builders
	local preview = workspace:FindFirstChild("NAU_Preview") or Instance.new("Folder")
	preview.Name = "NAU_Preview"
	preview:ClearAllChildren()
	preview.Parent = workspace
	require(Builders.Lobby).build(preview):PivotTo(CFrame.new(0, 0, 3000))
	require(Builders.ProvingGrounds).build(preview):PivotTo(CFrame.new(0, 0, 4400))
	return preview
end
