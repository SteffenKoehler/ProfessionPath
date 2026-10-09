# Extract the DBC files SkillPath needs from the client's MPQ archives (newest patch wins).
# Raw DBCs are Blizzard data: they stay local (tools/dbc is git-ignored).
import os, sys, mpyq

DATA = sys.argv[1] if len(sys.argv) > 1 else r"D:/Programme/WoW_3.3.5a_rising-gods.de/Data"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dbc")
LOCALE = "deDE"
# lowest -> highest priority
ARCHIVES = ["locale-%s.MPQ", "expansion-locale-%s.MPQ", "lichking-locale-%s.MPQ",
            "patch-%s.MPQ", "patch-%s-2.MPQ", "patch-%s-3.MPQ"]
NAMES = ["SkillLineAbility", "Spell", "SkillLine", "Lock", "SkillRaceClassInfo", "SpellFocusObject", "TotemCategory"]

os.makedirs(OUT, exist_ok=True)
found = {}
for pattern in ARCHIVES:
    path = os.path.join(DATA, LOCALE, pattern % LOCALE)
    if not os.path.exists(path):
        continue
    mpq = mpyq.MPQArchive(path, listfile=True)
    files = set(mpq.files or [])
    for name in NAMES:
        key = ("DBFilesClient\\%s.dbc" % name).encode()
        if key in files:
            data = mpq.read_file(key.decode())
            if data:
                found[name] = (os.path.basename(path), data)
for name in NAMES:
    if name not in found:
        print("missing", name)
        continue
    src, data = found[name]
    with open(os.path.join(OUT, name + ".dbc"), "wb") as f:
        f.write(data)
    print("%-20s %9d bytes from %s" % (name, len(data), src))
