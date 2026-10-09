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
