-- SnapChar – Einstellungen (8. Tab, kleiner Zahnrad-Tab ganz unten)
-- Links: Gegenstandsstufen ein/aus. Rechts: Reihenfolge der Tabs per Ziehen.
-- Unten mittig: Knopf, der Blizzards Original-Charakterfenster öffnet.

local ADDON, ns = ...
local L, T, Atlas = ns.L, ns.T, ns.Atlas

local tab = ns.CreatePanelTab()
ns.settingsTab = tab
local lp, rp = tab.lp, tab.rp

----------------------------------------------------------------------
-- Hilfen
----------------------------------------------------------------------
local function SectionTitle(parent, text, y)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOP", 0, y)
    t:SetText(text)
    local line = Atlas(parent, "UI-Character-Info-ScrollLine-Long", "ARTWORK", 0, true)
    line:SetPoint("TOPLEFT", 12, y - 26)
    line:SetPoint("TOPRIGHT", -12, y - 26)
    return t
end

-- Kategorie-Box: dünner Rahmen in Bronze, leicht abgedunkelter Hintergrund,
-- Überschrift oben links. Inhalte werden relativ zur Box angeordnet.
local function CategoryBox(parent, title, y, height)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 26, y)
    box:SetPoint("TOPRIGHT", -6, y)
    box:SetHeight(height)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0, 0, 0, 0.25)
    box:SetBackdropBorderColor(0.55, 0.42, 0.24, 0.9)
    local t = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 12, -10)
    t:SetText(title)
    return box
end

local function SettingCheck(parent, text, key, y)
    local c = ns.MakeCheck(parent, text, 0)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", 12, y)
    c:SetScript("OnClick", function(self) ns.SetSetting(key, self:GetChecked() and true or false) end)
    c.Refresh = function() c:SetChecked(ns.GetSetting(key)) end
    return c
end

----------------------------------------------------------------------
-- Links: Gegenstandsstufen
----------------------------------------------------------------------
local titleLayer = CreateFrame("Frame", nil, lp)
titleLayer:SetAllPoints(lp)
titleLayer:SetFrameLevel(lp:GetFrameLevel() + 30)
SectionTitle(titleLayer, L({ "Character SETTINGS" }, "Character Settings"), -26)

-- Scrollbereich für die Kategorien (zwischen Überschrift-Linie und Knopf unten)
local scroll = CreateFrame("ScrollFrame", nil, lp)
scroll:SetPoint("TOPLEFT", 6, -46)
scroll:SetPoint("BOTTOMRIGHT", -22, 26)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(1, 1)
scroll:SetScrollChild(content)

local sbar = CreateFrame("Slider", nil, lp)
sbar:SetOrientation("VERTICAL")
sbar:SetWidth(8)
sbar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, -4)
sbar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 4)
sbar:SetValueStep(1)
sbar:SetMinMaxValues(0, 0)
do
    local t = Atlas(sbar, "minimal-scrollbar-track-top", "BACKGROUND", 0, true);    t:SetPoint("TOP")
    local b = Atlas(sbar, "minimal-scrollbar-track-bottom", "BACKGROUND", 0, true); b:SetPoint("BOTTOM")
    local m = Atlas(sbar, "!minimal-scrollbar-track-middle", "BACKGROUND", 0, true)
    m:SetPoint("TOP", t, "BOTTOM"); m:SetPoint("BOTTOM", b, "TOP"); m:SetVertTile(true)
    local thumb = sbar:CreateTexture(nil, "ARTWORK")
    thumb:SetAtlas("minimal-scrollbar-small-thumb-middle")
    thumb:SetSize(8, 40)
    sbar:SetThumbTexture(thumb)
end
sbar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)

local function UpdateScroll()
    local max = math.max(0, content:GetHeight() - scroll:GetHeight())
    sbar:SetMinMaxValues(0, max)
    if sbar:GetValue() > max then sbar:SetValue(max) end
    sbar:SetShown(max > 0.5)
end
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(_, d) sbar:SetValue(sbar:GetValue() - d * 40) end)
scroll:SetScript("OnSizeChanged", function(_, w)
    if w and w > 0 then content:SetWidth(w) end
    UpdateScroll()
end)

