-- ProfessionPath route planner. Pure logic without WoW API calls, so it can be tested outside
-- the game: everything client-specific comes in through the options table.

ProfessionPath = ProfessionPath or {}
local Planner = {}
ProfessionPath.Planner = Planner

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
-- Recipes with a lower skill-up chance (green, close to grey) are only planned when no
-- other recipe gives points: they need many crafts and lots of material that the auction
-- house may not even have in stock, whatever its market value says.
Planner.MIN_CHANCE = 0.35
-- Without auction data a material is estimated at this multiple of its vendor sell price
-- (auction prices are typically a few times the sell price).
Planner.ESTIMATE_FACTOR = 4
local UNKNOWN_PRICE = 100 -- 1 silver for items without any price information

-- Price estimate without auction data: vendor buy price for vendor reagents, otherwise a
-- multiple of the vendor sell price. data = ProfessionPathData.
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
-- Price of a material at this point of the route: what the player still has (opts.stock,
-- used up along the route) costs only opts.ownPrice(item), e.g. its vendor sell price.
local function UnitPrice(item, opts)
	local stock = opts.stock
	if stock and (stock[item] or 0) > 0 then
		return opts.ownPrice(item)
	end
	return opts.price(item)
end

local function CraftCost(recipe, opts, makers, cache, depth)
	local cached = cache[recipe]
	if cached then
		return cached
	end
	local cost = 0
	for i = REAGENTS, #recipe, 2 do
		local item, count = recipe[i], recipe[i + 1]
		local price = UnitPrice(item, opts)
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

-- Takes the materials of `crafts` crafts out of opts.stock. What is not in stock and is
-- cheaper to make (as in CraftCost) uses up the materials of the intermediate instead.
-- Returns true when a material ran out, so cached craft costs are outdated.
local function Consume(recipe, crafts, opts, makers, cache, depth)
	local stock = opts.stock
	local ranOut = false
	for i = REAGENTS, #recipe, 2 do
		local item = recipe[i]
		local need = recipe[i + 1] * crafts
		local have = stock[item] or 0
		if have > 0 then
			local used = math.min(have, need)
			stock[item] = have - used
			need = need - used
			ranOut = ranOut or stock[item] <= 0
		end
		local maker = makers[item]
		if need > 0 and maker and maker ~= recipe and depth < 3
			and CraftCost(maker, opts, makers, cache, depth + 1) / maker[AMOUNT] < opts.price(item) then
			ranOut = Consume(maker, need / maker[AMOUNT], opts, makers, cache, depth + 1) or ranOut
		end
	end
	-- what a skill-up craft makes is the player's own material afterwards (heavy leather
	-- for armor kits, bolts for tailoring)
	local created = recipe[CREATED]
	if depth == 0 and created > 0 then
		if (stock[created] or 0) <= 0 then
			ranOut = true -- price of the created item changes too
		end
		stock[created] = (stock[created] or 0) + recipe[AMOUNT] * crafts
	end
	return ranOut
end

-- A short step between two steps of the same recipe (switched there because of rounding
-- or a material running out) is merged into them when that recipe still gives points.
local MERGE_POINTS = 2
local function MergeShortSteps(steps)
	local i = 2
	while i < #steps do
		local prev, step, nextStep = steps[i - 1], steps[i], steps[i + 1]
		local r = prev.recipe
		if nextStep.recipe == r and step.to - step.from <= MERGE_POINTS and Planner.Chance(r, step.to - 1) > 0 then
			local expected = 0
			for s = prev.from, nextStep.to - 1 do
				expected = expected + 1 / Planner.Chance(r, s)
			end
			prev.to, prev.crafts = nextStep.to, math.ceil(expected - 0.05)
			table.remove(steps, i + 1)
			table.remove(steps, i)
		else
			i = i + 1
		end
	end
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
	-- only what the character can craft right now (for the profession window)
	if opts.onlyKnown then
		return source == Planner.SOURCE_AUTO
	end
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
-- raceBit, hasAbility(spell), stock ({item = count}, changed while planning) with
-- ownPrice(item) for owned materials. Returns steps {recipe, from, to, crafts} and the end skill
-- (lower than `to` if no usable recipe gives points any more).
function Planner.Plan(recipes, from, to, opts)
	local makers = MakerIndex(recipes)
	local cache = {}
	local steps = {}
	local current, step
	local s = from
	local expected = 0
	while s < to do
		-- recipes close to grey only if nothing better gives points
		local best, bestScore
		for pass = 1, 2 do
			local minChance = pass == 1 and Planner.MIN_CHANCE or 0
			for _, r in ipairs(recipes) do
				local p = Planner.Chance(r, s)
				if p > 0 and p >= minChance and Usable(r, s, opts) then
					local score = (CraftCost(r, opts, makers, cache, 0) + Planner.CRAFT_EFFORT) / p
					if not bestScore or score < bestScore then
						best, bestScore = r, score
					end
				end
			end
			if best then
				break
			end
		end
		if not best then
			break
		end
		if current and current ~= best then
			local p = Planner.Chance(current, s)
			if p >= math.min(Planner.MIN_CHANCE, Planner.Chance(best, s)) and p > 0 and Usable(current, s, opts)
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
		local crafts = 1 / Planner.Chance(best, s)
		expected = expected + crafts
		if opts.stock and Consume(best, crafts, opts, makers, cache, 0) then
			for k in pairs(cache) do
				cache[k] = nil
			end
		end
		s = s + 1
		step.to = s
	end
	if step then
		step.crafts = math.ceil(expected - 0.05)
	end
	MergeShortSteps(steps)
	return steps, s
end

local function RemainingCrafts(step, skill)
	if skill >= step.to then
		return 0
	elseif skill > step.from then
		return math.ceil(step.crafts * (step.to - skill) / (step.to - step.from))
	end
	return step.crafts
end

-- Materials for the remaining steps: {item = count}. Partially done first step counts from
-- the current skill. What an earlier step makes (heavy leather, bolts) covers later needs.
function Planner.Materials(steps, skill)
	local need, made = {}, {}
	for _, step in ipairs(steps) do
		local crafts = RemainingCrafts(step, skill)
		local r = step.recipe
		for i = REAGENTS, #r, 2 do
			local item, count = r[i], r[i + 1] * crafts
			local fromMade = math.min(made[item] or 0, count)
			made[item] = (made[item] or 0) - fromMade
			need[item] = (need[item] or 0) + count - fromMade
		end
		if r[CREATED] > 0 then
			made[r[CREATED]] = (made[r[CREATED]] or 0) + r[AMOUNT] * crafts
		end
	end
	return need
end

-- What the rest of a route really costs: materials to buy at opts.price, own materials
-- (`have`) at opts.ownPrice, plus the effort per craft. Used to compare routes.
function Planner.RouteCost(steps, skill, have, opts)
	local cost = 0
	for item, count in pairs(Planner.Materials(steps, skill)) do
		local own = math.min(have[item] or 0, count)
		cost = cost + own * opts.ownPrice(item) + (count - own) * opts.price(item)
	end
	for _, step in ipairs(steps) do
		cost = cost + RemainingCrafts(step, skill) * Planner.CRAFT_EFFORT
	end
	return cost
end

Planner.FIELDS = {SPELL = SPELL, SOURCE = SOURCE, LEARN = LEARN, YELLOW = YELLOW, GREY = GREY, COST = COST,
	CREATED = CREATED, AMOUNT = AMOUNT, REAGENTS = REAGENTS}
