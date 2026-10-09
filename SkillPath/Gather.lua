-- SkillPath gathering professions: which zone to gather in at which skill (Herbalism,
-- Mining, Skinning) and where to fish. Pure logic; zone names are read from the world map.

SkillPath = SkillPath or {}
local G = {}
SkillPath.Gather = G

local Data = SkillPathGather
G.HERBALISM, G.MINING, G.SKINNING, G.FISHING = 182, 186, 393, 356
G.LINES = {[182] = true, [186] = true, [393] = true, [356] = true}

-- Keep the current zone unless another one is clearly better
local SWITCH_MARGIN = 1.3
-- Zones far above the character's level or of the other faction are only used when
-- nothing else gives points
local LEVEL_MARGIN = 4
local DANGER_FACTOR = 0.1
local ENEMY_FACTOR = 0.2
local SKIN_WEIGHT = 0.5 -- beasts have to be killed first

function G.IsGather(line)
	return G.LINES[line] ~= nil
end

-- Gathering skill-ups: orange from the requirement, yellow from +25, green from +50,
-- grey from +100; chance falls linearly from yellow to grey.
function G.Chance(req, s)
	if s < req then
		return 0
	end
	local yellow, grey = req + 25, req + 100
	if s >= grey then
		return 0
	elseif s < yellow then
		return 1
	end
	return (grey - s) / (grey - yellow)
end

function G.Color(req, s)
	if s < req + 25 then
		return "orange"
	elseif s < req + 50 then
		return "yellow"
	elseif s < req + 100 then
		return "green"
	end
	return "grey"
end

-- Skinning skill needed for a creature level
function G.SkinReq(level)
	if level <= 10 then
		return 1
	elseif level <= 20 then
		return (level - 10) * 10
	end
	return level * 5
end

-- Fishing: catches needed for one skill point (1 below 75, then one more per 25 skill)
function G.FishCatches(s)
	if s < 75 then
		return 1
	end
	return math.ceil((s - 75) / 25)
end

local function ZoneFactor(area, opts)
	local zone = Data.zones[area]
	if not zone then
		return 0
	end
	local factor = 1
	local level, faction = zone[3], zone[4]
	if opts.level and level > opts.level + LEVEL_MARGIN then
		factor = factor * DANGER_FACTOR
	end
	if opts.faction and faction ~= 0 and faction ~= opts.faction then
		factor = factor * ENEMY_FACTOR
	end
	return factor
end

-- What a zone offers at skill s: weighted spawns giving points, and their list
-- {item = id, req = n, count = n} (skinning: {level = n, req = n, count = n})
local function ZoneValue(line, area, s)
	local value, list = 0, nil
	if line == G.SKINNING then
		local skins = Data.skins[area]
		if not skins then
			return 0
		end
		for i = 1, #skins, 2 do
			local level, count = skins[i], skins[i + 1]
			local p = G.Chance(G.SkinReq(level), s)
			value = value + p * count * SKIN_WEIGHT
		end
	else
		local nodes = Data.nodes[line] and Data.nodes[line][area]
		if not nodes then
			return 0
		end
		for i = 1, #nodes, 3 do
			value = value + G.Chance(nodes[i + 1], s) * nodes[i + 2]
		end
	end
	return value
end

