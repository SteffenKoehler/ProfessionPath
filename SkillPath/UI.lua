-- SkillPath window: profession selection, route with rank notes, materials with bag counts.

SkillPath = SkillPath or {}
local SP = SkillPath
local L = SP.L
local Planner = SP.Planner
local Data = SkillPathData
local F = Planner.FIELDS
local Gather = SP.Gather

local WIDTH, HEIGHT = 440, 540
local ROW_HEIGHT = 18
local ROUTE_ROWS, MAT_ROWS = 13, 7
local COLORS = {orange = "ff8040", yellow = "ffff00", green = "40bf40", grey = "808080"}

local frame, routeScroll, matScroll, dropdown, status, vendorCheck
local routeRows, matRows = {}, {}
local entries, materials = {}, {}
local materialTotal = 0
local matLabel, priceLabel, hintLabel
local AVOID_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
-- undo arrow of the equipment manager (exists in 3.3.5)
local USE_AGAIN_ICON = "Interface\\PaperDollInfoFrame\\UI-GearManager-Undo"
local selected, rank = nil, 0
local gathering = false
local dirty, sinceRefresh, retries = true, 0, 0

local function Backdrop(f)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = {left = 11, right = 12, top = 12, bottom = 11},
	})
end

local function Label(parent, text, template)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
	fs:SetText(text or "")
	return fs
end

-- Rows ------------------------------------------------------------------------------------

local function CreateRow(parent, index, anchor)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(index - 1) * ROW_HEIGHT - 4)
	row:SetPoint("RIGHT", parent, "RIGHT", -38, 0)
	row.highlight = row:CreateTexture(nil, "BACKGROUND")
	row.highlight:SetAllPoints()
	row.highlight:SetTexture(1, 0.82, 0, 0.15)
	row.highlight:Hide()
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetWidth(ROW_HEIGHT - 2)
	row.icon:SetHeight(ROW_HEIGHT - 2)
	row.icon:SetPoint("LEFT", 2, 0)
	row.text = Label(row, "", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -90, 0)
	row.text:SetJustifyH("LEFT")
	row.right = Label(row, "", "GameFontHighlightSmall")
	row.right:SetPoint("RIGHT", -2, 0)
	row.right:SetJustifyH("RIGHT")
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return row
end

-- How to get a recipe the character does not know yet; nil if it is known or comes with the
-- profession. Returns text and color.
local function LearnHint(r)
	local spell = r[F.SPELL]
	if r[F.SOURCE] == Planner.SOURCE_AUTO or SP:Char().known[spell] then
		return nil
	end
	if r[F.SOURCE] == Planner.SOURCE_TRAINER then
		return format(L["Learn at trainer from %d (%s)"], r[F.LEARN], GetCoinTextureString(r[F.COST])), 0.6, 0.8, 1
	elseif Data.recipeItem[spell] then
		local name = SP:ItemName(Data.recipeItem[spell])
		local text = r[F.SOURCE] == Planner.SOURCE_VENDOR and L["Buy recipe: %s"] or L["Recipe needed: %s"]
		return format(text, name), 1, 0.5, 0.25
	end
end

-- Where an unknown recipe comes from, shown with the icons of the NPC dialogs:
-- trainer book, vendor bag, scroll for drops, tokens and quests
local SOURCE_ICONS = {
	[Planner.SOURCE_TRAINER] = "Interface\\GossipFrame\\TrainerGossipIcon",
	[Planner.SOURCE_VENDOR] = "Interface\\GossipFrame\\VendorGossipIcon",
	[Planner.SOURCE_OTHER] = "Interface\\Icons\\INV_Scroll_03",
}
local SOURCE_TITLES = {
	[Planner.SOURCE_TRAINER] = "Learn the recipe at the trainer",
	[Planner.SOURCE_VENDOR] = "Buy the recipe from a vendor",
	[Planner.SOURCE_OTHER] = "Recipe from a drop, tokens or a quest",
}

local function EntryRecipe(entry)
	return entry and (entry.step and entry.step.recipe or entry.recipe)
end