-- Kategorien untereinander: jede neue Box schließt mit Abstand an die vorige an
local nextY = -10
local function NextBox(title, height)
    local box = CategoryBox(content, title, nextY, height)
    nextY = nextY - height - 12
    content:SetHeight(-nextY -22)
    UpdateScroll()
    return box
end

local checks = {}

-- Regler mit Eingabefeld für einen Zahlenwert (Schritte 0.01).
-- Beim Ziehen läuft nur die Zahl mit; übernommen wird beim Loslassen oder
-- mit Enter im Feld (Punkt oder Komma: "1.25" / "1,25").
local function ValueSlider(box, y, key, min, max, labelText)
    local STEP = 0.01
    local function Round(v) return math.floor(v / STEP + 0.5) * STEP end

    local slider = CreateFrame("Slider", nil, box, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(17)
    local left = 16
    if labelText then
        local lbl = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", 16, y - 1)
        lbl:SetWidth(110)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(labelText)
        left = 130
    end
    slider:SetPoint("TOPLEFT", left, y)
    slider:SetPoint("TOPRIGHT", -96, y)
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(STEP)
    slider:SetObeyStepOnDrag(true)
    -- kein Mausrad: sonst verstellt man beim Scrollen der Einstellungen
    -- versehentlich den Regler, über dem die Maus gerade steht
    slider:EnableMouseWheel(false)

    local low = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, -1)
    low:SetText(("%.2f"):format(min))
    local high = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, -1)
    high:SetText(("%.2f"):format(max))

    local edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    edit:SetSize(52, 20)
    edit:SetPoint("LEFT", slider, "RIGHT", 18, 0)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(5)
    edit:SetJustifyH("CENTER")

    local updating = false
    local function Current() return ns.GetSetting(key) or 1 end
    local function ShowValue(v) edit:SetText(("%.2f"):format(v)) end

    local function Commit(v)
        v = math.max(min, math.min(max, Round(v)))
        updating = true
        slider:SetValue(v)
        updating = false
        ShowValue(v)
        if math.abs(Current() - v) > 0.0001 then ns.SetSetting(key, v) end
    end

    slider:SetScript("OnValueChanged", function(_, v)
        if not updating then ShowValue(Round(v)) end
    end)
    slider:SetScript("OnMouseUp", function(self) Commit(self:GetValue()) end)

    edit:SetScript("OnEnterPressed", function(self)
        local v = tonumber((self:GetText():gsub(",", ".")))
        if v then Commit(v) else ShowValue(Current()) end
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        ShowValue(Current())
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function() ShowValue(Current()) end)

    return {
        Refresh = function()
            updating = true
            slider:SetValue(Current())
            updating = false
            ShowValue(Current())
        end,
    }
end


