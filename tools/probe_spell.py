# Check field layout on known spells: 3275 Linen Bandage (First Aid), 2149 Handstitched Leather Boots
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dbc import DBC

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dbc")
spell = DBC(os.path.join(D, "Spell.dbc"))
print("Spell fields", spell.fields, "records", spell.records)
want = {3275, 2149, 7928}
for row in spell.rows():
    if row[0] in want:
        print(row[0], "name", spell.string(row[136]), "| reagents", row[52:60], "counts", row[60:68],
              "| effects", row[71:74], "base", row[80:83], "item", row[107:110], "| totems", row[50:52],
              "focus", row[18], "totemcat", row[-4:])

sla = DBC(os.path.join(D, "SkillLineAbility.dbc"))
print("SLA fields", sla.fields)
for row in sla.rows():
    if row[2] in want:
        print(row)

sl = DBC(os.path.join(D, "SkillLine.dbc"))
print("SkillLine fields", sl.fields)
for row in sl.rows():
    if row[0] in (129, 164, 165, 171, 185, 186, 197, 202, 333, 393, 755, 773, 182, 356):
        print(row[0], row[1], sl.string(row[3]))
