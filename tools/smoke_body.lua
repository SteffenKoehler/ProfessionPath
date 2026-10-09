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
table.sort(SP.skillOrder)

assert(SP:ScanTradeSkill() == 197, "scan should map tailoring")
assert(SP:Char().known[3915], "known recipe stored")

local profs = SP:GetProfessions()
assert(profs[197] and profs[197].rank == 120, "tailoring rank")

for _, line in ipairs(SP.skillOrder) do
	SP:Show(line)
	SP:Refresh()
	local steps, reached = SP:Plan(line, 1)
	print(string.format("skill %d: %d steps, reached %d", line, #steps, reached))
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
SP:ToggleAvoid(19441) -- Huge Venom Sac
local after = SP:Plan(129, 300)
for _, step in ipairs(after) do
	for i = 11, #step.recipe, 2 do
		assert(step.recipe[i] ~= 19441, "avoided material still planned")
	end
end
SP:ToggleAvoid(19441)
assert(not SkillPathDB.avoid[19441], "avoid toggled back")
SP:Refresh()
print("price checks ok")
