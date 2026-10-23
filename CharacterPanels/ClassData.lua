local _, AJ = ...

-- Shared setup for the class files in Classes\. Each class file reads the class, race
-- and faction from this table and writes its spells to AJ.SpellsByLevel. Only the file
-- for the player's class does anything; the others return at once.
-- Load this file before the files in Classes\ (see the .toc notes).

local _, classFile = UnitClass("player")
AJ.currentClass = classFile
AJ.playerRace = select(3, UnitRace("player"))
AJ.playerFaction = UnitFactionGroup("player")

-- Keeps the entries of each level for which keep(entry) is true.
local function filterLevels(levels, keep)
    local kept = {}
    for level, spells in pairs(levels) do
        local list = {}
        for _, spell in ipairs(spells) do
            if keep(spell) then tinsert(list, spell) end
        end
        kept[level] = list
    end
    return kept
end

-- Same rule as the WhatsTraining class files use: an entry with race = n is kept only
-- for that race; an entry with races = {...} only for those races; any other entry is kept.
function AJ.RaceFilter(levels)
    return filterLevels(levels, function(spell)
        if spell.race then return spell.race == AJ.playerRace end
        if spell.races then return tContains(spell.races, AJ.playerRace) end
        return true
    end)
end

-- An entry with faction = "Alliance" or "Horde" is kept only for that faction.
function AJ.FactionFilter(levels)
    return filterLevels(levels, function(spell)
        return spell.faction == nil or spell.faction == AJ.playerFaction
    end)
end

-- Groups of spell IDs where one member stands for the others, such as the ranks of an aura
-- (the spellbook shows one rank; the others are not listed). Learning any member counts
-- as learning the group. Class files call this as wt:AddOverriddenSpells(group, group, ...).
AJ.overrideGroups = AJ.overrideGroups or {}
AJ.overrideOf = AJ.overrideOf or {}

function AJ:AddOverriddenSpells(...)
    for i = 1, select("#", ...) do
        local group = select(i, ...)
        tinsert(self.overrideGroups, group)
        for _, id in ipairs(group) do self.overrideOf[id] = group end
    end
end

-- QuestSpells.lua calls this with every class's quest-taught spells. Only this class's are kept.
function AJ.AddQuestSpells(all)
    AJ.questSpells = (all and all[AJ.currentClass]) or {}
end
