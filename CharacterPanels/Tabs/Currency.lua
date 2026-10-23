-- SnapChar – Währungs-Tab (6. Tab)
-- Währungsliste mit Anzahl und Symbol, rechts Details, Maximum und Kontrollkästchen.
-- Alle Daten kommen vom Spiel (C_CurrencyInfo).

local ADDON, ns = ...
local L, T, MakeCheck, fmtNum = ns.L, ns.T, ns.MakeCheck, ns.fmtNum

----------------------------------------------------------------------
-- Währungen (C_CurrencyInfo)
----------------------------------------------------------------------
local CI = C_CurrencyInfo
local currencyTab
currencyTab = ns.CreateListTab({
    hasSubtitle = true,
    noDetailBar = true,
    childIndent = 14,
    events = { "CURRENCY_DISPLAY_UPDATE" },
    emptyText = L("TOKEN_DETAIL_SELECT_PROMPT", "Select a currency to view its details."),
    fetch = function()
        local list = {}
        if not (CI and CI.GetCurrencyListSize) then return list end
        for i = 1, CI.GetCurrencyListSize() or 0 do
            local d = CI.GetCurrencyListInfo(i)
            if d and d.name and d.name ~= "" then
                local e = {
                    index = i, key = d.currencyID ~= 0 and d.currencyID or ("h" .. d.name), data = d,
                    name = d.name,
                    isHeader = d.isHeader, isCollapsed = d.isHeader and not d.isHeaderExpanded,
                    isChild = (d.currencyListDepth or 0) > 1,
                    selectable = not d.isHeader,
                    hasBar = false,
                }
                if not d.isHeader then
                    e.rightText = fmtNum(d.quantity or 0)
                    e.rightIcon = d.iconFileID
                    e.subtitle = d.iconFileID and string.format("|T%d:16:16|t %s", d.iconFileID, fmtNum(d.quantity or 0))
                        or fmtNum(d.quantity or 0)
                    -- Beschreibung steht nur in den vollen Währungsdaten
                    local full = d.currencyID and CI.GetCurrencyInfo and CI.GetCurrencyInfo(d.currencyID)
                    e.desc = (full and full.description) or d.description
                end
                list[#list + 1] = e
            end
        end
        return list
    end,
    toggleHeader = function(e)
        CI.ExpandCurrencyList(e.index, e.isCollapsed)
    end,
    extraDetail = function(detail, parts)
        -- "Maximum" und ggf. Wochenmaximum unter der Beschreibung
        local function MakeLine(anchor, y)
            local l = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
            local v = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            v:SetPoint("RIGHT", detail, "RIGHT", -16, 0)
            v:SetPoint("TOP", l, "TOP")
            return l, v
        end
        local maxL, maxV = MakeLine(parts.desc, -24)
        local weekL, weekV = MakeLine(maxL, -8)

        local cUnused = MakeCheck(detail, L("UNUSED", "Unused"), 48)
        local cBackpack = MakeCheck(detail, L("SHOW_ON_BACKPACK", "Show on Backpack"), 20)
        -- Das Spiel meldet diese Änderungen nicht selbst: Liste und die
        -- Währungsleiste im Rucksack hier direkt aktualisieren
        local function RefreshAll()
            if currencyTab then currencyTab.Refresh() end
            local bt = _G.BackpackTokenFrame
            if bt and bt.Update then
                pcall(bt.Update, bt)
            elseif _G.BackpackTokenFrame_Update then
                pcall(_G.BackpackTokenFrame_Update)
            end
        end
        local function RefreshSoon()
            RefreshAll()
            C_Timer.After(0.1, RefreshAll) -- falls der Server einen Moment braucht
        end
        cUnused:SetScript("OnClick", function(self)
            if self.index then pcall(CI.SetCurrencyUnused, self.index, self:GetChecked()) end
            RefreshSoon()
        end)
        cBackpack:SetScript("OnClick", function(self)
            if self.index then pcall(CI.SetCurrencyBackpack, self.index, self:GetChecked()) end
            RefreshSoon()
        end)

        return function(e)
            local d = e.data
            local hasMax = (d.maxQuantity or 0) > 0
            maxL:SetShown(hasMax); maxV:SetShown(hasMax)
            maxL:SetText(L({ "MAXIMUM" }, "Maximum"))
            maxV:SetText(fmtNum(d.maxQuantity or 0))

            local hasWeek = (d.maxWeeklyQuantity or 0) > 0
            weekL:SetShown(hasWeek); weekV:SetShown(hasWeek)
            weekL:ClearAllPoints()
            weekL:SetPoint("TOPLEFT", hasMax and maxL or parts.desc, "BOTTOMLEFT", 0, hasMax and -8 or -24)
            weekL:SetText(T["Weekly Maximum"])
            weekV:SetText(fmtNum(d.quantityEarnedThisWeek or 0) .. " / " .. fmtNum(d.maxWeeklyQuantity or 0))

            cUnused.index, cBackpack.index = e.index, e.index
            cUnused:SetChecked(d.isTypeUnused)
            cBackpack:SetChecked(d.isShowInBackpack)
        end
    end,
})

ns.RegisterTab(6, "currency", currencyTab, L({ "CURRENCY", "TOKENS" }, "Currency"))
