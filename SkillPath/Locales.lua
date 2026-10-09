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
		["Learn %s at your trainer (skill %d, level %d) - needed to go past %d."] = "%s beim Lehrer lernen (Skill %d, Stufe %d) - nötig, um über %d zu kommen.",
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
