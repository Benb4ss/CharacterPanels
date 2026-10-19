-- SnapChar – Begleiter-Tab (9. Tab, nur mit Begleiter sichtbar: Jäger, Hexenmeister)
-- Links: Modell des Begleiters auf dem (entsättigten) Rassen-Hintergrund, Zufriedenheit,
-- Erfahrungsbalken. Rechts: "Stufe 8 Bär", Treue und eine Werteliste im Stil der
-- Charakterwerte (gleiche Optik, gleiche Schriftgröße, Tooltips von Blizzard).

local ADDON, ns = ...
local L, T, Atlas, IsSecret = ns.L, ns.T, ns.Atlas, ns.IsSecret

local PET_TAB = 9
local tab = ns.CreatePanelTab()
local frame, lp, rp = tab.frame, tab.lp, tab.rp

----------------------------------------------------------------------
-- Links: Hintergrund, Modell, Steuerung, Zufriedenheit, Erfahrung
----------------------------------------------------------------------
-- Rassen-Hintergrund wie beim Charakter, aber entsättigt (wie im Original)
local bgParts = {}
for i = 1, 4 do bgParts[i] = lp:CreateTexture(nil, "BACKGROUND", nil, 0) end
bgParts[1]:SetPoint("TOPLEFT")
bgParts[2]:SetPoint("TOPLEFT", bgParts[1], "TOPRIGHT")
bgParts[3]:SetPoint("TOPLEFT", bgParts[1], "BOTTOMLEFT")
bgParts[4]:SetPoint("TOPLEFT", bgParts[1], "BOTTOMRIGHT")
local function UpdateBackground()
    local src = ns.raceParts or {}
    local w, h = lp:GetSize()
    local wl, hl = w * 256 / 318, h * 255 / 383
    for i, t in ipairs(bgParts) do
        local o = src[i]
        local tex = o and o:GetTexture()
        if tex then
            t:SetTexture(tex)
            t:SetTexCoord(o:GetTexCoord())
        end
        t:SetDesaturated(true)
    end
    bgParts[1]:SetSize(wl, hl)
    bgParts[2]:SetSize(w - wl, hl)
    bgParts[3]:SetSize(wl, h - hl)
    bgParts[4]:SetSize(w - wl, h - hl)
end
Atlas(lp, "UI-Character-Info-RaceBG-Overlay", "BORDER"):SetAllPoints()

local model = CreateFrame("PlayerModel", nil, lp)
model:SetPoint("TOPLEFT", 60, -20)
model:SetPoint("BOTTOMRIGHT", -60, 50)
local camScale = 1
model:EnableMouse(true)
model:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
model:SetScript("OnUpdate", function(self)
    if self.dragX then
        local x = GetCursorPosition()
        self:SetFacing(self:GetFacing() + (x - self.dragX) * 0.02)
        self.dragX = x
    end
end)

-- Steuerung (Zoom, Drehen, Zurücksetzen) wie beim Charakter, nur bei Mauskontakt
local CONTROLS = {
    { icon = "common-icon-zoomin",      click = function() camScale = math.max(0.4, camScale - 0.1) model:SetCamDistanceScale(camScale) end },
    { icon = "common-icon-zoomout",     click = function() camScale = math.min(1.6, camScale + 0.1) model:SetCamDistanceScale(camScale) end },
    { icon = "common-icon-rotateleft",  click = function() model:SetFacing(model:GetFacing() - 0.4) end },
    { icon = "common-icon-rotateright", click = function() model:SetFacing(model:GetFacing() + 0.4) end },
    { icon = "common-icon-undo",        click = function() camScale = 1 model:SetCamDistanceScale(1) model:SetFacing(0) end },
}
local controls = CreateFrame("Frame", nil, lp)
controls:SetFrameLevel(model:GetFrameLevel() + 2)
controls:SetSize(#CONTROLS * 27, 22)
controls:SetPoint("CENTER", lp, "TOP", 7, -25)
controls:Hide()
for i, c in ipairs(CONTROLS) do
    local b = CreateFrame("Button", nil, controls)
    b:SetSize(22, 22)
    b:SetPoint("CENTER", controls, "CENTER", (i - 3) * 27, 0)
    b:SetNormalAtlas("common-button-square-gray-up")
    b:SetPushedAtlas("common-button-square-gray-down")
    local icon = Atlas(b, c.icon, "OVERLAY")
    icon:SetSize(15, 15)
    icon:SetPoint("CENTER")
    b:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function() icon:SetPoint("CENTER") end)
    b:SetScript("OnClick", c.click)
