-- SkillPath window: profession selection, route with rank notes, materials with bag counts.

SkillPath = SkillPath or {}
local SP = SkillPath
local L = SP.L
local Planner = SP.Planner
local Data = SkillPathData
local F = Planner.FIELDS

local WIDTH, HEIGHT = 440, 520
local ROW_HEIGHT = 18
local ROUTE_ROWS, MAT_ROWS = 13, 7
local COLORS = {orange = "ff8040", yellow = "ffff00", green = "40bf40", grey = "808080"}

local frame, routeScroll, matScroll, dropdown, status, vendorCheck
local routeRows, matRows = {}, {}
local entries, materials = {}, {}
local selected, rank = nil, 0
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
	local source = r[F.SOURCE]
	if source == Planner.SOURCE_TRAINER then
		GameTooltip:AddLine(format(L["Learn at trainer from %d (%s)"], r[F.LEARN], GetCoinTextureString(r[F.COST])), 0.6, 0.8, 1)
	elseif Data.recipeItem[r[F.SPELL]] and not SP:Char().known[r[F.SPELL]] then
		local name = SP:ItemName(Data.recipeItem[r[F.SPELL]])
		local text = source == Planner.SOURCE_VENDOR and L["Buy recipe: %s"] or L["Recipe needed: %s"]
		GameTooltip:AddLine(format(text, name), 1, 0.5, 0.25)
	end
	GameTooltip:Show()
end

local function ShowItemTooltip(row)
	if row.item then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. row.item)
		GameTooltip:Show()
	end
end

-- Data ------------------------------------------------------------------------------------

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

	if info and not (SP:Char().scanned or {})[selected] then
		entries[#entries + 1] = {note = L["Open the profession window once so SkillPath knows your recipes."], color = "ff8040"}
	end

	local steps, reached = SP:Plan(selected, rank)
	local nextRank = 1
	for _, step in ipairs(steps) do
		-- rank notes before the step that goes past the next cap
		while SP.RANKS[nextRank] and step.to > SP.RANKS[nextRank].cap do
			local r = SP.RANKS[nextRank]
			if maxRank <= r.cap then
				entries[#entries + 1] = {note = format(L["Learn %s at your trainer (skill %d, level %d) - needed to go past %d."],
					L[r.name], r.skill, r.level, r.cap), color = "66ccff"}
			end
			nextRank = nextRank + 1
		end
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

	for item, count in pairs(Planner.Materials(steps, rank)) do
		if count > 0 then
			materials[#materials + 1] = {item = item, need = count, have = GetItemCount(item, true)}
		end
	end
	table.sort(materials, function(a, b)
		return a.need > b.need
	end)
end

local function UpdateRoute()
	local offset = FauxScrollFrame_GetOffset(routeScroll)
	for i, row in ipairs(routeRows) do
		local entry = entries[offset + i]
		row.entry = entry
		row.item = nil
		row.highlight:Hide()
		row:SetScript("OnEnter", nil)
		if not entry then
			row:Hide()
		else
			row:Show()
			row.right:SetText("")
			if entry.note then
				row.icon:SetTexture(nil)
				row.text:SetText("|cff" .. entry.color .. entry.note .. "|r")
			elseif entry.recipe then
				local r = entry.recipe
				local spell = r[F.SPELL]
				local itemName = SP:ItemName(Data.recipeItem[spell])
				row.icon:SetTexture(SP:ItemIcon(Data.recipeItem[spell]))
				row.text:SetText(format("  %s", itemName))
				row.right:SetText(format("|cff808080%d-%d|r", r[F.LEARN], r[F.GREY]))
				row.item = Data.recipeItem[spell]
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
		if not m then
			row:Hide()
		else
			row:Show()
			local name, color = SP:ItemName(m.item)
			row.item = m.item
			row.icon:SetTexture(SP:ItemIcon(m.item))
			row.text:SetText(color and (color.hex .. name .. "|r") or name)
			local ok = m.have >= m.need
			row.right:SetText(format("|cff%s%s|r", ok and "40bf40" or "ffffff", format(L["have %d / need %d"], m.have, m.need)))
			row:SetScript("OnEnter", ShowItemTooltip)
		end
	end
	FauxScrollFrame_Update(matScroll, #materials, MAT_ROWS, ROW_HEIGHT)
end

function SP:Refresh()
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

local function InitDropdown()
	local profs = SP:GetProfessions()
	for _, line in ipairs(SP.skillOrder) do
		local info = UIDropDownMenu_CreateInfo()
		local p = profs[line]
		info.text = (SP.skillName[line] or "?") .. (p and format(" |cffaaaaaa(%d)|r", p.rank) or "")
		info.value = line
		info.checked = line == selected
		info.func = function()
			Select(line)
		end
		UIDropDownMenu_AddButton(info)
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
		routeRows[i] = CreateRow(frame, i, routeLabel)
		routeRows[i]:SetFrameLevel(routeScroll:GetFrameLevel() + 2)
	end

	local matLabel = Label(frame, L["Materials for the rest of the route"], "GameFontNormal")
	matLabel:SetPoint("TOPLEFT", routeLabel, "BOTTOMLEFT", 0, -(ROUTE_ROWS * ROW_HEIGHT + 16))
	matScroll = CreateFrame("ScrollFrame", "SkillPathMatScroll", frame, "FauxScrollFrameTemplate")
	matScroll:SetPoint("TOPLEFT", matLabel, "BOTTOMLEFT", 0, -4)
	matScroll:SetPoint("RIGHT", frame, "RIGHT", -38, 0)
	matScroll:SetHeight(MAT_ROWS * ROW_HEIGHT)
	matScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateMaterials)
	end)
	for i = 1, MAT_ROWS do
		matRows[i] = CreateRow(frame, i, matLabel)
		matRows[i]:SetFrameLevel(matScroll:GetFrameLevel() + 2)
	end

	frame:SetScript("OnShow", function()
		vendorCheck:SetChecked(SkillPathDB.options.vendorRecipes)
		SP:Refresh()
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

-- Button in the profession window
function SP:AttachTradeSkillButton()
	if SP.tradeSkillButton or not TradeSkillFrame then
		return
	end
	local button = CreateFrame("Button", "SkillPathTradeSkillButton", TradeSkillFrame, "UIPanelButtonTemplate")
	button:SetWidth(80)
	button:SetHeight(20)
	button:SetText("SkillPath")
	button:SetPoint("TOPRIGHT", TradeSkillFrame, "TOPRIGHT", -40, -44)
	button:SetScript("OnClick", function()
		local name = GetTradeSkillLine()
		SP:Show(name and SP.nameToSkill[name])
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Opens SkillPath for this profession."])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	SP.tradeSkillButton = button
end
