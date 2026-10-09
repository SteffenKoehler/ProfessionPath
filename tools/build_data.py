# Builds ProfessionPath/Data.lua from the client DBCs (tools/dbc, see extract_dbc.py) and the
# AzerothCore trainer/vendor/item tables (tools/cache, GPL-2.0). Only IDs and numbers end up
# in the addon; all names come from the game client at runtime (GetSpellInfo/GetItemInfo).
import os, re, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dbc import DBC

DBC_DIR = os.path.join(HERE, "dbc")
CACHE = os.path.join(HERE, "cache")
OUT = os.path.join(HERE, "..", "ProfessionPath", "Data.lua")

# skill line -> profession spell (its name is the localized profession name)
SKILLS = {
    129: 3273,   # First Aid
    164: 2018,   # Blacksmithing
    165: 2108,   # Leatherworking
    171: 2259,   # Alchemy
    185: 2550,   # Cooking
    186: 2575,   # Mining (smelting)
    197: 3908,   # Tailoring
    202: 4036,   # Engineering
    333: 7411,   # Enchanting
    755: 25229,  # Jewelcrafting
    773: 45357,  # Inscription
}

# Spell.dbc (3.3.5a, 234 fields)
S_FOCUS = 18            # RequiresSpellFocus
S_RECOVERY = 29         # RecoveryTime (ms)
S_CATEGORY_RECOVERY = 30
S_REAGENT = 52          # Reagent[8]
S_REAGENT_COUNT = 60    # ReagentCount[8]
S_EFFECT = 71           # Effect[3]
S_DIE_SIDES = 74
S_BASE_POINTS = 80
S_ITEM_TYPE = 107       # EffectItemType[3]
EFFECT_CREATE_ITEM = 24

# SkillLineAbility.dbc (14 fields)
A_SKILL, A_SPELL, A_RACE, A_CLASS, A_ACQUIRE, A_GREY, A_YELLOW = 1, 2, 3, 4, 9, 10, 11

# item_template columns (AzerothCore)
I_ENTRY, I_CLASS, I_REQ_SKILL, I_REQ_RANK, I_SPELL1, I_SPELL2 = 0, 1, 17, 18, 65, 72
I_BUY_COUNT, I_BUY_PRICE, I_SELL_PRICE = 9, 10, 11
ITEM_CLASS_RECIPE = 9
LEARN_SPELLS = (483, 55884)  # "Learning" spells; the taught recipe is in the next slot

SOURCE_AUTO, SOURCE_TRAINER, SOURCE_OTHER, SOURCE_VENDOR = 1, 2, 3, 4

TOKEN = re.compile(r"'((?:[^'\\]|\\.)*)'|(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|(NULL)|([(),;])")


def sql_rows(name, table):
    """Yield value lists (ints/floats/strings) from the INSERT statements of a dump."""
    text = open(os.path.join(CACHE, name), encoding="utf-8").read()
    head = "INSERT INTO `%s` VALUES" % table
    pos = text.find(head)
    while pos >= 0:
        i = pos + len(head)
        row, depth = None, 0
        for m in TOKEN.finditer(text, i):
            s, num, null, punct = m.groups()
            if punct == "(":
                row, depth = [], 1
            elif punct == ")":
                yield row
                row, depth = None, 0
            elif punct == ";":
                i = m.end()
                break
            elif punct == ",":
                continue
            elif depth:
                if s is not None:
                    row.append(s)
                elif null:
                    row.append(None)
                else:
                    row.append(float(num) if "." in num or "e" in num.lower() else int(num))
        pos = text.find(head, i)