end
local hoverWatch = CreateFrame("Frame", nil, lp)
hoverWatch:SetScript("OnUpdate", function()
    controls:SetShown(model:IsMouseOver() or controls:IsMouseOver())
end)

-- Zufriedenheit (nur Jäger): Symbol oben links mit Tooltip
local happy = CreateFrame("Frame", nil, lp)
happy:SetSize(24, 23)
happy:SetPoint("TOPLEFT", 44, -42)
happy:SetFrameLevel(model:GetFrameLevel() + 3)
happy.icon = happy:CreateTexture(nil, "ARTWORK")
happy.icon:SetAllPoints()
happy.icon:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
happy:EnableMouse(true)
happy:Hide()
local HAPPY_COORDS = {
    [1] = { 0.375, 0.5625, 0, 0.359375 },  -- unglücklich
    [2] = { 0.1875, 0.375, 0, 0.359375 },  -- zufrieden
    [3] = { 0, 0.1875, 0, 0.359375 },      -- glücklich
}
happy:SetScript("OnEnter", function(self)
    if not self.happiness then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(_G["PET_HAPPINESS" .. self.happiness] or "")
    if self.damage and PET_DAMAGE_PERCENTAGE then
        GameTooltip:AddLine(PET_DAMAGE_PERCENTAGE:format(self.damage), 1, 1, 1)
    end
    if self.loyaltyRate and self.loyaltyRate < 0 and LOSING_LOYALTY then
        GameTooltip:AddLine(LOSING_LOYALTY, 1, 1, 1)
    elseif self.loyaltyRate and self.loyaltyRate > 0 and GAINING_LOYALTY then
        GameTooltip:AddLine(GAINING_LOYALTY, 1, 1, 1)
    end
    GameTooltip:Show()
end)
happy:SetScript("OnLeave", GameTooltip_Hide)

-- Erfahrungsbalken unten mittig
local xp = CreateFrame("Frame", nil, lp)
xp:SetSize(300, 24)
xp:SetPoint("BOTTOM", 0, 18)
xp:SetFrameLevel(model:GetFrameLevel() + 3)
Atlas(xp, "common-stat-bar-BG", "BACKGROUND"):SetAllPoints()
local xpBar = CreateFrame("StatusBar", nil, xp)
xpBar:SetPoint("TOPLEFT", 3, -3)
xpBar:SetPoint("BOTTOMRIGHT", -3, 3)
do
    local fill = xpBar:CreateTexture(nil, "ARTWORK")
    fill:SetAtlas("common-stat-bar-white")
    xpBar:SetStatusBarTexture(fill)
    xpBar:SetStatusBarColor(0.58, 0.0, 0.55)
end
local xpText = ns.ScaleFont(xpBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), "ui")
xpText:SetPoint("CENTER", xp)

----------------------------------------------------------------------
-- Rechts: Kopf (Stufe/Familie, Treue) und Werteliste
----------------------------------------------------------------------
local levelText = rp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
levelText:SetPoint("TOP", 0, -24)
local loyaltyText = rp:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
loyaltyText:SetPoint("TOP", levelText, "BOTTOM", 0, -6)

local HEADER_H = 76 -- Platz für Stufe und Treue über der Liste

local listHost = CreateFrame("Frame", nil, rp)
listHost:SetPoint("TOPLEFT", 4, -HEADER_H)
listHost:SetPoint("BOTTOMRIGHT", -2, 6)
local border = Atlas(listHost, "common-insideframe", "BORDER")
border:SetAllPoints(listHost)
if ns.CopySlice then ns.CopySlice(border, nil, 24) end

local scroll = CreateFrame("ScrollFrame", nil, listHost)
scroll:SetPoint("TOPLEFT", 6, -5)
scroll:SetPoint("BOTTOMRIGHT", -8, 5)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(1, 1)
scroll:SetScrollChild(content)