-- Kategorie: Schriftgröße (Werteliste und übrige Tabs getrennt, 0.75–1.50)
local fontBox = NextBox(T["Font Size"], 116)
checks[#checks + 1] = ValueSlider(fontBox, -36, "statsFontScale", 0.75, 1.5, T["Stat list"])
checks[#checks + 1] = ValueSlider(fontBox, -76, "uiFontScale", 0.75, 1.5, T["Other tabs"])

-- Kategorie: Gegenstandsstufe
local ilvlBox = NextBox(T["Item Level"], 94)
checks[#checks + 1] = SettingCheck(ilvlBox, T["Show average item level"], "showAvgIlvl", -32)
checks[#checks + 1] = SettingCheck(ilvlBox, T["Show item level on equipment slots"], "showSlotIlvl", -60)

-- Kategorie: Titelleiste (Name und Stufe oben im Fenster)
local titleBox = NextBox(T["Title"], 94)
checks[#checks + 1] = SettingCheck(titleBox, T["Hide last name"], "hideLastName", -32)
checks[#checks + 1] = SettingCheck(titleBox, T["Hide level"], "hideLevel", -60)

----------------------------------------------------------------------
-- Rechts: Reihenfolge der Tabs (Ziehen und Ablegen)
----------------------------------------------------------------------
SectionTitle(rp, T["Tab Order"], -10)
--[[
local hint = rp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("TOPLEFT", 16, -56)
hint:SetPoint("TOPRIGHT", -16, -56)
hint:SetJustifyH("LEFT")
hint:SetText(T["Drag a tab to a new position. The first tab always stays on top."])
]]--
local ROW_H, ROW_GAP, LIST_TOP = 34, 3, -38
local rows = {}      -- [1] = fester Tab "Werte", [2..7] = ziehbar
local order = {}     -- aktuelle Reihenfolge (Tab-Indizes) für Zeile 2..7
local dragFrom       -- Position (1..6) des gezogenen Eintrags in 'order'

-- Icon eines Tabs in eine Textur übernehmen (Atlas oder Textur + Ausschnitt)
local function CopyIcon(dst, tabIndex)
    local src = ns.modeTabs[tabIndex] and ns.modeTabs[tabIndex].icon
    if tabIndex == 1 then
        SetPortraitTexture(dst, "player")
        dst:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        return
    end
    if tabIndex == 9 then -- Begleiter: Porträt des Tiers, ohne Tier ein Pfoten-Symbol
        if UnitExists("pet") then
            SetPortraitTexture(dst, "pet")
            dst:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            dst:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
            dst:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        return
    end
    if not src then return end
    local atlas = src.GetAtlas and src:GetAtlas()
    if atlas then
        dst:SetAtlas(atlas)
    else
        dst:SetTexture(src:GetTexture())
        dst:SetTexCoord(src:GetTexCoord())
    end
end

local function MakeRow(i)
    local r = CreateFrame("Button", nil, rp)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 16, LIST_TOP - (i - 1) * (ROW_H + ROW_GAP))
    r:SetPoint("TOPRIGHT", -16, LIST_TOP - (i - 1) * (ROW_H + ROW_GAP))

    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)

    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAtlas("charactercreate-customize-dropdown-linemouseover-middle")
    hl:SetAllPoints()
    hl:SetAlpha(0.3)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW_H - 6, ROW_H - 6)
    r.icon:SetPoint("LEFT", 3, 0)

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", -30, 0)
    r.name:SetJustifyH("LEFT")

    -- rechts: Griff zum Ziehen bzw. Schloss beim festen ersten Tab
    r.grip = r:CreateTexture(nil, "ARTWORK")
    r.grip:SetSize(16, 16)
    r.grip:SetPoint("RIGHT", -8, 0)
    return r
end

-- Einfüge-Linie und "Geist" des gezogenen Eintrags
local insertLine = rp:CreateTexture(nil, "OVERLAY")
insertLine:SetColorTexture(1, 0.82, 0, 1)
insertLine:SetHeight(2)
insertLine:Hide()

local ghost = CreateFrame("Frame", nil, UIParent)
ghost:SetFrameStrata("TOOLTIP")
ghost:SetSize(200, ROW_H)
ghost:Hide()
do
    local bg = ghost:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetSize(ROW_H - 6, ROW_H - 6)
    ghost.icon:SetPoint("LEFT", 3, 0)
    ghost.name = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ghost.name:SetPoint("LEFT", ghost.icon, "RIGHT", 8, 0)
end

local function Refresh()
    order = ns.GetTabOrder()
    for i = 1, #order + 1 do
        local r = rows[i] or MakeRow(i)
        rows[i] = r
        local tabIndex = (i == 1) and 1 or order[i - 1]
        r.tabIndex = tabIndex
        -- ohne Doppelpunkt am Ende ("Werte:" -> "Werte")
        r.name:SetText(((ns.tabTitles[tabIndex] or ""):gsub("%s*[:：]%s*$", "")))
        CopyIcon(r.icon, tabIndex)
        if i == 1 then
            r.grip:SetAtlas("Forge-Lock") -- bleibt fest oben
            r.grip:SetShown(r.grip:GetAtlas() ~= nil)
            r.name:SetFontObject("GameFontDisable")
        else
            r.grip:Hide()
            r.name:SetFontObject("GameFontHighlight")
        end
        r:SetAlpha(1)
    end
    for _, c in ipairs(checks) do c.Refresh() end
end

-- Lücke unter dem Mauszeiger: wie viele ziehbare Zeilen liegen darüber?
local function GapUnderCursor()
    local _, cy = GetCursorPosition()
    cy = cy / rp:GetEffectiveScale()
    local g = 0
    for i = 2, #order + 1 do
        local _, ry = rows[i]:GetCenter()
        if ry and ry > cy then g = g + 1 end
    end
    return g
end

local function PlaceInsertLine(g)
    insertLine:ClearAllPoints()
    if g == 0 then
        insertLine:SetPoint("BOTTOMLEFT", rows[2], "TOPLEFT", 0, ROW_GAP / 2 - 1)
        insertLine:SetPoint("BOTTOMRIGHT", rows[2], "TOPRIGHT", 0, ROW_GAP / 2 - 1)
    else
        insertLine:SetPoint("TOPLEFT", rows[g + 1], "BOTTOMLEFT", 0, -ROW_GAP / 2 + 1)
        insertLine:SetPoint("TOPRIGHT", rows[g + 1], "BOTTOMRIGHT", 0, -ROW_GAP / 2 + 1)
    end
    insertLine:Show()
end

ghost:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / s + 12, y / s)
    PlaceInsertLine(GapUnderCursor())
end)

local function StartDrag(r, pos)
    dragFrom = pos
    ghost.name:SetText(r.name:GetText())
    CopyIcon(ghost.icon, r.tabIndex)
    ghost:SetWidth(r:GetWidth() * rp:GetEffectiveScale() / UIParent:GetEffectiveScale())
    ghost:Show()
    r:SetAlpha(0.4)
end

local function StopDrag()
    if not dragFrom then return end
    local g = GapUnderCursor()
    ghost:Hide()
    insertLine:Hide()
    local from = dragFrom
    dragFrom = nil
    -- neue Position: der gezogene Eintrag zählt oberhalb der Lücke nicht mit
    local to = (g < from) and (g + 1) or g
    if to ~= from then
        local newOrder = { unpack(order) }
        local moved = table.remove(newOrder, from)
        table.insert(newOrder, to, moved)
        ns.SetSetting("tabOrder", newOrder)
    end
    Refresh()
end

-- Zeilen anlegen und Ziehen einrichten (Zeile 1 bleibt fest)
Refresh()
for i = 2, #order + 1 do
    local r = rows[i]
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function(self) StartDrag(self, i - 1) end)
    r:SetScript("OnDragStop", StopDrag)
