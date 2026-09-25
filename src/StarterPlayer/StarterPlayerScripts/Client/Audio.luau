-- Every sound the client plays goes through here (Phase 4): two sound groups the settings menu controls
-- (Music, Effects), one table of sound ids, one-shot effects and looping music.
-- Ids are real published sounds only ("rbxassetid://..."); a blank id is silent. Never invent ids.
local SoundService = game:GetService("SoundService")

local Audio = {}

local WORLD_SOUND_RANGE = 120 -- studs: a sound in the world (e.g. an ability cast) fades out by this distance

-- Phase 4 picks (owner-approved: Creator Store audio chosen by Claude for the owner to review). Only licensed
-- library audio Roblox publishes for every experience: APM Music ("APMOfficial"), Pro Sound Effects
-- ("ProSoundEffects") and DistroKid's official catalogue ("DistrokidOfficial"). All verified to load here.
-- The alternatives found are listed in HANDOFF.md.

-- name -> { id, volume (0-1, before the group's volume) }
Audio.SOUNDS = {
	-- Fights
	round_start = { id = "rbxassetid://9125585534", volume = 0.5 }, -- Gong, Chinese style single hit (PSE)
	elimination = { id = "rbxassetid://9119072660", volume = 0.7 }, -- you took someone out: metal clang (PSE)
	eliminated = { id = "rbxassetid://9114630843", volume = 0.6 }, -- you were taken out: gong crash (PSE)
	wrong_code = { id = "rbxassetid://9125540218", volume = 0.6 }, -- falling electronic beeps (PSE)
	time_left = { id = "rbxassetid://9042536620", volume = 0.6 }, -- 30 seconds left: "Feud Warrior - Hit" (APM)
	sudden_death = { id = "rbxassetid://9114631461", volume = 0.6 }, -- gong whoosh (PSE)
	round_won = { id = "rbxassetid://9042539915", volume = 0.6 }, -- "There's No Stopping Us - Hit" (APM)
	ability_cast = { id = "rbxassetid://9114159659", volume = 0.45 }, -- doppler whoosh, at the caster (PSE)
	income = { id = "rbxassetid://9113381319", volume = 0.4 }, -- passive yen: beads, like coins (PSE)
	-- Shop (owner-approved slots)
	shop_boot = { id = "rbxassetid://9120984896", volume = 0.6 }, -- the menu powers up: glassy zap (PSE)
	shop_select = { id = "rbxassetid://9118383130", volume = 0.5 }, -- a roster card is picked: servo (PSE)
	shop_charge = { id = "rbxassetid://9118883081", volume = 0.5 }, -- hold-to-buy charging: searing burst (PSE)
	shop_purchase = { id = "rbxassetid://9042539915", volume = 0.6 }, -- the "UNLOCKED" burst (APM)
	shop_equip = { id = "rbxassetid://9119072660", volume = 0.6 }, -- metal clang (PSE)
	shop_denied = { id = "rbxassetid://9125540218", volume = 0.6 }, -- not enough yen: falling beeps (PSE)
} :: { [string]: { id: string, volume: number } }

-- name -> looping track
Audio.MUSIC = {
	lobby = { id = "rbxassetid://1840540809", volume = 0.35 }, -- "Sunset Song" (APM), 3:21
	arena = { id = "rbxassetid://81035874477631", volume = 0.35 }, -- "Thunder over Kyoto" (DistroKid), 3:13
} :: { [string]: { id: string, volume: number } }

local groups: { [string]: SoundGroup } = {}

local function group(name: string): SoundGroup
	local existing = groups[name]
	if existing and existing.Parent then
		return existing
	end
	local g = SoundService:FindFirstChild("NAU_" .. name)
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = "NAU_" .. name
		g.Parent = SoundService
	end
	groups[name] = g :: SoundGroup
	return g :: SoundGroup
end

-- volume: 0-100 (the settings menu's slider value).
function Audio.setVolume(groupName: "Music" | "Effects", volume: number)
	group(groupName).Volume = math.clamp(volume, 0, 100) / 100
end

-- A one-shot effect. `parent` puts it in the world (3D sound); nil plays it flat for this player.
function Audio.play(name: string, parent: Instance?)
	local def = Audio.SOUNDS[name]
	if not def or def.id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = def.id
	s.Volume = def.volume
	s.SoundGroup = group("Effects")
	s.Parent = parent or SoundService
	s.Ended:Connect(function()
		s:Destroy()
	end)
	if parent then
		s.RollOffMaxDistance = WORLD_SOUND_RANGE
		s:Play()
	else
		SoundService:PlayLocalSound(s)
		task.delay(10, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end
end

local current: Sound? = nil
local currentName: string? = nil

-- Switches the looping music (nil = silence). The same track keeps playing uninterrupted.
function Audio.music(name: string?)
	if name == currentName then
		return
	end
	currentName = name
	if current then
		current:Destroy()
		current = nil
	end
	local def = name and Audio.MUSIC[name]
	if not def or def.id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "NAU_MusicTrack" -- not "NAU_Music": that's the Music sound group's name
	s.SoundId = def.id
	s.Volume = def.volume
	s.Looped = true
	s.SoundGroup = group("Music")
	s.Parent = SoundService
	s:Play()
	current = s
end

function Audio.Start()
	group("Music")
	group("Effects")
end

return Audio
