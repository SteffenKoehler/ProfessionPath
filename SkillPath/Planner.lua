-- SkillPath route planner. Pure logic without WoW API calls, so it can be tested outside
-- the game: everything client-specific comes in through the options table.

SkillPath = SkillPath or {}
local Planner = {}
SkillPath.Planner = Planner

-- recipe fields (see Data.lua)
local SPELL, SOURCE, LEARN, YELLOW, GREY, COST, RACE, ABILITY, CREATED, AMOUNT, REAGENTS = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
Planner.SOURCE_AUTO, Planner.SOURCE_TRAINER, Planner.SOURCE_OTHER, Planner.SOURCE_VENDOR = 1, 2, 3, 4

-- Keep the current recipe while a new one is at most this much cheaper per skill point,
-- so the route does not jump between recipes for tiny gains.
local SWITCH_MARGIN = 1.15
-- Every craft also costs effort (crafting time, getting the materials), counted as this many
-- copper. At low skill, where materials cost next to nothing, this prefers recipes that need
-- few crafts over a cheap green recipe that needs hundreds; at high skill gold decides.
Planner.CRAFT_EFFORT = 300
-- Without auction data a material is estimated at this multiple of its vendor sell price
-- (auction prices are typically a few times the sell price).
Planner.ESTIMATE_FACTOR = 4
local UNKNOWN_PRICE = 100 -- 1 silver for items without any price information

-- Price estimate without auction data: vendor buy price for vendor reagents, otherwise a
-- multiple of the vendor sell price. data = SkillPathData.
function Planner.EstimatePrice(item, data)
	local buy = data.vendor[item]
	if buy then
		return buy
	end
	local sell = data.sellPrice and data.sellPrice[item]
	return sell and sell * Planner.ESTIMATE_FACTOR or UNKNOWN_PRICE
end

-- Chance for a skill point at skill s: orange 100 %, then linear down to 0 at grey.
function Planner.Chance(recipe, s)
	local yellow, grey = recipe[YELLOW], recipe[GREY]
	if s >= grey then
		return 0
	elseif s < yellow then
		return 1
	end
	return (grey - s) / (grey - yellow)
end

-- Difficulty color name at skill s ("orange", "yellow", "green", "grey").
function Planner.Color(recipe, s)
	local yellow, grey = recipe[YELLOW], recipe[GREY]
	if s >= grey then
		return "grey"
	elseif s < yellow then
		return "orange"
	elseif s < (yellow + grey) / 2 then
		return "yellow"
	end
	return "green"
end

-- Index: created item -> cheapest recipe of this profession that makes it (for intermediates
-- like bolts of cloth, the cost is that of their materials).
local function MakerIndex(recipes)
	local makers = {}
	for _, r in ipairs(recipes) do
		local item = r[CREATED]
		if item > 0 and r[SOURCE] ~= Planner.SOURCE_OTHER then
			local old = makers[item]
			if not old or r[LEARN] < old[LEARN] then
				makers[item] = r
			end
		end
	end
	return makers
end

-- Material cost of one craft in copper. opts.price(item) gives the price of a material;
-- intermediates of this profession (bolts of cloth, bars ...) cost the cheaper of their
-- price and their own materials.
local function CraftCost(recipe, opts, makers, cache, depth)
	local cached = cache[recipe]
	if cached then
		return cached
	end
	local cost = 0
	for i = REAGENTS, #recipe, 2 do
		local item, count = recipe[i], recipe[i + 1]
		local price = opts.price(item)
		local maker = makers[item]
		if maker and maker ~= recipe and depth < 3 then
			local own = CraftCost(maker, opts, makers, cache, depth + 1) / maker[AMOUNT]
			if own < price then
				price = own
			end
		end
		cost = cost + price * count
	end
	cache[recipe] = cost
	return cost
end

-- Can the player use this recipe at skill s?
local function Usable(recipe, s, opts)
	local spell = recipe[SPELL]
	if opts.cooldown and opts.cooldown[spell] then
		return false
	end
	if opts.known and opts.known[spell] then
		return true
	end
	local source = recipe[SOURCE]
	if source == Planner.SOURCE_AUTO then
		return true
	elseif source == Planner.SOURCE_VENDOR then
		return opts.vendorRecipes and recipe[LEARN] <= s
	elseif source == Planner.SOURCE_TRAINER then
		if recipe[LEARN] > s then
			return false
		end
		local race = recipe[RACE]
		if race ~= 0 and opts.raceBit and bit.band(race, opts.raceBit) == 0 then
			return false
		end
		local ability = recipe[ABILITY]
		if ability ~= 0 and not (opts.hasAbility and opts.hasAbility(ability)) then
			return false
		end
		return true
	end
	return false
end

-- Plan from skill `from` to `to`. opts: price(item) in copper (required), cooldown (set of
-- spells to skip), known (set of spells), vendorRecipes (allow recipes bought from vendors),
-- raceBit, hasAbility(spell). Returns steps {recipe, from, to, crafts} and the end skill
-- (lower than `to` if no usable recipe gives points any more).
function Planner.Plan(recipes, from, to, opts)
	local makers = MakerIndex(recipes)
	local cache = {}
	local steps = {}
	local current, step
	local s = from
	local expected = 0
	while s < to do
		local best, bestScore
		for _, r in ipairs(recipes) do
			local p = Planner.Chance(r, s)
			if p > 0 and Usable(r, s, opts) then
				local score = (CraftCost(r, opts, makers, cache, 0) + Planner.CRAFT_EFFORT) / p
				if not bestScore or score < bestScore then
					best, bestScore = r, score
				end
			end
		end
		if not best then
			break
		end
		if current and current ~= best then
			local p = Planner.Chance(current, s)
			if p > 0 and Usable(current, s, opts)
				and (CraftCost(current, opts, makers, cache, 0) + Planner.CRAFT_EFFORT) / p <= bestScore * SWITCH_MARGIN then
				best = current
			end
		end
		if best ~= current then
			if step then
				step.crafts = math.ceil(expected - 0.05)
			end
			step = {recipe = best, from = s, to = s + 1}
			steps[#steps + 1] = step
			current = best
			expected = 0
		end
		expected = expected + 1 / Planner.Chance(best, s)
		s = s + 1
		step.to = s
	end
	if step then
		step.crafts = math.ceil(expected - 0.05)
	end
	return steps, s
end

-- Materials for the remaining steps: {item = count}. Partially done first step counts from
-- the current skill.
function Planner.Materials(steps, skill)
	local need = {}
	for _, step in ipairs(steps) do
		local crafts = step.crafts
		if skill > step.from and skill < step.to then
			crafts = math.ceil(crafts * (step.to - skill) / (step.to - step.from))
		elseif skill >= step.to then
			crafts = 0
		end
		local r = step.recipe
		for i = REAGENTS, #r, 2 do
			need[r[i]] = (need[r[i]] or 0) + r[i + 1] * crafts
		end
	end
	return need
end

Planner.FIELDS = {SPELL = SPELL, SOURCE = SOURCE, LEARN = LEARN, YELLOW = YELLOW, GREY = GREY, COST = COST,
	CREATED = CREATED, AMOUNT = AMOUNT, REAGENTS = REAGENTS}