local function ShowSourceTooltip(button)
	local r = EntryRecipe(button:GetParent().entry)
	if not r then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(L[SOURCE_TITLES[r[F.SOURCE]] or "Recipe not learned yet"])
	local text, red, green, blue = LearnHint(r)
	if text then
		GameTooltip:AddLine(text, red, green, blue, true)
	end
	GameTooltip:AddLine(L["The icon disappears once you have learned the recipe and opened the profession window."], 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

-- Shows the source icon on a route row if the recipe still has to be learned
local function SetSourceIcon(row, r)
	if r and LearnHint(r) and SOURCE_ICONS[r[F.SOURCE]] then
		row.book.icon:SetTexture(SOURCE_ICONS[r[F.SOURCE]])
		row.book:Show()
	end
end

local function ShowStepTooltip(row)
	local entry = row.entry
	if not entry or not entry.step then
		return
	end
	local r = entry.step.recipe
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("enchant:" .. r[F.SPELL])
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(format(L["Skill %d-%d, about %d crafts"], entry.step.from, entry.step.to, entry.step.crafts), 1, 1, 1)
	local text, red, green, blue = LearnHint(r)
	if text then
		GameTooltip:AddLine(text, red, green, blue)
	end
	GameTooltip:Show()
end

-- full text of a note, in case it is cut off in the row
local function ShowNoteTooltip(row)
	local entry = row.entry
	if entry and entry.note then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(entry.note, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end
end

local function ShowItemTooltip(row)
	if row.item then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. row.item)
		GameTooltip:Show()
	end
end

local PRICE_SOURCE = {vendor = "Vendor", auction = "Auction", estimate = "Estimate"}

local function ShowMaterialTooltip(row)
	if not row.item then
		return
	end
	ShowItemTooltip(row)
	GameTooltip:AddLine(" ")
	local m = row.material
	if SP:IsAvoided(row.item, selected) and m and m.need > 0 then
		GameTooltip:AddLine(L["Avoided, but still needed: in this skill range no other recipe gives enough skill points."], 1, 0.82, 0, true)
		if m.usedBy and #m.usedBy > 0 then
			GameTooltip:AddLine(L["Used by:"], 0.7, 0.7, 0.7)
			for _, step in ipairs(m.usedBy) do
				GameTooltip:AddLine(format("  %s (%d-%d)", SP:RecipeName(step.recipe[F.SPELL]), step.from, step.to), 1, 1, 1)
			end
		end
		GameTooltip:AddLine(L["Only for this profession."], 0.7, 0.7, 0.7)
		GameTooltip:AddLine(L["Right-click: use again"], 0.6, 0.8, 1)
	elseif SP:IsAvoided(row.item, selected) then
		GameTooltip:AddLine(L["Avoided: the route only uses it if there is no alternative."], 1, 0.4, 0.4, true)
		GameTooltip:AddLine(L["Only for this profession."], 0.7, 0.7, 0.7)
		GameTooltip:AddLine(L["Right-click: use again"], 0.6, 0.8, 1)
	else
		local price, source = SP:Price(row.item)
		GameTooltip:AddLine(format(L["Price per unit: %s (%s)"], GetCoinTextureString(math.floor(price)), L[PRICE_SOURCE[source] or source]), 1, 1, 1)
		GameTooltip:AddLine(L["Right-click: avoid this material"], 0.6, 0.8, 1)
	end
	GameTooltip:Show()
end

local SKIN_ICON = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01"
local FISH_ICON = "Interface\\Icons\\Trade_Fishing"

local function PlayerLevel()
	return UnitLevel("player") or 80
end

local function ZoneLabel(area)
	local level = Gather.ZoneLevel(area)
	local color = level > PlayerLevel() + 4 and "ff4040" or "aaaaaa"
	return format("%s |cff%s(%d)|r", Gather.ZoneName(area), color, level)
end

local function ShowGatherTooltip(row)
	local entry = row.entry
	local step = entry and entry.gather
	if not step then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(Gather.ZoneName(step.area))
	local level = Gather.ZoneLevel(step.area)
	if level > PlayerLevel() + 4 then
		GameTooltip:AddLine(format(L["Zone level %d - above your level"], level), 1, 0.25, 0.25)
	else
		GameTooltip:AddLine(format(L["Zone level %d"], level), 0.7, 0.7, 0.7)
	end
	GameTooltip:AddLine(" ")
	local s = math.max(rank, step.from)
	for _, c in ipairs(Gather.ZoneContents(selected, step.area, step.from, step.to)) do
		local color = COLORS[Gather.Color(c.req, s)]
		if c.item then
			GameTooltip:AddDoubleLine("|cff" .. color .. SP:ItemName(c.item) .. "|r", format(L["from skill %d, ~%d spawns"], c.req, c.count))
		else
			GameTooltip:AddDoubleLine("|cff" .. color .. format(L["Beasts level %d-%d"], c.minLevel, c.maxLevel) .. "|r",
				format(L["~%d spawns"], c.count))
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(format(L["Skill %d-%d, about %d gathers"], step.from, step.to, step.gathers), 1, 1, 1)
	GameTooltip:Show()
end

local function ShowFishTooltip(row)
	local step = row.entry and row.entry.fish
	if not step then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(format(L["Skill %d-%d, about %d catches"], step.from, step.to, step.catches))
	GameTooltip:AddLine(L["Zones where you catch fish at this skill:"], 0.7, 0.7, 0.7)
	for _, area in ipairs(step.areas) do
		GameTooltip:AddDoubleLine(ZoneLabel(area), format(L["minimum skill %d"], SkillPathGather.fishing[area]), 1, 1, 1, 0.7, 0.7, 0.7)
	end
	GameTooltip:Show()
end

-- Data ------------------------------------------------------------------------------------

-- Rank notes before the step that goes past the next cap; state = {next = index}
local function AddRankNotes(stepTo, maxRank, state)
	while SP.RANKS[state.next] and stepTo > SP.RANKS[state.next].cap do
		local r = SP.RANKS[state.next]
		if maxRank <= r.cap then
			entries[#entries + 1] = {note = format(L["Learn %s at your trainer (from skill %d, level %d)"],
				L[r.name], r.skill, r.level), color = "66ccff"}
		end
		state.next = state.next + 1
	end
end

