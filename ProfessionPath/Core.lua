-- ProfessionPath core: professions and skill of the player, known recipes (read from the
-- profession window), route calculation and item names.

ProfessionPath = ProfessionPath or {}
local SP = ProfessionPath
local L = SP.L
local Planner = SP.Planner
local Data = ProfessionPathData
local F = Planner.FIELDS

SP.MAX_SKILL = 450

-- Profession ranks: cap, skill and character level needed to learn the next rank
SP.RANKS = {
	{cap = 75, name = "Journeyman", skill = 50, level = 10},
	{cap = 150, name = "Expert", skill = 125, level = 20},
	{cap = 225, name = "Artisan", skill = 200, level = 35},
	{cap = 300, name = "Master", skill = 275, level = 50},
	{cap = 375, name = "Grand Master", skill = 350, level = 65},
}

local RACE_IDS = {Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8,
	BloodElf = 10, Draenei = 11}

-- Localized profession names from the profession spells; smelting opens its own window
local SMELTING_SPELL = 2656
-- Gathering professions: their spell carries the profession name (Skinning, Fishing);
-- Herbalism's spell is called "Herb Gathering", so its name comes from this list
local GATHER_SPELLS = {[393] = 8613, [356] = 7620}
local HERBALISM_NAMES = {enUS = "Herbalism", enGB = "Herbalism", deDE = "Kräuterkunde", frFR = "Herboristerie",
	esES = "Herboristería", esMX = "Herboristería", ruRU = "Травничество"}
SP.skillName, SP.nameToSkill, SP.skillOrder = {}, {}, {}

