-- SkillPath core: professions and skill of the player, known recipes (read from the
-- profession window), route calculation and item names.

SkillPath = SkillPath or {}
local SP = SkillPath
local L = SP.L
local Planner = SP.Planner
local Data = SkillPathData
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
	table.sort(SP.skillOrder, function(a, b)
		return (SP.skillName[a] or "") < (SP.skillName[b] or "")
	end)
end

local function CharKey()
	return (GetRealmName() or "?") .. "-" .. (UnitName("player") or "?")
end

function SP:Char()
	local key = CharKey()
	local chars = SkillPathDB.chars
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

-- Route for a profession from the given skill (default: the player's skill)
function SP:Plan(line, from)
	local recipes = Data.recipes[line]
	if not recipes then
		return {}, from or 1
	end
	local char = self:Char()
	local opts = {
		price = function(item)
			return self:Price(item)
		end,
		cooldown = Data.cooldown,
		known = char.known,
		vendorRecipes = SkillPathDB.options.vendorRecipes,
		raceBit = self:RaceBit(),
		hasAbility = function(spell)
			return IsSpellKnown and IsSpellKnown(spell) or false
		end,
	}
	return Planner.Plan(recipes, math.max(1, from or 1), SP.MAX_SKILL, opts)
end

-- Prices --------------------------------------------------------------------------------
-- Vendor reagents cost their vendor price; everything else the auction value from
-- Auctioneer or Auctionator if installed, otherwise an estimate from the vendor sell price.
-- Materials the player chose to avoid cost so much that the planner only uses them when
-- there is no alternative.

local AVOID_PRICE = 10000000 -- 1000 gold per unit
local PRICE_CACHE_TIME = 120
local priceCache, priceCacheTime = {}, 0

function SP:PriceSource()
	if AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue then
		return "Auctioneer"
	elseif Atr_GetAuctionBuyout then
		return "Auctionator"
	end
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

-- Price per unit in copper; second value: "vendor", "auction" or "estimate"
function SP:Price(item)
	if SkillPathDB.avoid[item] then
		return AVOID_PRICE, "avoid"
	end
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
			price, source = Planner.EstimatePrice(item, Data), "estimate"
		end
	end
	priceCache[item] = {price, source}
	return price, source
end

function SP:ClearPrices()
	wipe(priceCache)
end

function SP:ToggleAvoid(item)
	SkillPathDB.avoid[item] = not SkillPathDB.avoid[item] or nil
	wipe(priceCache)
end

-- Recipes that are not planned (drops, tokens, quests) but would give points at `skill`
function SP:MissingRecipes(line, skill, limit)
	local list = {}
	local known = self:Char().known
	for _, r in ipairs(Data.recipes[line] or {}) do
		local spell = r[F.SPELL]
		if not known[spell] and not Data.cooldown[spell] and r[F.SOURCE] ~= Planner.SOURCE_TRAINER
			and r[F.LEARN] <= skill and r[F.GREY] > skill and Data.recipeItem[spell] then
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
local scanTip = CreateFrame("GameTooltip", "SkillPathScanTooltip", nil, "GameTooltipTemplate")
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

-- Events
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:RegisterEvent("TRADE_SKILL_UPDATE")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("BAG_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == "SkillPath" then
			SkillPathDB = SkillPathDB or {}
			SkillPathDB.chars = SkillPathDB.chars or {}
			SkillPathDB.options = SkillPathDB.options or {}
			SkillPathDB.avoid = SkillPathDB.avoid or {}
			if SkillPathDB.options.vendorRecipes == nil then
				SkillPathDB.options.vendorRecipes = true
			end
		elseif arg1 == "Blizzard_TradeSkillUI" and SP.AttachTradeSkillButton then
			SP:AttachTradeSkillButton()
		end
	elseif event == "PLAYER_LOGIN" then
		InitNames()
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

SLASH_SKILLPATH1 = "/skillpath"
SLASH_SKILLPATH2 = "/spath"
SlashCmdList["SKILLPATH"] = function()
	SP:Toggle()
end
