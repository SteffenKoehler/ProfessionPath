# Run the planner outside the game (LuaJIT via lupa) and print routes with German names
# from Spell.dbc. Usage: test_planner.py <skill line> [from] [to] [raceBit]
import os, sys
from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dbc import DBC

skill = int(sys.argv[1]) if len(sys.argv) > 1 else 129
start = int(sys.argv[2]) if len(sys.argv) > 2 else 1
goal = int(sys.argv[3]) if len(sys.argv) > 3 else 450
race = int(sys.argv[4]) if len(sys.argv) > 4 else 1   # human

names = {}
sp = DBC(os.path.join(HERE, "dbc", "Spell.dbc"))
for row in sp.rows():
    for slot in range(136, 152):
        if row[slot]:
            names[row[0]] = sp.string(row[slot])
            break

lua = lupa.LuaRuntime()
addon = os.path.join(HERE, "..", "ProfessionPath")
for f in ("Data.lua", "Planner.lua"):
    lua.execute(open(os.path.join(addon, f), encoding="utf-8").read())
run = lua.eval("""function(skill, from, to, race)
    local opts = {cooldown = ProfessionPathData.cooldown, known = {}, vendorRecipes = true, raceBit = race,
        price = function(item) return ProfessionPath.Planner.EstimatePrice(item, ProfessionPathData) end}
    local steps, reached = ProfessionPath.Planner.Plan(ProfessionPathData.recipes[skill], from, to, opts)
    local out = {}
    for i, st in ipairs(steps) do
        out[i] = {st.recipe[1], st.from, st.to, st.crafts, st.recipe[3], st.recipe[4], st.recipe[5], st.recipe[2]}
    end
    return out, reached
end""")
steps, reached = run(skill, start, goal, race)
total = 0
for i in range(1, len(steps) + 1):
    s = steps[i]
    total += s[4]
    src = {1: "auto", 2: "trainer", 3: "other", 4: "VENDOR"}[s[8]]
    print("%3d-%3d  %3dx  %-40s (learn %d, yellow %d, grey %d, %s)" % (s[2], s[3], s[4], names.get(s[1], s[1]), s[5], s[6], s[7], src))
print("reached", reached, "crafts", total)