local function InitNames()
	for line, spell in pairs(Data.skills) do
		local name = GetSpellInfo(spell)
		if name then
			SP.skillName[line] = name
			SP.nameToSkill[name] = line
		end
		SP.skillOrder[#SP.skillOrder + 1] = line
	end
	local smelting = GetSpellInfo(SMELTING_SPELL)
	if smelting then
		SP.nameToSkill[smelting] = 186
	end
	for line, spell in pairs(GATHER_SPELLS) do
		local name = GetSpellInfo(spell)
		if name then
			SP.skillName[line] = name
			SP.nameToSkill[name] = line
		end
		SP.skillOrder[#SP.skillOrder + 1] = line
	end
	local herbalism = HERBALISM_NAMES[GetLocale()] or HERBALISM_NAMES.enUS
	SP.skillName[182] = herbalism
	SP.nameToSkill[herbalism] = 182
	SP.skillOrder[#SP.skillOrder + 1] = 182
	table.sort(SP.skillOrder, function(a, b)
		return (SP.skillName[a] or "") < (SP.skillName[b] or "")
	end)
end

local function CharKey()
	return (GetRealmName() or "?") .. "-" .. (UnitName("player") or "?")
end

function SP:Char()
	local key = CharKey()
	local chars = ProfessionPathDB.chars
	chars[key] = chars[key] or {known = {}, skills = {}}
	return chars[key]
end

-- Skill lines of the player: {[line] = {rank = n, max = n}}
function SP:GetProfessions()
	local result = {}
	for i = 1, GetNumSkillLines() do
		local name, header, _, rank, _, _, maxRank = GetSkillLineInfo(i)
		local line = not header and SP.nameToSkill[name]
		if line then
			result[line] = {rank = rank, max = maxRank}
		end
	end
	local char = self:Char()
	for line, info in pairs(result) do
		char.skills[line] = {rank = info.rank, max = info.max}
	end
	return result
end

-- Remember the recipes shown in the profession window (only ever adds; filters in the
-- window may hide some).
function SP:ScanTradeSkill()
	if IsTradeSkillLinked and IsTradeSkillLinked() then
		return
	end
	local name, rank, maxRank = GetTradeSkillLine()
	local line = name and SP.nameToSkill[name]
	if not line then
		return
	end
	local char = self:Char()
	for i = 1, GetNumTradeSkills() do
		local _, kind = GetTradeSkillInfo(i)
		if kind ~= "header" then
			local link = GetTradeSkillRecipeLink(i)
			local spell = link and tonumber(link:match("enchant:(%d+)"))
			if spell then
				char.known[spell] = true
			end
		end
	end
	char.scanned = char.scanned or {}
	char.scanned[line] = true
	if rank and rank > 0 then
		char.skills[line] = {rank = rank, max = maxRank}
	end
	return line
end

function SP:RaceBit()
	local _, race = UnitRace("player")
	local id = RACE_IDS[race or ""]
	return id and bit.lshift(1, id - 1) or nil
end

-- Price of a material avoided in this profession: so high that the planner only uses it
-- when there is no alternative
local AVOID_PRICE = 10000000 -- 1000 gold per unit

-- Route for a profession from the given skill (default: the player's skill) up to `to`
-- (default 450). onlyKnown: only recipes the character knows already.
function SP:Plan(line, from, onlyKnown, to)
	local recipes = Data.recipes[line]
	if not recipes then
		return {}, from or 1
	end
	local char = self:Char()
	local opts = {
		price = function(item)
			if self:IsAvoided(item, line) then
				return AVOID_PRICE
			end
			return self:Price(item)
		end,
		cooldown = Data.cooldown,
		known = char.known,
		vendorRecipes = ProfessionPathDB.options.vendorRecipes,
		raceBit = self:RaceBit(),
		hasAbility = function(spell)
			return IsSpellKnown and IsSpellKnown(spell) or false
		end,
		onlyKnown = onlyKnown,
	}
	from, to = math.max(1, from or 1), to or SP.MAX_SKILL
	if not ProfessionPathDB.options.ownMaterials then
		return Planner.Plan(recipes, from, to, opts)
	end
	-- Own materials: materials in bags and bank cost only their vendor sell price (what the
	-- player would get for them otherwise) while the route has not used them up. That route
	-- is planned skill point by skill point and can spend the stock on early recipes although
	-- the normal route would have used it later anyway, so both routes are compared by what
	-- they really cost and the cheaper one wins.
	local have = {}
	for _, r in ipairs(recipes) do
		for i = F.REAGENTS, #r, 2 do
			local item = r[i]
			if have[item] == nil then
				have[item] = GetItemCount(item, true) or 0
			end
		end
		local created = r[F.CREATED]
		if created > 0 and have[created] == nil then
			have[created] = GetItemCount(created, true) or 0
		end
	end
	opts.ownPrice = function(item)
		-- avoided stays avoided, even when the player has it
		if self:IsAvoided(item, line) then
			return AVOID_PRICE
		end
		return math.min(opts.price(item), self:SellPrice(item))
	end
	local steps, reached = Planner.Plan(recipes, from, to, opts)
	local stock = {}
	for item, count in pairs(have) do
		stock[item] = count
	end
	opts.stock = stock
	local ownSteps, ownReached = Planner.Plan(recipes, from, to, opts)
	opts.stock = nil
	if ownReached >= reached and Planner.RouteCost(ownSteps, from, have, opts) < Planner.RouteCost(steps, from, have, opts) then
		return ownSteps, ownReached
	end
	return steps, reached
end

-- Prices --------------------------------------------------------------------------------
-- Vendor reagents cost their vendor price; everything else the auction value from
-- Auctioneer or Auctionator if installed, otherwise an estimate from the vendor sell price.
-- Materials the player chose to avoid in a profession cost so much there that the planner
-- only uses them when there is no alternative (see SP:Plan).

local PRICE_CACHE_TIME = 120
local priceCache, priceCacheTime = {}, 0

function SP:PriceSource()
	if AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue then
		return "Auctioneer"
	elseif Atr_GetAuctionBuyout then
		return "Auctionator"
	end
end

-- Age of the auction data in seconds (nil if unknown) and whether the last scan was a
-- partial one (a search, not a full scan). Auctioneer stores every scan; Auctionator
-- (2.6.x for 3.3.5) only the end of its last full scan, in AUCTIONATOR_LAST_SCAN_TIME.
function SP:ScanAge()
	if not (AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue) then
		if Atr_GetAuctionBuyout and type(AUCTIONATOR_LAST_SCAN_TIME) == "number" then
			return math.max(0, time() - AUCTIONATOR_LAST_SCAN_TIME), false
		end
		return nil
	end
	if not AucAdvanced.API.GetScanStats then
		return nil
	end
	local ok, stats = pcall(AucAdvanced.API.GetScanStats)
	if not ok or type(stats) ~= "table" or not stats.LastScan then
		return nil
	end
	local partial = not stats.LastFullScan or stats.LastFullScan < stats.LastScan - 3600
	return math.max(0, time() - stats.LastScan), partial
end

local function AuctionPrice(item)
	local link = select(2, GetItemInfo(item))
	if not link then
		return nil
	end
	local ok, value
	if AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue then
		ok, value = pcall(AucAdvanced.API.GetMarketValue, link)
	elseif Atr_GetAuctionBuyout then
		ok, value = pcall(Atr_GetAuctionBuyout, link)
	end
	if ok and type(value) == "number" and value > 0 then
		return value
	end
end

-- Market price per unit in copper; second value: "vendor", "auction" or "estimate"
function SP:Price(item)
	local now = GetTime()
	if now - priceCacheTime > PRICE_CACHE_TIME then
		wipe(priceCache)
		priceCacheTime = now
	end
	local cached = priceCache[item]
	if cached then
		return cached[1], cached[2]
	end
	local price, source = Data.vendor[item], "vendor"
	if not price then
		price, source = AuctionPrice(item), "auction"
		if not price then
			local sell = SP:SellPrice(item)
			price, source = sell > 0 and sell * Planner.ESTIMATE_FACTOR or Planner.EstimatePrice(item, Data), "estimate"
		end
	end
	priceCache[item] = {price, source}
	return price, source
end

-- Vendor sell price in copper as the server sends it (GetItemInfo), else from Data
function SP:SellPrice(item)
	local sell = select(11, GetItemInfo(item))
	if type(sell) == "number" then
		return sell
	end
	return Data.sellPrice[item] or 0
end

function SP:ClearPrices()
	wipe(priceCache)
end

-- Avoiding is per profession: a material that is not worth it in one profession can still
-- be the cheapest way in another.
function SP:IsAvoided(item, line)
	local list = ProfessionPathDB.avoided[line]
	return list and list[item] or false
end

function SP:ToggleAvoid(item, line)
	local list = ProfessionPathDB.avoided[line] or {}
	ProfessionPathDB.avoided[line] = list
	list[item] = not list[item] or nil
	SP.recommendVersion = (SP.recommendVersion or 0) + 1
end

-- Recipes that are not planned (drops, tokens, quests) but would give points at `skill`
function SP:MissingRecipes(line, skill, limit)
	local list, seen = {}, {}
	local known = self:Char().known
	for _, r in ipairs(Data.recipes[line] or {}) do
		local spell = r[F.SPELL]
		-- one entry per created item (Alliance/Horde variants of a recipe look the same)
		local key = r[F.CREATED] > 0 and r[F.CREATED] or -spell
		if not known[spell] and not Data.cooldown[spell] and r[F.SOURCE] ~= Planner.SOURCE_TRAINER
			and r[F.LEARN] <= skill and r[F.GREY] > skill and Data.recipeItem[spell] and not seen[key] then
			seen[key] = true
			list[#list + 1] = r
		end
	end
	table.sort(list, function(a, b)
		return a[F.GREY] > b[F.GREY]
	end)
	while #list > (limit or 3) do
		table.remove(list)
	end
	return list
end

-- Item names: cached ones directly, others are requested from the server via a hidden
-- tooltip; the UI refreshes a moment later.
local scanTip = CreateFrame("GameTooltip", "ProfessionPathScanTooltip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
local requested = {}
SP.missingNames = 0

function SP:ItemName(item)
	local name, _, quality = GetItemInfo(item)
	if name then
		local color = ITEM_QUALITY_COLORS[quality or 1]
		return name, color
	end
	if not requested[item] then
		requested[item] = true
		scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
		scanTip:SetHyperlink("item:" .. item)
	end
	SP.missingNames = SP.missingNames + 1
	return "item:" .. item, nil
end

function SP:ItemIcon(item)
	return GetItemIcon and GetItemIcon(item) or select(10, GetItemInfo(item)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function SP:RecipeName(spell)
	local name, _, icon = GetSpellInfo(spell)
	return name or ("spell:" .. spell), icon
end

-- Server data -----------------------------------------------------------------------------
-- Data comes from AzerothCore (blizzlike); a server can differ. What it really offers is
-- read while a vendor or trainer window is open, saved per faction (recipe vendors differ)
-- and laid over Data: vendor prices of reagents, recipes sold by vendors, trainer recipes
-- with their skill requirement and cost. Only what the server shows is added, nothing is
-- removed (a trainer of a lower rank does not list everything).

local reagentSet, recipeItemSpells, spellRecipe, recipeNames

local function BuildIndexes()
	if reagentSet then
		return
	end
	reagentSet, recipeItemSpells, spellRecipe = {}, {}, {}
	for _, recipes in pairs(Data.recipes) do
		for _, r in ipairs(recipes) do
			spellRecipe[r[F.SPELL]] = r
			for i = F.REAGENTS, #r, 2 do
				reagentSet[r[i]] = true
			end
		end
	end
	for spell, item in pairs(Data.recipeItem) do
		recipeItemSpells[item] = recipeItemSpells[item] or {}
		table.insert(recipeItemSpells[item], spell)
	end
end

local function Learned()
	local faction = UnitFactionGroup("player") or "Neutral"
	ProfessionPathDB.learned = ProfessionPathDB.learned or {}
	local db = ProfessionPathDB.learned
	db[faction] = db[faction] or {vendor = {}, recipeVendor = {}, trainer = {}}
	return db[faction]
end

function SP:ApplyLearned()
	local learned = Learned()
	for item, price in pairs(learned.vendor) do
		Data.vendor[item] = price
	end
	for _, recipes in pairs(Data.recipes) do
		for _, r in ipairs(recipes) do
			local spell = r[F.SPELL]
			local trainer = learned.trainer[spell]
			if trainer and r[F.SOURCE] ~= Planner.SOURCE_AUTO then
				r[F.SOURCE], r[F.LEARN], r[F.COST] = Planner.SOURCE_TRAINER, trainer[1], trainer[2]
			elseif learned.recipeVendor[spell] and r[F.SOURCE] == Planner.SOURCE_OTHER then
				r[F.SOURCE] = Planner.SOURCE_VENDOR
			end
		end
	end
end

local function LearnedSomething(count)
	SP:ApplyLearned()
	SP:ClearPrices()
	print(format("|cffffd100ProfessionPath:|r " .. L["%d new entries learned from this vendor or trainer."], count))
	if SP.OnDataChanged then
		SP:OnDataChanged()
	end
end

local function ScanMerchant()
	BuildIndexes()
	local learned, changed = Learned(), 0
	for i = 1, GetMerchantNumItems() do
		local _, _, price, quantity, _, _, extendedCost = GetMerchantItemInfo(i)
		local link = GetMerchantItemLink(i)
		local item = link and tonumber(link:match("item:(%d+)"))
		-- only plain gold purchases (no tokens or honor)
		if item and price and price > 0 and not extendedCost then
			if reagentSet[item] then
				local unit = price / math.max(1, quantity or 1)
				if learned.vendor[item] ~= unit then
					if Data.vendor[item] ~= unit then
						changed = changed + 1
					end
					learned.vendor[item] = unit
				end
			end
			for _, spell in ipairs(recipeItemSpells[item] or {}) do
				if not learned.recipeVendor[spell] then
					learned.recipeVendor[spell] = true
					local r = spellRecipe[spell]
					if r and r[F.SOURCE] == Planner.SOURCE_OTHER then
						changed = changed + 1
					end
				end
			end
		end
	end
	if changed > 0 then
		LearnedSomething(changed)
	end
end

-- Recipe of a trainer entry: same spell name, and if that is not unique, the same created item
local function TrainerRecipe(line, name, link)
	recipeNames = recipeNames or {}
	if not recipeNames[line] then
		local names = {}
		for _, r in ipairs(Data.recipes[line] or {}) do
			local spellName = GetSpellInfo(r[F.SPELL])
			if spellName then
				names[spellName] = names[spellName] or {}
				table.insert(names[spellName], r)
			end
		end
		recipeNames[line] = names
	end
	local list = recipeNames[line][name]
	if not list then
		return nil
	elseif #list == 1 then
		return list[1]
	end
	local item = link and tonumber(link:match("item:(%d+)"))
	local found
	for _, r in ipairs(list) do
		if item and r[F.CREATED] == item then
			if found then
				return nil
			end
			found = r
		end
	end
	return found
end

local function ScanTrainer()
	if not (GetNumTrainerServices and GetTrainerServiceSkillLine) then
		return
	end
	BuildIndexes()
	local learned, changed = Learned(), 0
	for i = 1, GetNumTrainerServices() do
		local name, _, category = GetTrainerServiceInfo(i)
		local line = name and category ~= "header" and SP.nameToSkill[GetTrainerServiceSkillLine(i) or ""]
		local r = line and Data.recipes[line] and TrainerRecipe(line, name, GetTrainerServiceItemLink(i))
		if r and r[F.SOURCE] ~= Planner.SOURCE_AUTO then
			local _, req = GetTrainerServiceSkillReq(i)
			local cost = GetTrainerServiceCost(i) or 0
			local spell = r[F.SPELL]
			local old = learned.trainer[spell]
			if req and (not old or old[1] ~= req or old[2] ~= cost) then
				if r[F.SOURCE] ~= Planner.SOURCE_TRAINER or r[F.LEARN] ~= req or r[F.COST] ~= cost then
					changed = changed + 1
				end
				learned.trainer[spell] = {req, cost}
			end
		end
	end
	if changed > 0 then
		LearnedSomething(changed)
	end
end

-- Events
local events = CreateFrame("Frame")
SP.eventFrame = events -- for tools/smoke_test.py
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_UPDATE")
events:RegisterEvent("TRAINER_SHOW")
events:RegisterEvent("TRAINER_UPDATE")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:RegisterEvent("TRADE_SKILL_UPDATE")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("BAG_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == "ProfessionPath" then
			ProfessionPathDB = ProfessionPathDB or {}
			ProfessionPathDB.chars = ProfessionPathDB.chars or {}
			ProfessionPathDB.options = ProfessionPathDB.options or {}
			-- per profession since 0.4.0; the old account-wide list is dropped once
			ProfessionPathDB.avoid = nil
			ProfessionPathDB.avoided = ProfessionPathDB.avoided or {}
			if ProfessionPathDB.options.vendorRecipes == nil then
				ProfessionPathDB.options.vendorRecipes = true
			end
			if ProfessionPathDB.options.ownMaterials == nil then
				ProfessionPathDB.options.ownMaterials = true
			end
		elseif arg1 == "Blizzard_TradeSkillUI" and SP.AttachTradeSkillButton then
			SP:AttachTradeSkillButton()
		end
	elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		ScanMerchant()
	elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
		ScanTrainer()
	elseif event == "PLAYER_LOGIN" then
		InitNames()
		SP:ApplyLearned()
		if IsAddOnLoaded("Blizzard_TradeSkillUI") and SP.AttachTradeSkillButton then
			SP:AttachTradeSkillButton()
		end
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
		local line = SP:ScanTradeSkill()
		if line and SP.OnDataChanged then
			SP:OnDataChanged(line)
		end
	elseif SP.OnDataChanged then
		SP:OnDataChanged()
	end
end)

SLASH_PROFESSIONPATH1 = "/professionpath"
SLASH_PROFESSIONPATH2 = "/ppath"
SlashCmdList["PROFESSIONPATH"] = function()
	SP:Toggle()
end