end

-- Standard-Reihenfolge wiederherstellen
local reset = CreateFrame("Button", nil, rp, "UIPanelButtonTemplate")
reset:SetSize(140, 24)
reset:SetPoint("TOP", 0, LIST_TOP - (#order + 1) * (ROW_H + ROW_GAP) - 8)
reset:SetText(L({ "RESET_TO_DEFAULT", "RESET" }, "Reset"))
reset:SetScript("OnClick", function()
    ns.SetSetting("tabOrder", nil)
    Refresh()
end)

tab.frame:HookScript("OnShow", Refresh)
tab.frame:HookScript("OnHide", function()
    dragFrom = nil
    ghost:Hide()
    insertLine:Hide()
end)
ns.OnSettingChanged(function() if tab.frame:IsShown() then Refresh() end end)

--[[--------------------------------------------------------------------
-- Unten mittig: Blizzards Original-Charakterfenster freigeben (wie /snapchar blizzard):
-- SnapChar schließt sich, danach öffnen Taste oder Menü-Knopf 15 Sek. lang das Original
----------------------------------------------------------------------
local open = CreateFrame("Button", nil, tab.frame, "UIPanelButtonTemplate")
open:SetSize(240, 26)
open:SetPoint("BOTTOM", lp, "BOTTOM", 0, 20) -- mittig in der linken Hälfte
open:SetFrameLevel(tab.frame:GetFrameLevel() + 10)
open:SetText(T["Open Blizzard Character Frame"])
open:SetScript("OnClick", function()
    if ns.OpenOriginalCharacter then ns.OpenOriginalCharacter() end
end)
]]--
ns.RegisterTab(8, "settings", tab, L({ "SETTINGS" }, "Settings"))
