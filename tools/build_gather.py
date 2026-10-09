# Builds ProfessionPath/GatherData.lua: where to gather at which skill (Herbalism, Mining,
# Skinning, Fishing). Sources: client DBCs (Lock, AreaTable, WorldMapArea) and the
# AzerothCore spawn/template/loot/fishing tables (GPL-2.0). IDs and numbers only; zone
# and item names come from the game client at runtime.
import os, sys, statistics
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dbc import DBC
from build_data import sql_rows

DBC_DIR = os.path.join(HERE, "dbc")
OUT = os.path.join(HERE, "..", "ProfessionPath", "GatherData.lua")

HERBALISM, MINING, SKINNING, FISHING = 182, 186, 393, 356
LOCK_KEY_SKILL = 2
LOCKTYPE = {2: HERBALISM, 3: MINING}
GO_TYPE_CHEST = 3
ITEM_CLASS_TRADE_GOODS = 7

# creature_template.type_flags: skinned with Herbalism / Mining / Engineering instead
TYPE_FLAG_OTHER_SKINNING = 0x100 | 0x200 | 0x8000
CREATURE_TYPE_CRITTER = 8
MAPS = (0, 1, 530, 571)  # Eastern Kingdoms, Kalimdor, Outland, Northrend


def zones_from_dbc():
    """AreaTable: area -> (zone, map, faction); WorldMapArea: zone -> (world map id, bounds)."""
    area = DBC(os.path.join(DBC_DIR, "AreaTable.dbc"))
    parent, info = {}, {}
    for row in area.rows():
        parent[row[0]] = row[2]
        # name in the language of the client the DBCs come from (deDE slot = 3)
        name = area.string(row[11 + 3]) if row[11 + 3] else ""
        info[row[0]] = {"map": row[1], "faction": row[28], "name": name, "key": ""}
    wma = DBC(os.path.join(DBC_DIR, "WorldMapArea.dbc"))
    worldmap, bounds = {}, []
    for i, row in enumerate(wma.rows()):
        zone = row[2]
        if zone and row[1] in MAPS:
            f = wma.float_row(i)
            worldmap[zone] = row[0]
            info[zone]["key"] = wma.string(row[3])  # internal English map name, e.g. BoreanTundra
            bounds.append((row[1], zone, f[4], f[5], f[6], f[7]))
    return parent, info, worldmap, bounds


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    parent, info, worldmap, bounds = zones_from_dbc()

    def top_zone(area):
        seen = 0
        while parent.get(area) and seen < 5:
            area, seen = parent[area], seen + 1
        return area

    # Creature spawns rarely have a zone id. Learn the zones from the positions of game
    # objects (which nearly always have one): grid cell -> most frequent zone.
    CELL = 100.0
    grid = defaultdict(Counter)
    for row in sql_rows("gameobject.sql", "gameobject"):
        if row[2] in MAPS and row[3]:
            grid[(row[2], int(row[7] // CELL), int(row[8] // CELL))][top_zone(row[3])] += 1
    cell_zone = {cell: zones.most_common(1)[0][0] for cell, zones in grid.items()}

    def zone_of(map_id, zone_id, x, y):
        if zone_id:
            return top_zone(zone_id)
        cx, cy = int(x // CELL), int(y // CELL)
        zone = cell_zone.get((map_id, cx, cy))
        if zone:
            return zone
        near = Counter()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                z = cell_zone.get((map_id, cx + dx, cy + dy))
                if z:
                    near[z] += 1
        if near:
            return near.most_common(1)[0][0]
        # last resort: the world map rectangle, only if exactly one contains the point
        found = [zone for m, zone, left, right, top, bottom in bounds
                 if m == map_id and bottom <= x <= top and right <= y <= left]
        return found[0] if len(found) == 1 else 0

    # gathering nodes: template -> (skill line, required skill, loot id)
    locks = {}
    for row in DBC(os.path.join(DBC_DIR, "Lock.dbc")).rows():
        for k in range(8):
            if row[1 + k] == LOCK_KEY_SKILL and row[9 + k] in LOCKTYPE:
                locks[row[0]] = (LOCKTYPE[row[9 + k]], max(1, row[17 + k]))
    nodes = {}
    for row in sql_rows("gameobject_template.sql", "gameobject_template"):
        if row[1] == GO_TYPE_CHEST and row[8] in locks:
            skill, req = locks[row[8]]
            nodes[row[0]] = {"skill": skill, "req": req, "loot": row[9]}

    # main item of a node: the item with the highest chance in its loot
    best_item = {}
    for row in sql_rows("gameobject_loot_template.sql", "gameobject_loot_template"):
        entry, item, ref, chance = row[0], row[1], row[2], row[3]
        if ref or item <= 0:
            continue
        old = best_item.get(entry)
        if old is None or chance > old[1]:
            best_item[entry] = (item, chance)

    # only trade goods (herbs, ore, stone) count: quest objects also use herb/mining locks
    trade_goods = set()
    for row in sql_rows("item_template.sql", "item_template"):
        if row[1] == ITEM_CLASS_TRADE_GOODS:
            trade_goods.add(row[0])

    # Spawn pools: one spawn point is listed for several node types (e.g. Fel Iron and
    # Khorium) but only some spawn at a time. Weight each spawn with its probability.
    limit = {row[0]: row[1] for row in sql_rows("pool_template.sql", "pool_template")}
    members = defaultdict(list)
    for row in sql_rows("pool_gameobject.sql", "pool_gameobject"):
        members[row[1]].append((row[0], row[2]))
    mother = {row[0]: (row[1], row[2]) for row in sql_rows("pool_pool.sql", "pool_pool")}
    children = Counter(m for m, _ in mother.values())

    def share(pool, chance, count):
        if chance > 0:
            return min(1.0, chance / 100.0)
        n = limit.get(pool, 0)
        return 1.0 if n <= 0 or count <= 0 else min(1.0, n / count)

    def pool_active(pool, depth=0):
        if pool not in mother or depth > 3:
            return 1.0
        parent_pool, chance = mother[pool]
        return share(parent_pool, chance, children[parent_pool]) * pool_active(parent_pool, depth + 1)

    weight = {}
    for pool, lst in members.items():
        zero = sum(1 for _, c in lst if c == 0)
        active = pool_active(pool)
        for guid, chance in lst:
            weight[guid] = share(pool, chance, zero) * active

    # node spawns per zone; key (skill, item, req) so variants of one node merge
    gather = defaultdict(lambda: defaultdict(float))
    for row in sql_rows("gameobject.sql", "gameobject"):
        node = nodes.get(row[1])
        if not node or row[2] not in MAPS:
            continue
        item = best_item.get(node["loot"], (0, 0))[0]
        if item not in trade_goods:
            continue
        zone = zone_of(row[2], row[3], row[7], row[8])
        if zone in worldmap:
            gather[(zone, node["skill"])][(item, node["req"])] += weight.get(row[0], 1.0)

    # creatures: skinnable ones per zone and level, and all levels for the zone level
    skinnable, levels_of = {}, {}
    for row in sql_rows("creature_template.sql", "creature_template"):
        entry, minl, maxl, ctype, tflags, skinloot = row[0], row[10], row[11], row[32], row[33], row[36]
        if ctype == CREATURE_TYPE_CRITTER:
            continue
        levels_of[entry] = (minl + maxl) // 2
        if skinloot and not (tflags & TYPE_FLAG_OTHER_SKINNING):
            skinnable[entry] = (minl + maxl) // 2
    zone_levels = defaultdict(list)
    skins = defaultdict(Counter)
    for row in sql_rows("creature.sql", "creature"):
        cid, map_id = row[1], row[4]
        if map_id not in MAPS or cid not in levels_of:
            continue
        zone = zone_of(map_id, row[5], row[10], row[11])
        if zone not in worldmap:
            continue
        level = levels_of[cid]
        if 0 < level <= 83:
            zone_levels[zone].append(level)
        if cid in skinnable:
            skins[zone][skinnable[cid]] += 1

    zone_level = {z: int(statistics.median(lv)) for z, lv in zone_levels.items() if len(lv) >= 10}

    # fishing: minimum skill per zone (lowest of the zone and its subareas)
    fishing = {}
    for entry, skill in sql_rows("skill_fishing_base_level.sql", "skill_fishing_base_level"):
        zone = top_zone(entry)
        if zone in worldmap and skill > -100:
            fishing[zone] = min(fishing.get(zone, 999), max(1, skill))

    used_zones = {z for z, _ in gather} | set(skins) | set(fishing)
    out = ["-- Generated by tools/build_gather.py - do not edit.",
           "-- Sources: WoW 3.3.5a client tables and AzerothCore spawn/loot/fishing data (GPL-2.0).",
           "-- zones[area] = {world map id, map, level, faction (2 Alliance, 4 Horde, 0 both),",
           "--               German name, internal map name} (names only as fallback, see Gather.lua)",
           "-- nodes[skill][area] = {item, required skill, spawns, ...}",
           "-- skins[area] = {creature level, spawns, ...}; fishing[area] = minimum skill",
           "ProfessionPathGather = {",
           "\tzones = {"]
    for z in sorted(used_zones):
        out.append("\t\t[%d] = {%d, %d, %d, %d, %s, %s}," % (z, worldmap[z], info[z]["map"], zone_level.get(z, 0),
                   info[z]["faction"], lua_str(info[z]["name"]), lua_str(info[z]["key"])))
    out.append("\t},")
    out.append("\tnodes = {")
    for skill in (HERBALISM, MINING):
        out.append("\t\t[%d] = {" % skill)
        for (zone, sk) in sorted(k for k in gather if k[1] == skill):
            parts = []
            for (item, req), n in sorted(gather[(zone, sk)].items(), key=lambda kv: kv[0][1]):
                if n >= 0.5:
                    parts += [item, req, int(round(n))]
            if not parts:
                continue
            out.append("\t\t\t[%d] = {%s}," % (zone, ",".join(map(str, parts))))
        out.append("\t\t},")
    out.append("\t},")
    out.append("\tskins = {")
    for zone in sorted(skins):
        parts = []
        for level, n in sorted(skins[zone].items()):
            parts += [level, n]
        out.append("\t\t[%d] = {%s}," % (zone, ",".join(map(str, parts))))
    out.append("\t},")
    out.append("\tfishing = {")
    for zone in sorted(fishing):
        out.append("\t\t[%d] = %d," % (zone, fishing[zone]))
    out.append("\t},")
    out.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\r\n") as f:
        f.write("\n".join(out) + "\n")

    print("zones", len(used_zones), "with level", sum(1 for z in used_zones if z in zone_level))
    print("herb zones", sum(1 for k in gather if k[1] == HERBALISM), "mining zones", sum(1 for k in gather if k[1] == MINING))
    print("skin zones", len(skins), "fishing zones", len(fishing), "size", os.path.getsize(OUT))


if __name__ == "__main__":
    main()