def main():
    # trainer recipes: spell -> (min required skill, cost, required ability)
    trainer = {}
    for row in sql_rows("trainer_spell.sql", "trainer_spell"):
        _, spell, cost, skill, rank, ab1, ab2, ab3 = row[:8]
        if skill not in SKILLS:
            continue
        ability = ab1 or ab2 or ab3
        old = trainer.get(spell)
        if old is None or rank < old[0]:
            trainer[spell] = (rank, cost, ability)

    # items sold by vendors for plain gold (recipes for tokens/badges count as "other");
    # unlimited ones count as cheap reagents
    vendor_reagent, vendor_gold = set(), set()
    for row in sql_rows("npc_vendor.sql", "npc_vendor"):
        _, _, item, maxcount, _, extcost = row[:6]
        if item > 0 and extcost == 0:
            vendor_gold.add(item)
            if maxcount == 0:
                vendor_reagent.add(item)

    # recipe items: taught spell -> (item, required skill rank, sold by a vendor)
    recipe_items = {}
    item_prices = {}  # item -> (buy price per unit, sell price)
    for row in sql_rows("item_template.sql", "item_template"):
        item_prices[row[I_ENTRY]] = (row[I_BUY_PRICE] // max(1, row[I_BUY_COUNT]), row[I_SELL_PRICE])
        if row[I_CLASS] != ITEM_CLASS_RECIPE or row[I_REQ_SKILL] not in SKILLS:
            continue
        taught = row[I_SPELL2] if row[I_SPELL1] in LEARN_SPELLS else row[I_SPELL1]
        if not taught or taught <= 0:
            continue
        item = row[I_ENTRY]
        sold = item in vendor_gold
        old = recipe_items.get(taught)
        # prefer a vendor item, then the lowest requirement
        if old is None or (sold and not old[2]) or (sold == old[2] and row[I_REQ_RANK] < old[1]):
            recipe_items[taught] = (item, row[I_REQ_RANK], sold)

    # skill line abilities: merge rows of the same spell (race/class variants)
    abilities = {}
    for row in DBC(os.path.join(DBC_DIR, "SkillLineAbility.dbc")).rows():
        skill, spell = row[A_SKILL], row[A_SPELL]
        if skill not in SKILLS or row[A_GREY] == 0:
            continue
        # learned together with the profession only if that holds for every class
        # (death knights get some recipes automatically via a class-restricted row)
        auto = row[A_ACQUIRE] == 1 and row[A_CLASS] == 0
        a = abilities.get(spell)
        if a is None:
            abilities[spell] = {"skill": skill, "race": row[A_RACE], "auto": auto,
                                "yellow": row[A_YELLOW], "grey": row[A_GREY]}
        else:
            a["race"] = 0 if (a["race"] == 0 or row[A_RACE] == 0) else (a["race"] | row[A_RACE])
            a["auto"] = a["auto"] or auto

    spells = {}
    for row in DBC(os.path.join(DBC_DIR, "Spell.dbc")).rows(signed=True):
        if row[0] in abilities:
            spells[row[0]] = row

    recipes = defaultdict(list)
    cooldown, recipe_item_of = set(), {}
    stats = defaultdict(lambda: defaultdict(int))
    for spell, a in sorted(abilities.items()):
        row = spells.get(spell)
        if row is None:
            continue
        reagents = []
        for i in range(8):
            item, count = row[S_REAGENT + i], row[S_REAGENT_COUNT + i]
            if item > 0 and count > 0:
                reagents += [item, count]
        if not reagents:
            continue  # no material: nothing to plan (e.g. gathering abilities)
        created, amount = 0, 0
        for e in range(3):
            if row[S_EFFECT + e] == EFFECT_CREATE_ITEM and row[S_ITEM_TYPE + e] > 0:
                created = row[S_ITEM_TYPE + e]
                amount = max(1, row[S_BASE_POINTS + e] + max(1, row[S_DIE_SIDES + e]))
                break
        t, ri = trainer.get(spell), recipe_items.get(spell)
        if a["auto"]:
            source, learn, cost, ability = SOURCE_AUTO, 1, 0, 0
        elif t:
            source, learn, cost, ability = SOURCE_TRAINER, max(1, t[0]), t[1], t[2]
        elif ri:
            source, learn, cost, ability = (SOURCE_VENDOR if ri[2] else SOURCE_OTHER), max(1, ri[1]), 0, 0
            recipe_item_of[spell] = ri[0]
        else:
            source, learn, cost, ability = SOURCE_OTHER, 0, 0, 0
        if row[S_RECOVERY] > 0 or row[S_CATEGORY_RECOVERY] > 0:
            cooldown.add(spell)  # transmutes, research, special cloth: not for leveling
        stats[a["skill"]][source] += 1
        recipes[a["skill"]].append([spell, source, learn, a["yellow"], a["grey"], cost, a["race"], ability,
                                    created, amount] + reagents)

    used = {r[i] for lst in recipes.values() for r in lst for i in range(10, len(r), 2)}

    def id_set(name, ids):
        out.append("\t%s = {" % name)
        ids = sorted(ids)
        for i in range(0, len(ids), 16):
            out.append("\t\t" + " ".join("[%d]=1," % v for v in ids[i:i + 16]))
        out.append("\t},")

    out = ["-- Generated by tools/build_data.py - do not edit.",
           "-- Sources: WoW 3.3.5a client tables (IDs and skill levels only) and AzerothCore",
           "-- trainer/vendor/item data (GPL-2.0). Names are read from the game client at runtime.",
           "-- recipe = {spell, source (1 auto, 2 trainer, 3 other, 4 vendor recipe), learn, yellow, grey,",
           "--           trainer cost, race mask, required ability, created item, amount, reagent, count, ...}",
           "-- vendor = buy price of vendor reagents, sellPrice = vendor sell price of other reagents",
           "ProfessionPathData = {",
           "\tskills = {"]
    for skill, spell in sorted(SKILLS.items()):
        out.append("\t\t[%d] = %d," % (skill, spell))
    out.append("\t},")
    out.append("\trecipes = {")
    for skill in sorted(recipes):
        out.append("\t\t[%d] = {" % skill)
        for r in sorted(recipes[skill], key=lambda r: (r[3], r[0])):
            out.append("\t\t\t{%s}," % ",".join(str(v) for v in r))
        out.append("\t\t},")
    out.append("\t},")
    # recipe spell -> recipe item (to show which recipe to buy or find)
    out.append("\trecipeItem = {")
    pairs = sorted(recipe_item_of.items())
    for i in range(0, len(pairs), 8):
        out.append("\t\t" + " ".join("[%d]=%d," % p for p in pairs[i:i + 8]))
    out.append("\t},")
    id_set("cooldown", cooldown)

    # vendor reagents: item -> buy price per unit (copper)
    def price_map(name, values):
        out.append("	%s = {" % name)
        pairs = sorted(values.items())
        for i in range(0, len(pairs), 10):
            out.append("		" + " ".join("[%d]=%d," % p for p in pairs[i:i + 10]))
        out.append("	},")

    price_map("vendor", {i: max(1, item_prices.get(i, (1, 0))[0]) for i in vendor_reagent & used})
    # value of the other reagents for estimates without auction data: vendor sell price
    # (or a quarter of the buy price if it has none)
    estimate = {}
    for i in used - vendor_reagent:
        buy, sell = item_prices.get(i, (0, 0))
        value = sell or buy // 4
        if value > 0:
            estimate[i] = value
    price_map("sellPrice", estimate)
    out.append("}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\r\n") as f:
        f.write("\n".join(out) + "\n")

    for skill in sorted(stats):
        s = stats[skill]
        print("skill %3d: auto %3d  trainer %3d  vendor recipe %3d  other %3d"
              % (skill, s[SOURCE_AUTO], s[SOURCE_TRAINER], s[SOURCE_VENDOR], s[SOURCE_OTHER]))
    print("cooldown:", len(cooldown), " vendor reagents:", len(vendor_reagent & used), " estimates:", len(estimate),
          " size:", os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main()