-- Things in a zone that give points somewhere in [from, to)
function G.ZoneContents(line, area, from, to)
	local list = {}
	if line == G.SKINNING then
		local skins = Data.skins[area] or {}
		local minLevel, maxLevel, count = nil, nil, 0
		for i = 1, #skins, 2 do
			local level = skins[i]
			local req = G.SkinReq(level)
			if G.Chance(req, from) > 0 or G.Chance(req, to - 1) > 0 then
				minLevel = math.min(minLevel or level, level)
				maxLevel = math.max(maxLevel or level, level)
				count = count + skins[i + 1]
			end
		end
		if minLevel then
			list[1] = {minLevel = minLevel, maxLevel = maxLevel, count = count, req = G.SkinReq(minLevel)}
		end
		return list
	end
	local nodes = Data.nodes[line] and Data.nodes[line][area] or {}
	local merged = {}
	for i = 1, #nodes, 3 do
		local item, req, count = nodes[i], nodes[i + 1], nodes[i + 2]
		if G.Chance(req, from) > 0 or G.Chance(req, to - 1) > 0 then
			local m = merged[item]
			if m then
				m.count = m.count + count
				m.req = math.min(m.req, req)
			else
				m = {item = item, req = req, count = count}
				merged[item] = m
				list[#list + 1] = m
			end
		end
	end
	table.sort(list, function(a, b)
		return a.req < b.req
	end)
	return list
end

-- Average chance of a gather in the zone at skill s (weighted by spawns that give points)
local function AverageChance(line, area, s)
	local sum, count = 0, 0
	if line == G.SKINNING then
		local skins = Data.skins[area] or {}
		for i = 1, #skins, 2 do
			local p = G.Chance(G.SkinReq(skins[i]), s)
			if p > 0 then
				sum, count = sum + p * skins[i + 1], count + skins[i + 1]
			end
		end
	else
		local nodes = Data.nodes[line] and Data.nodes[line][area] or {}
		for i = 1, #nodes, 3 do
			local p = G.Chance(nodes[i + 1], s)
			if p > 0 then
				sum, count = sum + p * nodes[i + 2], count + nodes[i + 2]
			end
		end
	end
	return count > 0 and sum / count or 0
end

-- Route for Herbalism, Mining or Skinning. opts: level (character), faction (2/4).
-- Returns steps {area, from, to, gathers} and the end skill.
function G.Plan(line, from, to, opts)
	local areas = {}
	local source = line == G.SKINNING and Data.skins or (Data.nodes[line] or {})
	for area in pairs(source) do
		areas[#areas + 1] = area
	end
	table.sort(areas)
	local steps, step, current = {}, nil, nil
	local s = math.max(1, from)
	while s < to do
		local best, bestScore
		for _, area in ipairs(areas) do
			local score = ZoneValue(line, area, s) * ZoneFactor(area, opts)
			if score > 0 and (not bestScore or score > bestScore) then
				best, bestScore = area, score
			end
		end
		if not best then
			break
		end
		if current and current ~= best then
			local keep = ZoneValue(line, current, s) * ZoneFactor(current, opts)
			if keep > 0 and keep * SWITCH_MARGIN >= bestScore then
				best = current
			end
		end
		if best ~= current then
			step = {area = best, from = s, to = s + 1, gathers = 0}
			steps[#steps + 1] = step
			current = best
		end
		local p = AverageChance(line, best, s)
		step.gathers = step.gathers + (p > 0 and 1 / p or 0)
		s = s + 1
		step.to = s
	end
	for _, st in ipairs(steps) do
		st.gathers = math.ceil(st.gathers - 0.05)
	end
	return steps, s
end

-- Fishing: steps per rank band with zones where you can fish without losing catches.
-- Returns steps {from, to, catches, areas = {area, ...}}.
local FISH_BANDS = {1, 75, 150, 225, 300, 375, 450}

function G.PlanFishing(from, to, opts)
	local steps = {}
	for i = 1, #FISH_BANDS - 1 do
		local a, b = math.max(from, FISH_BANDS[i]), math.min(to, FISH_BANDS[i + 1])
		if a < b then
			local catches = 0
			for s = a, b - 1 do
				catches = catches + G.FishCatches(s)
			end
			-- zones whose minimum skill fits the start of the band, best match first
			local list = {}
			for area, min in pairs(Data.fishing) do
				if min <= a and ZoneFactor(area, opts) >= 1 then
					list[#list + 1] = area
				end
			end
			table.sort(list, function(x, y)
				local mx, my = Data.fishing[x], Data.fishing[y]
				if mx ~= my then
					return mx > my
				end
				local lx, ly = Data.zones[x][3], Data.zones[y][3]
				return math.abs(lx - (opts.level or lx)) < math.abs(ly - (opts.level or ly))
			end)
			while #list > 3 do
				table.remove(list)
			end
			steps[#steps + 1] = {from = a, to = b, catches = catches, areas = list}
		end
	end
	return steps, to
end

-- Items (or skinning level ranges) that give points at skill s anywhere, for the side list
function G.PointsNow(line, s)
	local seen, list = {}, {}
	if line == G.SKINNING then
		local minLevel, maxLevel
		for level = 1, 83 do
			if G.Chance(G.SkinReq(level), s) > 0 then
				minLevel = minLevel or level
				maxLevel = level
			end
		end
		if minLevel then
			list[1] = {minLevel = minLevel, maxLevel = maxLevel, req = G.SkinReq(minLevel)}
		end
		return list
	end
	for _, nodes in pairs(Data.nodes[line] or {}) do
		for i = 1, #nodes, 3 do
			local item, req = nodes[i], nodes[i + 1]
			if G.Chance(req, s) > 0 and not seen[item .. ":" .. req] then
				seen[item .. ":" .. req] = true
				list[#list + 1] = {item = item, req = req}
			end
		end
	end
	table.sort(list, function(a, b)
		return a.req > b.req
	end)
	return list
end

-- Zone names ----------------------------------------------------------------------------
-- Read once from the world map in the client's language (map id -> name); until then or if
-- that is not possible, the German name (German client) or the internal map name.

local mapNames

local function ScanWorldMap()
	if mapNames or not (GetMapZones and SetMapZoom and GetCurrentMapAreaID) then
		return
	end
	if WorldMapFrame and WorldMapFrame:IsShown() then
		return -- do not move the map the player is looking at; try again later
	end
	local names = {}
	local ok = pcall(function()
		for continent = 1, 4 do
			local zones = {GetMapZones(continent)}
			for index = 1, #zones do
				SetMapZoom(continent, index)
				names[GetCurrentMapAreaID()] = zones[index]
			end
		end
	end)
	pcall(SetMapToCurrentZone)
	if ok then
		mapNames = names
	end
end

local function Prettify(key)
	return (key:gsub("(%l)(%u)", "%1 %2"))
end

function G.ZoneName(area)
	local zone = Data.zones[area]
	if not zone then
		return "?"
	end
	ScanWorldMap()
	local name = mapNames and mapNames[zone[1]]
	if name then
		return name
	end
	if GetLocale and GetLocale() == "deDE" and zone[5] ~= "" then
		return zone[5]
	end
	return Prettify(zone[6])
end

function G.ZoneLevel(area)
	local zone = Data.zones[area]
	return zone and zone[3] or 0
end
