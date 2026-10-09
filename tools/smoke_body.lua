-- Executed by smoke_test.py after the addon files are loaded.
local SP = SkillPath

-- the event frame is the first frame Core.lua created; trigger its handler via the events
-- the addon listens to by calling the same functions it would call
SP.skillName, SP.nameToSkill, SP.skillOrder = {}, {}, {}
for line, spell in pairs(SkillPathData.skills) do
	local name = GetSpellInfo(spell)
	SP.skillName[line] = name
	SP.nameToSkill[name] = line
	SP.skillOrder[#SP.skillOrder + 1] = line
end
for _, line in ipairs({182, 393, 356}) do
	SP.skillName[line] = "Gather" .. line
	SP.skillOrder[#SP.skillOrder + 1] = line
end
table.sort(SP.skillOrder)

assert(SP:ScanTradeSkill() == 197, "scan should map tailoring")
assert(SP:Char().known[3915], "known recipe stored")

local profs = SP:GetProfessions()
assert(profs[197] and profs[197].rank == 120, "tailoring rank")

for _, line in ipairs(SP.skillOrder) do
	SP:Show(line)
	SP:Refresh()
	if not SP.Gather.IsGather(line) then
		local steps, reached = SP:Plan(line, 1)
		print(string.format("skill %d: %d steps, reached %d", line, #steps, reached))
	end
end
SP:Toggle()
SP:Toggle()
SP:OnDataChanged(197)
SP:Refresh()

-- prices: vendor reagent uses the vendor price, others an estimate; avoiding changes the route
local thread = 2320
assert(SP:Price(thread) == SkillPathData.vendor[thread], "vendor price")
local price, source = SP:Price(14047)
assert(price > 0 and source == "estimate", "estimate for runecloth")
local before = SP:Plan(129, 300)
SP:ToggleAvoid(19441, 129) -- Huge Venom Sac, in First Aid only
local after = SP:Plan(129, 300)
for _, step in ipairs(after) do
	for i = 11, #step.recipe, 2 do
		assert(step.recipe[i] ~= 19441, "avoided material still planned")
	end
end
assert(not SP:IsAvoided(19441, 185), "avoiding is per profession")
SP:ToggleAvoid(19441, 129)
assert(not SP:IsAvoided(19441, 129), "avoid toggled back")
SP:Refresh()
print("price checks ok")

-- regression: cheap Small Venom Sacs must not lead to ~245 green Anti-Venom crafts at 132
do
	local prices = {[1475] = 5, [2592] = 3000}  -- like the user's auction house: sacs free, wool expensive
	local opts = {cooldown = SkillPathData.cooldown, known = {}, vendorRecipes = true, raceBit = 1,
		price = function(item) return prices[item] or SkillPath.Planner.EstimatePrice(item, SkillPathData) end}
	local steps = SkillPath.Planner.Plan(SkillPathData.recipes[129], 132, 150, opts)
	local crafts = 0
	for _, step in ipairs(steps) do
		crafts = crafts + step.crafts
		print(string.format("  first aid %d-%d spell %d x%d", step.from, step.to, step.recipe[1], step.crafts))
	end
	assert(crafts < 60, "too many crafts for 132-150: " .. crafts)
end
print("effort check ok")

-- gathering: every profession plans to 450 for a level 80 character of both factions
for _, line in ipairs({182, 186, 393}) do
	for _, faction in ipairs({2, 4}) do
		local steps, reached = SP.Gather.Plan(line, 1, 450, {level = 80, faction = faction})
		assert(reached == 450, "gathering " .. line .. " stops at " .. reached)
	end
end
local fish = SP.Gather.PlanFishing(1, 450, {level = 80, faction = 2})
assert(#fish == 6 and #fish[1].areas > 0, "fishing bands")
print("gathering ok")

-- zone names come from the world map by map file name (Howling Fjord = area 495)
assert(SP.Gather.ZoneName(495) == "Heulender Fjord", "zone name by map file: " .. SP.Gather.ZoneName(495))
print("zone names ok")

-- still needed check: avoid every material of First Aid 150-210 and refresh the window
SP:Show(129)
for _, r in ipairs(SkillPathData.recipes[129]) do
	for i = 11, #r, 2 do
		if not SP:IsAvoided(r[i], 129) then SP:ToggleAvoid(r[i], 129) end
	end
end
SP:Refresh()
SkillPathDB.avoided[129] = nil
SP:Refresh()
print("still needed ok")

-- book check: route rows with unknown recipes refresh without errors
SP:Char().known = {}
SP:Show(185)
SP:Refresh()
print("book ok")

-- profession window check: tabs, marks in the recipe list, select button
TradeSkillFrame = CreateFrame("Frame", "TradeSkillFrame")
TRADE_SKILLS_DISPLAYED = 2
CreateFrame("Button", "TradeSkillSkill1")
CreateFrame("Button", "TradeSkillSkill2")
for _, name in ipairs({"TradeSkillListScrollFrame", "TradeSkillListScrollFrameScrollBar", "TradeSkillInputBox", "UIErrorsFrame"}) do
	CreateFrame("Frame", name)
end
local hooks = {}
hooksecurefunc = function(name, f) hooks[name] = f end
TradeSkillFrame_SetSelection = function() end
TradeSkillFrame_Update = function() end
ExpandTradeSkillSubClass = function() end
SP:AttachTradeSkillButton()
assert(SP.tradeSkillTab and SP.selectTab, "tabs created")
hooks.TradeSkillFrame_Update()
local rec = SP:Recommended()
assert(rec and rec.planned and not rec.spell, "nothing known: planned recipe only")
SP.selectTab:GetScript("OnClick")()
print("profession window ok", rec.planned[1])

-- substitute check: route recipe unknown -> best known recipe in the profession window
SP:Char().known = {[2963] = true, [2402] = true} -- Bolt of Linen Cloth, Woolen Cape (green at 120)
SP.recommendVersion = SP.recommendVersion + 1
local sub = SP:Recommended()
assert(sub and sub.planned, "planned recipe")
print("substitute", sub.planned[1], sub.spell, sub.substitute)
assert(sub.spell == 2402 and sub.substitute, "best known recipe instead of the unknown planned one")
SP.selectTab:GetScript("OnClick")()
SP.selectTab:GetScript("OnEnter")(SP.selectTab)
print("substitute ok")
