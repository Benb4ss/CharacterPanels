-- SnapChar – Skills-Tab (4. Tab)
-- Berufe, Waffenfertigkeiten, Rüstungskunde, Sprachen mit Balken, rechts Details.
-- Alle Daten kommen vom Spiel (C_SkillInfo).

local ADDON, ns = ...
local L = ns.L

----------------------------------------------------------------------
-- Skills (C_SkillInfo)
----------------------------------------------------------------------
local SI = C_SkillInfo
-- Kategorien, die das Original nicht anzeigt (Klassenfertigkeiten, "nicht anzeigen")
local HIDDEN_SKILL_CATEGORIES = { [7] = true, [12] = true }

local skillsTab = ns.CreateListTab({
    barAtlas = "common-stat-bar-blue",
    hasSubtitle = false,
    childIndent = 0,
    events = { "SKILL_LINES_CHANGED" },
    emptyText = L("SKILL_DETAIL_SELECT_PROMPT", "Select a skill to view its details."),
    fetch = function()
        local raw, seenNames = {}, {}
        if not (SI and SI.GetNumSkillLines) then return raw end
        for i = 1, SI.GetNumSkillLines() or 0 do
            local d = SI.GetSkillLineInfo(i)
            if d and d.name and d.name ~= "" then
                local hidden = d.isHeader and HIDDEN_SKILL_CATEGORIES[d.skillID]
                    or (not d.isHeader and HIDDEN_SKILL_CATEGORIES[d.skillLineCategoryID])
                    -- Unter-Fertigkeit eines Berufs (gleicher Name, parentSkillLineID gesetzt):
                    -- blendet das Original aus
                    or (not d.isHeader and (d.parentSkillLineID or 0) ~= 0)
                if d.isHeader then seenNames = {} end
                -- Sicherheitsnetz: gleicher Name zweimal unter derselben Überschrift
                if not d.isHeader and seenNames[d.name] then hidden = true end
                if not hidden and not d.isHeader then seenNames[d.name] = true end
                if not hidden then
                    local hasBar = not d.isHeader and (d.maxRank or 0) > 0
                    local rank, maxRank = d.rank or 0, d.maxRank or 0
                    local text = rank .. " / " .. maxRank
                    if (d.modifier or 0) ~= 0 then
                        text = string.format("%d (%+d) / %d", rank, d.modifier, maxRank)
                    end
                    raw[#raw + 1] = {
                        index = d.skillIndex or i, key = d.skillID, data = d,
                        name = d.name, desc = d.description,
                        isHeader = d.isHeader, isCollapsed = d.isCollapsed,
                        selectable = not d.isHeader,
                        hasBar = hasBar, barValue = rank, barMax = math.max(maxRank, 1),
                        barText = text,
                    }
                end
            end
        end
        -- leere Überschriften (ohne Einträge darunter) weglassen, wie im Original
        local list = {}
        for i, e in ipairs(raw) do
            local nextE = raw[i + 1]
            local empty = e.isHeader and not e.isCollapsed and (not nextE or nextE.isHeader)
            if not empty then list[#list + 1] = e end
        end
        return list
    end,
    toggleHeader = function(e)
        if e.isCollapsed then SI.ExpandSkillHeader(e.index) else SI.CollapseSkillHeader(e.index) end
    end,
})

ns.RegisterTab(4, "skills", skillsTab, L("SKILLS", "Skills"))