local function BuildGather(maxRank)
	local opts = {level = PlayerLevel(), faction = UnitFactionGroup("player") == "Alliance" and 2 or 4}
	local state = {next = 1}
	if selected == Gather.FISHING then
		local steps = Gather.PlanFishing(math.max(1, rank), SP.MAX_SKILL, opts)
		for _, step in ipairs(steps) do
			AddRankNotes(step.to, maxRank, state)
			entries[#entries + 1] = {fish = step}
		end
		return
	end
	local steps, reached = Gather.Plan(selected, rank, SP.MAX_SKILL, opts)
	for _, step in ipairs(steps) do
		AddRankNotes(step.to, maxRank, state)
		entries[#entries + 1] = {gather = step}
	end
	if reached >= SP.MAX_SKILL and rank >= SP.MAX_SKILL then
		entries[#entries + 1] = {note = L["Done - maximum skill reached."], color = "40bf40"}
	end
	for _, c in ipairs(Gather.PointsNow(selected, math.max(1, rank))) do
		materials[#materials + 1] = {gather = c}
	end
end

local function Build()
	wipe(entries)
	wipe(materials)
	SP.missingNames = 0
	if not selected then
		return
	end
	local profs = SP:GetProfessions()
	local info = profs[selected] or SP:Char().skills[selected]
	rank = info and info.rank or 0
	local maxRank = info and info.max or 0
	local name = SP.skillName[selected] or "?"
	if info then
		status:SetText(format("%s  |cffffffff%d / %d|r", name, rank, maxRank))
	else
		status:SetText(format("%s  |cff808080%s|r", name, L["Not learned"]))
	end

	-- Gather.lua is missing when the client still has an old SkillPath.toc loaded (the
	-- client only reads .toc files when it starts)
	if not Gather then
		gathering = false
		if selected == 182 or selected == 393 or selected == 356 then
			entries[#entries + 1] = {note = L["Please restart the game client completely to load all SkillPath files."], color = "ff4040"}
			return
		end
	else
		gathering = Gather.IsGather(selected)
	end
	if gathering then
		BuildGather(maxRank)
		return
	end

	if info and not (SP:Char().scanned or {})[selected] then
		entries[#entries + 1] = {note = L["Open the profession window once so SkillPath knows your recipes."], color = "ff8040"}
	end

	local steps, reached = SP:Plan(selected, rank)
	local state = {next = 1}
	for _, step in ipairs(steps) do
		AddRankNotes(step.to, maxRank, state)
		entries[#entries + 1] = {step = step}
	end
	if reached >= SP.MAX_SKILL and rank >= SP.MAX_SKILL then
		entries[#entries + 1] = {note = L["Done - maximum skill reached."], color = "40bf40"}
	elseif reached < SP.MAX_SKILL then
		entries[#entries + 1] = {note = format(L["No further recipe from trainers or vendors gives skill points from %d on."], reached), color = "ff8040"}
		local missing = SP:MissingRecipes(selected, reached, 4)
		if #missing > 0 then
			entries[#entries + 1] = {note = L["To continue you need one of these recipes:"], color = "ffffff"}
			for _, r in ipairs(missing) do
				entries[#entries + 1] = {recipe = r}
			end
		end
	end

	local total = 0
	local usedBy = {}
	for _, step in ipairs(steps) do
		if step.to > rank then
			local r = step.recipe
			for i = F.REAGENTS, #r, 2 do
				usedBy[r[i]] = usedBy[r[i]] or {}
				table.insert(usedBy[r[i]], step)
			end
		end
	end
	for item, count in pairs(Planner.Materials(steps, rank)) do
		if count > 0 then
			local have = GetItemCount(item, true)
			materials[#materials + 1] = {item = item, need = count, have = have, usedBy = usedBy[item]}
			-- avoided materials the route still needs are bought too, at market price
			if have < count then
				total = total + (count - have) * SP:Price(item)
			end
		end
	end
	table.sort(materials, function(a, b)
		return a.need > b.need
	end)
	-- Avoided materials the route no longer needs stay listed (so they can be used again)
	-- while a recipe of this profession that still gives points uses them; once all of
	-- those are grey, they drop out of the list but stay avoided.
	local listed, relevant = {}, {}
	for _, m in ipairs(materials) do
		listed[m.item] = true
	end
	for _, r in ipairs(Data.recipes[selected] or {}) do
		if r[F.GREY] > rank then
			for i = F.REAGENTS, #r, 2 do
				if SP:IsAvoided(r[i], selected) then
					relevant[r[i]] = true
				end
			end
		end
	end
	for item in pairs(SkillPathDB.avoided[selected] or {}) do
		if relevant[item] and not listed[item] then
			materials[#materials + 1] = {item = item, need = 0, have = GetItemCount(item, true)}
		end
	end
	materialTotal = total
end

local function UpdateRoute()
	local offset = FauxScrollFrame_GetOffset(routeScroll)
	for i, row in ipairs(routeRows) do
		local entry = entries[offset + i]
		row.entry = entry
		row.item = nil
		row.highlight:Hide()
		row.book:Hide()
		row:SetScript("OnEnter", nil)
		if not entry then
			row:Hide()
		else
			row:Show()
			row.right:SetText("")
			-- notes use the full width, other rows leave room for the count on the right
			row.text:SetPoint("RIGHT", row, "RIGHT", entry.note and -2 or -90, 0)
			if entry.note then
				row.icon:SetTexture(nil)
				row.text:SetText("|cff" .. entry.color .. entry.note .. "|r")
				row:SetScript("OnEnter", ShowNoteTooltip)
			elseif entry.gather or entry.fish then
				local step = entry.gather or entry.fish
				local done = rank >= step.to
				if rank >= step.from and rank < step.to then
					row.highlight:Show()
				end
				local where
				if entry.fish then
					row.icon:SetTexture(FISH_ICON)
					local names = {}
					for _, area in ipairs(step.areas) do
						names[#names + 1] = Gather.ZoneName(area)
					end
					where = table.concat(names, ", ")
					row.right:SetText(done and "" or format("~%d", step.catches))
					row:SetScript("OnEnter", ShowFishTooltip)
				else
					local contents = Gather.ZoneContents(selected, step.area, step.from, step.to)
					local first = contents[#contents]
					row.icon:SetTexture(first and first.item and SP:ItemIcon(first.item) or SKIN_ICON)
					where = ZoneLabel(step.area)
					row.right:SetText(done and "" or format("~%d", step.gathers))
					row:SetScript("OnEnter", ShowGatherTooltip)
				end
				row.text:SetText(format("|cffaaaaaa%3d-%3d|r  %s%s|r", step.from, step.to, done and "|cff808080" or "|cffffffff", where))
			elseif entry.recipe then
				local r = entry.recipe
				local spell = r[F.SPELL]
				local itemName = SP:ItemName(Data.recipeItem[spell])
				row.icon:SetTexture(SP:ItemIcon(Data.recipeItem[spell]))
				row.text:SetText(format("  %s", itemName))
				row.right:SetText(format("|cff808080%d-%d|r", r[F.LEARN], r[F.GREY]))
				row.item = Data.recipeItem[spell]
				SetSourceIcon(row, r)
				row:SetScript("OnEnter", ShowItemTooltip)
			else
				local step = entry.step
				local r = step.recipe
				local name, icon = SP:RecipeName(r[F.SPELL])
				local created = r[F.CREATED]
				row.icon:SetTexture(created > 0 and SP:ItemIcon(created) or icon)
				local done = rank >= step.to
				local current = rank >= step.from and rank < step.to
				local crafts = step.crafts
				if current then
					crafts = math.ceil(step.crafts * (step.to - rank) / (step.to - step.from))
					row.highlight:Show()
				end
				local color = done and COLORS.grey or COLORS[Planner.Color(r, math.max(rank, step.from))]
				row.text:SetText(format("|cffaaaaaa%3d-%3d|r  |cff%s%s|r", step.from, step.to, color, name))
				row.right:SetText(done and "" or format("x%d", crafts))
				if not done then
					SetSourceIcon(row, r)
				end
				row:SetScript("OnEnter", ShowStepTooltip)
			end
		end
	end
	FauxScrollFrame_Update(routeScroll, #entries, ROUTE_ROWS, ROW_HEIGHT)
end

local function UpdateMaterials()
	local offset = FauxScrollFrame_GetOffset(matScroll)
	for i, row in ipairs(matRows) do
		local m = materials[offset + i]
		row.gatherRow = m and m.gather and true or nil
		if not m then
			row:Hide()
		elseif m.gather then
			row:Show()
			row.avoidButton:Hide()
			row.warn:Hide()
			row.material = nil
			local c = m.gather
			local color = COLORS[Gather.Color(c.req, math.max(1, rank))]
			row.icon:SetDesaturated(false)
			if c.item then
				row.item = c.item
				row.icon:SetTexture(SP:ItemIcon(c.item))
				row.text:SetText("|cff" .. color .. SP:ItemName(c.item) .. "|r")
				row:SetScript("OnEnter", ShowItemTooltip)
			else
				row.item = nil
				row.icon:SetTexture(SKIN_ICON)
				row.text:SetText("|cff" .. color .. format(L["Beasts level %d-%d"], c.minLevel, c.maxLevel) .. "|r")
				row:SetScript("OnEnter", nil)
			end
			row.right:SetText(format("|cffaaaaaa%s|r", format(L["from skill %d"], c.req)))
		else
			row:Show()
			local name, color = SP:ItemName(m.item)
			row.item = m.item
			row.icon:SetTexture(SP:ItemIcon(m.item))
			row.avoidButton:Show()
			row.avoidButton.icon:SetTexture(SP:IsAvoided(m.item, selected) and USE_AGAIN_ICON or AVOID_ICON)
			row.material = m
			if SP:IsAvoided(m.item, selected) and m.need > 0 then
				-- avoided, but the route cannot do without it
				row.warn:Show()
				row.icon:SetDesaturated(false)
				row.text:SetText(color and (color.hex .. name .. "|r") or name)
				row.right:SetText(format("|cffffd100%s|r  %s", L["still needed"], format(L["have %d / need %d"], m.have, m.need)))
			elseif SP:IsAvoided(m.item, selected) then
				row.warn:Hide()
				row.icon:SetDesaturated(true)
				row.text:SetText("|cff808080" .. name .. "|r")
				row.right:SetText(format("|cffff6666%s|r", L["avoided"]))
			else
				row.warn:Hide()
				row.icon:SetDesaturated(false)
				row.text:SetText(color and (color.hex .. name .. "|r") or name)
				local ok = m.have >= m.need
				row.right:SetText(format("|cff%s%s|r", ok and "40bf40" or "ffffff", format(L["have %d / need %d"], m.have, m.need)))
			end
			row:SetScript("OnEnter", ShowMaterialTooltip)
		end
	end
	FauxScrollFrame_Update(matScroll, #materials, MAT_ROWS, ROW_HEIGHT)
	if gathering then
		if selected == Gather.FISHING then
			matLabel:SetText(format(L["Catches per skill point at your skill: %d"], Gather.FishCatches(math.max(1, rank))))
		else
			matLabel:SetText(L["Gives skill points at your skill now"])
		end
		priceLabel:SetText("")
		hintLabel:SetText("")
		vendorCheck:Hide()
		return
	end
	hintLabel:SetText(#materials > 0 and L["X: avoid a material"] or "")
	vendorCheck:Show()
	local source = SP:PriceSource()
	matLabel:SetText(format("%s  |cffffffff~%s|r", L["Materials for the rest of the route"],
		GetCoinTextureString(math.floor(materialTotal / 100) * 100)))
	priceLabel:SetText(format(L["Prices: %s"], source or L["estimate from vendor prices"]))
end

function SP:Refresh()
	SP.recommendVersion = (SP.recommendVersion or 0) + 1
	if not frame or not frame:IsShown() then
		dirty = true
		return
	end
	Build()
	UpdateRoute()
	UpdateMaterials()
	dirty = false
	sinceRefresh = 0
	-- item names not cached yet: try again shortly
	if SP.missingNames > 0 and retries < 5 then
		retries = retries + 1
		dirty = true
	else
		retries = 0
	end
end

function SP:OnDataChanged(line)
	SP.recommendVersion = (SP.recommendVersion or 0) + 1
	dirty = true
	if line and frame and frame:IsShown() and SP.followTradeSkill then
		selected = line
		UIDropDownMenu_SetText(dropdown, SP.skillName[line] or "?")
	end
end

-- Dropdown --------------------------------------------------------------------------------

local function Select(line)
	selected = line
	UIDropDownMenu_SetText(dropdown, SP.skillName[line] or "?")
	FauxScrollFrame_SetOffset(routeScroll, 0)
	routeScroll:SetVerticalScroll(0)
	SP:Refresh()
	-- scroll so that the current step is visible
	for i, entry in ipairs(entries) do
		if entry.step and rank < entry.step.to then
			local offset = math.max(0, math.min(i - 2, #entries - ROUTE_ROWS))
			FauxScrollFrame_SetOffset(routeScroll, offset)
			routeScroll:SetVerticalScroll(offset * ROW_HEIGHT)
			UpdateRoute()
			break
		end
	end
end

-- Professions grouped like in the game: crafting, gathering, secondary skills
local GROUPS = {
	{key = "crafting", name = "Crafting", lines = {171, 164, 333, 202, 773, 755, 165, 197}},
	{key = "gathering", name = "Gathering", lines = {182, 186, 393}},
	{key = "secondary", name = "Secondary skills", lines = {129, 185, 356}},
}

local function ByName(lines)
	local sorted = {}
	for i, line in ipairs(lines) do
		sorted[i] = line
	end
	table.sort(sorted, function(a, b)
		return (SP.skillName[a] or "") < (SP.skillName[b] or "")
	end)
	return sorted
end

local function AddTitle(text, level)
	local info = UIDropDownMenu_CreateInfo()
	info.text = text
	info.isTitle = true
	info.notCheckable = true
	UIDropDownMenu_AddButton(info, level)
end

local function AddProfession(line, profs, level)
	local info = UIDropDownMenu_CreateInfo()
	local p = profs[line]
	info.text = (SP.skillName[line] or "?") .. (p and format(" |cffaaaaaa(%d)|r", p.rank) or "")
	info.value = line
	info.checked = line == selected
	info.func = function()
		Select(line)
		CloseDropDownMenus()
	end
	UIDropDownMenu_AddButton(info, level)
end

-- Level 1: your professions, then the groups; level 2: all professions of a group
local function InitDropdown(_, level)
	level = level or 1
	local profs = SP:GetProfessions()
	if level == 1 then
		local mine = {}
		for _, group in ipairs(GROUPS) do
			for _, line in ipairs(group.lines) do
				if profs[line] then
					mine[#mine + 1] = line
				end
			end
		end
		if #mine > 0 then
			AddTitle(L["Your professions"], level)
			for _, line in ipairs(ByName(mine)) do
				AddProfession(line, profs, level)
			end
		end
		AddTitle(L["All professions"], level)
		for _, group in ipairs(GROUPS) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = L[group.name]
			info.value = group.key
			info.hasArrow = true
			info.notCheckable = true
			UIDropDownMenu_AddButton(info, level)
		end
	elseif level == 2 then
		for _, group in ipairs(GROUPS) do
			if group.key == UIDROPDOWNMENU_MENU_VALUE then
				for _, line in ipairs(ByName(group.lines)) do
					AddProfession(line, profs, level)
				end
			end
		end
	end
end

-- Frame -----------------------------------------------------------------------------------

local function CreateMainFrame()
	frame = CreateFrame("Frame", "SkillPathFrame", UIParent)
	frame:SetWidth(WIDTH)
	frame:SetHeight(HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	Backdrop(frame)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "SkillPathFrame")

	local title = Label(frame, "SkillPath", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -18)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	dropdown = CreateFrame("Frame", "SkillPathDropDown", frame, "UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT", 4, -40)
	UIDropDownMenu_SetWidth(dropdown, 150)
	UIDropDownMenu_Initialize(dropdown, InitDropdown)

	status = Label(frame, "", "GameFontNormal")
	status:SetPoint("LEFT", dropdown, "RIGHT", -6, 2)

	vendorCheck = CreateFrame("CheckButton", "SkillPathVendorCheck", frame, "UICheckButtonTemplate")
	vendorCheck:SetWidth(24)
	vendorCheck:SetHeight(24)
	vendorCheck:SetPoint("TOPLEFT", 20, -72)
	_G["SkillPathVendorCheckText"]:SetText(L["Use vendor recipes"])
	vendorCheck:SetScript("OnClick", function(self)
		SkillPathDB.options.vendorRecipes = self:GetChecked() and true or false
		SP:Refresh()
	end)
	vendorCheck:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Also plan recipes you can buy from vendors (the recipe to buy is shown in the tooltip)."], nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	vendorCheck:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local routeLabel = Label(frame, L["Route"], "GameFontNormal")
	routeLabel:SetPoint("TOPLEFT", 22, -102)
	routeScroll = CreateFrame("ScrollFrame", "SkillPathRouteScroll", frame, "FauxScrollFrameTemplate")
	routeScroll:SetPoint("TOPLEFT", routeLabel, "BOTTOMLEFT", 0, -4)
	routeScroll:SetPoint("RIGHT", frame, "RIGHT", -38, 0)
	routeScroll:SetHeight(ROUTE_ROWS * ROW_HEIGHT)
	routeScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateRoute)
	end)
	for i = 1, ROUTE_ROWS do
		local row = CreateRow(frame, i, routeLabel)
		row:SetFrameLevel(routeScroll:GetFrameLevel() + 2)
		-- book: the recipe still has to be learned (tooltip says where)
		local book = CreateFrame("Button", nil, row)
		book:SetWidth(14)
		book:SetHeight(14)
		book:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
		book:SetFrameLevel(row:GetFrameLevel() + 1)
		book.icon = book:CreateTexture(nil, "ARTWORK")
		book.icon:SetAllPoints()
		book:SetScript("OnEnter", ShowSourceTooltip)
		book:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		book:Hide()
		row.book = book
		routeRows[i] = row
	end

	matLabel = Label(frame, L["Materials for the rest of the route"], "GameFontNormal")
	matLabel:SetPoint("TOPLEFT", routeLabel, "BOTTOMLEFT", 0, -(ROUTE_ROWS * ROW_HEIGHT + 16))
	matScroll = CreateFrame("ScrollFrame", "SkillPathMatScroll", frame, "FauxScrollFrameTemplate")
	matScroll:SetPoint("TOPLEFT", matLabel, "BOTTOMLEFT", 0, -4)
	matScroll:SetPoint("RIGHT", frame, "RIGHT", -38, 0)
	matScroll:SetHeight(MAT_ROWS * ROW_HEIGHT)
	matScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateMaterials)
	end)
	for i = 1, MAT_ROWS do
		local row = CreateRow(frame, i, matLabel)
		row:SetFrameLevel(matScroll:GetFrameLevel() + 2)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, button)
			if not self.item then
				return
			end
			if button == "RightButton" and not self.gatherRow then
				SP:ToggleAvoid(self.item, selected)
				SP:Refresh()
				ShowMaterialTooltip(self)
			elseif IsModifiedClick("CHATLINK") then
				local link = select(2, GetItemInfo(self.item))
				if link then
					ChatEdit_InsertLink(link)
				end
			end
		end)
		-- visible button to avoid the material (right-click on the row does the same)
		local avoid = CreateFrame("Button", nil, row)
		avoid:SetWidth(14)
		avoid:SetHeight(14)
		avoid:SetPoint("RIGHT", row, "RIGHT", -2, 0)
		avoid:SetFrameLevel(row:GetFrameLevel() + 1)
		-- own texture object, switched between the avoid and the undo icon
		avoid.icon = avoid:CreateTexture(nil, "ARTWORK")
		avoid.icon:SetAllPoints()
		avoid.icon:SetTexture(AVOID_ICON)
		avoid:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		avoid:SetScript("OnClick", function()
			if row.item and not row.gatherRow then
				SP:ToggleAvoid(row.item, selected)
				SP:Refresh()
			end
		end)
		avoid:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if row.item and SP:IsAvoided(row.item, selected) then
				GameTooltip:SetText(L["Use this material again"])
			else
				GameTooltip:SetText(L["Avoid this material"])
				GameTooltip:AddLine(L["The route is recalculated without it where possible."], 1, 1, 1, true)
				GameTooltip:AddLine(L["Only for this profession."], 0.7, 0.7, 0.7)
			end
			GameTooltip:Show()
		end)
		avoid:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row.avoidButton = avoid
		row.right:ClearAllPoints()
		row.right:SetPoint("RIGHT", avoid, "LEFT", -4, 0)
		-- yellow "!" for avoided materials the route still needs
		row.warn = row:CreateTexture(nil, "OVERLAY")
		row.warn:SetWidth(14)
		row.warn:SetHeight(14)
		row.warn:SetPoint("RIGHT", row.right, "LEFT", -2, 0)
		row.warn:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
		row.warn:Hide()
		matRows[i] = row
	end

	hintLabel = Label(frame, "", "GameFontDisableSmall")
	hintLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 16)

	priceLabel = Label(frame, "", "GameFontDisableSmall")
	priceLabel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 16)

	frame:SetScript("OnShow", function()
		vendorCheck:SetChecked(SkillPathDB.options.vendorRecipes)
		SP:ClearPrices()
		SP:Refresh()
		SP:UpdateTradeSkillTab()
	end)
	frame:SetScript("OnHide", function()
		SP:UpdateTradeSkillTab()
	end)
	frame:SetScript("OnUpdate", function(_, elapsed)
		sinceRefresh = sinceRefresh + elapsed
		if dirty and sinceRefresh > 0.5 then
			SP:Refresh()
		end
	end)
end

-- Opens the window; line = profession to show (default: the first one the player has)
function SP:Show(line)
	if not frame then
		CreateMainFrame()
	end
	if not line and not selected then
		local profs = SP:GetProfessions()
		for _, l in ipairs(SP.skillOrder) do
			if profs[l] then
				line = l
				break
			end
		end
		line = line or SP.skillOrder[1]
	end
	frame:Show()
	if line then
		Select(line)
	end
end

function SP:Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		SP:Show()
	end
end

-- Profession window --------------------------------------------------------------------
-- Tabs on the right edge (like the skill line tabs of the spellbook): SkillPath itself and
-- "select the recommended recipe". The recommended recipe is also marked in the list.

local TAB_ICON = "Interface\\Icons\\INV_Scroll_06" -- scroll with quill: a written guide
local SELECT_ICON = "Interface\\Icons\\Ability_Hunter_SniperShot" -- crosshair: pick the recipe
local MARK_ICON = "Interface\\Icons\\INV_Scroll_06"

-- Skins like ElvUI replace the window art with a backdrop: then the tabs sit right at the
-- backdrop's edge and get a plain border instead of the spellbook tab art.
local function StyleTab(tab, skinned)
	if skinned then
		tab.background:Hide()
		tab:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
		if not tab.skinned and tab.SetTemplate then
			pcall(tab.SetTemplate, tab, "Default")
			tab.skinned = true
		end
	else
		tab.background:Show()
	end
end

local function PlaceTradeSkillTabs()
	local tab, selectTab = SP.tradeSkillTab, SP.selectTab
	local skin = TradeSkillFrame.backdrop or (TradeSkillFrame.template and TradeSkillFrame)
	tab:ClearAllPoints()
	if skin then
		tab:SetPoint("TOPLEFT", skin, "TOPRIGHT", 2, -40)
	else
		tab:SetPoint("TOPLEFT", TradeSkillFrame, "TOPRIGHT", -33, -65)
	end
	selectTab:ClearAllPoints()
	selectTab:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", 0, skin and -6 or -17)
	StyleTab(tab, skin)
	StyleTab(selectTab, skin)
end

function SP:UpdateTradeSkillTab()
	local tab = SP.tradeSkillTab
	if tab then
		tab:SetChecked(frame and frame:IsShown() and 1 or nil)
	end
end

local function CreateTab(name, icon, checkable)
	local tab = CreateFrame(checkable and "CheckButton" or "Button", name, TradeSkillFrame)
	tab:SetWidth(32)
	tab:SetHeight(32)
	tab.background = tab:CreateTexture(nil, "BACKGROUND")
	tab.background:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
	tab.background:SetWidth(64)
	tab.background:SetHeight(64)
	tab.background:SetPoint("TOPLEFT", -3, 11)
	tab:SetNormalTexture(icon)
	tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	if checkable then
		tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")
	end
	tab:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return tab
end

-- Recommendation for the open profession window. The window can only show recipes the
-- character knows: if the recipe of the current route step is not learned yet, the best
-- known recipe that still gives points is recommended instead, and the planned one is named
-- in the tooltips. Cached until the skill, the known recipes or the options change
-- (TradeSkillFrame_Update runs on every scroll).
local recommendCache, recommendKey
SP.recommendVersion = 0

local function StepAt(steps, skill)
	for _, step in ipairs(steps) do
		if skill >= step.from and skill < step.to then
			return step
		end
	end
end

local function Remaining(step, skill)
	return math.ceil(step.crafts * (step.to - skill) / (step.to - step.from))
end

-- Returns {planned = route recipe, spell/recipe/crafts/to = what to craft now (nil if no
-- known recipe gives points), substitute = true if that is not the planned recipe}
function SP:Recommended()
	local name, skill = GetTradeSkillLine()
	local line = name and SP.nameToSkill[name]
	if not line or (SP.Gather and SP.Gather.IsGather(line)) or not skill or skill <= 0 then
		return nil
	end
	local key = line .. ":" .. skill .. ":" .. SP.recommendVersion .. ":" .. tostring(SkillPathDB.options.vendorRecipes)
	if key ~= recommendKey then
		recommendKey, recommendCache = key, false
		local route = StepAt(SP:Plan(line, skill), skill)
		if route then
			local planned = route.recipe
			local rec = {planned = planned}
			if not LearnHint(planned) then
				rec.spell, rec.recipe, rec.crafts, rec.to = planned[F.SPELL], planned, Remaining(route, skill), route.to
			else
				local alt = StepAt(SP:Plan(line, skill, true, route.to), skill)
				if alt then
					rec.spell, rec.recipe = alt.recipe[F.SPELL], alt.recipe
					rec.crafts, rec.to, rec.substitute = Remaining(alt, skill), alt.to, true
				end
			end
			recommendCache = rec
		end
	end
	return recommendCache or nil
end

-- Tooltip lines about the planned recipe when it is not learned yet
local function AddPlannedLines(rec)
	if rec.spell and not rec.substitute then
		return
	end
	local hint = LearnHint(rec.planned)
	GameTooltip:AddLine(format(L["The route plans %s - not learned yet."], SP:RecipeName(rec.planned[F.SPELL])), 1, 0.5, 0.25, true)
	if hint then
		GameTooltip:AddLine(hint, 0.6, 0.8, 1, true)
	end
	if rec.substitute then
		GameTooltip:AddLine(L["Until then this is your best known recipe."], 0.7, 0.7, 0.7, true)
	end
end

local function RecipeSpell(index)
	local link = GetTradeSkillRecipeLink(index)
	return link and tonumber(link:match("enchant:(%d+)"))
end

local function ShowMarkTooltip(mark)
	local rec = SP:Recommended()
	if not (rec and rec.spell) then
		return
	end
	GameTooltip:SetOwner(mark, "ANCHOR_RIGHT")
	GameTooltip:SetText(L["Recommended by SkillPath"])
	GameTooltip:AddLine(format(L["About %d more crafts up to skill %d."], rec.crafts, rec.to), 1, 1, 1)
	AddPlannedLines(rec)
	GameTooltip:Show()
end

-- Marks the recommended recipe in the visible rows of the profession window
local function UpdateTradeSkillMarks()
	local rec = SP:Recommended()
	for i = 1, TRADE_SKILLS_DISPLAYED or 8 do
		local button = _G["TradeSkillSkill" .. i]
		if button then
			local mark = button.skillPathMark
			if not mark then
				mark = CreateFrame("Button", nil, button)
				mark:SetWidth(14)
				mark:SetHeight(14)
				mark:SetPoint("RIGHT", button, "RIGHT", -2, 0)
				mark:SetFrameLevel(button:GetFrameLevel() + 2)
				local icon = mark:CreateTexture(nil, "OVERLAY")
				icon:SetAllPoints()
				icon:SetTexture(MARK_ICON)
				mark:SetScript("OnEnter", ShowMarkTooltip)
				mark:SetScript("OnLeave", function()
					GameTooltip:Hide()
				end)
				button.skillPathMark = mark
			end
			local index = button:IsShown() and button:GetID()
			if rec and rec.spell and index and index > 0 and RecipeSpell(index) == rec.spell then
				mark:Show()
			else
				mark:Hide()
			end
		end
	end
end

-- Selects the recommended recipe, scrolls to it and enters the number of crafts. Filters
-- and the search box may hide it; then they are reset.
local function FindRecipe(spell)
	for index = 1, GetNumTradeSkills() do
		local _, kind = GetTradeSkillInfo(index)
		if kind ~= "header" and RecipeSpell(index) == spell then
			return index
		end
	end
end

local function ResetTradeSkillFilters()
	if TradeSkillFrameEditBox then
		TradeSkillFrameEditBox:SetText("")
	end
	if SetTradeSkillItemNameFilter then
		SetTradeSkillItemNameFilter(nil)
	end
	if TradeSkillOnlyShowMakeable then
		TradeSkillOnlyShowMakeable(false)
		if TradeSkillFrameAvailableFilterCheckButton then
			TradeSkillFrameAvailableFilterCheckButton:SetChecked(false)
		end
	end
	if SetTradeSkillSubClassFilter then
		SetTradeSkillSubClassFilter(0, 1, 1)
	end
	if SetTradeSkillInvSlotFilter then
		SetTradeSkillInvSlotFilter(0, 1, 1)
	end
	ExpandTradeSkillSubClass(0)
end

local function SelectRecommended()
	local rec = SP:Recommended()
	if not rec then
		UIErrorsFrame:AddMessage(L["SkillPath has no recommendation for this profession at your skill."], 1, 0.82, 0)
		return
	end
	if not rec.spell then
		-- no known recipe gives points: say what to learn
		local hint = LearnHint(rec.planned)
		UIErrorsFrame:AddMessage(format(L["%s is not learned yet."], SP:RecipeName(rec.planned[F.SPELL]))
			.. (hint and (" " .. hint) or ""), 1, 0.82, 0)
		return
	end
	local index = FindRecipe(rec.spell)
	if not index then
		ResetTradeSkillFilters()
		index = FindRecipe(rec.spell)
	end
	if not index then
		UIErrorsFrame:AddMessage(format(L["%s is not learned yet."], SP:RecipeName(rec.spell)), 1, 0.82, 0)
		return
	end
	TradeSkillFrame_SetSelection(index)
	local offset = math.max(0, index - 1)
	FauxScrollFrame_SetOffset(TradeSkillListScrollFrame, offset)
	TradeSkillListScrollFrameScrollBar:SetValue(offset * (TRADE_SKILL_HEIGHT or 16))
	TradeSkillFrame_Update()
	if TradeSkillInputBox then
		TradeSkillInputBox:SetNumber(math.max(1, rec.crafts))
	end
end

function SP:AttachTradeSkillButton()
	if SP.tradeSkillTab or not TradeSkillFrame then
		return
	end
	local tab = CreateTab("SkillPathTradeSkillTab", TAB_ICON, true)
	tab:SetScript("OnClick", function()
		if frame and frame:IsShown() then
			frame:Hide()
		else
			local name = GetTradeSkillLine()
			SP:Show(name and SP.nameToSkill[name])
		end
		SP:UpdateTradeSkillTab()
	end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("SkillPath")
		GameTooltip:AddLine(L["Opens SkillPath for this profession."], 1, 1, 1)
		GameTooltip:Show()
	end)
	SP.tradeSkillTab = tab

	local selectTab = CreateTab("SkillPathSelectTab", SELECT_ICON, false)
	selectTab:SetScript("OnClick", SelectRecommended)
	selectTab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Select recommended recipe"])
		local rec = SP:Recommended()
		if rec and rec.spell then
			GameTooltip:AddLine(format("%s: %s", SP:RecipeName(rec.spell), format(L["about %d crafts"], rec.crafts)), 1, 1, 1)
		end
		if rec then
			AddPlannedLines(rec)
		end
		GameTooltip:AddLine(L["Selects the recipe SkillPath recommends at your skill and enters the number of crafts."], 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	SP.selectTab = selectTab

	-- skins are applied when the window is first shown, so place the tabs on every show
	TradeSkillFrame:HookScript("OnShow", function()
		PlaceTradeSkillTabs()
		SP:UpdateTradeSkillTab()
	end)
	PlaceTradeSkillTabs()
	hooksecurefunc("TradeSkillFrame_Update", UpdateTradeSkillMarks)
end
