# SkillPath

Profession leveling routes for **World of Warcraft 3.3.5a** (Wrath of the Lich King), shown
directly in the game - for every profession, in every client language.

Instead of copying a written guide, SkillPath **calculates** the route from the game data:
for each skill point it picks the recipe with the best ratio of skill-up chance to material
cost, from the recipes you can actually get.

## Features

- All crafting professions: Alchemy, Blacksmithing, Cooking, Enchanting, Engineering,
  First Aid, Inscription, Jewelcrafting, Leatherworking, Tailoring, plus Mining (smelting).
- Route from your current skill to 450: skill range, recipe (colored by difficulty) and
  how often to craft it. The current step is highlighted.
- Trainer recipes and the recipes you already know; optionally also recipes you can buy
  from vendors (tooltip shows which recipe to buy).
- Notes where you need to learn the next rank (Journeyman ... Grand Master) and which
  recipes you need when trainers and vendors run out (drops, tokens).
- Material list for the rest of the route with the amount in your bags and bank and the
  estimated cost. Click the X next to a material to avoid it in this profession (e.g. rare drops): the route is
  recalculated without it where possible.
- Prices: vendor reagents at their vendor price, everything else at the auction value from
  **Auctioneer** or **Auctionator** if one of them is installed, otherwise estimated from
  the vendor sell price. Intermediates (bolts of cloth, bars) cost the cheaper of buying
  and crafting them.
- Recipe skill-up chance: orange 100 %, then falling linearly to 0 at grey. Recipes close
  to grey are only planned when nothing else gives points.
- Gathering professions: **Herbalism, Mining and Skinning** show which zone to go to at
  which skill (zone with the most spawns that give points, weighted by spawn pools),
  with zone level and an estimate of how often to gather; zones far above your level or
  of the other faction are only suggested when nothing else fits. **Fishing** shows
  zones where you catch fish at each rank and how many catches a point takes.
- Names come from your game client, so the addon works in German, English, French, ...
  without translation tables. The interface itself is in English and German.

## Usage

- `/skillpath` or `/spath` toggles the window, or click the scroll tab on the right edge of
  the profession window (like the tabs of the spellbook).
- Open each profession window once, so SkillPath knows the recipes you already have.
- In the profession window SkillPath marks the recommended recipe at the right edge of its
  row; the crosshair tab below the SkillPath tab selects it (clearing filters if needed)
  and enters the number of crafts.

## Installation

Copy the folder `SkillPath` into `Interface/AddOns/` and **restart the game client** (WoW
3.3.5a only picks up new addon folders after a full restart).

## How the data is made

`SkillPath/Data.lua` is generated, not written by hand:

1. `tools/extract_dbc.py` reads `SkillLineAbility.dbc`, `Spell.dbc`, `Lock.dbc`,
   `AreaTable.dbc` and `WorldMapArea.dbc` from the client's MPQ archives (recipe skill
   levels, reagents, gathering node skills, zones). The raw files stay local.
2. `tools/build_data.py` combines them with the trainer, vendor and item tables of
   [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) (GPL-2.0) to know where a
   recipe is learned and at which skill, and writes `Data.lua` (IDs and numbers only).

3. `tools/build_gather.py` writes `GatherData.lua` from AzerothCore's spawn, loot, pool and
   fishing tables: node spawns and skinnable beasts per zone, zone levels, fishing skill.

`tools/test_planner.py <skill line>` and `tools/test_gather.py <skill line> [level] [faction]`
print routes outside the game, `tools/smoke_test.py`
loads the whole addon against a stubbed WoW API.

## Roadmap

- Recipe sources (trainer, vendor, drop) in more detail.

## License

GPL-2.0 (the recipe data is derived from AzerothCore's GPL-2.0 database). World of Warcraft
is a trademark of Blizzard Entertainment.
