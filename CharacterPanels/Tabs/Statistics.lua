-- SnapChar – Statistik-Tab (7. Tab)
-- Eigene Liste im Stil der anderen Tabs (Ruf, Fertigkeiten). Die Daten kommen genau
-- wie bei Blizzards Statistik-Fenster vom Spiel: Kategorien, Unterkategorien, Werte.
-- /snapstatisticsinfo zeigt die Rohdaten (zur Fehlersuche).

local ADDON, ns = ...
local L, IsSecret = ns.L, ns.IsSecret

local ROOT_CATEGORY_ID = -1
local collapsed = {} -- categoryID -> true, wenn zugeklappt (wie Blizzard: anfangs alles offen)

-- Kategorien in Blizzards Reihenfolge: Hauptkategorien, direkt danach ihre Unterkategorien
local function BuildCategories()
    local raw = GetStatisticsCategoryList and GetStatisticsCategoryList() or {}
    local ordered = {}
    for k, id in pairs(raw) do
        if type(k) == "number" and id then ordered[#ordered + 1] = { index = k, id = id } end
    end
    table.sort(ordered, function(a, b) return a.index < b.index end)

    local roots, children = {}, {}
    for _, o in ipairs(ordered) do
        local _, parent = GetCategoryInfo(o.id)
        if parent == ROOT_CATEGORY_ID or parent == nil then
            roots[#roots + 1] = o.id
        else
            children[parent] = children[parent] or {}
            table.insert(children[parent], o.id)
        end
    end
    return roots, children
end

-- Wert als Text: Zahlen, Gold (mit Münz-Symbolen) oder Texte wie "343 (Bestien)"
local function ValueText(quantity)
    if quantity == nil or IsSecret(quantity) then return "--" end
    local q = tostring(quantity)
    if q == "" or q == "0" or q == "--" then return "--" end
    return q
end

local function AddStatistics(list, categoryID, isChild)
    local num = GetCategoryNumAchievements and GetCategoryNumAchievements(categoryID) or 0
    for i = 1, num do
        local quantity, skip, statID = GetStatistic(categoryID, i)
        if not skip and statID then
            local name = select(2, GetAchievementInfo(statID))
            list[#list + 1] = {
                key = "s" .. statID,
                name = name or UNKNOWN,
                rightText = ValueText(quantity),
                isChild = isChild,
            }
        end
    end
end

local statsTab = ns.CreateListTab({
    childIndent = 14,
    noDetailBar = true,
    events = { "CRITERIA_UPDATE" },
    fetch = function()
        local list = {}
        if not GetStatisticsCategoryList then return list end
        local roots, children = BuildCategories()
        for _, rootID in ipairs(roots) do
            list[#list + 1] = {
                key = rootID, name = GetCategoryInfo(rootID) or UNKNOWN,
                isHeader = true, isCollapsed = collapsed[rootID],
            }
            if not collapsed[rootID] then
                AddStatistics(list, rootID, false)
                for _, subID in ipairs(children[rootID] or {}) do
                    list[#list + 1] = {
                        key = subID, name = GetCategoryInfo(subID) or UNKNOWN,
                        isHeader = true, isSubHeader = true, isCollapsed = collapsed[subID],
                    }
                    if not collapsed[subID] then AddStatistics(list, subID, true) end
                end
            end
        end
        return list
    end,
    toggleHeader = function(e)
        collapsed[e.key] = not collapsed[e.key] or nil
    end,
})

ns.RegisterTab(7, "statistics", statsTab, L({ "STATISTICS" }, "Statistics"))

----------------------------------------------------------------------
-- Hilfen für /snapstatisticsinfo: Text-Fenster zum Kopieren, Werte als Text
----------------------------------------------------------------------
local inspectFrame
local function ShowTextWindow(out)
    if not inspectFrame then
        inspectFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        inspectFrame:SetSize(700, 450)
        inspectFrame:SetPoint("CENTER")
        inspectFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        inspectFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        inspectFrame:SetBackdropColor(0, 0, 0, 0.95)
        inspectFrame:EnableMouse(true)
        inspectFrame:SetMovable(true)
        inspectFrame:RegisterForDrag("LeftButton")
        inspectFrame:SetScript("OnDragStart", inspectFrame.StartMoving)
        inspectFrame:SetScript("OnDragStop", inspectFrame.StopMovingOrSizing)

        local c = CreateFrame("Button", nil, inspectFrame, "UIPanelCloseButton")
        c:SetPoint("TOPRIGHT", 0, 0)

        local sf = CreateFrame("ScrollFrame", nil, inspectFrame, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 10, -28)
        sf:SetPoint("BOTTOMRIGHT", -30, 10)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(650)
        eb:SetScript("OnEscapePressed", function() inspectFrame:Hide() end)
        sf:SetScrollChild(eb)
        inspectFrame.eb = eb

        local hint = inspectFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", 10, -10)
        hint:SetText("Strg+A, Strg+C zum Kopieren")
    end

    inspectFrame.eb:SetText(table.concat(out, "\n"))
    inspectFrame:Show()
    inspectFrame.eb:SetFocus()
    inspectFrame.eb:HighlightText()
end

local function SafeStr(v)
    if IsSecret(v) then return "<secret>" end
    local t = type(v)
    if t == "string" then
        return '"' .. v:gsub("\n", "\\n"):gsub("|", "||") .. '"'
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    end
    return "<" .. t .. ">"
end

local function FlatDump(v, indent, out, depth)
    depth = depth or 0
    if type(v) ~= "table" or depth > 2 then
        out[#out + 1] = indent .. SafeStr(v)
        return
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local x = v[k]
        if type(x) == "table" and not x.GetObjectType then
            out[#out + 1] = indent .. tostring(k) .. ":"
            FlatDump(x, indent .. "  ", out, depth + 1)
        elseif type(x) ~= "function" and not (type(x) == "table") then
            out[#out + 1] = indent .. tostring(k) .. " = " .. SafeStr(x)
        end
    end
end

----------------------------------------------------------------------
-- /snapstatisticsinfo: Rohdaten des Statistik-Systems (zur Fehlersuche)
----------------------------------------------------------------------
SLASH_SNAPSTATISTICSINFO1 = "/snapstatisticsinfo"
SlashCmdList.SNAPSTATISTICSINFO = function()
    local out = {}
    local function add(x) out[#out + 1] = x end
    local function match(name)
        local l = tostring(name):lower()
        return l:find("statistic") or l:find("achievement") or l:find("category")
    end

    -- 1) Funktionen
    local funcs = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "function" and match(k) then funcs[#funcs + 1] = k end
        if type(k) == "string" and k:find("^C_") and type(v) == "table" then
            local nsHit = match(k)
            for fk, fv in pairs(v) do
                if type(fv) == "function" and (nsHit or match(fk)) then funcs[#funcs + 1] = k .. "." .. tostring(fk) end
            end
        end
    end
    table.sort(funcs)
    add("=== Funktionen ===")
    for i = 1, #funcs, 3 do add("  " .. table.concat(funcs, ", ", i, math.min(i + 2, #funcs))) end

    -- 2) Retail-Weg: Kategorien und Statistiken
    add("")
    add("=== Kategorien (GetStatisticsCategoryList) ===")
    if GetStatisticsCategoryList then
        local ok, cats = pcall(GetStatisticsCategoryList)
        if ok and type(cats) == "table" then
            add("Anzahl: " .. #cats)
            for i, id in ipairs(cats) do
                if i > 25 then add("  …") break end
                local name, parent = GetCategoryInfo and GetCategoryInfo(id)
                local n = GetCategoryNumAchievements and GetCategoryNumAchievements(id) or "?"
                add(string.format("  [%s] %s (Eltern: %s, Einträge: %s)", tostring(id), SafeStr(name), tostring(parent), tostring(n)))
                -- die ersten Statistiken dieser Kategorie mit Wert
                if type(n) == "number" and n > 0 and GetAchievementInfo then
                    for j = 1, math.min(n, 4) do
                        local ok2, sid, sname = pcall(GetAchievementInfo, id, j)
                        if ok2 and sid then
                            local val = GetStatistic and select(2, pcall(GetStatistic, sid))
                            add(string.format("      %s: %s = %s", tostring(sid), SafeStr(sname), SafeStr(val)))
                        end
                    end
                end
            end
        else
            add("  Aufruf fehlgeschlagen: " .. SafeStr(cats))
        end
    else
        add("  nicht vorhanden")
    end

    -- 3) Was das Original-Fenster gerade anzeigt
    add("")
    add("=== StatisticsFrame ===")
    local sf = _G.StatisticsFrame
    if not sf then
        add("  nicht gefunden")
    else
        local m = {}
        for k, v in pairs(sf) do if type(k) == "string" and type(v) == "function" then m[#m + 1] = k end end
        table.sort(m)
        add("Methoden: " .. table.concat(m, ", "))
        local box = sf.ScrollBox
        local dp = box and box.GetDataProvider and box:GetDataProvider()
        if dp and dp.Enumerate then
            local n = 0
            -- Baum-Liste: Enumerate(indexBegin, indexEnd, excludeCollapsed);
            -- false = auch zugeklappte Einträge mitnehmen
            local okE, iter, st, ctl = pcall(dp.Enumerate, dp, nil, nil, false)
            if not okE then okE, iter, st, ctl = pcall(dp.Enumerate, dp) end
            if not okE then iter, st, ctl = function() end, nil, nil end
            for _, elem in iter, st, ctl do
                n = n + 1
                if n > 25 then add("  …") break end
                local data = elem.GetData and elem:GetData() or elem
                add("Eintrag " .. n .. ":")
                FlatDump(data, "    ", out)
            end
            if n == 0 then add("  (keine Einträge)") end
        else
            add("  kein DataProvider gefunden")
        end
        -- weitere Teile (z. B. Detailbereich)
        for k, v in pairs(sf) do
            if type(k) == "string" and type(v) == "table" and v.GetObjectType and k ~= "ScrollBox" and k ~= "ScrollBar" then
                local mm = {}
                for kk, vv in pairs(v) do if type(kk) == "string" and type(vv) == "function" then mm[#mm + 1] = kk end end
                table.sort(mm)
                add("Teil " .. k .. ": " .. table.concat(mm, ", "))
            end
        end
    end

    ShowTextWindow(out)
    print("|cff33ff99[" .. ADDON .. "]|r Statistik-Info gesammelt (" .. #out .. " Zeilen).")
end
