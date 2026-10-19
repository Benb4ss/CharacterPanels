-- SnapChar – Ruf-Tab (3. Tab)
-- Fraktionsliste mit auf-/zuklappbaren Überschriften, rechts Details und Kontrollkästchen.
-- Alle Daten kommen vom Spiel (C_Reputation).

local ADDON, ns = ...
local L, MakeCheck, fmtNum = ns.L, ns.MakeCheck, ns.fmtNum

----------------------------------------------------------------------
-- Ruf (C_Reputation)
----------------------------------------------------------------------
local RC = C_Reputation
local function StandingText(reaction)
    local key = "FACTION_STANDING_LABEL" .. (reaction or 4)
    local ok, txt = pcall(GetText, key, UnitSex("player"))
    return (ok and txt) or _G[key] or ""
end
local function StandingColor(reaction)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if c then return { c.r, c.g, c.b } end
    return { 0, 0.6, 0.1 }
end
local function RepBarValues(d)
    local minV, maxV, cur = d.currentReactionThreshold or 0, d.nextReactionThreshold or 0, d.currentStanding or 0
    if maxV <= minV then return 1, 1 end -- höchste Stufe erreicht
    return cur - minV, maxV - minV
end

local repTab = ns.CreateListTab({
    barAtlas = "common-stat-bar-white",
    hasSubtitle = true,
    childIndent = 14,
    events = { "UPDATE_FACTION" },
    emptyText = L("REPUTATION_DETAIL_SELECT_PROMPT", "Select a faction to view its details."),
    fetch = function()
        local list = {}
        if not RC then return list end
        for i = 1, RC.GetNumFactions() or 0 do
            local d = RC.GetFactionDataByIndex(i)
            if d and d.name then
                local hasBar = (not d.isHeader) or d.isHeaderWithRep
                local v, m = RepBarValues(d)
                list[#list + 1] = {
                    index = i, key = d.factionID, data = d,
                    name = d.name, desc = d.description,
                    isHeader = d.isHeader, isChild = d.isChild, isCollapsed = d.isCollapsed,
                    selectable = (not d.isHeader) or d.isHeaderWithRep,
                    hasBar = hasBar, barValue = v, barMax = m,
                    barColor = StandingColor(d.reaction),
                    barText = StandingText(d.reaction),
                    subtitle = StandingText(d.reaction),
                    detailBarText = fmtNum(v) .. " / " .. fmtNum(m),
                }
            end
        end
        return list
    end,
    toggleHeader = function(e)
        if e.isCollapsed then RC.ExpandFactionHeader(e.index) else RC.CollapseFactionHeader(e.index) end
    end,
    extraDetail = function(detail)
        local cAtWar = MakeCheck(detail, L("AT_WAR", "At War"), 76)
        cAtWar:SetHighlightTexture(130754, "ADD") -- gekreuzte Schwerter wie im Original
        local cInactive = MakeCheck(detail, L({ "MOVE_TO_INACTIVE" }, "Move to Inactive"), 48)
        local cWatch = MakeCheck(detail, L({ "SHOW_FACTION_ON_MAINSCREEN", "MAJOR_FACTION_WATCH_FACTION_BUTTON_LABEL" }, "Show as Experience Bar"), 20)

        cAtWar:SetScript("OnClick", function(self)
            if self.index then pcall(RC.ToggleFactionAtWar, self.index) end
        end)
        cInactive:SetScript("OnClick", function(self)
            if self.index then pcall(RC.SetFactionActive, self.index, not self:GetChecked()) end
        end)
        cWatch:SetScript("OnClick", function(self)
            if not self.index then return end
            if self:GetChecked() then
                pcall(RC.SetWatchedFactionByIndex, self.index)
            elseif RC.SetWatchedFactionByID then
                pcall(RC.SetWatchedFactionByID, 0)
            else
                pcall(RC.SetWatchedFactionByIndex, 0)
            end
        end)

        return function(e)
            local d = e.data
            for _, c in ipairs({ cAtWar, cInactive, cWatch }) do c.index = e.index end
            cAtWar:SetChecked(d.atWarWith)
            cAtWar:SetEnabled(d.canToggleAtWar and true or false)
            local active = true
            if RC.IsFactionActive then
                local ok, a = pcall(RC.IsFactionActive, e.index)
                if ok then active = a end
            end
            cInactive:SetChecked(not active)
            cInactive:SetEnabled(d.canSetInactive ~= false)
            cWatch:SetChecked(d.isWatched)
        end
    end,
})

ns.RegisterTab(3, "rep", repTab, L("REPUTATION", "Reputation"))
