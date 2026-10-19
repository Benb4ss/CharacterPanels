-- SnapChar – Skills-Tab (4. Tab)
-- Berufe, Waffenfertigkeiten, Rüstungskunde, Sprachen mit Balken, rechts Details.
-- Alle Daten kommen vom Spiel (C_SkillInfo)[cite: 4].

local ADDON, ns = ...
local L = ns.L

----------------------------------------------------------------------
-- Skills (C_SkillInfo) & Weapon Skill Calculations
----------------------------------------------------------------------
local SI = C_SkillInfo
-- Kategorien, die das Original nicht anzeigt (Klassenfertigkeiten, "nicht anzeigen")
local HIDDEN_SKILL_CATEGORIES = { [7] = true, [12] = true }

local SKILL_RANKS_PER_SKILL_LEVEL = 5;
local RAID_BOSS_LEVEL = 63;
local WEAPON_SKILL_SAME_LEVEL_OFFSET = 0;

local function CreateWeaponSkillDisplay(isRanged)
    return { isRanged = isRanged };
end

-- Weapon skill lines and whether they are ranged, ported from SkillsFrame.lua[cite: 2]
local WEAPON_SKILL_LINES = {
    [43]    = CreateWeaponSkillDisplay(false),   -- Swords
    [44]    = CreateWeaponSkillDisplay(false),   -- Axes
    [45]    = CreateWeaponSkillDisplay(true),    -- Bows
    [46]    = CreateWeaponSkillDisplay(true),    -- Guns
    [54]    = CreateWeaponSkillDisplay(false),   -- Maces
    [55]    = CreateWeaponSkillDisplay(false),   -- Two-Handed Swords
    [136]   = CreateWeaponSkillDisplay(false),   -- Staves
    [160]   = CreateWeaponSkillDisplay(false),   -- Two-Handed Maces
    [172]   = CreateWeaponSkillDisplay(false),   -- Two-Handed Axes
    [173]   = CreateWeaponSkillDisplay(false),   -- Daggers
    [176]   = CreateWeaponSkillDisplay(true),    -- Thrown
    [226]   = CreateWeaponSkillDisplay(true),    -- Crossbows
    [228]   = CreateWeaponSkillDisplay(true),    -- Wands
    [229]   = CreateWeaponSkillDisplay(false),   -- Polearms
    [162]   = CreateWeaponSkillDisplay(false),   -- Fist Weapons / Unarmed
    [3014]  = CreateWeaponSkillDisplay(false),   -- Feral Combat
};

local function GetExpectedSkillForLevelOffset(levelOffset)
    return (UnitLevel("player") + levelOffset) * SKILL_RANKS_PER_SKILL_LEVEL;
end

local function GetWeaponSkillDiff(levelOffset, weaponSkill)
    local targetDefenseSkill = GetExpectedSkillForLevelOffset(levelOffset);
    return targetDefenseSkill - weaponSkill;
end

local function GetHitDodgeParryChance(levelOffset, weaponSkill)
    return GetWeaponSkillDiff(levelOffset, weaponSkill) * -0.04;
end

local function GetCriticalHitChance(levelOffset, weaponSkill)
    return GetWeaponSkillDiff(levelOffset, weaponSkill) * -0.04;
end

local function FormatSignedPercent(value)
    if value == -0.0 then
        value = 0.0;
    end
    local text = string.format("%.2f%%", value);
    if value > 0 then
        text = "+"..text;
    end
    return text;
end

local function FormatPercent(value)
    return string.format("%.0f%%", value);
end

