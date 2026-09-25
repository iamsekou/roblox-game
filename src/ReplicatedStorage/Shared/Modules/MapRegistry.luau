-- Data-driven map rotation. Each entry names a builder module in ServerStorage.Assets.Builders.
-- Adding a map = one builder that honours the map contract (docs/DESIGN.md) + one line here.
-- The round system never needs to change to add a map.

export type MapDef = {
	id: string,
	displayName: string,
	builder: string,
	enabled: boolean,
}

local maps: { MapDef } = {
	{ id = "ProvingGrounds", displayName = "The Proving Grounds", builder = "ProvingGrounds", enabled = true },
	-- Five more slots are planned for Phase 4. They join this list only once they're built and play-tested.
}

local MapRegistry = {}

function MapRegistry.enabled(): { MapDef }
	local result = {}
	for _, def in maps do
		if def.enabled then
			table.insert(result, def)
		end
	end
	return result
end

function MapRegistry.get(id: string): MapDef?
	for _, def in maps do
		if def.id == id then
			return def
		end
	end
	return nil
end

return MapRegistry
