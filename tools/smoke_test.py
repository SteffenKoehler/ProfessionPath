# Smoke test: load the whole addon in LuaJIT with a stubbed WoW API, open the window for
# every profession and run one refresh, to catch runtime errors before testing in game.
import os
from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "SkillPath")

STUBS = r"""
local noop = function() end
local objects = {}
local function Object(name)
    local o = {}
    local scripts = {}
    local shown = false
    local level = 1
    setmetatable(o, {__index = function(t, k)
        if k == "SetScript" then return function(self, n, f) scripts[n] = f end end
        if k == "GetScript" then return function(self, n) return scripts[n] end end
        if k == "Show" then return function(self) shown = true if scripts.OnShow then scripts.OnShow(self) end end end
        if k == "Hide" then return function(self) shown = false end end
        if k == "IsShown" then return function() return shown end end
        if k == "GetFrameLevel" then return function() return level end end
        if k == "SetFrameLevel" then return function(_, l) level = l end end
        if k == "GetChecked" then return function() return 1 end end
        if k:match("^Create") then return function() return Object() end end
        if k:match("^Get") then return function() return 0 end end
        return noop
    end})
    if name then _G[name] = o; _G[name .. "Text"] = Object() end
    return o
end
CreateFrame = function(_, name) return Object(name) end
UIParent, WorldFrame, GameTooltip = Object(), Object(), Object()
UISpecialFrames = {}
ITEM_QUALITY_COLORS = setmetatable({}, {__index = function() return {hex = "|cffffffff"} end})
bit = require("bit")
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
format = string.format
GetLocale = function() return "deDE" end
GetRealmName = function() return "Realm" end
UnitName = function() return "Tester" end
UnitRace = function() return "Mensch", "Human" end
GetSpellInfo = function(id) return "Spell" .. id, nil, "icon" end
GetItemInfo = function(id) if id % 3 == 0 then return nil end return "Item" .. id, nil, 1 end
GetItemIcon = function() return "icon" end
GetItemCount = function() return 3 end
GetCoinTextureString = function(c) return tostring(c) end
IsSpellKnown = function() return false end
IsAddOnLoaded = function() return false end
TradeSkillFrame = nil
local skills = {{"Spell3908", false, nil, 120, nil, nil, 150}, {"Spell2550", false, nil, 300, nil, nil, 300}}
GetNumSkillLines = function() return #skills end
GetSkillLineInfo = function(i) return unpack(skills[i]) end
GetTradeSkillLine = function() return "Spell3908", 120, 150 end
GetNumTradeSkills = function() return 2 end
GetTradeSkillInfo = function(i) return "x", i == 1 and "header" or "optimal" end
GetTradeSkillRecipeLink = function() return "|Henchant:3915|h[x]|h" end
IsTradeSkillLinked = function() return false end
UIDropDownMenu_SetWidth, UIDropDownMenu_SetText, UIDropDownMenu_Initialize = noop, noop, noop
UIDropDownMenu_CreateInfo = function() return {} end
UIDropDownMenu_AddButton = noop
local offsets = {}
FauxScrollFrame_GetOffset = function(f) return offsets[f] or 0 end
FauxScrollFrame_SetOffset = function(f, o) offsets[f] = o end
FauxScrollFrame_Update = noop
FauxScrollFrame_OnVerticalScroll = noop
SlashCmdList = {}
"""


def main():
    lua = lupa.LuaRuntime()
    lua.execute(STUBS)
    for f in ("Locales.lua", "Data.lua", "Planner.lua", "Core.lua", "UI.lua"):
        lua.execute(open(os.path.join(ADDON, f), encoding="utf-8").read())
    lua.execute("SkillPathDB = {chars = {}, options = {vendorRecipes = true}}")
    lua.execute(open(os.path.join(HERE, "smoke_body.lua"), encoding="utf-8").read())
    print("smoke test passed")


main()