local bar = CreateFrame("Slider", nil, listHost)
bar:SetOrientation("VERTICAL")
bar:SetWidth(8)
bar:SetPoint("TOPRIGHT", -8, -20)
bar:SetPoint("BOTTOMRIGHT", -8, 20)
bar:SetMinMaxValues(0, 0)
bar:SetValueStep(1)
do
    local t = Atlas(bar, "minimal-scrollbar-track-top", "BACKGROUND", 0, true);    t:SetPoint("TOP")
    local b = Atlas(bar, "minimal-scrollbar-track-bottom", "BACKGROUND", 0, true); b:SetPoint("BOTTOM")
    local m = Atlas(bar, "!minimal-scrollbar-track-middle", "BACKGROUND", 0, true)
    m:SetPoint("TOP", t, "BOTTOM"); m:SetPoint("BOTTOM", b, "TOP"); m:SetVertTile(true)
    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetAtlas("minimal-scrollbar-small-thumb-middle")
    thumb:SetSize(8, 40)
    bar:SetThumbTexture(thumb)
end
bar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(_, d) bar:SetValue(bar:GetValue() - d * 30) end)

local scrollbarShown
local function UpdateScroll()
    local max = math.max(0, content:GetHeight() - scroll:GetHeight())
    bar:SetMinMaxValues(0, max)
    if bar:GetValue() > max then bar:SetValue(max) end
    local need = max > 0.5
    bar:SetShown(need)
    if need ~= scrollbarShown then
        scrollbarShown = need
        if not need then bar:SetValue(0) end
        C_Timer.After(0, function()
            scroll:ClearAllPoints()
            scroll:SetPoint("TOPLEFT", 6, -5)
            scroll:SetPoint("BOTTOMRIGHT", scrollbarShown and -24 or -8, 5)
            content:SetWidth(scroll:GetWidth())
        end)
    end
end
scroll:SetScript("OnSizeChanged", function(_, w)
    if w and w > 0 then content:SetWidth(w) end
    UpdateScroll()
end)

-- Zeilen im Stil der Charakter-Werteliste (gleiche Maße und Schrift)
local ROW_H, HEADER_BAR_H, GAP_ABOVE, GAP_BELOW = 18, 29, -3, -4
local function Shrink(fs) -- eine Schriftgröße kleiner, wie in der Werteliste
    local font, size, flags = fs:GetFont()
    if font and size then fs:SetFont(font, size - 1, flags) end
    return ns.ScaleFont(fs, "stats")
end

local layout = {} -- Reihenfolge aller Zeilen (Überschriften und Werte)

