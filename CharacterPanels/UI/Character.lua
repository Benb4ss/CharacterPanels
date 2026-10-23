-- Character.lua
--
-- The character panel as a section of the Journal, ported from SnapChar: the
-- model and its controls, the equipment slots with item levels, the
-- resistances, the stat list, and the equipment manager with its flyout and
-- icon picker. Two side tabs switch the right pane between the stat list and
-- the manager.
--
-- Layouts (Components.lua):
--   single      the character alone on one page; the right pane is folded
--   singleLeft  the character on the left page, the right pane on the right
-- The manager lives in the right pane, so choosing it opens the wide layout.
--
-- Not ported: the combat-safe slot overlays (weapon swaps and item use during
-- combat, which SnapChar does with secure buttons), SnapChar's other tabs,
-- its settings, and the replacement of Blizzard's window.

local _, AJ = ...
local UI = AJ.UI
local C = UI.Components
local ns = AJ
local ctx = {}   -- the window's pieces, filled in at load (see BuildAll)
local HELPERS = AJ.Helpers
local AddClassBackground, AnySecret, ApplyPanelInsets, Atlas, BG_CROP_BOTTOM, BackgroundBox, CopySlice, CropBottom, DressPanel, FindRegionByAtlas, IsSecret, L, MakeSideBox, PANEL_GROUPS, PANEL_SIDES, PanelInset, PlaceList, SetVal, Shrink, StatListHeight, StatListOffset, StatRowInset, TrackPanel, UpdateClassBackgrounds, WithColon = HELPERS.AddClassBackground, HELPERS.AnySecret, HELPERS.ApplyPanelInsets, HELPERS.Atlas, HELPERS.BG_CROP_BOTTOM, HELPERS.BackgroundBox, HELPERS.CopySlice, HELPERS.CropBottom, HELPERS.DressPanel, HELPERS.FindRegionByAtlas, HELPERS.IsSecret, HELPERS.L, HELPERS.MakeSideBox, HELPERS.PANEL_GROUPS, HELPERS.PANEL_SIDES, HELPERS.PanelInset, HELPERS.PlaceList, HELPERS.SetVal, HELPERS.Shrink, HELPERS.StatListHeight, HELPERS.StatListOffset, HELPERS.StatRowInset, HELPERS.TrackPanel, HELPERS.UpdateClassBackgrounds, HELPERS.WithColon
local FrameBorder, SetBorderCorner, FrameTopDetail = HELPERS.FrameBorder, HELPERS.SetBorderCorner, HELPERS.FrameTopDetail

local Section = UI:NewSection("character", { label = "Character", order = 10 })

-- The toolbar tab shows the player's class: the client's own class icon file,
-- the same one the icon picker uses. The Journal reads Section.icon when it
-- builds the toolbar, so it is set at load (after a reload), at login, and
-- again when the window is first created.
local function SetTabIcon()
    local _, classFile = UnitClass("player")
    if classFile then
        Section.icon = "Interface\\Icons\\ClassIcon_" .. classFile:sub(1, 1) .. classFile:sub(2):lower()
    end
end
SetTabIcon()

----------------------------------------------------------------------
-- Sizes. SnapChar drew this panel at 700 x 540; the Journal window adds a
-- toolbar, a header and a frame border, so the frame is larger by the chrome
-- amounts below. Adjust these by eye.
----------------------------------------------------------------------
-- The window has the Journal's two layouts, as its own sections do:
--   folded  one page (SINGLE_W), the character alone
--   open    the two-page book (BOOK_W): the character on the left page, the
--           stat list on the right, or the list tabs and the manager
-- The sizes are those of the Journal's own windows (see the screenshots of
-- Tab 3 and Tab 4, at the same screen scale). The window keeps its scale.
local W = UI.Widgets
local SINGLE_W = W.SINGLE_PAGE_WIDTH   -- one page: 448
local BOOK_W = 713                      -- two pages, measured from the book
local LEFT_PAGE_W = 413                 -- the character's page in the book; the stat list has the rest
local CHROME_W, CHROME_H = 40, 81       -- frame border and margins, across and down
local WINDOW_H = 508                    -- the height of the Journal's pages, measured
local PANE_H = WINDOW_H - CHROME_H      -- the room for the panes below the toolbar
-- The panes and the tab panels are drawn above the book's pages, which would
-- otherwise cover their backgrounds.
local PANE_LEVEL = 20
-- The title of the stat page, in the toolbar row above the right page
local STATS_TITLE_W, STATS_TITLE_H = 150, 32   -- plate size
local STATS_TITLE_Y = 24                       -- pixels above the right page's top edge

-- The picture behind the character, and the radial mask that fades it out toward its edges
local _, raceToken = UnitRace("player")
local RADIAL_FADE = "Interface\\AddOns\\CharacterPanels\\Assets\\RadialFade2.tga"

-- The text of a side panel is kept inside its border: pixels in from the
-- sides, and from the top and bottom
local SIDE_TEXT_PAD_X, SIDE_TEXT_PAD_TOP, SIDE_TEXT_PAD_BOTTOM = 26, 18, 14

-- The vertical separator between the character and the stat list.
-- Set to true to show it again (for the artwork).
local SHOW_DIVIDER = false

-- The gear columns: the left column's left edge, and the right column's right
-- edge, from the sides of the character pane (negative: in from the right).
local LEFT_COLUMN_X, RIGHT_COLUMN_X = 45, -40

-- Side tabs, on the window's right edge (SnapChar's geometry)
-- The side tabs: their size, their spacing and the inset of the icon, which
-- fills the tab to its bevel. Tune these for the look.
local SIDE_TAB_STEP, SIDE_TAB_TOP = 52, -40
-- Moves the tab column sideways: -1 closes the 1-pixel gap to the frame
local SIDE_TAB_X = -1


-- Equipment slots, measured from the client by SnapChar
local SLOT_SIZE, SLOT_GAP = 41.1, 47.8
local FRAME_W, FRAME_H = 61.1, 61.1
-- the eight slots of a column must fit the page: 71 down from the top, 10 at the bottom
local SLOT_SCALE = 0.94
local AMMO_SIZE = 26
local WEAPON_ROW_Y = 42
local LEFT_SLOTS = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot" }
local RIGHT_SLOTS = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local BOTTOM_SLOTS = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }
local RELIC_CLASSES = { DRUID = true, PALADIN = true, SHAMAN = true }
local NO_AMMO = { MAGE = true, PRIEST = true, WARLOCK = true, PALADIN = true, DRUID = true, SHAMAN = true }
local RELIC_EMPTY_TEXTURE = 136522
local AMMO_EMPTY_TEXTURE = 136520
local ILVL_IGNORE = { [0] = true, [4] = true, [19] = true }           -- shirt, tabard, ammo
local AVG_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 18 }

-- Stat list
local ROW_H, HEADER_BAR_H = 18, 29
local HEADER_GAP_ABOVE, HEADER_GAP_BELOW = -3, -4

-- Resistances
local RES_ICON, RES_STEP = 18, 46
-- The resistances' height from the top of the character: without, and with the item level
local RES_TOP, RES_TOP_WITH_AVG = -20, -36
local RESIST_ICON_FILE = "Interface\\PaperDollInfoFrame\\UI-Character-ResistanceIcons"

-- Equipment manager
local BUTTON_AREA_H = 74
local SET_ROW_H = 56
local DEFAULT_SET_ICON = 134400 -- question mark

-- Icon picker
local ICON_SIZE, ICON_STEP, ICON_COLS, VISIBLE_ROWS = 36, 46, 10, 7

-- Flyout
local FLYOUT_TEX = [[Interface\PaperDollInfoFrame\UI-GearManager-Flyout]]
local PER_ROW, MAX_ROWS = 5, 4
local PER_PAGE = PER_ROW * MAX_ROWS
local FLY_BORDER = 3
local FLY_ITEM_W, FLY_ITEM_H, FLY_XOFS, FLY_YOFS = 37, 37, 4, -5
local FLY_ROW_H = 54
local FLY_PULL = {
    side = { n = "UI-Character-Info-Button-PullSide", o = "UI-Character-Info-Button-PullSide-Open", p = "UI-Character-Info-Button-PullSide-Pressed" },
    up   = { n = "UI-Character-Info-Button-PullUp",   o = "UI-Character-Info-Button-PullUp-Open",   p = "UI-Character-Info-Button-PullUp-Pressed" },
}

----------------------------------------------------------------------

-- The class background of Blizzard's stat list (CharacterStatsPaneScrollBox
-- .ClassBackground), copied onto our side panels. It is read from the client
-- each time a panel is shown, as the race art is.
-- /journalpanel set border|stat|class left|right|top|bottom <n>
-- /journalpanel set left|right|top|bottom <n>      (all three parts)
-- /journalpanel list height <n> | list reset        the stat list's height
-- /journalpanel list top|left <n>                   where the stat list starts
-- /journalpanel row left|right <n>                  the stat rows' insets
-- /journalpanel show | reset
SLASH_JOURNALPANEL1 = "/journalpanel"
SlashCmdList.JOURNALPANEL = function(msg)
    local w = {}
    for word in msg:gmatch("%S+") do w[#w + 1] = word end
    local cmd = w[1]
    local function num(x) return x and tonumber(x) end
    local saved = AJ.settings
    if cmd == "set" and PANEL_GROUPS[w[2] or ""] and PANEL_SIDES[w[3] or ""] and num(w[4]) then
        saved.panelInset = saved.panelInset or {}
        saved.panelInset[w[2]] = saved.panelInset[w[2]] or {}
        saved.panelInset[w[2]][w[3]] = num(w[4])
    elseif cmd == "set" and PANEL_SIDES[w[2] or ""] and num(w[3]) then
        saved.panelInset = saved.panelInset or {}
        for g in pairs(PANEL_GROUPS) do
            saved.panelInset[g] = saved.panelInset[g] or {}
            saved.panelInset[g][w[2]] = num(w[3])
        end
    elseif cmd == "list" and w[2] == "height" and num(w[3]) then
        saved.statListHeight = num(w[3])
    elseif cmd == "list" and w[2] == "reset" then
        saved.statListHeight, saved.statListOffset = nil, nil
    elseif cmd == "list" and (w[2] == "top" or w[2] == "left") and num(w[3]) then
        saved.statListOffset = saved.statListOffset or {}
        saved.statListOffset[w[2]] = num(w[3])
    elseif cmd == "row" and (w[2] == "left" or w[2] == "right") and num(w[3]) then
        saved.statRowInset = saved.statRowInset or {}
        saved.statRowInset[w[2]] = num(w[3])
    elseif cmd == "reset" then
        saved.panelInset, saved.statRowInset, saved.statListHeight = nil, nil, nil
    elseif cmd == "check" then
        local function size(f) return f and ("%.0fx%.0f"):format(f:GetWidth() or 0, f:GetHeight() or 0) or "-" end
        AJ:Print(("expanded %s, mode %s, window %s"):format(tostring(ctx.expanded), tostring(ctx.mode), size(ctx.frame)))
        AJ:Print(("list shown %s, right shown %s, scroll %s, content %s"):format(
            tostring(ctx.listHost and ctx.listHost:IsShown()), tostring(ctx.right and ctx.right:IsShown()),
            size(ctx.scroll), size(ctx.content)))
        for i = 1, 3 do
            local r = ctx.statRows and ctx.statRows[i + 1]
            if r and r.label then
                AJ:Print(("row %d: %s = %s (row %s)"):format(i, tostring(r.label:GetText()),
                    tostring(r.fs and r.fs:GetText()), size(r.row)))
            end
        end
        return
    elseif cmd ~= "show" then
        AJ:Print("usage: /journalpanel set border|stat|class left|right|top|bottom <n>, set left|right|top|bottom <n>, list height <n>, list top|left <n>, list reset, row left|right <n>, show, check, reset")
        return
    end
    ApplyPanelInsets()
    if ctx.PlaceList then ctx.PlaceList() end
    if ctx.LayoutStatRows then ctx.LayoutStatRows() end
    for _, g in ipairs({ "border", "stat", "class", "lborder", "lstat" }) do
        local i = PanelInset(g)
        AJ:Print(("%s: left %s, right %s, top %s, bottom %s"):format(g, i.left, i.right, i.top, i.bottom))
    end
    local rl, rr = StatRowInset()
    AJ:Print(("stat rows: left %s, right %s"):format(rl, rr))
    AJ:Print("stat list height: " .. tostring(StatListHeight() or "whole panel"))
    local ox, oy = StatListOffset()
    AJ:Print(("stat list offset: left %s, top %s"):format(ox, oy))
end

local function CropTabIcon(tex, l, r, t, b)
    tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
end

local function ErrorMessage(msg)
    if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1, 0.1, 0.1) end
end

-- Remembers the folded state per character, in the Journal's own data
local function IsExpandedSaved()
    return not (AJ.char and AJ.char.characterPanelFolded)
end

local function SaveExpanded(expanded)
    if AJ.char then AJ.char.characterPanelFolded = not expanded end
end

-- Spell damage per magic school, shown as a tooltip on the Spell Damage row.
-- Schools 2-7 are Holy, Fire, Nature, Frost, Shadow, Arcane (1 is Physical).
local SPELL_DAMAGE_SCHOOLS = { 2, 3, 4, 5, 6, 7 }
local SCHOOL_NAMES = { [2] = "Holy", [3] = "Fire", [4] = "Nature", [5] = "Frost", [6] = "Shadow", [7] = "Arcane" }

