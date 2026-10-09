-- UI texts: English keys, translations per client language (missing ones show the key).
-- Recipe, item and profession names come from the game client and need no translation.

SkillPath = SkillPath or {}

local translations = {
	deDE = {
		["Route"] = "Route",
		["Materials for the rest of the route"] = "Material für die restliche Route",
		["Use vendor recipes"] = "Händlerrezepte einplanen",
		["Also plan recipes you can buy from vendors (the recipe to buy is shown in the tooltip)."] = "Auch Rezepte einplanen, die man bei Händlern kaufen kann (welches, steht im Tooltip).",
		["Not learned"] = "Nicht erlernt",
		["Done - maximum skill reached."] = "Fertig - höchster Skill erreicht.",
		["No further recipe from trainers or vendors gives skill points from %d on."] = "Ab %d gibt kein Rezept von Lehrern oder Händlern mehr Punkte.",
		["To continue you need one of these recipes:"] = "Zum Weitermachen brauchst du eines dieser Rezepte:",
		["Learn %s at your trainer (from skill %d, level %d)"] = "%s beim Lehrer lernen (ab Skill %d, Stufe %d)",
		["Journeyman"] = "Geselle",
		["Expert"] = "Experte",
		["Artisan"] = "Fachmann",
		["Master"] = "Meister",
		["Grand Master"] = "Großmeister",
		["Buy recipe: %s"] = "Rezept kaufen: %s",
		["Recipe needed: %s"] = "Rezept nötig: %s",
		["Learn at trainer from %d (%s)"] = "Beim Lehrer ab %d (%s)",
		["Skill %d-%d, about %d crafts"] = "Skill %d-%d, etwa %d Mal herstellen",
		["Open the profession window once so SkillPath knows your recipes."] = "Öffne einmal das Berufsfenster, damit SkillPath deine Rezepte kennt.",
		["have %d / need %d"] = "vorhanden %d / benötigt %d",
		["Opens SkillPath for this profession."] = "Öffnet SkillPath für diesen Beruf.",
		["Vendor"] = "Händler",
		["Auction"] = "Auktionshaus",
		["Estimate"] = "Schätzung",
		["Price per unit: %s (%s)"] = "Preis pro Stück: %s (%s)",
		["Right-click: avoid this material"] = "Rechtsklick: Material meiden",
		["Right-click: use again"] = "Rechtsklick: wieder verwenden",
		["Avoided: the route only uses it if there is no alternative."] = "Gemieden: Die Route nutzt es nur, wenn es keine Alternative gibt.",
		["avoided"] = "gemieden",
		["Prices: %s"] = "Preise: %s",
		["estimate from vendor prices"] = "Schätzung aus Händlerpreisen",
		["Please restart the game client completely to load all SkillPath files."] = "Bitte den Spielclient komplett neu starten, damit alle SkillPath-Dateien geladen werden.",
		["Your professions"] = "Deine Berufe",
		["All professions"] = "Alle Berufe",
		["Crafting"] = "Herstellung",
		["Gathering"] = "Sammeln",
		["Secondary skills"] = "Nebenberufe",
		["Avoid this material"] = "Material meiden",
		["Use this material again"] = "Material wieder verwenden",
		["The route is recalculated without it where possible."] = "Die Route wird, wo möglich, ohne dieses Material neu berechnet.",
		["X: avoid a material"] = "X: Material meiden",
		["Zone level %d"] = "Gebietsstufe %d",
		["Zone level %d - above your level"] = "Gebietsstufe %d - über deiner Stufe",
		["from skill %d, ~%d spawns"] = "ab Skill %d, ~%d Vorkommen",
		["~%d spawns"] = "~%d Vorkommen",
		["Beasts level %d-%d"] = "Tiere Stufe %d-%d",
		["Skill %d-%d, about %d gathers"] = "Skill %d-%d, etwa %d Mal sammeln",
		["Skill %d-%d, about %d catches"] = "Skill %d-%d, etwa %d Fänge",
		["Zones where you catch fish at this skill:"] = "Gebiete, in denen du bei diesem Skill Fische fängst:",
		["minimum skill %d"] = "mindestens Skill %d",
		["from skill %d"] = "ab Skill %d",
		["Gives skill points at your skill now"] = "Gibt bei deinem Skill jetzt Punkte",
		["Catches per skill point at your skill: %d"] = "Fänge pro Skillpunkt bei deinem Skill: %d",
		["Commands: /skillpath (or /spath) - toggle the window"] = "Befehle: /skillpath (oder /spath) - Fenster ein/aus",
	},
}

local locale = GetLocale()
local current = translations[locale] or {}
SkillPath.L = setmetatable({}, {
	__index = function(_, key)
		return current[key] or key
	end
})