local skillsTab = ns.CreateListTab({
    barAtlas = "common-stat-bar-blue",
    hasSubtitle = false,
    childIndent = 0,
    events = { "SKILL_LINES_CHANGED" },
    emptyText = L("SKILL_DETAIL_SELECT_PROMPT", "Select a skill to view its details."),
    
    -- Weapon skill details: a title plate over each section, as the stats panel
    -- does, and each figure on its own line under it.
    -- Formulas and glancing blow calls: SkillsFrame.lua. Wording: a guess from the screenshot.
    extraDetail = function(detail, widgets)
        local PLATE_H, PLATE_MIN_W = 40, 200   -- bigger title plates
        local PLATE_GAP, LINE_GAP = 12, 6
        local BOSS_PLATE_NUDGE_X = -3          -- "Against Raid Bosses" moved 3px left
        local WHITE = "|cffffffff"             -- the key words
        local YELLOW = "|cffffd100"            -- the rest

        local box = CreateFrame("Frame", nil, detail)
        box:SetPoint("TOPLEFT", widgets.desc, "BOTTOMLEFT", 0, -10)
        box:SetPoint("BOTTOMRIGHT", 0, 0)   -- gives the box a height, as the old weaponDetails frame had
        box:Hide()

        local function NewPlate()
            local plate = CreateFrame("Frame", nil, box)
            plate.isPlate = true
            plate:SetHeight(PLATE_H)
            local bg = plate:CreateTexture(nil, "BACKGROUND")
            bg:SetAtlas("UI-Character-Info-Title")
            bg:SetAllPoints()
            plate.text = ns.ScaleFont(plate:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), "stats")
            plate.text:SetPoint("CENTER")
            return plate
        end

        local function NewLine()
            local fs = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            ns.SetScaledFontObject(fs, "GameFontHighlightSmall", "ui")
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(true)
            return fs
        end

        local function SetPlate(plate, text)
            plate.text:SetText(text)
            plate:SetWidth(math.max(PLATE_MIN_W, plate.text:GetStringWidth() + 60))
        end

        -- Each item sits under the one before it; the first sits at the top.
        local function Place(item, prev, gap)
            item:ClearAllPoints()
            local y = prev and -gap or 0
            if item.isPlate then
                item:SetPoint("TOP", prev or box, prev and "BOTTOM" or "TOP", item.nudgeX or 0, y)
            else
                item:SetPoint("TOPLEFT", prev or box, prev and "BOTTOMLEFT" or "TOPLEFT", 0, y)
                item:SetPoint("RIGHT", box, "RIGHT", 0, 0)
            end
        end

        local function HitText(value)
            return YELLOW .. "Chance to " .. WHITE .. "Hit" .. YELLOW .. ", and to avoid being "
                .. WHITE .. "Dodged" .. YELLOW .. " or " .. WHITE .. "Parried" .. YELLOW .. ": " .. value .. "|r"
        end

        local function CritText(value)
            return YELLOW .. "Chance to " .. WHITE .. "Critically Hit" .. YELLOW .. ": " .. value .. "|r"
        end

        local plateSame, sameHit, sameCrit = NewPlate(), NewLine(), NewLine()
        local plateBoss, bossHit, bossCrit, glancing = NewPlate(), NewLine(), NewLine(), NewLine()
        plateBoss.nudgeX = BOSS_PLATE_NUDGE_X

        return function(e)
            if not e.isWeaponSkill then
                box:Hide()
                widgets.desc:SetHeight(120)
                return
            end
            box:Show()
            widgets.desc:SetHeight(40)

            local weaponSkill = e.rank + e.modifier
            local isRanged = e.weaponSkillData and e.weaponSkillData.isRanged
            local bossLevelOffset = RAID_BOSS_LEVEL - UnitLevel("player")

            SetPlate(plateSame, "Equal-Level Enemy")
            sameHit:SetText(HitText(FormatSignedPercent(GetHitDodgeParryChance(WEAPON_SKILL_SAME_LEVEL_OFFSET, weaponSkill))))
            sameCrit:SetText(CritText(FormatSignedPercent(GetCriticalHitChance(WEAPON_SKILL_SAME_LEVEL_OFFSET, weaponSkill))))

            SetPlate(plateBoss, "Against Raid Bosses")
            bossHit:SetText(HitText(FormatSignedPercent(GetHitDodgeParryChance(bossLevelOffset, weaponSkill))))
            bossCrit:SetText(CritText(FormatSignedPercent(GetCriticalHitChance(bossLevelOffset, weaponSkill))))

            Place(plateSame, nil)
            Place(sameHit, plateSame, LINE_GAP)
            Place(sameCrit, sameHit, LINE_GAP)
            Place(plateBoss, sameCrit, PLATE_GAP)
            Place(bossHit, plateBoss, LINE_GAP)
            Place(bossCrit, bossHit, LINE_GAP)

            -- Glancing blows apply to melee only (SkillsFrame.lua: ranged gets no glancing row)
            if not isRanged and GetGlancingBlowChance and GetGlancingBlowPenalty then
                local bossDefenseSkill = RAID_BOSS_LEVEL * SKILL_RANKS_PER_SKILL_LEVEL
                local chance = FormatPercent(GetGlancingBlowChance(weaponSkill, bossDefenseSkill) * 100)
                local penalty = FormatPercent(GetGlancingBlowPenalty(weaponSkill, bossDefenseSkill) * 100)
                glancing:SetText(YELLOW .. WHITE .. "Glancing Blows" .. YELLOW .. " occur " .. chance
                    .. " of the time and deal " .. penalty .. " less damage|r")
                glancing:Show()
                Place(glancing, bossCrit, LINE_GAP)
            else
                glancing:Hide()
            end
        end
    end,
      
    fetch = function()
        local raw, seenNames = {}, {}
        if not (SI and SI.GetNumSkillLines) then return raw end
        for i = 1, SI.GetNumSkillLines() or 0 do
            local d = SI.GetSkillLineInfo(i)
            if d and d.name and d.name ~= "" then
                local hidden = d.isHeader and HIDDEN_SKILL_CATEGORIES[d.skillID]
                    or (not d.isHeader and HIDDEN_SKILL_CATEGORIES[d.skillLineCategoryID])
                    or (not d.isHeader and (d.parentSkillLineID or 0) ~= 0)
                if d.isHeader then seenNames = {} end
                if not d.isHeader and seenNames[d.name] then hidden = true end
                if not hidden and not d.isHeader then seenNames[d.name] = true end
                if not hidden then
                    local hasBar = not d.isHeader and (d.maxRank or 0) > 0
                    local rank, maxRank = d.rank or 0, d.maxRank or 0
                    local modifier = d.modifier or 0
                    local text
                    if modifier ~= 0 then
                        text = string.format("%d (%+d) / %d", rank, modifier, maxRank)
                    else
                        text = rank .. " / " .. maxRank
                    end
                    
                    local weaponData = WEAPON_SKILL_LINES[d.skillID]

                    -- Package skill detail metrics for use in the list and detail panes[cite: 2, 4]
                    raw[#raw + 1] = {
                        index = d.skillIndex or i, key = d.skillID, data = d,
                        name = d.name, desc = d.description,
                        rank = rank, maxRank = maxRank, modifier = modifier,
                        isWeaponSkill = weaponData ~= nil,
                        weaponSkillData = weaponData,
                        isHeader = d.isHeader, isCollapsed = d.isCollapsed,
                        selectable = not d.isHeader,
                        hasBar = hasBar, barValue = rank, barMax = math.max(maxRank, 1),
                        barText = text,
                    }
                end
            end
        end
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