local function SpellDamageTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(L({ "STAT_SPELLDAMAGE", "BONUS_DAMAGE" }, "Spell Damage"), 1, 1, 1)
    for _, school in ipairs(SPELL_DAMAGE_SCHOOLS) do
        -- use the client's school name when it exists, otherwise our English name
        local name = _G["SPELL_SCHOOL" .. (school - 1) .. "_NAME"] or SCHOOL_NAMES[school]
        local v = GetSpellBonusDamage and GetSpellBonusDamage(school)
        -- in combat the value is secret: show "In Combat" instead of the number
        if AnySecret(v) then
            GameTooltip:AddDoubleLine(name, L("IN_COMBAT", "In Combat"), 1, 1, 1, 1, 0.2, 0.2)
        else
            GameTooltip:AddDoubleLine(name, tostring(v or 0), 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

----------------------------------------------------------------------
-- Stat definitions (the list on the right)
----------------------------------------------------------------------
local ROWS = {
    { header = L({ "STAT_CATEGORY_PRIMARY_ATTRIBUTES", "STAT_CATEGORY_PRIMARY", "STAT_CATEGORY_ATTRIBUTES" }, "Primary Attributes") },
	-- Movement Speed, moved here from the old General block (first row under Primary Attributes)
    { key = "MOVESPEED", name = L("STAT_MOVEMENT_SPEED", "Movement Speed"), update = function(fs)
        local _, run = GetUnitSpeed("player")
        fs:SetTextColor(1, 1, 1)
        -- during combat the speed value is secret, so show "In Combat" instead
        if AnySecret(run) then
            fs:SetText(L("IN_COMBAT", "In Combat"))
            fs:SetTextColor(1, 0.2, 0.2)
            return
        end
        if not run then fs:SetText("–") return end
        -- run speed as a percentage of base speed (base is 7)
        fs:SetFormattedText("%d%%", run / (BASE_MOVEMENT_SPEED or 7) * 100 + 0.5)
    end },
}

local STAT_KEYS = { "STRENGTH_COLON", "AGILITY_COLON", "STAMINA_COLON", "INTELLECT_COLON", "SPIRIT_COLON" }
local STAT_NAMES = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
local STAT_INFO_KEYS = { "STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT" }
for _, i in ipairs({ 1, 2, 4, 3, 5 }) do -- the client's order
    ROWS[#ROWS + 1] = {
        key = STAT_INFO_KEYS[i],
        name = L({ STAT_KEYS[i], "SPELL_STAT" .. i .. "_NAME" }, STAT_NAMES[i]),
        update = function(fs)
            local _, eff, pos, neg = UnitStat("player", i)
            SetVal(fs, "%d", eff)
            fs:SetTextColor(1, 1, 1)
            if not AnySecret(pos, neg) and pos and neg then
                if neg < 0 then fs:SetTextColor(1, 0.2, 0.2)
                elseif pos > 0 then fs:SetTextColor(0.2, 1, 0.2) end
            end
        end,
    }
end

local MORE_ROWS = {
    { header = L("STAT_CATEGORY_WEAPONS", "Weapons") },
    { key = "MAINHAND_DAMAGE", name = L({ "MAINHANDSLOT", "INVTYPE_WEAPONMAINHAND" }, "Main Hand"), update = function(fs)
		local lo, hi = UnitDamage("player")
		if lo == nil then fs:SetText("–") return end
		-- in combat the client returns secret values: show "In Combat" instead
		if AnySecret(lo, hi) then
			fs:SetText(L("IN_COMBAT", "In Combat"))
			fs:SetTextColor(1, 0.2, 0.2)
			return
		end
		fs:SetTextColor(1, 1, 1)
		fs:SetFormattedText("%d - %d", lo, hi)
	end },
    { key = "ATTACK_ATTACKSPEED", name = L({ "STAT_ATTACK_SPEED", "ATTACK_SPEED", "WEAPON_SPEED" }, "Attack Speed"), update = function(fs)
        SetVal(fs, "%.2f", (UnitAttackSpeed("player")))
    end },
    { key = "CRITCHANCE", name = L("STAT_CRITICAL_STRIKE", "Critical Strike"), update = function(fs)
        SetVal(fs, "%.2f%%", GetCritChance and GetCritChance())
    end },
    { key = { "HITCHANCE_MELEE", "HITCHANCE" }, fallbackTip = "melee", name = L({ "STAT_HIT_CHANCE", "HIT_CHANCE" }, "Hit Chance"), update = function(fs)
        SetVal(fs, "%.2f%%", GetHitModifier and GetHitModifier())
    end },

    { header = L({ "STAT_CATEGORY_SPELL", "SPELLS" }, "Spell") },
    { key = "SPELLHEALING", name = L({ "STAT_SPELLHEALING", "BONUS_HEALING" }, "Bonus Healing"), update = function(fs)
        SetVal(fs, "%d", GetSpellBonusHealing and GetSpellBonusHealing())
    end },
	-- Spell Damage row (in the Spell section, after Bonus Healing)
	{ key = "SPELLDAMAGE", name = L({ "STAT_SPELLDAMAGE", "BONUS_DAMAGE" }, "Spell Damage"), customTip = SpellDamageTooltip, update = function(fs)
		local best = 0
		for school = 2, 7 do                    -- magic schools: holy, fire, nature, frost, shadow, arcane
			local v = GetSpellBonusDamage and GetSpellBonusDamage(school)
			-- in combat the value is secret: do not compare it, show "In Combat" instead
			if AnySecret(v) then
				fs:SetText(L("IN_COMBAT", "In Combat"))
				fs:SetTextColor(1, 0.2, 0.2)
				return
			end
			if v and v > best then best = v end  -- keep the highest school
		end
		fs:SetTextColor(1, 1, 1)
		SetVal(fs, "%d", best)
	end },
    { key = "CRITCHANCE", name = L("STAT_CRITICAL_STRIKE", "Critical Strike"), update = function(fs)
        SetVal(fs, "%.2f%%", GetSpellCritChance and GetSpellCritChance(2))
    end },
    { key = { "HITCHANCE_SPELL", "HITCHANCE_MELEE", "HITCHANCE" }, fallbackTip = "spell", name = L({ "STAT_HIT_CHANCE", "HIT_CHANCE" }, "Hit Chance"), update = function(fs)
        SetVal(fs, "%.2f%%", GetSpellHitModifier and GetSpellHitModifier())
    end },

    { header = L("STAT_CATEGORY_DEFENSE", "Defense") },
    { key = "ARMOR", name = L({ "STAT_ARMOR", "ARMOR" }, "Armor"), update = function(fs)
        SetVal(fs, "%d", (select(2, UnitArmor("player"))))
    end },
    { key = "DEFENSE", name = L("DEFENSE", "Defense"), update = function(fs)
        -- effective defense / the maximum for the level
        local eff = GetEffectiveDefenseSkill and GetEffectiveDefenseSkill("player")
        if not IsSecret(eff) and eff == nil and UnitDefense then
            local base, mod = UnitDefense("player")
            if IsSecret(base) or IsSecret(mod) then
                eff = base
            elseif base ~= nil then
                eff = base + (mod or 0)
            end
        end
		local lvl = UnitLevel("player")
		if not IsSecret(eff) and eff == nil then
			fs:SetText("–")
		elseif IsSecret(eff) then
			fs:SetText(L("IN_COMBAT", "In Combat"))
			fs:SetTextColor(1, 0.2, 0.2)
		elseif IsSecret(lvl) then
			fs:SetTextColor(1, 1, 1)
			fs:SetFormattedText("%d", eff)
		else
			fs:SetTextColor(1, 1, 1)
			fs:SetFormattedText("%d / %d", eff, lvl * (SKILL_RANKS_PER_SKILL_LEVEL or 5))
		end
    end },
    { key = "DODGE", name = L("DODGE", "Dodge"), update = function(fs) SetVal(fs, "%.2f%%", GetDodgeChance and GetDodgeChance()) end },
    { key = "PARRY", name = L("PARRY", "Parry"), update = function(fs) SetVal(fs, "%.2f%%", GetParryChance and GetParryChance()) end },
    { key = "BLOCK", name = L("BLOCK", "Block"), update = function(fs) SetVal(fs, "%.2f%%", GetBlockChance and GetBlockChance()) end },
}
for _, r in ipairs(MORE_ROWS) do ROWS[#ROWS + 1] = r end

local RESISTS = {
    { key = "ARCANE_RESIST", school = 6, coords = { 0, 1, 0.2265625, 0.33984375 } },
    { key = "FIRE_RESIST",   school = 2, coords = { 0, 1, 0, 0.11328125 } },
    { key = "FROST_RESIST",  school = 4, coords = { 0, 1, 0.33984375, 0.453125 } },
    { key = "NATURE_RESIST", school = 3, coords = { 0, 1, 0.11328125, 0.2265625 } },
    { key = "SHADOW_RESIST", school = 5, coords = { 0, 1, 0.453125, 0.56640625 } },
}

----------------------------------------------------------------------
-- Stat tooltips: Blizzard's own updateFunc from PAPERDOLL_STATINFO fills a
-- hidden proxy frame, and its lines are copied to our rows. Only outside
-- combat, since the client would otherwise work with secret values.
----------------------------------------------------------------------
local tipProxy = CreateFrame("Frame", nil, UIParent)
tipProxy:Hide()
tipProxy.Label = tipProxy:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tipProxy.Value = tipProxy:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
tipProxy.Background = tipProxy:CreateTexture()
local PROXY_KEEP = { Label = true, Value = true, Background = true }

local function ProxyFields()
    local t = {}
    for k, v in pairs(tipProxy) do
        if type(k) == "string" and not PROXY_KEEP[k] then t[k] = v end
    end
    return t
end

-- Second tooltip line for the primary attributes, built here because the
-- client's own version looks up the translated stat name and fails on
-- non-English clients.
local PRIMARY = { STRENGTH = 1, AGILITY = 2, STAMINA = 3, INTELLECT = 4, SPIRIT = 5 }
local function PrimaryStatTooltip2(key, statIndex)
    local _, cls = UnitClass("player")
    local text = _G[cls .. "_" .. key .. "_TOOLTIP"] or _G["DEFAULT_" .. key .. "_TOOLTIP"]
    if type(text) ~= "string" then return nil end
    local _, eff = UnitStat("player", statIndex)
    if eff == nil or IsSecret(eff) then return nil end
    local ok, res = pcall(function()
        if statIndex == 4 then
            local spellCrit = GetSpellCritChanceFromStat(statIndex, eff) * 100
            if cls == "WARRIOR" or cls == "ROGUE" then return text:format(spellCrit) end
            local mana = math.min(INTELLECT_BREAK, eff)
                + (math.max(INTELLECT_BREAK, eff) - INTELLECT_BREAK) * MANA_PER_INTELLECT
            return text:format(tostring(mana), spellCrit)
        elseif statIndex == 3 then
            local bonus = math.min(STAMINA_BREAK, eff)
                + (math.max(STAMINA_BREAK, eff) - STAMINA_BREAK) * UnitHPPerStamina("player")
            return text:format(tostring(bonus))
        elseif statIndex == 5 then
            local hpFromSpirit = GetHealthRegenFromSpirit() * 0.75
            local manaFromSpirit = GetManaRegenFromSpirit()
            local hp, mana = GetHealthRegen(), GetManaRegen()
            local t
            if cls == "WARRIOR" or cls == "ROGUE" then
                t = text:format(hpFromSpirit * 5, hp * 5)
            else
                t = text:format(hpFromSpirit * 5, manaFromSpirit * 5, hp * 5, mana * 5)
            end
            return SPIRIT_STANDING_WARNING and (t .. "\n\n" .. SPIRIT_STANDING_WARNING) or t
        elseif statIndex == 1 then
            return text:format(GetAttackPowerForStat(statIndex, eff), math.floor(eff / 20))
        else
            local dodge = GetDodgeChanceFromAttribute() * 100
            local armor = eff * (ARMOR_PER_AGILITY or 2)
            local crit = GetCritChanceFromStat(statIndex, eff) * 100
            local ap = GetAttackPowerForStat(statIndex, eff)
            local rap = GetRangedAttackPowerForStat(statIndex, eff)
            if cls == "ROGUE" or cls == "HUNTER" then
                return text:format(crit, ap, rap, armor, dodge)
            elseif cls == "DRUID" then
                return text:format(crit, eff, armor, dodge)
            elseif cls == "WARRIOR" then
                return text:format(crit, rap, armor, dodge)
            end
            return text:format(crit, armor, dodge)
        end
    end)
    return ok and res or nil
end

local function RunStatInfo(key)
    local info = PAPERDOLL_STATINFO and PAPERDOLL_STATINFO[key]
    if not (info and info.updateFunc) then return false end
    for k in pairs(ProxyFields()) do tipProxy[k] = nil end
    tipProxy.Label:SetText("")
    if not pcall(info.updateFunc, tipProxy, "player") then
        -- the client stops after the first line of a primary attribute
        local idx = PRIMARY[key]
        if not (idx and tipProxy.tooltip) then return false end
        tipProxy.tooltip2 = PrimaryStatTooltip2(key, idx)
        tipProxy.onEnterFunc = nil
        return true
    end
    return tipProxy.tooltip ~= nil or tipProxy.onEnterFunc ~= nil
end

local function RefreshTooltipData(r)
    if not (r.key and r.row) then return end
    local keys = type(r.key) == "table" and r.key or { r.key }
    local found = false
    for _, key in ipairs(keys) do
        if RunStatInfo(key) then found = true break end
    end
    if not found then return end

    for k in pairs(r.tipKeys or {}) do r.row[k] = nil end
    r.tipKeys = ProxyFields()
    for k, v in pairs(r.tipKeys) do r.row[k] = v end

    local ok, lbl = pcall(tipProxy.Label.GetText, tipProxy.Label)
    if ok and type(lbl) == "string" and not IsSecret(lbl) and lbl ~= "" then
        if r.label then r.label:SetText(lbl) end
    end
end

local HIT_TIPS = {
    melee = {
        get = function() return GetHitModifier and GetHitModifier() end,
        text = "Increases your chance to hit with melee and ranged attacks by %s.\n\nReduces the chance for your attacks to miss.",
    },
    spell = {
        get = function() return GetSpellHitModifier and GetSpellHitModifier() end,
        text = "Increases your chance to hit with spells by %s.\n\nReduces the chance for your harmful spells to miss.",
    },
}

local function ShowFallbackTooltip(row)
    local tip = row.fallbackTip and HIT_TIPS[row.fallbackTip]
    if not tip then return end
    local title = L({ "STAT_HIT_CHANCE", "HIT_CHANCE" }, "Hit Chance")
    local v = tip.get()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if v ~= nil and not IsSecret(v) then
        local pct = string.format("%.2f%%", v)
        GameTooltip:SetText(title .. " " .. pct, 1, 1, 1)
        GameTooltip:AddLine(tip.text:format(pct), nil, nil, nil, true)
    else
        GameTooltip:SetText(title, 1, 1, 1)
        local general = tip.text:match("\n\n(.*)$")
        if general then GameTooltip:AddLine(general, nil, nil, nil, true) end
    end
    GameTooltip:Show()
end

local function ShowStatTooltip(row)
	if row.customTip then return row.customTip(row) end   -- new line
    if row.onEnterFunc and pcall(row.onEnterFunc, row) then return end
    if not row.tooltip then return ShowFallbackTooltip(row) end
    if PaperDollStatTooltip and pcall(PaperDollStatTooltip, row) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.tooltip, 1, 1, 1)
    if row.tooltip2 then GameTooltip:AddLine(row.tooltip2, nil, nil, nil, true) end
    GameTooltip:Show()
end

----------------------------------------------------------------------
-- Red button (the client's Equip/Save style)
----------------------------------------------------------------------
local function RedButton(parent, text, height)
    local ok, tb = pcall(CreateFrame, "Button", nil, parent, "SharedButtonSmallTemplate")
    if ok and tb then
        tb:SetHeight(height or 26)
        tb:SetText(text)
        return tb
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(height or 26)
    b.L = b:CreateTexture(nil, "BACKGROUND")
    b.R = b:CreateTexture(nil, "BACKGROUND")
    b.C = b:CreateTexture(nil, "BACKGROUND")
    b.L:SetPoint("LEFT")
    b.R:SetPoint("RIGHT")
    b.C:SetPoint("LEFT", b.L, "RIGHT")
    b.C:SetPoint("RIGHT", b.R, "LEFT")

    local function Apply(disabled)
        local s = disabled and "-Disabled" or ""
        local h = b:GetHeight()
        for _, part in ipairs({ { b.L, "128-RedButton-Left" }, { b.R, "128-RedButton-Right" } }) do
            part[1]:SetAtlas(part[2] .. s, true)
            local w, th = part[1]:GetSize()
            if th and th > 0 then part[1]:SetSize(w * h / th, h) end
        end
        b.C:SetAtlas("_128-RedButton-Center" .. s)
        b.C:SetHorizTile(true)
        b.C:SetHeight(h)
    end

    local hl = b:CreateTexture(nil, "ARTWORK")
    hl:SetAtlas("128-RedButton-Highlight")
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    hl:Hide()
    b:SetScript("OnEnter", function(self) if self:IsEnabled() then hl:Show() end end)
    b:SetScript("OnLeave", function() hl:Hide() end)

    b:SetNormalFontObject(GameFontNormal)
    b:SetHighlightFontObject(GameFontHighlight)
    b:SetDisabledFontObject(GameFontDisable)
    b:SetPushedTextOffset(1, -1)
    b:SetText(text)
    b:SetScript("OnEnable", function() Apply(false) end)
    b:SetScript("OnDisable", function() Apply(true) end)
    Apply(false)
    return b
end

----------------------------------------------------------------------
-- The window. Build functions share `ctx`, a table of the pieces they make.
-- Each function stays under Lua's limit of 200 locals.
----------------------------------------------------------------------
-- The tabs that cover both halves of the window (lists, panels, borrowed
-- windows) follow the fold state: their right part shows only when open.
local function PlaceWideTabs()
    for _, t in ipairs(ctx.wideTabs or {}) do
        t.frame:ClearAllPoints()
        t.frame:SetPoint("TOPLEFT", ctx.left, "TOPLEFT")
        t.frame:SetPoint("BOTTOMRIGHT", ctx.expanded and ctx.right or ctx.left, "BOTTOMRIGHT")
        if t.rp then t.rp:SetShown(ctx.expanded) end
        for _, p in ipairs(t.parts or {}) do p:SetShown(ctx.expanded) end
    end
end

local function BuildFrame(ctx)
    local startWide = IsExpandedSaved()
    local frame = C.CreateWindow("JournalCharacterFrame", "Character", startWide and BOOK_W or SINGLE_W, WINDOW_H,
        16, -104, SOUNDKIT.IG_SPELLBOOK_OPEN, SOUNDKIT.IG_SPELLBOOK_CLOSE)
    ctx.frame = frame
    ctx.wideTabs = {}
    ctx.mode = "stats"

    -- the two layouts; only one is shown at a time
    local page = C.CreatePage(frame)
    local book, leftPage, rightPage = C.CreateSplitBook(frame, LEFT_PAGE_W)
    ctx.page, ctx.book, ctx.leftPage, ctx.rightPage = page, book, leftPage, rightPage

    ctx.left = CreateFrame("Frame", nil, frame)
    ctx.left:SetFrameLevel(frame:GetFrameLevel() + PANE_LEVEL)
    ctx.right = CreateFrame("Frame", nil, frame)
    ctx.right:SetFrameLevel(frame:GetFrameLevel() + PANE_LEVEL)
    ctx.dividerHolder = CreateFrame("Frame", nil, frame)
    ctx.dividerHolder:SetFrameLevel(frame:GetFrameLevel() + PANE_LEVEL + 5)
    ctx.dividerHolder:SetAllPoints(ctx.right)
	
    -- the title plate over the right page: its text is set by UpdateHeader
    local rightTitle = CreateFrame("Frame", nil, frame)
    rightTitle:SetFrameLevel(frame:GetFrameLevel() + PANE_LEVEL + 6)
    rightTitle:SetSize(STATS_TITLE_W, STATS_TITLE_H)
    rightTitle:SetPoint("CENTER", ctx.right, "TOP", 0, STATS_TITLE_Y)
    rightTitle:Hide()
    local rightTitleBg = Atlas(rightTitle, "UI-Character-Info-Title", "BACKGROUND")
    rightTitleBg:SetAllPoints()
    local rightTitleText = rightTitle:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rightTitleText:SetPoint("CENTER")
    ns.ScaleFont(rightTitleText, "stats")
    ctx.rightTitle, ctx.rightTitleText = rightTitle, rightTitleText

    ctx.expanded = IsExpandedSaved()
    ctx.userExpanded = ctx.expanded
    ctx.SetExpanded = function(show, transient)
        ctx.expanded = show
        local left, right = ctx.left, ctx.right
        -- open: the two-page book, the character on the left page and the stat
        -- list on the right; folded: one page, the character alone
        left:ClearAllPoints()
        left:SetWidth(LEFT_PAGE_W)   -- the same width folded or open: the page's top left is the same in both
        if show then
            book:Show()
            page:Hide()
            frame:SetWidth(BOOK_W)
            left:SetPoint("TOPLEFT", leftPage, "TOPLEFT")
            left:SetPoint("BOTTOMLEFT", leftPage, "BOTTOMLEFT")
            right:ClearAllPoints()
            right:SetAllPoints(rightPage)
        else
            book:Hide()
            page:Show()
            frame:SetWidth(SINGLE_W)
            left:SetPoint("TOPLEFT", page, "TOPLEFT")
            left:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT")
        end
        local listMode = ctx.listMode
        left:SetShown(not listMode)
        right:SetShown(show and not listMode)
        ctx.dividerHolder:SetShown(show and not listMode)
        if ctx.UpdateHeader then ctx.UpdateHeader() end
        PlaceWideTabs()
        if show and not listMode then
            ctx.RefreshSidePanel()
            for _, delay in ipairs({ 0, 0.1, 0.3 }) do
                C_Timer.After(delay, function()
                    if ctx.expanded and ctx.frame:IsShown() then ctx.RefreshSidePanel() end
                end)
            end
        end
        AJ.UI.Components.SetExpandArrow(ctx.toggle, show)
        if not transient then
            ctx.userExpanded = show
            SaveExpanded(show)
        end
    end
end

local function BuildCharacterPane(ctx)
    local left = ctx.left

    -- the dark background and its border, on sublevel -8: behind the race
    -- picture (-7) and the model. Both are tracked as panels, so the
    -- lstat and lborder insets apply (/journalpanel set lstat|lborder ...)
    local leftBg = TrackPanel(Atlas(left, "UI-Character-Info-General-BG", "BACKGROUND", -8), left, "lstat")
    local leftBorder = FrameBorder(left, "common-insideframe", "lborder", "BORDER")
	FrameTopDetail(left, leftBorder)

    -- the picture behind the model: a square the height of the pane, faded out at its edges
    local bgImage = left:CreateTexture(nil, "BACKGROUND", nil, -7)
    bgImage:SetSize(PANE_H, PANE_H)
    bgImage:SetPoint("CENTER", left, "CENTER", 0, 15)
    bgImage:SetTexture("Interface\\AddOns\\CharacterPanels\\Assets\\" .. raceToken .. ".tga")
    local bgMask = left:CreateMaskTexture()
    bgMask:SetTexture(RADIAL_FADE)
    bgMask:SetAllPoints(bgImage)
    bgImage:AddMaskTexture(bgMask)

    -- race background in four pieces, as the client draws it
    local raceParts = {}
    for i, key in ipairs({ "TopLeft", "TopRight", "BotLeft", "BotRight" }) do
        local t = left:CreateTexture(nil, "BACKGROUND", nil, 0)
        t.key = key
        t:Hide()   -- hidden, but kept: the tabs copy its art
        raceParts[i] = t
    end
    raceParts[1]:SetPoint("TOPLEFT")
    raceParts[2]:SetPoint("TOPLEFT", raceParts[1], "TOPRIGHT")
    raceParts[3]:SetPoint("TOPLEFT", raceParts[1], "BOTTOMLEFT")
    raceParts[4]:SetPoint("TOPLEFT", raceParts[1], "BOTTOMRIGHT")

    local function LayoutRaceBg()
        local w, h = left:GetSize()
        if not w or w <= 1 then return end
        local wl, hl = w * 256 / 318, h * 255 / 383
        raceParts[1]:SetSize(wl, hl)
        raceParts[2]:SetSize(w - wl, hl)
        raceParts[3]:SetSize(wl, h - hl)
        raceParts[4]:SetSize(w - wl, h - hl)
    end
    left:SetScript("OnSizeChanged", LayoutRaceBg)

    ctx.UpdateRaceBg = function()
        local _, raceFile = UnitRace("player")
        for _, t in ipairs(raceParts) do
            local orig = _G["CharacterModelFrameBackground" .. t.key]
            local tex = orig and orig:GetTexture()
            if tex then
                t:SetTexture(tex)
                t:SetTexCoord(orig:GetTexCoord())
            elseif raceFile then
                local n = ({ TopLeft = 1, TopRight = 2, BotLeft = 3, BotRight = 4 })[t.key]
                t:SetTexture("Interface\\DressUpFrame\\DressUpBackground-" .. raceFile .. n)
            end
        end
        LayoutRaceBg()
    end

    local raceOverlay = Atlas(left, "UI-Character-Info-RaceBG-Overlay", "BORDER")
    ctx.raceParts = raceParts
    raceOverlay:SetAllPoints()
    raceOverlay:Hide()

    local model = CreateFrame("PlayerModel", nil, left)
    model:SetPoint("TOPLEFT", 60, -5)
    model:SetPoint("BOTTOMRIGHT", -60, 35)
    ctx.model = model
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

    -- zoom and rotate buttons, shown while the mouse is over the model
    local CONTROLS = {
        { icon = "common-icon-zoomin", click = function()
            camScale = math.max(0.4, camScale - 0.1) model:SetCamDistanceScale(camScale) end },
        { icon = "common-icon-zoomout", click = function()
            camScale = math.min(1.6, camScale + 0.1) model:SetCamDistanceScale(camScale) end },
        { icon = "common-icon-rotateleft", click = function() model:SetFacing(model:GetFacing() - 0.4) end },
        { icon = "common-icon-rotateright", click = function() model:SetFacing(model:GetFacing() + 0.4) end },
        { icon = "common-icon-undo", click = function()
            camScale = 1 model:SetCamDistanceScale(1) model:SetFacing(0) end },
    }
    local CTRL_SIZE, CTRL_GAP = 22, 27

    local controls = CreateFrame("Frame", nil, left)
    controls:SetFrameLevel(model:GetFrameLevel() + 2)
    controls:SetSize(#CONTROLS * CTRL_GAP, CTRL_SIZE)
    controls:SetPoint("CENTER", left, "TOP", 7, -25)
    controls:Hide()
    ctx.controls = controls

    local hoverWatch = CreateFrame("Frame", nil, left)
    hoverWatch:SetScript("OnUpdate", function()
        controls:SetShown(model:IsMouseOver() or controls:IsMouseOver())
    end)

    for i, c in ipairs(CONTROLS) do
        local b = CreateFrame("Button", nil, controls)
        b:SetSize(CTRL_SIZE, CTRL_SIZE)
        b:SetPoint("CENTER", controls, "CENTER", (i - 3) * CTRL_GAP, 0)
        b:SetNormalAtlas("common-button-square-gray-up")
        b:SetPushedAtlas("common-button-square-gray-down")
        local icon = Atlas(b, c.icon, "OVERLAY")
        icon:SetSize(15, 15)
        icon:SetPoint("CENTER")
        b:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, -1) end)
        b:SetScript("OnMouseUp", function() icon:SetPoint("CENTER") end)
        b:SetScript("OnClick", c.click)
    end

    -- resistances, in a row a
    for i, res in ipairs(RESISTS) do
        local b = CreateFrame("Frame", nil, left)
        b:SetFrameLevel(model:GetFrameLevel() + 2)
        b:SetSize(RES_STEP - 6, RES_ICON)
        b:SetPoint("TOP", left, "TOP", (i - 3) * RES_STEP + 5, RES_TOP)
        b:EnableMouse(true)

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(RES_ICON + 3, RES_ICON)
        icon:SetPoint("LEFT")
        icon:SetTexture(RESIST_ICON_FILE)
        icon:SetTexCoord(unpack(res.coords))

        local value = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetPoint("LEFT", icon, "RIGHT", 5, 0)

        res.row, res.fs = b, value
        res.update = function(fs)
            local _, total = UnitResistance("player", res.school)
            SetVal(fs, "%d", total)
        end
        b:SetScript("OnEnter", ShowStatTooltip)
        b:SetScript("OnLeave", function(self)
            self.UpdateTooltip = nil
            GameTooltip_Hide()
        end)
    end

    -- the arrow that folds the right pane away, shared with the spellbook
    local toggle = AJ.UI.Components.CreateExpandToggle(ctx.frame, left, function()
        if ctx.mode == "equip" then
            -- the manager needs the right half: folding leaves the character alone
            ctx.SetExpanded(false)
            ctx.SetMode("stats")
        else
            ctx.SetExpanded(not ctx.expanded)
        end
    end)
    ctx.toggle = toggle
end

local function BuildSlots(ctx)
    local left, model = ctx.left, ctx.model
    local slots = {}
    ctx.slots = slots

    local function IsRelicSlot(slotName)
        local _, classFile = UnitClass("player")
        return slotName == "RangedSlot" and RELIC_CLASSES[classFile]
    end

    local function GetSlotLabel(slotName)
        if IsRelicSlot(slotName) and RELICSLOT then return RELICSLOT end
        return _G[string.upper(slotName)] or slotName
    end

    local function GetEmptySlotTexture(slotName, fallback)
        if IsRelicSlot(slotName) then return RELIC_EMPTY_TEXTURE end
        if slotName == "AmmoSlot" then return AMMO_EMPTY_TEXTURE end
        local orig = _G["Character" .. slotName]
        if orig and orig.backgroundTextureName then return orig.backgroundTextureName end
        return fallback
    end


local function CreateSlot(slotName, small)
    local id, emptyTex = GetInventorySlotInfo(slotName)
    emptyTex = GetEmptySlotTexture(slotName, emptyTex)
    local size = small and AMMO_SIZE or SLOT_SIZE
    local b = CreateFrame("Button", nil, left)
    b:SetFrameLevel(model:GetFrameLevel() + 2)
    b:SetSize(size, size)
    b.small = small

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()

    b.iconBorder = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.iconBorder:SetTexture(651080)
    b.iconBorder:SetAllPoints()
    b.iconBorder:Hide()

    -- the slot frame sits behind the icon
    if small then
        b.frameTex = Atlas(b, "UI-Character-Info-GearSlotSmall", "BACKGROUND", 0, true)
    else
        b.frameTex = Atlas(b, "UI-Character-Info-GearSlot", "BACKGROUND", 0)
        b.frameTex:SetSize(FRAME_W, FRAME_H)
    end
    b.frameTex:SetPoint("CENTER")

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)

    b.ilvl = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.ilvl:SetPoint("TOPLEFT", 2, -2)
    b.ilvl:SetTextColor(1, 1, 1)

    b:SetHighlightTexture(130718, "ADD")
    b.slotId, b.slotName, b.emptyTex = id, slotName, emptyTex

    b:SetScript("OnEnter", function(self)
        -- the flyout (Alt, or an arrow in the manager) takes the tooltip
        if ctx.OnSlotEnter then ctx.OnSlotEnter(self) end
        if not (ctx.AnchorTooltipToFlyout and ctx.AnchorTooltipToFlyout()) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        end
        if GetInventoryItemTexture("player", self.slotId) then
            GameTooltip:SetInventoryItem("player", self.slotId)
        else
            GameTooltip:SetText(GetSlotLabel(self.slotName), 1, 1, 1)
        end
        GameTooltip:Show()
        if SetCursorHoveredItem and ItemLocation then
            local loc = ItemLocation:CreateFromEquipmentSlot(self.slotId)
            if loc and loc:IsValid() then SetCursorHoveredItem(loc) end
        end
    end)

    b:SetScript("OnLeave", function(self)
        if ctx.OnSlotLeave then ctx.OnSlotLeave(self) end
        GameTooltip_Hide()
        if ClearCursorHoveredItem then ClearCursorHoveredItem() end
        if ResetCursor then ResetCursor() end
    end)

    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function(self)
        if IsModifiedClick() then
            local link = GetInventoryItemLink("player", self.slotId)
            if link then HandleModifiedItemClick(link) end
        else
            PickupInventoryItem(self.slotId)
        end
    end)
    b:SetScript("OnDragStart", function(self) PickupInventoryItem(self.slotId) end)
    b:SetScript("OnReceiveDrag", function(self) PickupInventoryItem(self.slotId) end)

    slots[#slots + 1] = b
    return b
end


    local slotGroups = { left = {}, right = {}, bottom = {} }
    for _, name in ipairs(LEFT_SLOTS) do table.insert(slotGroups.left, CreateSlot(name)) end
    for _, name in ipairs(RIGHT_SLOTS) do table.insert(slotGroups.right, CreateSlot(name)) end
    for _, name in ipairs(BOTTOM_SLOTS) do table.insert(slotGroups.bottom, CreateSlot(name)) end
    ctx.slotGroups = slotGroups

    local hasAmmo = pcall(GetInventorySlotInfo, "AmmoSlot")
    local ammoSlot = hasAmmo and CreateSlot("AmmoSlot", true) or nil
    if ammoSlot then ammoSlot:SetFrameLevel(ammoSlot:GetFrameLevel() + 1) end
    ctx.ammoSlot = ammoSlot

    local function LayoutSlots()
        local k = SLOT_SCALE
        local size, fw, fh, gap = SLOT_SIZE * k, FRAME_W * k, FRAME_H * k, SLOT_GAP * k
        local top = 34 * k
        for _, group in pairs(slotGroups) do
            for _, b in ipairs(group) do
                b:SetSize(size, size)
                b.frameTex:SetSize(fw, fh)
                b:ClearAllPoints()
            end
        end
        for i, b in ipairs(slotGroups.left) do
            b:SetPoint("TOPLEFT", LEFT_COLUMN_X * k, -top - (i - 1) * gap)
        end
        for i, b in ipairs(slotGroups.right) do
            b:SetPoint("TOPRIGHT", RIGHT_COLUMN_X * k, -top - (i - 1) * gap)
        end
        for i, b in ipairs(slotGroups.bottom) do
            b:SetPoint("BOTTOM", (i - 2) * gap, WEAPON_ROW_Y * k)
        end
        if ammoSlot then
            -- the small frame's corner lines up with the large frame's corner
            local ranged = slotGroups.bottom[#slotGroups.bottom]
            local sfw, sfh = ammoSlot.frameTex:GetSize()
            local d = (fh - gap) / 2
            local ds = d * sfh / fh
            ammoSlot:SetSize(AMMO_SIZE * k, AMMO_SIZE * k)
            ammoSlot:ClearAllPoints()
            ammoSlot:SetPoint("CENTER", ranged, "CENTER", fw / 2 - d - ds + sfw / 2, -fh / 2 + d - ds + sfh / 2)
            local _, classFile = UnitClass("player")
            ammoSlot:SetShown(not NO_AMMO[classFile] and (not CharacterAmmoSlot or CharacterAmmoSlot:IsShown()))
        end
    end
    LayoutSlots()

    ctx.UpdateSlots = function()
        for _, b in ipairs(slots) do
            local tex = GetInventoryItemTexture("player", b.slotId)
            b.icon:SetTexture(tex or b.emptyTex)
            local count = tex and b.small and GetInventoryItemCount("player", b.slotId)
            b.count:SetText((count and count > 1) and count or "")
            local q = tex and GetInventoryItemQuality("player", b.slotId)
            if q and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
                local c = ITEM_QUALITY_COLORS[q]
                b.iconBorder:SetVertexColor(c.r, c.g, c.b)
                b.iconBorder:Show()
            else
                b.iconBorder:Hide()
            end
        end
    end

    -- item levels: in each slot, and the average above the character
    local ilvlPending = false

    local function GetSlotItemLevel(slotId)
        if not GetInventoryItemID("player", slotId) then return nil end
        local lvl
        if C_Item and C_Item.GetCurrentItemLevel and ItemLocation then
            local loc = ItemLocation:CreateFromEquipmentSlot(slotId)
            if loc and loc:IsValid() then lvl = C_Item.GetCurrentItemLevel(loc) end
        end
        if not lvl then
            local link = GetInventoryItemLink("player", slotId)
            if link and GetDetailedItemLevelInfo then lvl = GetDetailedItemLevelInfo(link) end
        end
        if lvl == nil or IsSecret(lvl) then ilvlPending = true return nil end
        return lvl
    end

    -- a two-handed weapon counts as one item; otherwise the two hands share one
    local function GetAverageItemLevel()
        local sum, n = 0, 0
        for _, id in ipairs(AVG_SLOTS) do
            sum = sum + (GetSlotItemLevel(id) or 0)
            n = n + 1
        end
        local mh, oh = GetSlotItemLevel(16), GetSlotItemLevel(17)
        local mhID = GetInventoryItemID("player", 16)
        local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        local equipLoc = mhID and getInstant and select(4, getInstant(mhID))
        local weapon
        if equipLoc == "INVTYPE_2HWEAPON" then
            weapon = mh or 0
        else
            weapon = ((mh or 0) + (oh or 0)) / 2
        end
        return (sum + weapon) / (n + 1)
    end

    local avgFrame = CreateFrame("Frame", nil, left)
    avgFrame:SetFrameLevel(model:GetFrameLevel() + 3)
    avgFrame:SetSize(160, 40)
    avgFrame:SetPoint("TOP", left, "TOP", 0, -8)
    local avgLabel = avgFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    avgLabel:SetPoint("TOP")
    avgLabel:SetText(L({ "STAT_AVERAGE_ITEM_LEVEL", "ITEM_LEVEL_ABBR" }, "Item Level"))
    local avgValue = avgFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    avgValue:SetPoint("TOP", avgLabel, "BOTTOM", 0, -2)

    ctx.UpdateItemLevels = function()
        ilvlPending = false
        for _, b in ipairs(slots) do
            local lvl = ns.GetSetting("showSlotIlvl") and not ILVL_IGNORE[b.slotId] and GetSlotItemLevel(b.slotId)
            b.ilvl:SetText((lvl and lvl > 0) and lvl or "")
        end
        local showAvg = ns.GetSetting("showAvgIlvl") and true or false
        avgFrame:SetShown(showAvg)
        ctx.controls:ClearAllPoints()
        if showAvg then
            ctx.controls:SetPoint("TOP", avgValue, "BOTTOM", 7, -6)
            avgValue:SetFormattedText("%.1f", GetAverageItemLevel())
        else
            ctx.controls:SetPoint("CENTER", left, "TOP", 7, -25)
        end
        -- the resistances sit under the controls, at the top of the character
        for i, res in ipairs(RESISTS) do
            res.row:ClearAllPoints()
            res.row:SetPoint("TOP", left, "TOP", (i - 3) * RES_STEP + 5, showAvg and RES_TOP_WITH_AVG or RES_TOP)
        end
    end

    ctx.IsItemLevelPending = function() return ilvlPending end
end

local function BuildStatsPane(ctx)
    local right = ctx.right


    -- the divider between the panes
    local divider = ctx.dividerHolder:CreateTexture(nil, "OVERLAY")
    ctx.SetupDivider = function()
        divider:SetAtlas("common-framedivider", true)
        local w, h = divider:GetSize()
        local rot = 0
        local o = FindRegionByAtlas(CharacterFrameRightPaneHost, "common-framedivider")
        if o then
            if o.GetRotation then rot = o:GetRotation() or 0 end
            local ow, oh = o:GetSize()
            if ow and oh and ow > 0 and oh > 0 then w, h = ow, oh end
        end
        local paneH = PANE_H - 2
        divider:ClearAllPoints()
        if rot == 0 and w > h then rot = math.pi / 2 end
        if rot ~= 0 then
            divider:SetSize(paneH, math.min(w, h))
        else
            divider:SetSize(math.min(w, h), paneH)
        end
        divider:SetRotation(rot)
        divider:SetShown(SHOW_DIVIDER)   -- see SHOW_DIVIDER at the top
        divider:SetPoint("CENTER", right, "LEFT", 0, 0)
    end

    -- the list area, with the client's frame border, a scroll bar and content
    -- the panel beside the page keeps its size (the manager and the border
    -- are placed in it); the stat list inside it can be shorter
    local panelHost = CreateFrame("Frame", nil, right)
    panelHost:SetPoint("TOPLEFT", 4, -6)
    panelHost:SetPoint("BOTTOMRIGHT", -2, 6)
    ctx.panelHost = panelHost
    local listHost = CreateFrame("Frame", nil, panelHost)
    ctx.listHost = listHost
    ctx.PlaceList = function()
        PlaceList(listHost, panelHost)
        if ctx.PlaceManagerList then ctx.PlaceManagerList() end
    end
    PlaceList(listHost, panelHost)
    AddClassBackground(listHost)
    -- the background fills the list area, inside the ornate border
    local rightBg = TrackPanel(Atlas(listHost, "UI-Character-Info-Stat-BG", "BACKGROUND", -8), listHost, "stat")
    CropBottom(rightBg, BG_CROP_BOTTOM)

    local scroll = CreateFrame("ScrollFrame", nil, listHost)
    scroll:SetPoint("TOPLEFT", 6, -5)
    scroll:SetPoint("BOTTOMRIGHT", -24, 5)

    -- the client's border: the manager's border is anchored to it, so it stays
    -- where it is, hidden; the list has its own border, placed by the insets
    local insideFrame = Atlas(panelHost, "common-insideframe", "BORDER")
    ctx.insideFrame = insideFrame
    insideFrame:Hide()
    local statBorder = FrameBorder(listHost, "common-insideframe", "border", "BORDER")
	FrameTopDetail(listHost, statBorder)
    ctx.SetupListBorder = function()
        local o = CharacterStatsPaneScrollBox and CharacterStatsPaneScrollBox.Border
        insideFrame:ClearAllPoints()
        local copied = 0
        if o and o.GetNumPoints then
            for i = 1, o:GetNumPoints() do
                local p, rel, rp, x, y = o:GetPoint(i)
                if rel == nil or rel == CharacterStatsPaneScrollBox then
                    insideFrame:SetPoint(p, panelHost, rp, x, y)
                    copied = copied + 1
                end
            end
        end
        if copied < 2 then
            insideFrame:ClearAllPoints()
            insideFrame:SetAllPoints(panelHost)
        end
        SetBorderCorner(insideFrame)
    end

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

	-- In combat, the client returns a secret number here, and ScrollUtil compares it.
	-- Answer with our own value, computed from heights the code already reads without error.
	scroll.GetVerticalScrollRange = function(self)
		return math.max(0, content:GetHeight() - self:GetHeight())
	end
    -- the client's own scroll bar: the MinimalScrollBar template, the same
    -- one the client's lists use. ScrollUtil wires it to the scroll frame:
    -- wheel and steppers step by the pan extent (30 pixels), the track
    -- pages, the thumb is proportional, the steppers hold to repeat
    local bar = CreateFrame("EventFrame", nil, listHost, "MinimalScrollBar")
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 2, -14)   -- flush with the list
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 2, 14)
    scroll:EnableMouseWheel(true)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
	scroll:SetScript("OnScrollRangeChanged", function() ctx.UpdateScrollRange() end)
    ctx.scroll, ctx.content = scroll, content
    ctx.statRows = ROWS
    local scrollbarShown
    ctx.UpdateScrollRange = function()
        -- sizes are often not known yet on the first show: take the width now
        local sw = scroll:GetWidth()
        if sw and sw > 0 then content:SetWidth(sw) end
        local max = math.max(0, content:GetHeight() - scroll:GetHeight())
		local h = scroll:GetHeight()
		bar:SetVisibleExtentPercentage(h > 0 and h / (max + h) or 0)
        if scroll:GetVerticalScroll() > max then scroll:SetVerticalScroll(max) end

        local need = max > 0.5
        if need ~= scrollbarShown then
            scrollbarShown = need
            -- explicit Show/Hide is respected: ScrollBarMixin only toggles
            -- itself when hideIfUnscrollable is set
            bar:SetShown(need)
            if not need then scroll:SetVerticalScroll(0) end
            -- re-anchor on the next frame; doing it inside the size change hides the list
            C_Timer.After(0, function()
                scroll:ClearAllPoints()
                scroll:SetPoint("TOPLEFT", 6, -5)
                scroll:SetPoint("BOTTOMRIGHT", scrollbarShown and -24 or -8, 5)
                content:SetWidth(scroll:GetWidth())
                -- keep the thumb's size in sync after the resize
                local h = scroll:GetHeight()
                local range = scroll:GetVerticalScrollRange()
                bar:SetVisibleExtentPercentage(h > 0 and h / (range + h) or 0)
            end)
        end
    end
    scroll:SetScript("OnSizeChanged", function(self, w)
        if w and w > 0 then content:SetWidth(w) end
        ctx.LayoutStatRows()
        ctx.UpdateScrollRange()
    end)

    -- rows: headers, and label/value pairs with zebra stripes
    local y, zebra = 0, true
    local statLayout = {}
    for _, r in ipairs(ROWS) do
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)

        if r.header then
            local gap = (y == 0) and 0 or HEADER_GAP_ABOVE
            local h = gap + HEADER_BAR_H + HEADER_GAP_BELOW
            row:SetHeight(h)
            row:SetFrameLevel(content:GetFrameLevel() + 2)
            local bar2 = Atlas(row, "UI-Character-Info-Title", "BACKGROUND")
            bar2:SetPoint("TOPLEFT", 6, -gap)
            bar2:SetPoint("TOPRIGHT", -6, -gap)
            bar2:SetHeight(HEADER_BAR_H)
            local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            t:SetPoint("CENTER", bar2)
            Shrink(t)
            ns.ScaleFont(t, "stats")
            t:SetText(r.header)
            y = y + h
            statLayout[#statLayout + 1] = { row = row, h = h, bar = bar2 }
            zebra = true
        else
            row:SetHeight(ROW_H)
            if zebra then
                local line = Atlas(row, "UI-Character-Info-Line-Bounce", "BACKGROUND")
                line:SetAllPoints()
            end
            zebra = not zebra

            local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            value:SetPoint("RIGHT", -8, 0)
            value:SetJustifyH("RIGHT")
            Shrink(value)
            ns.ScaleFont(value, "stats")

            -- the name runs up to the value; too long, it is cut with "..."
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", 8, 0)
            label:SetPoint("RIGHT", value, "LEFT", -6, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetMaxLines(1)
            Shrink(label)
            ns.ScaleFont(label, "stats")
            label:SetText(WithColon(r.name))

            r.fs = value
            r.row, r.label = row, label
            row.labelFS = label
            row.fallbackTip = r.fallbackTip
			row.customTip = r.customTip
            row:EnableMouse(true)
            row:SetScript("OnEnter", ShowStatTooltip)
            row:SetScript("OnLeave", function(self)
                self.UpdateTooltip = nil
                GameTooltip_Hide()
            end)
            y = y + ROW_H
            statLayout[#statLayout + 1] = { row = row, isRow = true }
        end
    end
    content:SetHeight(y)

    -- The list fits the panel. Rows and headers are as tall as the font needs,
    -- and shorter when the whole list would not fit the panel without scrolling.
    ctx.LayoutStatRows = function()
        local k = math.max(1, ns.GetFontScale("stats"))
        local base = 0
        for _, e in ipairs(statLayout) do
            base = base + (e.isRow and ROW_H * k or e.h * k)
        end
        local avail = scroll:GetHeight() or 0
        local fit = 1
        if not StatListHeight() and avail > 0 and base > avail then fit = avail / base end
        local yy = 0
        for _, e in ipairs(statLayout) do
            local h = (e.isRow and ROW_H * k or e.h * k) * fit
            e.row:ClearAllPoints()
            local rowL, rowR = 0, 0
            if e.isRow then rowL, rowR = StatRowInset() end
            e.row:SetPoint("TOPLEFT", rowL, -yy)
            e.row:SetPoint("TOPRIGHT", -rowR, -yy)
            e.row:SetHeight(h)
            if e.bar then e.bar:SetHeight(HEADER_BAR_H * fit) end
            yy = yy + h
        end
        content:SetHeight(yy)
    end
    ns.fontScaleCallbacks.stats = function()
        ctx.LayoutStatRows()
        ctx.UpdateScrollRange()
    end

	ctx.UpdateStats = function()
		local canRefresh = not InCombatLockdown()
		-- one failing row must not stop the rest: in combat the client
		-- can return values an update chokes on
		local function run(update, fs)
			local ok, err = pcall(update, fs)
			if not ok and geterrorhandler then geterrorhandler()(err) end
		end
		for _, res in ipairs(RESISTS) do
			if canRefresh then RefreshTooltipData(res) end
			run(res.update, res.fs)
		end
		for _, r in ipairs(ROWS) do
			if r.fs then
				if canRefresh then RefreshTooltipData(r) end
				run(r.update, r.fs)
			end
		end
	end

    -- Everything the side panel shows, read again. Run when the panel appears,
    -- since on the first open it can be filled while it is still folded.
    ctx.RefreshSidePanel = function()
        ctx.SetupListBorder()
        UpdateClassBackgrounds()
        ctx.UpdateStats()
        ctx.LayoutStatRows()
        ctx.UpdateScrollRange()
    end

    for _, r in ipairs(ROWS) do
        if r.row then
            r.row:SetScript("OnEnter", ShowStatTooltip)
        end
    end
end

----------------------------------------------------------------------
-- Equipment manager (takes the place of the stat list)
----------------------------------------------------------------------
local function BuildManager(ctx)
    local frame, right, listHost = ctx.frame, ctx.right, ctx.listHost
    local ES = C_EquipmentSet
    ctx.ES = ES

    local manager = CreateFrame("Frame", nil, right)
    manager:SetAllPoints(ctx.panelHost)
    manager:Hide()
    ctx.manager = manager

    -- small dialog: a name, or a plain question
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(320, 130)
    popup:SetFrameStrata("DIALOG")
    popup:EnableMouse(true)
    popup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    popup:Hide()
    popup.text = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    popup.text:SetPoint("TOP", 0, -24)
    popup.text:SetWidth(280)
    popup.edit = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    popup.edit:SetSize(200, 22)
    popup.edit:SetPoint("TOP", popup.text, "BOTTOM", 0, -10)
    popup.edit:SetAutoFocus(false)
    popup.edit:SetMaxLetters(16)
    popup.ok = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    popup.ok:SetSize(110, 24)
    popup.ok:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 18)
    popup.ok:SetText(L("OKAY", "Okay"))
    popup.cancel = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    popup.cancel:SetSize(110, 24)
    popup.cancel:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 18)
    popup.cancel:SetText(L("CANCEL", "Cancel"))
    popup.cancel:SetScript("OnClick", function() popup:Hide() end)
    popup.ok:SetScript("OnClick", function()
        local value = strtrim(popup.edit:GetText() or "")
        if popup.withEdit and value == "" then return end
        popup:Hide()
        if popup.onAccept then popup.onAccept(value) end
    end)
    popup.edit:SetScript("OnEnterPressed", function() popup.ok:Click() end)
    popup.edit:SetScript("OnEscapePressed", function() popup:Hide() end)
    frame:HookScript("OnHide", function() popup:Hide() end)

    ctx.ShowPopup = function(text, withEdit, defaultText, onAccept)
        popup:ClearAllPoints()
        popup:SetPoint("CENTER", frame, "CENTER")
        popup.text:SetText(text)
        popup.withEdit, popup.onAccept = withEdit, onAccept
        popup.edit:SetShown(withEdit)
        popup.edit:SetText(defaultText or "")
        popup:Show()
        if withEdit then
            popup.edit:SetFocus()
            popup.edit:HighlightText()
        end
    end

    -- the list, in the stat list's box: the same place, width and insets, but
    -- shorter, as the buttons take the bottom of the panel
    local mList = CreateFrame("Frame", nil, manager)
    local function PlaceManagerList()
        PlaceList(mList, manager)
        mList:SetHeight(StatListHeight() - BUTTON_AREA_H)
    end
    ctx.PlaceManagerList = PlaceManagerList
    PlaceManagerList()
    local mBorder = DressPanel(mList)

    local mScroll = CreateFrame("ScrollFrame", nil, mList)
    mScroll:SetPoint("TOPLEFT", mBorder, "TOPLEFT", 12, -12)
    mScroll:SetPoint("BOTTOMRIGHT", mBorder, "BOTTOMRIGHT", -26, 10)
    local mContent = CreateFrame("Frame", nil, mScroll)
    mContent:SetSize(1, 1)
    mScroll:SetScrollChild(mContent)
    mScroll:SetScript("OnSizeChanged", function(_, w) mContent:SetWidth(w) end)
    mScroll:EnableMouseWheel(true)

    -- the same scroll bar as the stat list, hidden while the sets all fit
    -- (SetHideIfUnscrollable); nudge the -6 to move it in or out
    local mBar = CreateFrame("EventFrame", nil, mList, "MinimalScrollBar")
    mBar:SetPoint("TOPRIGHT", mBorder, "TOPRIGHT", -6, -14)
    mBar:SetPoint("BOTTOMRIGHT", mBorder, "BOTTOMRIGHT", -6, 14)
    mBar:SetHideIfUnscrollable(true)
    ScrollUtil.InitScrollFrameWithScrollBar(mScroll, mBar)

    local setRows = {}
    local newBtn, equipBtn, saveBtn
    local RefreshManager

    local function EquipSet(id)
        if not (ES and id) then return end
        if InCombatLockdown() then
            ErrorMessage(ERR_NOT_IN_COMBAT or "You can't do that while in combat")
            return
        end
        ES.UseEquipmentSet(id)
    end

    local function DeleteSet(id, name)
        ctx.ShowPopup(string.format("Delete the set \"%s\"?", name), false, nil, function()
            ES.DeleteEquipmentSet(id)
            if ctx.selectedSetID == id then ctx.selectedSetID = nil end
        end)
    end

    local function UpdateRowHover(r)
        local over = r:IsMouseOver()
        r.hover:SetShown(over)
        r.edit:SetShown(over)
        r.delete:SetShown(over)
    end

    local function SmallIconButton(parent, texture)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(16, 16)
        b.texture = b:CreateTexture(nil, "ARTWORK")
        b.texture:SetAllPoints()
        b.texture:SetTexture(texture)
        b:SetHighlightTexture(texture, "ADD")
        b:Hide()
        return b
    end

    local function GetSetRow(i)
        local r = setRows[i]
        if r then return r end

        r = CreateFrame("Button", nil, mContent)
        r:SetHeight(SET_ROW_H - 6)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * SET_ROW_H)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * SET_ROW_H)

        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(40, 40)
        r.icon:SetPoint("LEFT", 6, 0)
        r.iconBorder = Atlas(r, "UI-Character-Info-OutfitIcon-Frame", "OVERLAY")
        r.iconBorder:SetPoint("TOPLEFT", r.icon, -5, 5)
        r.iconBorder:SetPoint("BOTTOMRIGHT", r.icon, 5, -5)

        r.card = Atlas(r, "UI-Character-Info-OutfitCard", "BACKGROUND")
        r.card:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 4)
        r.card:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, -4)
        r.card:SetPoint("RIGHT", -2, 0)
        -- the hover card sits under the name and the tick
        r.hover = Atlas(r, "UI-Character-Info-OutfitCard-Hover", "BORDER")
        r.hover:SetAllPoints(r.card)
        r.hover:Hide()

        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetPoint("LEFT", r.card, "LEFT", 14, 0)
        r.name:SetPoint("RIGHT", r.card, "RIGHT", -44, 0)
        r.name:SetJustifyH("LEFT")

        r.check = Atlas(r, "UI-Character-Info-Icon-Tick", "OVERLAY", 0, true)
        r.check:SetPoint("TOPRIGHT", r.card, "TOPRIGHT", -8, -5)

        r.delete = SmallIconButton(r, 130775)
        r.delete:SetPoint("BOTTOMRIGHT", r.card, "BOTTOMRIGHT", -8, 6)
        r.edit = SmallIconButton(r, 311226)
        r.edit:SetPoint("RIGHT", r.delete, "LEFT", -4, 0)

        r.delete:SetScript("OnClick", function() DeleteSet(r.setID, r.setName) end)
        r.edit:SetScript("OnClick", function()
            ctx.selectedSetID = r.setID
            if ctx.ApplySetIgnores then ctx.ApplySetIgnores(ctx.selectedSetID) end
            RefreshManager()
            ctx.OpenPicker(r.setID)
        end)
        for _, btn in ipairs({ r.delete, r.edit }) do
            btn:SetScript("OnLeave", function() UpdateRowHover(r) end)
        end

        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, button)
            if ctx.selectedSetID ~= self.setID then
                ctx.selectedSetID = self.setID
                if ctx.ApplySetIgnores then ctx.ApplySetIgnores(ctx.selectedSetID) end
            end
            RefreshManager()
            if button == "RightButton" and MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateButton(L("EQUIPSET_EQUIP", "Equip"), function() EquipSet(self.setID) end)
                    root:CreateButton(L("EQUIPMENT_SET_EDIT", "Rename"), function() ctx.OpenPicker(self.setID) end)
                    root:CreateButton(L("DELETE", "Delete"), function() DeleteSet(self.setID, self.setName) end)
                end)
            end
        end)
        r:SetScript("OnDoubleClick", function(self) EquipSet(self.setID) end)

        -- drag a set onto the action bar
        r:RegisterForDrag("LeftButton")
        r:SetScript("OnDragStart", function(self)
            if self.setID and ES.PickupEquipmentSet then ES.PickupEquipmentSet(self.setID) end
        end)

        r:SetScript("OnEnter", function(self)
            UpdateRowHover(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = GameTooltip.SetEquipmentSet and pcall(GameTooltip.SetEquipmentSet, GameTooltip, self.setID)
            if not ok or GameTooltip:NumLines() == 0 then
                GameTooltip:SetText(self.setName, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function(self)
            UpdateRowHover(self)
            GameTooltip_Hide()
        end)

        setRows[i] = r
        return r
    end

    newBtn = CreateFrame("Button", nil, manager)
    newBtn:SetHeight(32)
    newBtn:SetPoint("TOPLEFT", mBorder, "BOTTOMLEFT", 8, -6)
    newBtn:SetPoint("TOPRIGHT", mBorder, "BOTTOMRIGHT", -8, -6)
    local newBg = Atlas(newBtn, "common-button-tertiary-normal", "BACKGROUND")
    newBg:SetAllPoints()
    local newHl = Atlas(newBtn, "common-button-tertiary-normal", "HIGHLIGHT")
    newHl:SetAllPoints()
    newHl:SetBlendMode("ADD")
    newHl:SetAlpha(0.3)
    local newIcon = Atlas(newBtn, "UI-Character-Info-Icon-Add", "ARTWORK", 0, true)
    newIcon:SetPoint("LEFT", 14, 0)
    local newText = newBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    newText:SetPoint("LEFT", newIcon, "RIGHT", 8, 0)
    newText:SetTextColor(0.2, 1, 0.2)
    newText:SetText(L("PAPERDOLL_NEWEQUIPMENTSET", "New Set"))
    newBtn:SetScript("OnClick", function()
        -- as in the client: clear the selection, and ignore shirt and tabard by default
        ctx.selectedSetID = nil
        if ctx.ResetIgnoresForNewSet then ctx.ResetIgnoresForNewSet() end
        RefreshManager()
        ctx.OpenPicker(nil)
    end)

    equipBtn = RedButton(manager, L("EQUIPSET_EQUIP", "Equip"), 26)
    equipBtn:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 0, -4)
    equipBtn:SetPoint("TOPRIGHT", newBtn, "BOTTOM", -3, -4)
    equipBtn:SetScript("OnClick", function() EquipSet(ctx.selectedSetID) end)

    saveBtn = RedButton(manager, L("SAVE", "Save"), 26)
    saveBtn:SetPoint("TOPLEFT", newBtn, "BOTTOM", 3, -4)
    saveBtn:SetPoint("TOPRIGHT", newBtn, "BOTTOMRIGHT", 0, -4)
    saveBtn:SetScript("OnClick", function()
        if not ctx.selectedSetID then return end
        local name, icon = ES.GetEquipmentSetInfo(ctx.selectedSetID)
        ctx.ShowPopup(string.format("Save your current equipment to \"%s\"?", name), false, nil, function()
            ES.SaveEquipmentSet(ctx.selectedSetID, icon)
        end)
    end)

    RefreshManager = function()
        if not ES then
            newBtn:Disable() equipBtn:Disable() saveBtn:Disable()
            return
        end
        local sets = {}
        for _, id in ipairs(ES.GetEquipmentSetIDs() or {}) do
            local name, icon, _, isEquipped, _, _, _, numLost = ES.GetEquipmentSetInfo(id)
            if name then
                sets[#sets + 1] = { id = id, name = name, icon = icon, equipped = isEquipped, lost = numLost or 0 }
            end
        end
        table.sort(sets, function(a, b) return a.name:lower() < b.name:lower() end)

        local found = false
        for i, s in ipairs(sets) do
            local r = GetSetRow(i)
            r.setID, r.setName, r.setIcon = s.id, s.name, s.icon
            r.icon:SetTexture(s.icon or DEFAULT_SET_ICON)
            r.name:SetText(s.name)
            if s.lost > 0 then r.name:SetTextColor(1, 0.2, 0.2) else r.name:SetTextColor(1, 0.82, 0) end
            r.check:SetShown(s.equipped)
            r.card:SetAtlas(s.id == ctx.selectedSetID and "UI-Character-Info-OutfitCard-Selected" or "UI-Character-Info-OutfitCard")
            UpdateRowHover(r)
            r:Show()
            if s.id == ctx.selectedSetID then found = true end
        end
        for i = #sets + 1, #setRows do setRows[i]:Hide() end
        if not found then
            if ctx.selectedSetID and ctx.ClearIgnores then ctx.ClearIgnores() end
            ctx.selectedSetID = nil
        end
        mContent:SetHeight(math.max(1, #sets * SET_ROW_H))

        local canAdd = #sets < (MAX_EQUIPMENT_SETS_PER_PLAYER or 10)
        newBtn:SetEnabled(canAdd)
        newBtn:SetAlpha(canAdd and 1 or 0.5)
        equipBtn:SetEnabled(ctx.selectedSetID ~= nil)
        saveBtn:SetEnabled(ctx.selectedSetID ~= nil)
    end
    ctx.RefreshManager = RefreshManager
    ctx.saveBtn = saveBtn

    manager:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    manager:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    manager:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    manager:SetScript("OnEvent", function(self)
        if self:IsVisible() then RefreshManager() end
    end)
    manager:SetScript("OnShow", function()
        UpdateClassBackgrounds()
        RefreshManager()
    end)
end

----------------------------------------------------------------------
-- Icon picker (to the right of the window, as GearManagerPopupFrame is)
----------------------------------------------------------------------
local function BuildIconPicker(ctx)
    local f, ES = ctx.frame, ctx.ES

    local picker = CreateFrame("Frame", nil, f)
    picker:SetSize(540, 500)
    picker:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
    picker:SetFrameStrata("DIALOG")
    picker:EnableMouse(true)
    picker:Hide()
    ctx.picker = picker

    local pBg = picker:CreateTexture(nil, "BACKGROUND", nil, -8)
    pBg:SetPoint("TOPLEFT", 6, -6)
    pBg:SetPoint("BOTTOMRIGHT", -6, 6)
    pBg:SetColorTexture(0.04, 0.035, 0.03, 0.97)

    do -- frame from the macro popup's pieces
        local tl = Atlas(picker, "macropopup-topleft", "BORDER", 1, true);     tl:SetPoint("TOPLEFT")
        local tr = Atlas(picker, "macropopup-topright", "BORDER", 1, true);    tr:SetPoint("TOPRIGHT")
        local bl = Atlas(picker, "macropopup-bottomleft", "BORDER", 1, true);  bl:SetPoint("BOTTOMLEFT")
        local br = Atlas(picker, "macropopup-bottomright", "BORDER", 1, true); br:SetPoint("BOTTOMRIGHT")
        local top = Atlas(picker, "_macropopup-top", "BORDER", 0, true)
        top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("TOPRIGHT", tr, "TOPLEFT"); top:SetHorizTile(true)
        local bot = Atlas(picker, "_macropopup-bottom", "BORDER", 0, true)
        bot:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT"); bot:SetHorizTile(true)
        local le = Atlas(picker, "!macropopup-left", "BORDER", 0, true)
        le:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); le:SetPoint("BOTTOMLEFT", bl, "TOPLEFT"); le:SetVertTile(true)
        local ri = Atlas(picker, "!macropopup-right", "BORDER", 0, true)
        ri:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT"); ri:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT"); ri:SetVertTile(true)
    end

    local pNameLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pNameLabel:SetPoint("TOPLEFT", 26, -18)
    pNameLabel:SetText(L("GEARSETS_POPUP_TEXT", "Enter Set Name (Max 16 Characters):"))

    local pEdit = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    pEdit:SetSize(260, 24)
    pEdit:SetPoint("TOPLEFT", pNameLabel, "BOTTOMLEFT", 6, -6)
    pEdit:SetAutoFocus(false)
    pEdit:SetMaxLetters(16)

    -- the chosen icon, top right
    local pSelBtn = CreateFrame("Button", nil, picker)
    pSelBtn:SetSize(40, 40)
    pSelBtn:SetPoint("TOPRIGHT", -22, -18)
    local pSelIcon = pSelBtn:CreateTexture(nil, "ARTWORK")
    pSelIcon:SetAllPoints()
    local pSelFrame = pSelBtn:CreateTexture(nil, "BACKGROUND")
    pSelFrame:SetTexture(130764)
    pSelFrame:SetPoint("TOPLEFT", -6, 6)
    pSelFrame:SetPoint("BOTTOMRIGHT", 6, -6)
    pSelBtn:SetHighlightTexture(130718, "ADD")

    local pSelTitle = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pSelTitle:SetPoint("TOPRIGHT", pSelBtn, "TOPLEFT", -10, -2)
    pSelTitle:SetText(L("ICON_SELECTION_TITLE_CURRENT", "Currently Selected"))
    local pSelHint = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pSelHint:SetPoint("TOPRIGHT", pSelTitle, "BOTTOMRIGHT", 0, -3)
    pSelHint:SetText(L("ICON_SELECTION_CLICK", "Click to view in the list"))

    local pChoose = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pChoose:SetPoint("TOPLEFT", 26, -104)
    pChoose:SetText(L("MACRO_POPUP_CHOOSE_ICON", "Choose an Icon:"))

    local FILTERS = {
        { key = "all",    text = L("ICON_FILTER_ALL", "All Icons") },
        { key = "spells", text = L("ICON_FILTER_SPELLS", "Spells") },
        { key = "items",  text = L("ICON_FILTER_ITEMS", "Items") },
        { key = "class",  text = "My Class" },
    }

    -- every icon in the own spellbook (new API, else the old one)
    local function AddSpellbookIcons(add)
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
            local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
            for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
                local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
                if info then
                    for idx = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                        local item = C_SpellBook.GetSpellBookItemInfo(idx, bank)
                        if item then add(item.iconID) end
                    end
                end
            end
        elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellTexture then
            for tab = 1, GetNumSpellTabs() do
                local _, _, offset, num = GetSpellTabInfo(tab)
                for idx = offset + 1, offset + num do
                    add(GetSpellTexture(idx, "spell"))
                end
            end
        end
    end

    local pDrop = CreateFrame("Button", nil, picker)
    pDrop:SetSize(170, 28)
    pDrop:SetPoint("TOPRIGHT", -40, -96)
    local pDropBg = Atlas(pDrop, "common-dropdown-textholder", "BACKGROUND")
    pDropBg:SetAllPoints()
    local pDropArrow = Atlas(pDrop, "common-dropdown-a-button", "ARTWORK", 0, true)
    pDropArrow:SetPoint("RIGHT", -2, 0)
    local pDropText = pDrop:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pDropText:SetPoint("LEFT", 10, 0)
    pDropText:SetPoint("RIGHT", pDropArrow, "LEFT", -4, 0)
    pDropText:SetJustifyH("LEFT")

    -- the grid: fixed buttons, whose icons are swapped as the list scrolls
    local pGrid = CreateFrame("Frame", nil, picker)
    pGrid:SetPoint("TOPLEFT", 28, -125)
    pGrid:SetPoint("BOTTOMRIGHT", -36, 52)

    -- the client's scroll bar, over the grid's fake scroll: the bar's
    -- percentage stands for the first visible row, rounded to whole rows
    local pBar = CreateFrame("EventFrame", nil, picker, "MinimalScrollBar")
    pBar:SetPoint("TOPLEFT", pGrid, "TOPRIGHT", 10, -14)
    pBar:SetPoint("BOTTOMLEFT", pGrid, "BOTTOMRIGHT", 10, 14)
    pBar:SetHideIfUnscrollable(true)

    local pState = { icons = {}, selected = DEFAULT_SET_ICON, filter = "all", setID = nil, row = 0, scrollable = 0 }
    local pButtons = {}
    local UpdateGrid

    for i = 1, ICON_COLS * VISIBLE_ROWS do
        local b = CreateFrame("Button", nil, pGrid)
        b:SetSize(ICON_SIZE, ICON_SIZE)
        local col, row = (i - 1) % ICON_COLS, math.floor((i - 1) / ICON_COLS)
        b:SetPoint("TOPLEFT", col * ICON_STEP, -row * ICON_STEP)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.sel = b:CreateTexture(nil, "OVERLAY")
        b.sel:SetTexture(130724)
        b.sel:SetPoint("TOPLEFT", -4, 4)
        b.sel:SetPoint("BOTTOMRIGHT", 4, -4)
        b.sel:SetBlendMode("ADD")
        b:SetHighlightTexture(130718, "ADD")
        b:SetScript("OnClick", function(self)
            pState.selected = self.iconID
            pSelIcon:SetTexture(self.iconID)
            UpdateGrid()
        end)
        pButtons[i] = b
    end

    local function NormalizeIcon(v)
        if type(v) == "string" and not v:find("[\\/]") then
            return "Interface\\Icons\\" .. v
        end
        return v
    end

    local function BuildIconList(filter)
        local list, seen = {}, {}
        local function add(icon)
            icon = NormalizeIcon(icon)
            if icon and not seen[icon] then
                seen[icon] = true
                list[#list + 1] = icon
            end
        end
        add(DEFAULT_SET_ICON)
        if filter == "class" then
            local _, classFile = UnitClass("player")
            if classFile then
                local nice = classFile:sub(1, 1) .. classFile:sub(2):lower()
                add("Interface\\Icons\\ClassIcon_" .. nice)
            end
            AddSpellbookIcons(add)
            return list
        end
        if filter ~= "spells" then
            for slot = 1, 19 do add(GetInventoryItemTexture("player", slot)) end
        end
        if filter ~= "items" and GetMacroIcons then
            local t = {}
            pcall(GetMacroIcons, t)
            for _, v in ipairs(t) do add(v) end
        end
        if filter ~= "spells" and GetMacroItemIcons then
            local t = {}
            pcall(GetMacroItemIcons, t)
            for _, v in ipairs(t) do add(v) end
        end
        return list
    end

    UpdateGrid = function()
        local offset = pState.row * ICON_COLS
        for i, b in ipairs(pButtons) do
            local icon = pState.icons[offset + i]
            b.iconID = icon
            if icon then
                b.icon:SetTexture(icon)
                b.sel:SetShown(icon == pState.selected)
                b:Show()
            else
                b:Hide()
            end
        end
    end

    local function SetFilter(key)
        pState.filter = key
        for _, fl in ipairs(FILTERS) do
            if fl.key == key then pDropText:SetText(fl.text) end
        end
        pState.icons = BuildIconList(key)
        local rows = math.ceil(#pState.icons / ICON_COLS)
        pState.scrollable = math.max(0, rows - VISIBLE_ROWS)
        pBar:SetVisibleExtentPercentage(rows > 0 and math.min(1, VISIBLE_ROWS / rows) or 0)
        pBar:SetPanExtentPercentage(pState.scrollable > 0 and 1 / pState.scrollable or 0)
        pBar:SetScrollPercentage(0, true)
        UpdateGrid()
    end

    local function ScrollToSelected()
        for idx, icon in ipairs(pState.icons) do
            if icon == pState.selected then
                local row = math.min(math.floor((idx - 1) / ICON_COLS), pState.scrollable or 0)
                pBar:SetScrollPercentage(pState.scrollable > 0 and row / pState.scrollable or 0, true)
                break
            end
        end
        UpdateGrid()
    end

    -- the percentage is rounded back into a whole row on every scroll
    pBar:RegisterCallback(ScrollBarMixin.Event.OnScroll, function()
        pState.row = math.floor(pBar:GetScrollPercentage() * (pState.scrollable or 0) + 0.5)
        UpdateGrid()
    end)
    pGrid:EnableMouseWheel(true)
    pGrid:SetScript("OnMouseWheel", function(_, delta) pBar:ScrollStepInDirection(-delta) end)
    pSelBtn:SetScript("OnClick", ScrollToSelected)

    pDrop:SetScript("OnClick", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then
            for i, fl in ipairs(FILTERS) do
                if fl.key == pState.filter then SetFilter(FILTERS[i % #FILTERS + 1].key) break end
            end
            return
        end
        MenuUtil.CreateContextMenu(self, function(_, root)
            for _, fl in ipairs(FILTERS) do
                root:CreateRadio(fl.text,
                    function() return pState.filter == fl.key end,
                    function() SetFilter(fl.key) end)
            end
        end)
    end)

    local pCancel = RedButton(picker, L("CANCEL", "Cancel"), 26)
    pCancel:SetWidth(120)
    pCancel:SetPoint("BOTTOMRIGHT", -16, 10)
    pCancel:SetScript("OnClick", function() picker:Hide() end)

    local pOkay = RedButton(picker, L("OKAY", "Okay"), 26)
    pOkay:SetWidth(120)
    pOkay:SetPoint("RIGHT", pCancel, "LEFT", -6, 0)

    pEdit:SetScript("OnTextChanged", function(self)
        pOkay:SetEnabled(strtrim(self:GetText() or "") ~= "")
    end)
    pEdit:SetScript("OnEnterPressed", function() if pOkay:IsEnabled() then pOkay:Click() end end)
    pEdit:SetScript("OnEscapePressed", function() picker:Hide() end)

    pOkay:SetScript("OnClick", function()
        local name = strtrim(pEdit:GetText() or "")
        if name == "" or not ES then return end
        local existing = ES.GetEquipmentSetID(name)
        if existing and existing ~= pState.setID then
            ErrorMessage("A set with this name already exists.")
            return
        end
        if pState.setID then
            ES.ModifyEquipmentSet(pState.setID, name, pState.selected)
        else
            ES.CreateEquipmentSet(name, pState.selected)
            ctx.selectedSetID = ES.GetEquipmentSetID(name)
        end
        picker:Hide()
        ctx.RefreshManager()
    end)

    -- opens for a new set (no id) or for editing one (its id)
    ctx.OpenPicker = function(setID)
        pState.setID = setID
        local name, icon = "", nil
        if setID then name, icon = ES.GetEquipmentSetInfo(setID) end
        SetFilter("all")
        pState.selected = icon or DEFAULT_SET_ICON
        pSelIcon:SetTexture(pState.selected)
        pEdit:SetText(name or "")
        pOkay:SetEnabled((name or "") ~= "")
        picker:Show()
        ScrollToSelected()
        pEdit:SetFocus()
        pEdit:HighlightText()
    end

    f:HookScript("OnHide", function() picker:Hide() end)
    ctx.manager:HookScript("OnHide", function() picker:Hide() end)
end

----------------------------------------------------------------------
-- Equipment flyout: Alt over a slot, or an arrow in the manager, opens the
-- items that fit the slot. A click equips one; the ignore marks and "place in
-- bags" are there too. Own frames, not Blizzard's EquipmentFlyoutFrame.
----------------------------------------------------------------------
local function BuildFlyout(ctx)
    local f, slots, manager, picker = ctx.frame, ctx.slots, ctx.manager, ctx.picker
    local ES, left = ctx.ES, ctx.left
    local LOC_PLACEINBAGS = EQUIPMENTFLYOUT_PLACEINBAGS_LOCATION or 0xFFFFFFFF
    local LOC_IGNORE = EQUIPMENTFLYOUT_IGNORESLOT_LOCATION or 0xFFFFFFFE
    local LOC_UNIGNORE = EQUIPMENTFLYOUT_UNIGNORESLOT_LOCATION or 0xFFFFFFFD
    local LOC_FIRST_SPECIAL = LOC_UNIGNORE
    local COMBAT_SLOTS = INVSLOTS_EQUIPABLE_IN_COMBAT or { [16] = true, [17] = true, [18] = true }
    local INV_PLAYER = ITEM_INVENTORY_LOCATION_PLAYER or 0x00100000
    local TEX = {
        oneL = { 0, 0.09765625, 0.5546875, 0.77734375 },     oneR = { 0.41796875, 0.51171875, 0.5546875, 0.77734375 },
        rowL = { 0, 0.16796875, 0.5546875, 0.77734375 },     rowC = { 0.16796875, 0.328125, 0.5546875, 0.77734375 },
        rowR = { 0.328125, 0.51171875, 0.5546875, 0.77734375 },
        top = { 0, 0.8359375, 0, 0.19140625 }, mid = { 0, 0.8359375, 0.19140625, 0.35546875 },
        bot = { 0, 0.8359375, 0.35546875, 0.546875 },
    }

    local ignored = {}   -- slotId -> true; the client keeps the real list
    local selectedSetID -- read from ctx when needed

    local function UpdateIgnoreTextures()
        local show = manager:IsVisible()
        for _, b in ipairs(slots) do
            if b.ignoreTex then b.ignoreTex:SetShown(show and ignored[b.slotId] == true) end
        end
    end

    local function SetIgnored(slotId, on)
        if not ES then return end
        if on then ES.IgnoreSlotForSave(slotId) else ES.UnignoreSlotForSave(slotId) end
        ignored[slotId] = on or nil
        UpdateIgnoreTextures()
    end

    ctx.ClearIgnores = function()
        if ES and ES.ClearIgnoredSlotsForSave then ES.ClearIgnoredSlotsForSave() end
        wipe(ignored)
        UpdateIgnoreTextures()
    end

    ctx.ApplySetIgnores = function(setID)
        ctx.ClearIgnores()
        if not (setID and ES and ES.GetIgnoredSlots) then return end
        for slotId, ign in pairs(ES.GetIgnoredSlots(setID) or {}) do
            if ign then SetIgnored(slotId, true) end
        end
    end

    ctx.ResetIgnoresForNewSet = function()
        ctx.ClearIgnores()
        SetIgnored(4, true)   -- shirt
        SetIgnored(19, true)  -- tabard
    end

    -- the ignore mark on every slot
    for _, b in ipairs(slots) do
        b.ignoreTex = b:CreateTexture(nil, "OVERLAY", nil, 3)
        b.ignoreTex:SetTexture([[Interface\PaperDollInfoFrame\UI-GearManager-LeaveItem-Transparent]])
        b.ignoreTex:SetPoint("CENTER")
        b.ignoreTex:SetSize(b:GetWidth() * 40 / 37, b:GetHeight() * 40 / 37)
        b.ignoreTex:Hide()
    end

    -- the flyout frame
    local flyout = CreateFrame("Frame", nil, f)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetSize(43, 43)
    flyout:Hide()
    flyout.highlight = flyout:CreateTexture(nil, "OVERLAY")
    flyout.highlight:SetTexture([[Interface\PaperDollInfoFrame\UI-GearManager-ItemButton-Highlight]])
    flyout.highlight:SetTexCoord(0, 0.78125, 0, 0.78125)

    local holder = CreateFrame("Frame", nil, flyout)
    holder:EnableMouse(true)
    holder:SetClampedToScreen(true)
    holder.bgs = {}

    local function GetBG(i)
        local t = holder.bgs[i]
        if not t then
            t = holder:CreateTexture(nil, "BACKGROUND")
            t:SetTexture(FLYOUT_TEX)
            holder.bgs[i] = t
        end
        return t
    end

    local function PlaceBG(i, coords, w, h, prev, below)
        local t = GetBG(i)
        t:ClearAllPoints()
        t:SetTexCoord(unpack(coords))
        t:SetSize(w, h)
        if not prev then
            t:SetPoint("TOPLEFT", -5, 4)
        elseif below then
            t:SetPoint("TOPLEFT", prev, "BOTTOMLEFT")
        else
            t:SetPoint("TOPLEFT", prev, "TOPRIGHT")
        end
        t:Show()
        return t
    end

    local function LayoutBackground(n)
        local used = 0
        local function add(coords, w, h, below)
            used = used + 1
            return PlaceBG(used, coords, w, h, used > 1 and holder.bgs[used - 1] or nil, below)
        end
        if n == 1 then
            add(TEX.oneL, 25, FLY_ROW_H) add(TEX.oneR, 24, FLY_ROW_H)
        elseif n <= PER_ROW then
            add(TEX.rowL, 43, FLY_ROW_H)
            for _ = 2, n - 1 do add(TEX.rowC, 41, FLY_ROW_H) end
            add(TEX.rowR, 47, FLY_ROW_H)
        else
            local rows = math.ceil(n / PER_ROW)
            add(TEX.top, 214, 49)
            for _ = 2, rows - 1 do add(TEX.mid, 214, 42, true) end
            add(TEX.bot, 214, 49, true)
        end
        for i = used + 1, #holder.bgs do holder.bgs[i]:Hide() end
    end

    -- page bar, for more than 20 items
    local nav = CreateFrame("Frame", nil, flyout)
    nav:SetSize(214, 41)
    nav:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", -5, 0)
    nav:EnableMouse(true)
    do
        local bg = nav:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(FLYOUT_TEX)
        bg:SetTexCoord(0, 0.8359375, 0.7890625, 0.94921875)
        bg:SetAllPoints()
    end
    local function NavButton(dir)
        local b = CreateFrame("Button", nil, nav)
        b:SetSize(32, 32)
        local base = [[Interface\Buttons\UI-SpellbookIcon-]] .. dir .. "Page-"
        b:SetNormalTexture(base .. "Up")
        b:SetPushedTexture(base .. "Down")
        b:SetDisabledTexture(base .. "Disabled")
        b:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
        return b
    end
    nav.prev = NavButton("Prev")
    nav.prev:SetPoint("LEFT", 6, 1)
    nav.next = NavButton("Next")
    nav.next:SetPoint("RIGHT", -3, 1)
    do
        local pt = nav:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        pt:SetPoint("LEFT", 36, 1)
        pt:SetText(PREVIOUS or "Prev")
        local nt = nav:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        nt:SetPoint("RIGHT", -33, 1)
        nt:SetText(NEXT or "Next")
    end

    -- item buttons
    local buttons = {}
    local itemTable, display = {}, {}
    local OnFlyoutClick

    local function CreateItemButton()
        local i = #buttons + 1
        local ok, b = pcall(CreateFrame, "ItemButton", nil, holder)
        if not ok or not b then b = CreateFrame("Button", nil, holder, "ItemButtonTemplate") end
        b:SetSize(FLY_ITEM_W, FLY_ITEM_H)
        b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cooldown:SetAllPoints()
        local row = math.floor((i - 1) / PER_ROW)
        if (i - 1) % PER_ROW == 0 then
            b:SetPoint("TOPLEFT", holder, "TOPLEFT", FLY_BORDER, -FLY_BORDER - (FLY_ITEM_H - FLY_YOFS) * row)
        else
            b:SetPoint("TOPLEFT", buttons[i - 1], "TOPRIGHT", FLY_XOFS, 0)
        end
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function(self) OnFlyoutClick(self) end)
        b:SetScript("OnEnter", function(self) if self.UpdateTooltip then self.UpdateTooltip() end end)
        b:SetScript("OnLeave", function() GameTooltip_Hide() if ResetCursor then ResetCursor() end end)
        buttons[i] = b
        return b
    end

    local function SpecialTooltip(text)
        return function()
            GameTooltip:SetOwner(holder, "ANCHOR_RIGHT", 6, -holder:GetHeight() - 6)
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:Show()
        end
    end

    local function SetupButton(btn, location, slot)
        btn.location = location
        if btn.cooldown then btn.cooldown:Hide() end
        if location >= LOC_FIRST_SPECIAL then
            local tex, text
            if location == LOC_IGNORE then
                tex, text = [[Interface\PaperDollInfoFrame\UI-GearManager-LeaveItem-Opaque]], EQUIPMENT_MANAGER_IGNORE_SLOT or "Ignore this slot"
            elseif location == LOC_UNIGNORE then
                tex, text = [[Interface\PaperDollInfoFrame\UI-GearManager-Undo]], EQUIPMENT_MANAGER_UNIGNORE_SLOT or "Unignore this slot"
            else
                tex, text = [[Interface\PaperDollInfoFrame\UI-GearManager-ItemIntoBag]], EQUIPMENT_MANAGER_PLACE_IN_BAGS or "Place in bags"
            end
            SetItemButtonTexture(btn, tex)
            SetItemButtonCount(btn, nil)
            SetItemButtonQuality(btn, nil, nil)
            SetItemButtonTextureVertexColor(btn, 1, 1, 1)
            SetItemButtonNormalTextureVertexColor(btn, 1, 1, 1)
            btn.UpdateTooltip = SpecialTooltip(text)
        else
            local ok, itemID, _, tex, count, dur, maxDur, _, _, start, duration, enable, setTooltip, quality, _, isBound =
                pcall(EquipmentManager_GetItemInfoByLocation, location)
            if not ok then tex = nil end
            if tex then
                SetItemButtonTexture(btn, tex)
                SetItemButtonCount(btn, count)
                local broken = maxDur and dur == 0
                local g = broken and 0 or 1
                SetItemButtonTextureVertexColor(btn, broken and 0.9 or 1, g, g)
                SetItemButtonNormalTextureVertexColor(btn, broken and 0.9 or 1, g, g)
                pcall(SetItemButtonQuality, btn, quality, itemID, false, isBound)
                if btn.cooldown and start and CooldownFrame_Set then CooldownFrame_Set(btn.cooldown, start, duration, enable) end
                btn.UpdateTooltip = function()
                    GameTooltip:SetOwner(btn, (btn:GetRight() or 0) < GetScreenWidth() / 2 and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
                    if setTooltip then setTooltip() end
                    if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
                    GameTooltip:Show()
                end
            else
                SetItemButtonTexture(btn, slot.emptyTex)
                SetItemButtonCount(btn, 0)
                btn.UpdateTooltip = nil
            end
        end
        if btn:IsMouseOver() and btn.UpdateTooltip then btn.UpdateTooltip() end
    end

    -- arrows beside the slots, visible in the manager
    local PULL = FLY_PULL
    local DIRS = {
        LEFT  = { set = PULL.side, rot = 0,       w = 20, h = 43 },
        RIGHT = { set = PULL.side, rot = math.pi, w = 20, h = 43 },
        UP    = { set = PULL.up,   rot = 0,       w = 43, h = 20 },
    }
    local popouts = {}
    local ShowFlyout

    local function RefreshPopout(p)
        local d = DIRS[p.dir]
        local normal = p.locked and d.set.o or d.set.n
        p:SetNormalAtlas(normal, true)
        p:SetPushedAtlas(d.set.p, true)
        p:SetHighlightAtlas(normal, "ADD")
        p:SetSize(d.w, d.h)
        for _, t in ipairs({ p:GetNormalTexture(), p:GetPushedTexture(), p:GetHighlightTexture() }) do
            if t and t.SetRotation then t:SetRotation(d.rot) end
        end
    end

    local function CreatePopout(b, dir)
        local p = CreateFrame("Button", nil, left)
        p.dir, p.slot = dir, b
        p:SetFrameLevel(math.max(1, b:GetFrameLevel() - 1))
        if dir == "LEFT" then
            p:SetPoint("RIGHT", b, "LEFT", -5, 0)
        elseif dir == "UP" then
            p:SetPoint("BOTTOM", b, "TOP", 0, 5)
        else
            p:SetPoint("LEFT", b, "RIGHT", 5, 0)
        end
        RefreshPopout(p)
        p:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            if self.locked then
                self.locked = false
                flyout:Hide()
            else
                self.locked = true
                ShowFlyout(self.slot)
            end
            RefreshPopout(self)
        end)
        for _, ev in ipairs({ "OnShow", "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp" }) do
            p:SetScript(ev, RefreshPopout)
        end
        p:Hide()
        b.popout = p
        popouts[#popouts + 1] = p
    end

    local slotGroups = ctx.slotGroups
    for _, b in ipairs(slotGroups.left) do CreatePopout(b, "RIGHT") end
    for _, b in ipairs(slotGroups.right) do CreatePopout(b, "LEFT") end
    for _, b in ipairs(slotGroups.bottom) do CreatePopout(b, "UP") end

    local function UnlockAll()
        for _, p in ipairs(popouts) do
            if p.locked then p.locked = false RefreshPopout(p) end
        end
    end

    local function ShowPopouts(show)
        for _, p in ipairs(popouts) do
            p:SetShown(show and p.slot:IsShown())
        end
    end

    local function UpdatePage()
        local slot = flyout.slot
        local total = flyout.total
        local maxPage = math.max(1, math.ceil(total / PER_PAGE))
        local page = math.min(math.max(flyout.page or 1, 1), maxPage)
        flyout.page = page
        local offset = (page - 1) * PER_PAGE
        local numOnPage = (page == maxPage) and (total - offset) or PER_PAGE

        nav:SetShown(maxPage > 1)
        nav.prev:SetEnabled(page > 1)
        nav.next:SetEnabled(page < maxPage)

        while #buttons < numOnPage do CreateItemButton() end
        for i, btn in ipairs(buttons) do
            if i <= numOnPage then
                btn:Show()
                SetupButton(btn, display[offset + i], slot)
            else
                btn:Hide()
            end
        end

        -- from page 2 on, pages are full (the page bar takes room)
        local n = (page == 1) and numOnPage or PER_PAGE
        local cols = math.min(n, PER_ROW)

        flyout:ClearAllPoints()
        flyout:SetPoint("CENTER", slot, "CENTER")
        flyout.highlight:ClearAllPoints()
        flyout.highlight:SetPoint("CENTER", slot, "CENTER")
        flyout.highlight:SetSize(slot:GetWidth() * 50 / 37, slot:GetHeight() * 50 / 37)

        local anchor = slot.popout or slot
        holder:ClearAllPoints()
        if slot.popout and slot.popout.dir == "LEFT" then
            holder:SetPoint("TOPRIGHT", anchor, "TOPLEFT", 0, -3)
        elseif slot.popout and slot.popout.dir == "UP" then
            holder:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 0)
        else
            holder:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, -3)
        end
        holder:SetSize(cols * FLY_ITEM_W + (cols - 1) * FLY_XOFS + FLY_BORDER,
            43 + math.floor((n - 1) / PER_ROW) * (FLY_ITEM_H - FLY_YOFS))
        if flyout.numShown ~= n then
            LayoutBackground(n)
            flyout.numShown = n
        end
    end

    ShowFlyout = function(slot)
        if not (slot and slot.slotId) or slot.slotName == "AmmoSlot" then return end
        if flyout.slot ~= slot then
            flyout.page = nil
            if flyout.slot and flyout.slot.popout and flyout.slot.popout.locked then
                flyout.slot.popout.locked = false
                RefreshPopout(flyout.slot.popout)
            end
        end
        flyout.slot = slot
        local id = slot.slotId

        wipe(itemTable)
        wipe(display)
        if GetInventoryItemsForSlot then GetInventoryItemsForSlot(id, itemTable) end
        for location in pairs(itemTable) do
            if (location - id) ~= INV_PLAYER then -- the equipped item is not listed
                display[#display + 1] = location
            end
        end
        table.sort(display) -- equipped, bags, bank

        local showIgnore = manager:IsVisible() and (ctx.selectedSetID ~= nil or picker:IsShown())
        if showIgnore then
            table.insert(display, 1, ignored[id] and LOC_UNIGNORE or LOC_IGNORE)
        end
        if GetInventoryItemTexture("player", id) then
            table.insert(display, 1, LOC_PLACEINBAGS)
        end

        flyout.total = #display
        if flyout.total == 0 then
            flyout:Hide()
            return
        end
        UpdatePage()
        flyout:Show()
    end

    local function HideFlyout()
        flyout:Hide()
    end

    nav.prev:SetScript("OnClick", function() flyout.page = (flyout.page or 1) - 1 UpdatePage() end)
    nav.next:SetScript("OnClick", function() flyout.page = (flyout.page or 1) + 1 UpdatePage() end)

    local function IsOverSlot(slot)
        return slot:IsMouseOver()
    end

    -- without Alt, the flyout stays only while the mouse is on the slot or
    -- its arrow is locked
    flyout:SetScript("OnUpdate", function(self)
        if IsModifiedClick("SHOWITEMFLYOUT") then return end
        local slot = self.slot
        if slot and slot.popout and slot.popout.locked then return end
        if slot and slot:IsVisible() and IsOverSlot(slot) then return end
        self:Hide()
    end)

    flyout:SetScript("OnShow", function(self)
        self:RegisterEvent("BAG_UPDATE")
        self:RegisterEvent("UNIT_INVENTORY_CHANGED")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    end)
    flyout:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        if self.slot and self.slot.popout and self.slot.popout.locked then
            self.slot.popout.locked = false
            RefreshPopout(self.slot.popout)
        end
        self.slot = nil
    end)
    flyout:SetScript("OnEvent", function(self, event, unit)
        if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
        if self.slot then
            local page = self.page
            ShowFlyout(self.slot)
            self.page = page
            if self:IsShown() then UpdatePage() end
        end
    end)

    -- a click on an entry (as the client's flyout button does)
    OnFlyoutClick = function(btn)
        local slot = flyout.slot
        if not (slot and btn.location) then return end
        local id = slot.slotId
        local loc = btn.location
        if loc == LOC_IGNORE or loc == LOC_UNIGNORE then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            SetIgnored(id, loc == LOC_IGNORE)
            if ctx.saveBtn and ctx.selectedSetID then ctx.saveBtn:Enable() end
            ShowFlyout(slot)
            return
        end
        if UnitAffectingCombat("player") and not COMBAT_SLOTS[id] then
            UIErrorsFrame:AddMessage(ERR_CLIENT_LOCKED_OUT or ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1, 1.0)
            return
        end
        local action
        if loc == LOC_PLACEINBAGS then
            action = EquipmentManager_UnequipItemInSlot(id)
        else
            action = EquipmentManager_EquipItemByLocation(loc, id)
        end
        if action then EquipmentManager_RunAction(action) end
        if slot.popout and slot.popout.locked then flyout:Hide() end
    end

    -- hover and Alt
    local hoverSlot

    local function UpdateFlyoutFor(slot)
        if slot.slotName == "AmmoSlot" then return end
        local locked = slot.popout and slot.popout.locked
        local alt = IsModifiedClick("SHOWITEMFLYOUT")
        local shownHere = flyout:IsShown() and flyout.slot == slot
        if (alt and not shownHere) or locked then
            ShowFlyout(slot)
        elseif shownHere and not locked and not alt then
            HideFlyout()
        end
    end

    ctx.OnSlotEnter = function(slot)
        hoverSlot = slot
        UpdateFlyoutFor(slot)
    end
    ctx.OnSlotLeave = function(slot)
        if hoverSlot == slot then hoverSlot = nil end
    end
    ctx.AnchorTooltipToFlyout = function()
        if flyout:IsShown() then
            GameTooltip:SetOwner(holder, "ANCHOR_RIGHT", 6, -holder:GetHeight() - 6)
            return true
        end
    end

    local modWatch = CreateFrame("Frame")
    modWatch:RegisterEvent("MODIFIER_STATE_CHANGED")
    modWatch:SetScript("OnEvent", function()
        local s = hoverSlot
        if s and s:IsVisible() and IsOverSlot(s) then
            UpdateFlyoutFor(s)
            local fn = s:GetScript("OnEnter")
            if fn then fn(s) end
        end
    end)

    left:HookScript("OnHide", HideFlyout)
    manager:HookScript("OnShow", function()
        ShowPopouts(true)
        if ctx.selectedSetID then ctx.ApplySetIgnores(ctx.selectedSetID) else UpdateIgnoreTextures() end
    end)
    manager:HookScript("OnHide", function()
        UnlockAll()
        HideFlyout()
        ShowPopouts(false)
        ctx.ClearIgnores()
    end)
    picker:HookScript("OnHide", function()
        if not ctx.selectedSetID and manager:IsVisible() then ctx.ClearIgnores() end
        if flyout:IsShown() and flyout.slot then ShowFlyout(flyout.slot) end
    end)
end

----------------------------------------------------------------------
-- SnapChar's shared pieces, under the names the Tabs/ files use. The Tabs/
-- files get the Journal's addon table as `ns`, so these are set on it.
-- Everything below sits in one block: its locals stay out of the file's
-- own count of 200.
----------------------------------------------------------------------
do
local T = setmetatable({}, { __index = function(_, k) return k end })
local fmtNum = BreakUpLargeNumbers or tostring

ns.L, ns.T, ns.fmtNum = L, T, fmtNum
ns.IsSecret, ns.Atlas, ns.WithColon = IsSecret, Atlas, WithColon
ns.CopySlice, ns.CropBottom, ns.CropTabIcon = CopySlice, CropBottom, CropTabIcon
ns.BG_CROP_BOTTOM = BG_CROP_BOTTOM
ns.ShowStatTooltip = ShowStatTooltip
ns.LEFT_W = LEFT_PAGE_W
ns.CombatError = function() ErrorMessage(ERR_NOT_IN_COMBAT or "You can't do that while in combat") end
ns.CombatSettingsNotice = function() end -- nothing waits for combat in this window

----------------------------------------------------------------------
-- Settings: stored in the Journal's account-wide settings. Until the addon
-- has loaded its data, the defaults apply.
----------------------------------------------------------------------
local SETTING_DEFAULTS = { showAvgIlvl = true, showSlotIlvl = true, windowScale = 1,
    statsFontScale = 1, uiFontScale = 1, hideLastName = false, hideLevel = false }
local settingListeners = {}

function ns.GetSetting(key)
    local s = AJ.settings
    if s and s[key] ~= nil then return s[key] end
    return SETTING_DEFAULTS[key]
end

function ns.OnSettingChanged(fn) settingListeners[#settingListeners + 1] = fn end

local function FireSetting(key)
    for _, fn in ipairs(settingListeners) do fn(key) end
end

function ns.SetSetting(key, value)
    if not AJ.settings then return end
    AJ.settings[key] = value
    FireSetting(key)
end

function ns.ApplyAllSettings() FireSetting(nil) end

----------------------------------------------------------------------
-- Font sizes: each text remembers its base size and is scaled by its group
-- ("stats" = the stat list, "ui" = the other tabs).
----------------------------------------------------------------------
local FONT_KEYS = { stats = "statsFontScale", ui = "uiFontScale" }
local fontRegistry = { stats = setmetatable({}, { __mode = "k" }), ui = setmetatable({}, { __mode = "k" }) }
ns.fontScaleCallbacks = {}

function ns.GetFontScale(group) return ns.GetSetting(FONT_KEYS[group]) or 1 end

local function SetFontBase(fs, group, font, size, flags)
    fontRegistry[group][fs] = { font, size, flags }
    fs:SetFont(font, size * ns.GetFontScale(group), flags)
    return fs
end

function ns.ScaleFont(fs, group)
    local base = fontRegistry[group][fs]
    if base then return SetFontBase(fs, group, base[1], base[2], base[3]) end
    local font, size, flags = fs:GetFont()
    if not (font and size) then return fs end
    return SetFontBase(fs, group, font, size, flags)
end

function ns.SetScaledFontObject(fs, fontObject, group)
    local obj = type(fontObject) == "string" and _G[fontObject] or fontObject
    fs:SetFontObject(obj)
    local font, size, flags
    if obj and obj.GetFont then font, size, flags = obj:GetFont() end
    if not (font and size) then font, size, flags = fs:GetFont() end
    if not (font and size) then return fs end
    return SetFontBase(fs, group, font, size, flags)
end

local function ApplyFontGroup(group)
    local sc = ns.GetFontScale(group)
    for fs, base in pairs(fontRegistry[group]) do fs:SetFont(base[1], base[2] * sc, base[3]) end
    local cb = ns.fontScaleCallbacks[group]
    if cb then cb() end
end

ns.OnSettingChanged(function(key)
    if key == nil or key == "statsFontScale" then ApplyFontGroup("stats") end
    if key == nil or key == "uiFontScale" then ApplyFontGroup("ui") end
end)

----------------------------------------------------------------------
-- Bars, checkboxes
----------------------------------------------------------------------
local BAR_INSET = 5
local function MakeBar(parent, w, h, fillAtlas)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(w, h)
    Atlas(holder, "common-stat-bar-BG", "BACKGROUND"):SetAllPoints()
    local b = CreateFrame("StatusBar", nil, holder)
    b:SetPoint("TOPLEFT", BAR_INSET, -BAR_INSET)
    b:SetPoint("BOTTOMRIGHT", -BAR_INSET, BAR_INSET)
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetAtlas(fillAtlas)
    b:SetStatusBarTexture(fill)
    holder.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.text:SetPoint("LEFT", holder, "LEFT", 4, 0)
    holder.text:SetPoint("RIGHT", holder, "RIGHT", -4, 0)
    holder.text:SetJustifyH("CENTER")
    holder.text:SetWordWrap(false)
    ns.ScaleFont(holder.text, "ui")
    function holder:SetMinMaxValues(a, c) b:SetMinMaxValues(a, c) end
    function holder:SetValue(v) b:SetValue(v) end
    function holder:SetStatusBarColor(r, g, bl) b:SetStatusBarColor(r, g, bl) end
    return holder
end

local function MakeCheck(detail, labelText, y)
    local c = CreateFrame("CheckButton", nil, detail)
    c:SetSize(24, 24)
    c:SetPoint("BOTTOMLEFT", 16, y)
    c:SetNormalAtlas("checkbox-minimal")
    c:SetPushedAtlas("checkbox-minimal")
    c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    c:GetCheckedTexture():SetAtlas("checkmark-minimal")
    c:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    c:GetDisabledCheckedTexture():SetAtlas("checkmark-minimal-disabled")
    c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    c.label = ns.ScaleFont(c:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "ui")
    c.label:SetPoint("LEFT", c, "RIGHT", 6, 0)
    c.label:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    c.label:SetJustifyH("LEFT")
    c.label:SetText(labelText)
    c:SetScript("OnEnable", function(self) ns.SetScaledFontObject(self.label, "GameFontNormal", "ui") end)
    c:SetScript("OnDisable", function(self) ns.SetScaledFontObject(self.label, "GameFontDisable", "ui") end)
    return c
end
ns.MakeCheck = MakeCheck

----------------------------------------------------------------------
-- List tab: the list is on the left, the details on the right
----------------------------------------------------------------------
local LIST_ROW_H = 30

-- The pane a list or panel tab starts from (JournalHelpers.MakeTabPane), at the
-- book's sizes and the panel's text inset
local function NewTabPane(look)
    return HELPERS.MakeTabPane(ctx.frame, ctx.left, ctx.right, {
        pageWidth = LEFT_PAGE_W,
        level = PANE_LEVEL,
        pad = { x = SIDE_TEXT_PAD_X, top = SIDE_TEXT_PAD_TOP, bottom = SIDE_TEXT_PAD_BOTTOM },
        look = look,
    })
end

local function CreateListTab(opts)
    local tab = {}
    local selectedKey

    -- the left page holds the list, the right panel the details
    local pane = NewTabPane()
    local frame, lp, lbox, rp = pane.frame, pane.lp, pane.lbox, pane.rp
    tab.frame = frame

    -- the list's lines, along the top and bottom of its page
    local topLine = Atlas(lbox, "UI-Character-Info-ScrollLine-Long", "ARTWORK", 0, true)
    topLine:SetPoint("TOPLEFT", 8, -36)
    topLine:SetPoint("TOPRIGHT", -8, -36)
    local botLine = Atlas(lbox, "UI-Character-Info-ScrollLine-Long", "ARTWORK", 0, true)
    botLine:SetPoint("BOTTOMLEFT", 8, 12)
    botLine:SetPoint("BOTTOMRIGHT", -8, 12)

    -- scroll area
    local scroll = CreateFrame("ScrollFrame", nil, lp)
    scroll:SetPoint("TOPLEFT", 34, -40)
    scroll:SetPoint("BOTTOMRIGHT", -50, 30)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    -- the client's scroll bar; ScrollUtil steps the wheel by one list row
    -- (the pan extent, 30 pixels) and keeps the thumb proportional
    local sbar = CreateFrame("EventFrame", nil, lp, "MinimalScrollBar")
    sbar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 10, -14)
    sbar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 10, 14)
    scroll:EnableMouseWheel(true)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, sbar)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then content:SetWidth(w) end end)

    local function UpdateScroll()
        local max = math.max(0, content:GetHeight() - scroll:GetHeight())
        if scroll:GetVerticalScroll() > max then scroll:SetVerticalScroll(max) end
        sbar:SetShown(max > 0.5)
    end

    -- rows
    local rows = {}

    local function UpdateRowHighlight(r)
        local e = r.entry
        local sel = e and not e.isHeader and e.key == selectedKey
        local show = sel or r:IsMouseOver()
        -- big headers get no highlight; sub-headers are highlighted like entries
        local bigHeader = e and e.isHeader and not e.isSubHeader
        for _, t in ipairs(r.hl) do
            t:SetShown(show and not bigHeader)
            t:SetAlpha(sel and 0.35 or 0.2)
        end
    end

    local function GetRow(i)
        local r = rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, content)
        r:SetHeight(LIST_ROW_H - 2)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_H)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * LIST_ROW_H)

        r.headerBg = Atlas(r, "common-button-list-collapseExpand", "BACKGROUND")
        r.headerBg:SetAllPoints()
        r.state = Atlas(r, "common-button-list-minus", "ARTWORK", 0, true)
        r.state:SetPoint("RIGHT", -8, 0)

        r.subIcon = Atlas(r, "campaign_headericon_open", "ARTWORK", 0, true)

        local hl1 = Atlas(r, "charactercreate-customize-dropdown-linemouseover-side", "BACKGROUND", 1)
        hl1:SetPoint("TOPLEFT"); hl1:SetPoint("BOTTOMLEFT"); hl1:SetWidth(12)
        local hl3 = Atlas(r, "charactercreate-customize-dropdown-linemouseover-side", "BACKGROUND", 1)
        hl3:SetPoint("TOPRIGHT"); hl3:SetPoint("BOTTOMRIGHT"); hl3:SetWidth(12)
        hl3:SetTexCoord(1, 0, 0, 1)
        local hl2 = Atlas(r, "charactercreate-customize-dropdown-linemouseover-middle", "BACKGROUND", 1)
        hl2:SetPoint("TOPLEFT", hl1, "TOPRIGHT"); hl2:SetPoint("BOTTOMRIGHT", hl3, "BOTTOMLEFT")
        r.hl = { hl1, hl2, hl3 }

        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)

        r.bar = MakeBar(r, 150, 22, opts.barAtlas)

        r.valueIcon = r:CreateTexture(nil, "ARTWORK")
        r.valueIcon:SetSize(18, 18)
        r.valueIcon:SetPoint("RIGHT", -12, 0)
        r.value = ns.ScaleFont(r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), "ui")
        r.value:SetPoint("RIGHT", r.valueIcon, "LEFT", -6, 0)

        r:SetScript("OnClick", function(self)
            local e = self.entry
            if not e then return end
            if e.isHeader then
                opts.toggleHeader(e)
                if e.selectable then selectedKey = e.key; ctx.OpenForDetails() end
            else
                selectedKey = e.key
                ctx.OpenForDetails()
            end
            tab.Refresh()
        end)
        r:SetScript("OnEnter", UpdateRowHighlight)
        r:SetScript("OnLeave", UpdateRowHighlight)

        rows[i] = r
        return r
    end

    local function SetupRow(r, e)
        r.entry = e
        local bigHeader = e.isHeader and not e.isSubHeader
        r.headerBg:SetShown(bigHeader)
        r.state:SetShown(bigHeader)
        if bigHeader then
            r.state:SetAtlas(e.isCollapsed and "common-button-list-plus" or "common-button-list-minus", true)
        end
        r.subIcon:SetShown(e.isSubHeader)

        r.name:ClearAllPoints()
        if e.isSubHeader then
            r.subIcon:SetAtlas(e.isCollapsed and "campaign_headericon_closed" or "campaign_headericon_open", true)
            r.subIcon:ClearAllPoints()
            r.subIcon:SetPoint("LEFT", 12 + (opts.childIndent or 14), 0)
            r.name:SetPoint("LEFT", r.subIcon, "RIGHT", 4, 0)
        else
            local indent = e.isHeader and (e.isChild and 14 or 0) or ((opts.childIndent or 14) + (e.isChild and 14 or 0))
            r.name:SetPoint("LEFT", 12 + indent, 0)
        end
        local rightAnchor = (e.hasBar and r.bar) or (e.rightText and r.value) or nil
        if rightAnchor then
            r.name:SetPoint("RIGHT", rightAnchor, "LEFT", -8, 0)
        else
            r.name:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        end
        r.value:SetShown(e.rightText ~= nil)
        r.valueIcon:SetShown(e.rightIcon ~= nil)
        if e.rightText then r.value:SetText(e.rightText) end
        if e.rightIcon then r.valueIcon:SetTexture(e.rightIcon) end
        ns.SetScaledFontObject(r.name, bigHeader and "GameFontNormal" or "GameFontHighlight", "ui")
        r.name:SetText(e.name)

        r.bar:SetShown(e.hasBar)
        if e.hasBar then
            r.bar:SetMinMaxValues(0, e.barMax)
            r.bar:SetValue(e.barValue)
            if e.barColor then r.bar:SetStatusBarColor(unpack(e.barColor)) end
            r.bar.text:SetText(e.barText)
            r.bar:ClearAllPoints()
            if e.isHeader then
                r.bar:SetPoint("RIGHT", r.state, "LEFT", -8, 0)
            else
                r.bar:SetPoint("RIGHT", -12, 0)
            end
        end
        UpdateRowHighlight(r)
    end

    -- details
    local dEmpty = rp:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    dEmpty:SetPoint("CENTER")
    dEmpty:SetWidth(200)
    dEmpty:SetText(opts.emptyText)

    local detail = CreateFrame("Frame", nil, rp)
    detail:SetAllPoints()

    local dName = ns.ScaleFont(detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"), "ui")
    dName:SetPoint("TOP", 0, -22)
    local dSub = ns.ScaleFont(detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), "ui")
    dSub:SetPoint("TOP", dName, "BOTTOM", 0, -4)

    local lineY = opts.hasSubtitle and -64 or -50
    local dLine = Atlas(detail, "UI-Character-Info-ScrollLine-Long", "ARTWORK", 0, true)
    dLine:SetPoint("TOPLEFT", 12, lineY)
    dLine:SetPoint("TOPRIGHT", -12, lineY)

    local dBar = MakeBar(detail, 200, 24, opts.barAtlas)
    dBar:SetPoint("TOP", 0, lineY - 14)
    ns.SetScaledFontObject(dBar.text, "GameFontHighlight", "ui")

    local descY = opts.noDetailBar and (lineY - 12) or (lineY - 52)
    local dDesc = ns.ScaleFont(detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), "ui")
    dDesc:SetPoint("TOPLEFT", 16, descY)
    dDesc:SetPoint("TOPRIGHT", -16, descY)
    dDesc:SetJustifyH("LEFT")
    dDesc:SetJustifyV("TOP")
    dDesc:SetSpacing(2)

    local extraUpdate = opts.extraDetail and opts.extraDetail(detail, { desc = dDesc })

    local function UpdateDetail(e)
        if not e then
            detail:Hide()
            dEmpty:Show()
            return
        end
        dEmpty:Hide()
        detail:Show()
        dName:SetText(e.name)
        dSub:SetText(e.subtitle or "")
        local showBar = e.hasBar and not opts.noDetailBar
        dBar:SetShown(showBar)
        if showBar then
            dBar:SetMinMaxValues(0, e.barMax)
            dBar:SetValue(e.barValue)
            if e.barColor then dBar:SetStatusBarColor(unpack(e.barColor)) end
            dBar.text:SetText(e.detailBarText or e.barText)
        end
        dDesc:SetText(e.desc or "")
        if extraUpdate then extraUpdate(e) end
    end

    tab.Refresh = function()
        if not frame:IsShown() then return end
        local entries = opts.fetch() or {}
        local sel
        for i, e in ipairs(entries) do
            local r = GetRow(i)
            SetupRow(r, e)
            r:Show()
            if e.key ~= nil and e.key == selectedKey and e.selectable then sel = e end
        end
        for i = #entries + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(1, #entries * LIST_ROW_H))
        UpdateScroll()
        UpdateDetail(sel)
    end

    ns.OnSettingChanged(function(key)
        if key == nil or key == "uiFontScale" then tab.Refresh() end
    end)
    for _, ev in ipairs(opts.events or {}) do frame:RegisterEvent(ev) end
    frame:SetScript("OnEvent", function() tab.Refresh() end)
    frame:SetScript("OnShow", function() UpdateClassBackgrounds() tab.Refresh() end)
    ctx.wideTabs[#ctx.wideTabs + 1] = { frame = frame, rp = rp }
    PlaceWideTabs()
    return tab
end
ns.CreateListTab = CreateListTab

-- Panel tab: an empty area in the look of the others, for the tab's own
-- content (settings, the pet)
local function CreatePanelTab(opts)
    local tab = {}
    local pane = NewTabPane(opts and opts.look)
    local frame, lp, rp = pane.frame, pane.lp, pane.rp
    tab.frame = frame

    frame:HookScript("OnShow", UpdateClassBackgrounds)
    tab.lp, tab.rp = lp, rp
    ctx.wideTabs[#ctx.wideTabs + 1] = { frame = frame, rp = rp }
    PlaceWideTabs()
    return tab
end
ns.CreatePanelTab = CreatePanelTab

-- Borrowed tab: one of Blizzard's own windows, moved into our two halves
-- while its tab is open. layout(bf, lp, rp, move) may split its parts.
local borrowTabs = {}
local function CreateBorrowTab(globalName, layout)
    local f, left, right = ctx.frame, ctx.left, ctx.right
    local tab = {}
    local rightParts = {}   -- the parts of the borrowed window that sit in the right half
    local frame = CreateFrame("Frame", nil, f)
    frame:SetPoint("TOPLEFT", left, "TOPLEFT")
    frame:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
    frame:SetFrameLevel(f:GetFrameLevel() + PANE_LEVEL)
    frame:Hide()
    frame:SetClipsChildren(true)   -- folded: the right half, and anything in it, is not drawn
    tab.frame = frame


local pane = HELPERS.MakeTabPane(frame, left, right, {
    pageWidth = LEFT_PAGE_W,
    level = PANE_LEVEL,
    pad = { x = SIDE_TEXT_PAD_X, top = SIDE_TEXT_PAD_TOP, bottom = SIDE_TEXT_PAD_BOTTOM },
})
pane.frame:Show()
local lp, rp = pane.lp, pane.rp



    local saved
    local function SavePoints(fr)
        local pts = {}
        for i = 1, fr:GetNumPoints() do pts[i] = { fr:GetPoint(i) } end
        return pts
    end
    local function RestorePoints(fr, pts)
        fr:ClearAllPoints()
        for _, pt in ipairs(pts) do fr:SetPoint(unpack(pt)) end
    end

    function tab.Steal()
        local bf = _G[globalName]
        if not bf or saved then return end
        saved = { parent = bf:GetParent(), points = SavePoints(bf), shown = bf:IsShown(), parts = {} }
        tab.movePart = function(part, ...)
            if not part then return end
            if not saved.parts[part] then saved.parts[part] = SavePoints(part) end
            part:ClearAllPoints()
            part:SetPoint(...)
            if select(2, ...) == rp then rightParts[#rightParts + 1] = part end
        end
        bf:SetParent(frame)
        bf:ClearAllPoints()
        bf:SetAllPoints(frame)
        bf:SetFrameLevel(frame:GetFrameLevel() + 2)
        if layout then layout(bf, lp, rp, tab.movePart) end
        bf:Show()
    end

    function tab.GiveBack()
        local bf = _G[globalName]
        if not (bf and saved) then return end
        bf:SetParent(saved.parent)
        RestorePoints(bf, saved.points)
        for part, pts in pairs(saved.parts) do RestorePoints(part, pts) end
        bf:SetShown(saved.shown)
        saved = nil
    end

    frame:SetScript("OnShow", function()
        tab.Steal()
		PlaceWideTabs()
        local bf = _G[globalName]
        if bf then
            for _, m in ipairs({ "Update", "Refresh" }) do
                if bf[m] then pcall(bf[m], bf) break end
            end
        end
    end)
    frame:HookScript("OnShow", UpdateClassBackgrounds)
    borrowTabs[#borrowTabs + 1] = tab
    ctx.wideTabs[#ctx.wideTabs + 1] = { frame = frame, rp = rp, parts = rightParts }
    PlaceWideTabs()
    return tab
end
ns.CreateBorrowTab = CreateBorrowTab

----------------------------------------------------------------------
-- Side tabs and modes. Nine tabs stand on the window's right edge, as in
-- SnapChar. 1 = stat list, 2 = equipment manager. 3-9 are the Tabs/ files,
-- which add themselves with ns.RegisterTab.
----------------------------------------------------------------------
local MODE_ICON = { "portrait", 133122, 8197103, 2447783, 8197097, 8197078, 8197104,
    "Interface\\Icons\\INV_Misc_Gear_01", "petportrait" }
local SMALL_TABS = { [8] = true }       -- the settings tab, small, at the bottom
local SMALL_TAB_SCALE = 0.7
local DEFAULT_TAB_ORDER = { 2, 9, 3, 4, 5, 6, 7 }
local SORTABLE = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [9] = true }

local MODES = { [1] = "stats", [2] = "equip" }   -- tab index -> mode name
local LIST_TABS = {}                              -- mode name -> tab (with .frame)
local TAB_TITLES = {}                             -- mode name -> title
local TAB_TOOLTIPS = { [1] = "Character Stats", [2] = "Equipment Manager" }
local registered = { [1] = true, [2] = true }     -- index -> the tab exists
local unavailable = {}                            -- index -> hidden (no pet)
local modeTabs = {}
ns.modeTabs, ns.tabTitles = modeTabs, TAB_TOOLTIPS

-- The saved order of tabs 2-7 and 9; tab 1 stays on top
local function GetTabOrder()
    local o = ns.GetSetting("tabOrder")
    if type(o) == "table" then
        local seen, ok, list = {}, true, {}
        for _, v in ipairs(o) do
            if type(v) ~= "number" or not SORTABLE[v] or seen[v] then ok = false break end
            seen[v] = true
            list[#list + 1] = v
        end
        if ok then
            -- an older saved order without the pet tab: put it after the equipment manager
            if not seen[9] then
                local at = #list + 1
                for i, v in ipairs(list) do if v == 2 then at = i + 1 end end
                table.insert(list, at, 9)
                seen[9] = true
            end
            if #list == #DEFAULT_TAB_ORDER then return list end
        end
    end
    return { unpack(DEFAULT_TAB_ORDER) }
end
ns.GetTabOrder = GetTabOrder

-- Places the side tabs: tabs that are missing or unavailable take no room
local function ApplyTabIconLayout()
    local f = ctx.frame
    local posOf, p = { [1] = 1 }, 1
    for _, idx in ipairs(GetTabOrder()) do
        if registered[idx] and not unavailable[idx] then
            p = p + 1
            posOf[idx] = p
        end
    end
    for i, t in ipairs(modeTabs) do
        t:ClearAllPoints()
        local shown = (i <= 2 or (registered[i] and not unavailable[i])) and not SMALL_TABS[i]
        t:SetShown(shown)
        if shown then
            if SMALL_TABS[i] then
                t:SetScale(SMALL_TAB_SCALE)
                t:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", SIDE_TAB_X, 10 / SMALL_TAB_SCALE)
            else
                t:SetScale(1)
                t:SetPoint("TOPLEFT", f, "TOPRIGHT", SIDE_TAB_X, SIDE_TAB_TOP - ((posOf[i] or i) - 1) * SIDE_TAB_STEP)
            end
        end
    end
end

-- Shows one mode. The list tabs cover both halves of the window, so the
-- window is opened fully first; the manager needs the right half.
local function SetMode(mode)
    ctx.mode = mode
    local listTab = LIST_TABS[mode]
    ctx.listMode = listTab ~= nil
    ctx.left:Show()
    if mode == "equip" then
        ctx.SetExpanded(true, true)
    else
        ctx.SetExpanded(ctx.userExpanded, true)
    end
    if listTab then
        ctx.left:Hide()
        ctx.right:Hide()
    else
        ctx.listHost:SetShown(mode == "stats")
        ctx.manager:SetShown(mode == "equip")
    end
    for m, t in pairs(LIST_TABS) do t.frame:SetShown(m == mode) end
    for i, m in pairs(MODES) do
        if modeTabs[i] then modeTabs[i].selected:SetShown(m == mode) end
    end
    ctx.UpdateHeader()
end

ctx.SetMode = SetMode

-- Selecting a row of a list shows its details: a folded window opens
ctx.OpenForDetails = function()
    if not ctx.expanded then ctx.SetExpanded(true) end
end

local function WireTab(i)
    local t = modeTabs[i]
    if not t then return end
    t:SetScript("OnClick", function()
        UI.Widgets.PlayUISound(UI.Widgets.Sounds.PAGE)
        if MODES[i] then SetMode(MODES[i]) end
    end)
    t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TAB_TOOLTIPS[i] or "", 1, 1, 1)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", GameTooltip_Hide)
end

function ns.RegisterTab(index, mode, tab, title)
    MODES[index] = mode
    LIST_TABS[mode] = tab
    TAB_TITLES[mode] = title
    TAB_TOOLTIPS[index] = title
    registered[index] = true
    WireTab(index)
    ApplyTabIconLayout()
end

function ns.SetTabAvailable(i, available)
    if not modeTabs[i] then return end
    unavailable[i] = (not available) or nil
    ApplyTabIconLayout()
    -- the tab's content went away while it was open: back to the stats
    local mode = MODES[i]
    if not available and mode and LIST_TABS[mode] and ctx.mode == mode then SetMode("stats") end
end

ns.SetModeByName = function(mode) SetMode(mode) end


-- The settings button: on the expand arrow's row, 4 pixels to its left, as the
-- Spellbook's rank button is. It opens the settings view.
local function BuildSettingsButton()
    local b = CreateFrame("Button", nil, ctx.frame)
    b:SetFrameLevel(ctx.frame:GetFrameLevel() + PANE_LEVEL + 10)
    b:SetSize(23, 23)
    b:SetPoint("LEFT", ctx.frame, "TOPLEFT", 15, -56)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(MODE_ICON[8])

    b:SetScript("OnClick", function()
        UI.Widgets.PlayUISound(UI.Widgets.Sounds.PAGE)
        if MODES[8] then SetMode(MODES[8]) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(TAB_TOOLTIPS[8] or "Settings", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    ctx.settingsButton = b
end

local function BuildModes()
    local f = ctx.frame
    for i, iconTex in ipairs(MODE_ICON) do
        local t = AJ.UI.Components.CreateSideTab(f)
        t:SetFrameLevel(f:GetFrameLevel())

        if type(iconTex) == "number" or (type(iconTex) == "string" and iconTex:find("\\")) then
            t.icon:SetTexture(iconTex)
        elseif i == 2 then
            -- the manager's own icon, from Blizzard's sidebar
            local orig = PaperDollSidebarTab2 and PaperDollSidebarTab2.Icon
            if orig and orig:GetTexture() then
                t.icon:SetTexture(orig:GetTexture())
                local ulx, uly, _, lly, urx = orig:GetTexCoord()
                CropTabIcon(t.icon, ulx, urx, uly, lly)
            else
                t.icon:SetTexture(514608)
            end
        end

        t.selected:SetShown(i == 1)
        modeTabs[i] = t
    end
    WireTab(1)
    WireTab(2)
    ApplyTabIconLayout()
	BuildSettingsButton()
end

----------------------------------------------------------------------
-- Header, update loop, events
----------------------------------------------------------------------
local function BuildEvents()
    local frame = ctx.frame

    ctx.UpdateHeader = function()
	        -- the title plate over the right page
        local rightText
        if ctx.mode == "stats" then
            rightText = L("CHARACTER_STATS", "Character Stats")
        elseif ctx.mode == "equip" then
            rightText = L("EQUIPMENT_MANAGER", "Equipment Manager")
        else
            rightText = TAB_TITLES[ctx.mode]
        end
        if ctx.rightTitle then
            ctx.rightTitleText:SetText(rightText or "")
            ctx.rightTitle:SetWidth(math.max(STATS_TITLE_W, ctx.rightTitleText:GetStringWidth() + 40))
            ctx.rightTitle:SetShown(rightText ~= nil and ctx.expanded)
        end
        -- a tab of the tab files names the window; otherwise the character
        if LIST_TABS[ctx.mode] and TAB_TITLES[ctx.mode] then
            frame:SetTitle(TAB_TITLES[ctx.mode])
            return
        end
        local name, surname = UnitName("player")
        name = name or ""
        if surname and surname ~= "" and not ns.GetSetting("hideLastName") then
            name = name .. " " .. surname
        end
        -- the name in white, the class in its class colour, the level in yellow
        local className, classFile = UnitClass("player")
        local classColour = "|cffffffff"
        local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if c then classColour = ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
        local title = ("|cffffffff%s|r  %s%s|r"):format(name, classColour, className or "")
        local level = UnitLevel("player")
        if not (ns.GetSetting("hideLevel") or IsSecret(level)) then
            title = title .. ("  |cffffd100%s %d|r"):format(L("LEVEL", "Level"), level)
        end
        frame:SetTitle(title)
    end

    ctx.UpdateAll = function()
        ctx.UpdateHeader()
        UpdateClassBackgrounds()
        ctx.UpdateSlots()
        ctx.UpdateItemLevels()
        ctx.UpdateStats()
        ctx.LayoutStatRows()
        ctx.UpdateScrollRange()
        if modeTabs[1] then
            SetPortraitTexture(modeTabs[1].icon, "player")
            CropTabIcon(modeTabs[1].icon, 0, 1, 0, 1)
        end
    end

    local function LayOut()
        ctx.model:SetUnit("player")
        ctx.SetupDivider()
        ctx.SetupListBorder()
        ctx.UpdateRaceBg()
        SetMode(ctx.mode)
        ctx.UpdateAll()
    end

    frame:HookScript("OnShow", function()
        LayOut()
        -- on the first show the panes may not have their size yet; lay out
        -- again once the frame has been drawn
        C_Timer.After(0, function()
            if frame:IsShown() then LayOut() end
        end)
    end)

    ns.OnSettingChanged(function(key)
        if key == nil or key == "showAvgIlvl" or key == "showSlotIlvl" then ctx.UpdateItemLevels() end
        if key == nil or key == "hideLastName" or key == "hideLevel" then ctx.UpdateHeader() end
        if key == nil or key == "tabOrder" then ApplyTabIconLayout() end
    end)

    local EVENTS = {
        "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED",
        "UNIT_STATS", "UNIT_RESISTANCES", "UNIT_AURA", "UNIT_ATTACK_POWER", "UNIT_DAMAGE",
        "UNIT_ATTACK_SPEED", "UNIT_MAXHEALTH", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
        "UPDATE_SHAPESHIFT_FORM", "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE",
        "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED", "GET_ITEM_INFO_RECEIVED",
    }
    local listener = CreateFrame("Frame")
    for _, e in ipairs(EVENTS) do listener:RegisterEvent(e) end
    listener:SetScript("OnEvent", function(_, event, unit)
        if not frame:IsShown() then return end
        if event == "GET_ITEM_INFO_RECEIVED" then
            if ctx.IsItemLevelPending() then ctx.UpdateItemLevels() end
            return
        end
        -- unit events pass the unit first; others (PLAYER_LEVEL_UP) do not
        if event:find("^UNIT_") and unit ~= "player" then return end
        if event == "PLAYER_ENTERING_WORLD" or event == "UNIT_MODEL_CHANGED" then
            ctx.model:SetUnit("player")
            ctx.UpdateRaceBg()
        end
        ctx.UpdateAll()
    end)
end

-- The character's pieces, in SnapChar's order. Built at load: the Tabs/
-- files create their panels as they load, so the window must exist by then.
local function BuildAll()
    BuildFrame(ctx)
    BuildCharacterPane(ctx)
    ns.raceParts = ctx.raceParts
    BuildSlots(ctx)
    BuildStatsPane(ctx)
    BuildManager(ctx)
    BuildIconPicker(ctx)
    BuildFlyout(ctx)
    BuildModes()
    ctx.SetExpanded(ctx.expanded, true)
    BuildEvents()
    ns.mainFrame = ctx.frame
    ns.left, ns.right = ctx.left, ctx.right
    ns.OpenOriginalCharacter = function()
        if InCombatLockdown() then
            ns.CombatError()
            return
        end
        ctx.frame:Hide()
        ToggleCharacter("PaperDollFrame")
    end
end
BuildAll()

local loginWatch = CreateFrame("Frame")
loginWatch:RegisterEvent("PLAYER_LOGIN")
loginWatch:SetScript("OnEvent", SetTabIcon)

----------------------------------------------------------------------
-- Section. Built already at load; the first opening applies the saved state.
----------------------------------------------------------------------
function Section:Create()
    SetTabIcon()
    ctx.userExpanded = IsExpandedSaved()
    ctx.SetExpanded(ctx.userExpanded, true)
    ApplyTabIconLayout()
    ns.ApplyAllSettings()
    SetMode(ctx.mode)
    ctx.UpdateAll()
    return ctx.frame
end

-- UI:Open calls this each time the tab is opened
function Section:Refresh()
    ctx.UpdateAll()
end

function Section:HasNews() return false end
function Section:IsUnderWay() return false end
end -- shared block



