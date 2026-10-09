# Print gathering routes outside the game. Usage: test_gather.py <skill line> [level] [faction 2/4] [from]
import os, sys
from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from build_data import sql_rows

line = int(sys.argv[1]) if len(sys.argv) > 1 else 182
level = int(sys.argv[2]) if len(sys.argv) > 2 else 80
faction = int(sys.argv[3]) if len(sys.argv) > 3 else 2
start = int(sys.argv[4]) if len(sys.argv) > 4 else 1

lua = lupa.LuaRuntime()
lua.execute("GetLocale = function() return 'deDE' end")
addon = os.path.join(HERE, "..", "SkillPath")
for f in ("GatherData.lua", "Gather.lua"):
    lua.execute(open(os.path.join(addon, f), encoding="utf-8").read())

items = {}
wanted = set()
for nodes in (lua.eval("SkillPathGather.nodes[%d]" % line) or {}).values():
    for i in range(1, len(nodes) + 1, 3):
        wanted.add(nodes[i])
if wanted:
    for row in sql_rows("item_template.sql", "item_template"):
        if row[0] in wanted:
            items[row[0]] = row[4]

G = lua.eval("SkillPath.Gather")
opts = lua.table_from({"level": level, "faction": faction})
if line == 356:
    steps, reached = G.PlanFishing(start, 450, opts)
    for i in range(1, len(steps) + 1):
        st = steps[i]
        zones = ", ".join(G.ZoneName(st.areas[j]) for j in range(1, len(st.areas) + 1))
        print("%3d-%3d  ~%4d catches  %s" % (st["from"], st.to, st.catches, zones))
else:
    steps, reached = G.Plan(line, start, 450, opts)
    for i in range(1, len(steps) + 1):
        st = steps[i]
        contents = G.ZoneContents(line, st.area, st["from"], st.to)
        what = []
        for j in range(1, len(contents) + 1):
            c = contents[j]
            if c.item:
                what.append("%s(%d)x%d" % (items.get(c.item, c.item), c.req, c.count))
            else:
                what.append("beasts %d-%d x%d" % (c.minLevel, c.maxLevel, c.count))
        print("%3d-%3d  ~%4d  %-28s L%-2d  %s" % (st["from"], st.to, st.gathers, G.ZoneName(st.area),
                                                G.ZoneLevel(st.area), ", ".join(what)))
print("reached", reached)