local function AddHeader(text)
    local row = CreateFrame("Frame", nil, content)
    row:SetFrameLevel(content:GetFrameLevel() + 2)
    local gap = (#layout == 0) and 0 or GAP_ABOVE
    local barTex = Atlas(row, "UI-Character-Info-Title", "BACKGROUND")
    barTex:SetPoint("TOPLEFT", 6, -gap)
    barTex:SetPoint("TOPRIGHT", -6, -gap)
    barTex:SetHeight(HEADER_BAR_H)
    local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("CENTER", barTex)
    Shrink(t)
    t:SetText(text)
    layout[#layout + 1] = { row = row, h = gap + HEADER_BAR_H + GAP_BELOW, header = true }
    return row
end

local function AddRow(name, opts)
    local row = CreateFrame("Frame", nil, content)
    local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("RIGHT", -8, 0)
    value:SetJustifyH("RIGHT")
    Shrink(value)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local x = 8
    if opts.icon then
        -- Widerstände: Symbol links vor dem Namen
        local ic = row:CreateTexture(nil, "ARTWORK")
        ic:SetSize(18, 18)
        ic:SetPoint("LEFT", 6, 0)
        ic:SetTexture(opts.icon)
        if opts.coords then ic:SetTexCoord(unpack(opts.coords)) end
        x = 30
    end
    label:SetPoint("LEFT", x, 0)
    label:SetPoint("RIGHT", value, "LEFT", -6, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetMaxLines(1)
    Shrink(label)
    label:SetText(ns.WithColon(name))

    row.fs, row.label = value, label
    row.key, row.hideAt, row.update = opts.key, opts.hideAt, opts.update
    row:EnableMouse(true)
    row:SetScript("OnEnter", ns.ShowStatTooltip)
    row:SetScript("OnLeave", function(self)
        self.UpdateTooltip = nil
        GameTooltip_Hide()
    end)
    layout[#layout + 1] = { row = row, isRow = true }
    return row
end

-- Zeilen neu anordnen: ausgeblendete Zeilen belegen keinen Platz, die Zebra-
-- Streifen richten sich nach den sichtbaren Zeilen, Zeilen wachsen mit der Schrift
local function Relayout()
    local rowH = math.floor(ROW_H * math.max(1, ns.GetFontScale("stats")) + 0.5)
    local y, zebra = 0, true
    for _, e in ipairs(layout) do
        local r = e.row
        if e.header then
            zebra = true
        end
        if r.hidden then
            r:Hide()
        else
            r:Show()
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r:SetPoint("TOPRIGHT", 0, -y)
            local h = e.isRow and rowH or e.h
            r:SetHeight(h)
            y = y + h
            if e.isRow then
                if not r.zebraTex then
                    r.zebraTex = Atlas(r, "UI-Character-Info-Line-Bounce", "BACKGROUND")
                    r.zebraTex:SetAllPoints()
                end
                r.zebraTex:SetShown(zebra)
                zebra = not zebra
            end
        end
    end
    content:SetHeight(math.max(1, y))
    UpdateScroll()
end

----------------------------------------------------------------------
-- Werte: im Kampf geheim -> nur direkt anzeigbare Werte aktualisieren
----------------------------------------------------------------------
local function SetVal(fs, fmt, v)
    if IsSecret(v) then fs:SetFormattedText(fmt, v)
    elseif v == nil then fs:SetText("–")
    else fs:SetFormattedText(fmt, v) end
end

-- Hilfs-Frame für Blizzards Wert-Funktionen (liefern Text, Tooltip, Ausblenden)
local proxyParent = CreateFrame("Frame")
proxyParent:Hide()
local proxy = CreateFrame("Frame", nil, proxyParent)
proxy.Label = proxy:CreateFontString(nil, "OVERLAY", "GameFontNormal")
proxy.Value = proxy:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
proxy.Background = proxy:CreateTexture()
local KEEP = { Label = true, Value = true, Background = true }

local function RunBlizzard(row)
    local info = row.key and PAPERDOLL_STATINFO and PAPERDOLL_STATINFO[row.key]
    if not (info and info.updateFunc) then return false end
    for k in pairs(proxy) do
        if type(k) == "string" and not KEEP[k] then proxy[k] = nil end
    end
    proxy.Value:SetText("")
    proxy:Show()
    if not pcall(info.updateFunc, proxy, "pet") then return false end
    -- Tooltip-Daten übernehmen
    for k in pairs(row.tipKeys or {}) do row[k] = nil end
    row.tipKeys = {}
    for k, v in pairs(proxy) do
        if type(k) == "string" and not KEEP[k] then
            row.tipKeys[k] = true
            row[k] = v
        end
    end
    -- Ausblenden wie im Original (hideAt bzw. von Blizzard versteckt)
    local hide = not proxy:IsShown()
    if row.hideAt ~= nil and proxy.numericValue ~= nil and not IsSecret(proxy.numericValue)
        and proxy.numericValue == row.hideAt then
        hide = true
    end
    row.hidden = hide
    local ok, txt = pcall(proxy.Value.GetText, proxy.Value)
    if ok and txt and not IsSecret(txt) and txt ~= "" then row.fs:SetText(txt) end
    return true
end

local rows = {}
AddHeader(L({ "STAT_CATEGORY_GENERAL", "GENERAL" }, "General"))
rows[#rows + 1] = AddRow(L({ "HEALTH" }, "Health"), { key = "HEALTH",
    update = function(fs) SetVal(fs, "%s", UnitHealthMax("pet")) end })
rows[#rows + 1] = AddRow(L({ "STAT_ARMOR", "ARMOR" }, "Armor"), { key = "ARMOR",
    update = function(fs) SetVal(fs, "%d", (select(2, UnitArmor("pet")))) end })
rows[#rows + 1] = AddRow(L({ "DAMAGE" }, "Damage"), { key = "MAINHAND_DAMAGE",
    update = function(fs)
        local lo, hi = UnitDamage("pet")
        if lo == nil and not IsSecret(lo) then fs:SetText("–") return end
        fs:SetFormattedText("%d - %d", lo, hi)
    end })
rows[#rows + 1] = AddRow(L({ "STAT_ATTACK_POWER", "MELEE_ATTACK_POWER" }, "Attack Power"), { key = "ATTACK_AP", hideAt = 0 })
rows[#rows + 1] = AddRow(L({ "STAT_SPELLPOWER", "SPELL_BONUS" }, "Spell Power"), { key = "SPELLPOWER", hideAt = 0 })
rows[#rows + 1] = AddRow(L({ "STAT_HIT_CHANCE", "HIT_CHANCE" }, "Hit Chance"), { key = "HITCHANCE", hideAt = 0 })
rows[#rows + 1] = AddRow(L("STAT_CRITICAL_STRIKE", "Critical Strike"), { key = "CRITCHANCE", hideAt = 0 })
rows[#rows + 1] = AddRow(L({ "STAT_HASTE", "HASTE" }, "Haste"), { key = "HASTE", hideAt = 0 })
rows[#rows + 1] = AddRow(L("STAT_MOVEMENT_SPEED", "Movement Speed"), { key = "MOVESPEED",
    update = function(fs)
        local _, run = GetUnitSpeed("pet")
        fs:SetTextColor(1, 1, 1)
        if IsSecret(run) then
            -- im Kampf geheim: Prozent lassen sich nicht ausrechnen
            fs:SetText(T["In Combat"])
            fs:SetTextColor(1, 0.2, 0.2)
            return
        end
        if not run then fs:SetText("–") return end
        fs:SetFormattedText("%d%%", run / (BASE_MOVEMENT_SPEED or 7) * 100 + 0.5)
    end })

AddHeader(L({ "STAT_CATEGORY_RESISTANCE", "RESISTANCE_LABEL" }, "Resistances"))
local RES_FILE = "Interface\\PaperDollInfoFrame\\UI-Character-ResistanceIcons"
for _, r in ipairs({
    { school = 6, key = "ARCANE_RESIST", coords = { 0, 1, 0.2265625, 0.33984375 } },
    { school = 2, key = "FIRE_RESIST",   coords = { 0, 1, 0, 0.11328125 } },
    { school = 4, key = "FROST_RESIST",  coords = { 0, 1, 0.33984375, 0.453125 } },
    { school = 3, key = "NATURE_RESIST", coords = { 0, 1, 0.11328125, 0.2265625 } },
    { school = 5, key = "SHADOW_RESIST", coords = { 0, 1, 0.453125, 0.56640625 } },
}) do
    local school = r.school
    rows[#rows + 1] = AddRow(_G["SPELL_SCHOOL" .. school .. "_NAME"] or r.key, {
        key = r.key, icon = RES_FILE, coords = r.coords,
        update = function(fs) SetVal(fs, "%d", (select(2, UnitResistance("pet", school)))) end,
    })
end

----------------------------------------------------------------------
-- Aktualisieren
----------------------------------------------------------------------
local function UpdateHeaderInfo()
    local family = UnitCreatureFamily("pet")
    local level = UnitLevel("pet")
    if UNIT_TYPE_LEVEL_TEMPLATE and family and level then
        levelText:SetFormattedText(UNIT_TYPE_LEVEL_TEMPLATE, level, family)
    elseif level then
        levelText:SetFormattedText("%s %s", L("LEVEL", "Level"), tostring(level))
    else
        levelText:SetText("")
    end
    local loyalty = C_PetInfo and C_PetInfo.GetPetLoyalty and C_PetInfo.GetPetLoyalty()
    loyaltyText:SetText(loyalty or "")

    local h, dmg, rate
    if GetPetHappiness then h, dmg, rate = GetPetHappiness() end
    if h and HAPPY_COORDS[h] then
        happy.happiness, happy.damage, happy.loyaltyRate = h, dmg, rate
        happy.icon:SetTexCoord(unpack(HAPPY_COORDS[h]))
        happy:Show()
    else
        happy:Hide()
    end

    local cur, max = 0, 0
    if GetPetExperience then cur, max = GetPetExperience() end
    if max and not IsSecret(max) and max > 0 then
        xpBar:SetMinMaxValues(0, max)
        xpBar:SetValue(cur or 0)
        xpText:SetFormattedText("%s %s/%s", XP or "XP", ns.fmtNum(cur or 0), ns.fmtNum(max))
        xp:Show()
    else
        xp:Hide()
    end
end

local function UpdateStats()
    local outOfCombat = not InCombatLockdown()
    for _, row in ipairs(rows) do
        -- außerhalb des Kampfes: Blizzards Text, Tooltip und Ausblenden
        if outOfCombat then
            -- liefert Blizzard für einen Wert nichts, den wir auch nicht selbst
            -- berechnen können: Zeile ausblenden statt leer anzeigen
            if not RunBlizzard(row) and not row.update then row.hidden = true end
        end
        -- direkt anzeigbare Werte (auch im Kampf, als geheime Werte)
        if row.update then row.update(row.fs) end
    end
    Relayout()
end

local function UpdateAll()
    if not frame:IsShown() then return end
    if not (HasPetUI and HasPetUI()) then
        levelText:SetText(L({ "ERR_NO_PET", "PET" }, "No pet"))
        loyaltyText:SetText("")
        model:ClearModel()
        happy:Hide()
        xp:Hide()
        return
    end
    UpdateHeaderInfo()
    UpdateStats()
end

local function UpdateModel()
    if HasPetUI and HasPetUI() and UnitExists("pet") then
        model:SetUnit("pet")
        model:SetCamDistanceScale(camScale)
    end
end

frame:HookScript("OnShow", function()
    UpdateBackground()
    UpdateModel()
    UpdateAll()
end)

-- Größere/kleinere Schrift in der Werteliste: Zeilen neu anordnen
ns.OnSettingChanged(function(key)
    if (key == nil or key == "statsFontScale") and frame:IsShown() then Relayout() end
end)

----------------------------------------------------------------------
-- Tab-Knopf: Porträt des Begleiters, nur sichtbar mit Begleiter
----------------------------------------------------------------------
local function UpdateTabButton()
    local t = ns.modeTabs and ns.modeTabs[PET_TAB]
    local has = HasPetUI and HasPetUI()
    if t and t.icon and has then
        SetPortraitTexture(t.icon, "pet")
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    ns.SetTabAvailable(PET_TAB, has)
    -- Begleiter weg, während sein Tab offen ist: zurück zu den Werten
    if not has and frame:IsShown() and not InCombatLockdown() and ns.SetModeByName then
        ns.SetModeByName("stats")
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UNIT_PET")
ev:RegisterEvent("PET_UI_UPDATE")
ev:RegisterEvent("PET_STATS_UPDATE")
ev:RegisterEvent("UNIT_PET_EXPERIENCE")
ev:RegisterEvent("UNIT_HAPPINESS")
ev:RegisterEvent("UNIT_PORTRAIT_UPDATE")
ev:RegisterEvent("UNIT_MODEL_CHANGED")
ev:RegisterEvent("UNIT_LEVEL")
for _, e in ipairs({ "UNIT_STATS", "UNIT_AURA", "UNIT_MAXHEALTH", "UNIT_RESISTANCES",
                     "UNIT_ATTACK_POWER", "UNIT_DAMAGE", "UNIT_ATTACK_SPEED" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_PET" then
        if unit ~= "player" then return end
        UpdateTabButton()
        UpdateModel()
        UpdateAll()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "PET_UI_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
        UpdateTabButton()
        UpdateModel()
        UpdateAll()
        return
    end
    if unit and unit ~= "pet" then return end
    if event == "UNIT_PORTRAIT_UPDATE" then UpdateTabButton() return end
    if event == "UNIT_MODEL_CHANGED" then UpdateModel() return end
    UpdateAll()
end)

ns.RegisterTab(PET_TAB, "pet", tab, L({ "PET" }, "Pet"))
UpdateTabButton()
