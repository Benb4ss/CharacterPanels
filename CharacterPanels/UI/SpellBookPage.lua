local _, AJ = ...

-- The spellbook page. Skill lines are side tabs on the window's right edge.
-- The selected line's learned spells fill the pages. The arrow on the left page folds
-- the book to one page. Tab, arrow and size values are from Character.lua.
-- The banner under the tabs switches to the "Not yet learned" page: every class spell
-- the character has not learned, in level order, whatever its specialization.

local W = AJ.UI.Widgets

local COLS, ICON, PAD, ROW_HEIGHT = 2, 26, 8, 50
local TOP, SIDE, BOTTOM = 52, 16, 16              -- spell area inside a page, below the title rule
local HIDDEN_RANK_ALPHA = 0.7                  -- the lower ranks hidden by the highest-rank filter
local FUTURE_TOP = 32                             -- the same for the "Not yet learned" page (tune here)
local BOOK_INSET = 6                              -- the book's inset from the frame (Layouts.lua)
local TAB_STEP, TAB_TOP, TAB_X = 52, -40, -1
local PANE_W = 413                                -- width the arrow is placed against (Character.lua)
local PANE_LEVEL = 20
local BANK = Enum.SpellBookSpellBank.Player
local PET_BANK = Enum.SpellBookSpellBank.Pet      -- the pet's spells (Blizzard_SpellBookCategory.lua)
local SPELL_TYPE = Enum.SpellBookItemType.Spell
local pickupSpell = (C_Spell and C_Spell.PickupSpell) or PickupSpell

-- Moves the folded page's grid sideways, in pixels (+ right, - left), so its left
-- column lines up with the book's. 0 = the page's own margin.
local SINGLE_LEFT_SHIFT = 0

-- The ranks button: a placeholder icon until Blizzard's is known
local RANK_ICON_ALL = "Interface\\AddOns\\CharacterPanels\\Assets\\IconAR.tga"   -- shown while every rank is listed
local RANK_ICON_MAX = "Interface\\AddOns\\CharacterPanels\\Assets\\IconMR.tga"   -- shown while only the highest rank is listed

-- The "Not yet learned" page
local NOT_LEARNED_NAME = "Not yet learned"
local NOT_LEARNED_ICON = 134400                   -- INV_Misc_QuestionMark
local RULE_COLOUR = { 0.19, 0.12, 0.06, 0.5 }     -- the rule under each level header

-- The banner (ported from WhatsTraining's Banner.lua)
local BANNER_W, BANNER_H = 60, 103
local BANNER_ICON_UP = 1                          -- the emblem and its mask, relative to the badge (positive = up)
local BADGE_Y = -56                               -- the badge (emblem ring) below the banner top; the press moves it 2px further down
local BANNER_TOP, CLIP_TOP = 27, 36               -- from Banner.lua: banner and clip offsets from the page top
local BANNER_X = -10                               -- clip offset from the page's right edge
local PAGER_X, PAGER_Y = -16, 10                  -- paging control: offset from the page's bottom right
local BANNER_ATLAS_BG = "communities-guildbanner-background"
local BANNER_ATLAS_BORDER = "communities-guildbanner-border"
local BANNER_MASK = "Interface\\AddOns\\CharacterPanels\\Assets\\banner-corner-mask"
local BANNER_RANK_MASK = "Interface\\AddOns\\CharacterPanels\\Assets\\banner-rank-mask"
local RANK_BANNER_OFFSET = -56
-- the rank banner changes colour with the ranks setting, as the banner for Not yet learned does
local RANK_BANNER_ALL_COLOUR = { 0.95, 0.90, 0.78 }  -- all ranks: parchment (placeholder)
local RANK_BANNER_MAX_COLOUR = { 0.55, 0.70, 0.85 }  -- highest rank only: blue-grey (placeholder)
local BANNER_ICON_FUTURE = "Interface\\Icons\\INV_Misc_Book_09"   -- shown on the "Not yet learned" page
local BANNER_ICON_NOT_LEARNED = "Interface\\Icons\\INV_Misc_Book_04"  -- shown on the learned-spells pages, on the banner that opens "Not yet learned"
local FACTION_COLORS = {                          -- CharacterSelect.xml faction colors
    Alliance = { 0.29, 0.33, 0.91 },
    Horde = { 0.90, 0.05, 0.07 },
}

-- Cell text, band, border and hover
local NAME_SIZE, RANK_SIZE = 12, 9
local NAME_FACE = GameFontNormal:GetFont()        -- the font file; only the size is changed
local NAME_COLOUR = { 0.08, 0.04, 0.02 }
local RANK_COLOUR = { 0.19, 0.12, 0.06 }
local BORDER_TEXTURE = "Interface\\Buttons\\UI-Quickslot2"   -- fallback ring
local BORDER_ATLAS = "spellbook-item-iconframe"              -- Blizzard's icon frame (name not verified)
local BORDER_SHADOW_ATLAS = "spellbook-item-iconframe-shadow" -- the soft shadow under it
local BORDER_X = -4   -- moves the border left (negative) or right (positive), in pixels
local BORDER_Y = -2   -- moves the border down (negative) or up (positive), in pixels

-- Passive spells: the round frame and a circular icon, as the shopping list's round icons.
local PASSIVE_BORDER_ATLAS = "talents-node-circle-gray"   -- the round frame (Widgets.lua's plain frame)
local PASSIVE_MASK_ATLAS = "talents-node-circle-mask"     -- clips the icon to a circle
local PASSIVE_BORDER_X, PASSIVE_BORDER_Y = 0, 0           -- nudges the round frame, in pixels

local ICON_BORDER = 40
local PASSIVE_BORDER_SIZE = 32   -- the round frame's size in pixels; lower it to shrink the circle
local ICON_LEFT = 10                              -- icon's inset from the band's left edge
local TEXT_GAP = 18                               -- from the icon's right edge to the name
local BAND_ATLAS = "spellbook-item-backplate"     -- Blizzard's row backplate
local BAND_COLOUR = { 1, 0.95, 0.80, 0.18 }       -- used if the atlas doesn't exist
local BAND_GAP = 4                                -- space between one row and the next
local BAND_RIGHT_GAP = 6                          -- space between one column and the next
local BAND_ALPHA = 0.3   -- transparency of the spell rows: 1 = solid, 0 = invisible
local HOVER_ATLAS = "spellbook-item-highlight"    -- tried first; not in the atlas list, so the band is used

local GRID_MARGIN = 24                            -- empty space on each side, so the grid sits in the middle

-- Saved per character. Stored as "highest only" so that a missing value means "show all".
local function ShowAllRanksSaved() return not (AJ.char and AJ.char.spellbookHighestOnly) end
local function SaveShowAllRanks(showAll) if AJ.char then AJ.char.spellbookHighestOnly = not showAll end end

local function IsFoldedSaved() return not (AJ.char and AJ.char.spellbookFolded == false) end
local function SaveFolded(folded) if AJ.char then AJ.char.spellbookFolded = folded end end

-- The number in a spell's rank text ("Rank 2" -> 2). Nil for spells with no rank.
local function rankOf(spellID)
    local sub = C_Spell.GetSpellSubtext(spellID)
    local digits = sub and sub:match("(%d+)")
    return digits and tonumber(digits) or nil
end

-- Keeps only the highest rank of each spell name. Spells with no rank are always kept.
local function highestRankOnly(spells)
    local best = {}
    for _, id in ipairs(spells) do
        local name, rank = C_Spell.GetSpellName(id), rankOf(id)
        if rank and (not best[name] or rank > best[name].rank) then
            best[name] = { id = id, rank = rank }
        end
    end
    local kept = {}
    for _, id in ipairs(spells) do
        local name, rank = C_Spell.GetSpellName(id), rankOf(id)
        if rank == nil or (best[name] and best[name].id == id) then
            tinsert(kept, id)
        end
    end
    return kept
end

-- Marks a learned spell known. Override groups list ranks in ascending order, so the lower
-- ranks before it are obsolete and count as known too. Higher ranks are not marked.
local function markKnown(line, id)
    line.known[id] = true
    local group = AJ.overrideOf and AJ.overrideOf[id]
    if not group then return end
    for i, member in ipairs(group) do
        if member == id then
            for j = 1, i - 1 do line.known[group[j]] = true end
            return
        end
    end
end

-- The learned spells by skill line (General, class, current spec). Passives included.
-- Each line keeps its full list (ids) and the set of spells it counts as known (known).
local function knownLines()
    local lines = {}
    for lineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        if info and not info.shouldHide and (info.offSpecID or 0) == 0 then
            local line = { name = info.name, iconID = info.iconID, ids = {}, known = {} }
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, BANK)
                if item and item.itemType == SPELL_TYPE and item.spellID then
                    tinsert(line.ids, item.spellID)
                    markKnown(line, item.spellID)
                end
            end
            if #line.ids > 0 then tinsert(lines, line) end
        end
    end
    return lines
end

-- The pet's learned spells from the Pet bank, as one skill line. Nil when there is no pet spellbook.
-- Slots run 1..count with slotIndexOffset 0 (Blizzard_SpellBookCategory.lua, SpellBookPetCategoryMixin).
-- The line's source table maps each spell to its slot and bank, for the drag.
local function knownPetLine()
    local count = C_SpellBook.HasPetSpells()
    if not (count and count > 0 and PetHasSpellbook()) then return nil end
    local line = { name = UnitName("pet") or PET, iconID = GetPetIcon(), ids = {}, known = {}, source = {} }
    for slot = 1, count do
        local item = C_SpellBook.GetSpellBookItemInfo(slot, PET_BANK)
        -- pet items are PetAction (type 3); a stance or command has an actionID and no spellID
        if item and (item.spellID or item.actionID) then
            local key = item.spellID or item.actionID
            tinsert(line.ids, key)
            line.source[key] = { slot = slot, bank = PET_BANK, name = item.name, subName = item.subName,
                iconID = item.iconID, hasSpell = item.spellID ~= nil }
            markKnown(line, key)
        end
    end
    if #line.ids == 0 then return nil end
    return line
end

-- The skill lines as the page shows them: learned spells only, with the rank filter applied.
local function displayLines(raw, showAllRanks)
    local out = {}
    for _, line in ipairs(raw) do
        local entries, hidden = {}, {}
        if showAllRanks then
            for _, id in ipairs(line.ids) do tinsert(entries, id) end
        else
            local shown, isShown = highestRankOnly(line.ids), {}
            for _, id in ipairs(shown) do
                tinsert(entries, id)
                isShown[id] = true
            end
            local rest = {}
            for _, id in ipairs(line.ids) do
                if not isShown[id] then tinsert(rest, id) end
            end
            if #rest > 0 then
                tinsert(entries, { separator = true })
                for _, id in ipairs(rest) do
                    tinsert(entries, id)
                    hidden[id] = true
                end
            end
        end
        if #entries > 0 then
            tinsert(out, { name = line.name, iconID = line.iconID, entries = entries, unlearned = {}, hidden = hidden, source = line.source })
        end
    end
    return out
end

-- The class's spells grouped by level, in level order. AJ.SpellsByLevel is filled by the
-- class file in the Journal's Classes folder for the character's class.
local function classSpellsByLevel()
    local byLevel, levels, groups = AJ.SpellsByLevel or {}, {}, {}
    for level in pairs(byLevel) do tinsert(levels, level) end
    table.sort(levels)
    for _, level in ipairs(levels) do
        local ids = {}
        for _, spell in ipairs(byLevel[level]) do tinsert(ids, spell.id) end
        tinsert(groups, { level = level, ids = ids })
    end
    return groups
end

-- The class's spell IDs in level order (used by /jspells).
local function classSpellIds()
    local ids = {}
    for _, group in ipairs(classSpellsByLevel()) do
        for _, id in ipairs(group.ids) do tinsert(ids, id) end
    end
    return ids
end

-- The "Not yet learned" page: every class spell the character does not know, whatever its
-- specialization, grouped by level with a header per level. Unknown spells are drawn
-- cannot be dragged until learned.
local function levelLabel(level, count)
    return format("Level %d  \226\128\162  %d %s", level, count, count == 1 and "spell" or "spells")
end

local function continuedLabel(level)
    return format("Level %d  \226\128\162  continued", level)
end

-- Quest-taught spells for this race (QuestSpells.lua): spell ID -> the lowest level of a
-- quest that teaches it to this race.
local function questSpellLevels()
    local levels = {}
    for id, entries in pairs(AJ.questSpells or {}) do
        for _, entry in ipairs(entries) do
            if entry.races and tContains(entry.races, AJ.playerRace) then
                if levels[id] == nil or entry.level < levels[id] then levels[id] = entry.level end
            end
        end
    end
    return levels
end

local function notLearnedLine(raw, showAllRanks)
    local known = {}
    for _, line in ipairs(raw) do
        for id in pairs(line.known) do known[id] = true end
    end

    -- the trainer's spells by level, then the quest spells at their quest level; a spell
    -- counts once, at its first level. Each candidate keeps its place within its level.
    local levelOf, seqOf, ids = {}, {}, {}
    local function add(id, level)
        if known[id] or levelOf[id] ~= nil then return end
        levelOf[id] = level
        seqOf[id] = #ids + 1
        tinsert(ids, id)
    end
    for _, group in ipairs(classSpellsByLevel()) do
        for _, id in ipairs(group.ids) do add(id, group.level) end
    end
    local questLevels = questSpellLevels()
    local questIds = {}
    for id in pairs(questLevels) do tinsert(questIds, id) end
    table.sort(questIds)
    for _, id in ipairs(questIds) do add(id, questLevels[id]) end

    table.sort(ids, function(x, y)
        if levelOf[x] ~= levelOf[y] then return levelOf[x] < levelOf[y] end
        return seqOf[x] < seqOf[y]
    end)
    -- the rank filter looks across all levels, so a higher rank on a later level still counts
    if not showAllRanks then ids = highestRankOnly(ids) end

    local counts = {}
    for _, id in ipairs(ids) do counts[levelOf[id]] = (counts[levelOf[id]] or 0) + 1 end

    local entries, unlearned, lastLevel = {}, {}, nil
    for _, id in ipairs(ids) do
        local level = levelOf[id]
        if level ~= lastLevel then
            tinsert(entries, { label = levelLabel(level, counts[level]), level = level })
            lastLevel = level
        end
        tinsert(entries, id)
        unlearned[id] = true
    end
    return { name = NOT_LEARNED_NAME, iconID = NOT_LEARNED_ICON, entries = entries, unlearned = unlearned }
end

-- The hover: Blizzard's hover art if it exists; otherwise the row's own backplate,
-- brightened, so the highlight has the band's shape.
local function setHoverArt(tex)
    if C_Texture.GetAtlasInfo(HOVER_ATLAS) then
        tex:SetAtlas(HOVER_ATLAS)
    elseif C_Texture.GetAtlasInfo(BAND_ATLAS) then
        tex:SetAtlas(BAND_ATLAS)
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0.35)
    else
        tex:SetColorTexture(1, 1, 1, 0.12)
    end
end

local function createSpellCell(parent)
    local cell = CreateFrame("Button", nil, parent)
    cell:RegisterForDrag("LeftButton")

    -- the row's band: the icon and its border sit inside it
    cell.band = cell:CreateTexture(nil, "BACKGROUND")
    cell.band:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -BAND_GAP / 2)
    cell.band:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -BAND_RIGHT_GAP, BAND_GAP / 2)
    if C_Texture.GetAtlasInfo(BAND_ATLAS) then
        cell.band:SetAtlas(BAND_ATLAS)
    else
        cell.band:SetColorTexture(unpack(BAND_COLOUR))
    end
    cell.band:SetAlpha(BAND_ALPHA)

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(ICON, ICON)
    cell.icon:SetPoint("LEFT", cell, "LEFT", ICON_LEFT, 0)
    cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Blizzard's icon frame, with its shadow under it. Falls back to the quickslot ring.
    cell.shadow = cell:CreateTexture(nil, "BACKGROUND", nil, 2)
    cell.shadow:SetSize(ICON_BORDER + 1, ICON_BORDER + 1)
    cell.shadow:SetPoint("CENTER", cell.icon, "CENTER", BORDER_X, BORDER_Y)
    if C_Texture.GetAtlasInfo(BORDER_SHADOW_ATLAS) then
        cell.shadow:SetAtlas(BORDER_SHADOW_ATLAS)
    else
        --cell.shadow:Hide()
    end

    cell.border = cell:CreateTexture(nil, "OVERLAY")
    cell.border:SetSize(ICON_BORDER, ICON_BORDER)
    cell.border:SetPoint("CENTER", cell.icon, "CENTER", BORDER_X, BORDER_Y)
    if C_Texture.GetAtlasInfo(BORDER_ATLAS) then
        cell.border:SetAtlas(BORDER_ATLAS)
    else
        cell.border:SetTexture(BORDER_TEXTURE)
    end
	-- The mask that makes a passive's icon round. setFrame adds it or removes it.
    cell.round = false
    cell.roundMask = cell:CreateMaskTexture()
    cell.roundMask:SetAtlas(PASSIVE_MASK_ATLAS)
    cell.roundMask:SetAllPoints(cell.icon)

    cell.name = cell:CreateFontString(nil, "OVERLAY")
    cell.name:SetFont(NAME_FACE, NAME_SIZE, "")
    cell.name:SetPoint("TOPLEFT", cell.icon, "TOPRIGHT", TEXT_GAP, -2)
    cell.name:SetJustifyH("LEFT")
    cell.name:SetWordWrap(false)
    cell.name:SetTextColor(unpack(NAME_COLOUR))

    cell.subText = cell:CreateFontString(nil, "OVERLAY")
    cell.subText:SetFont(NAME_FACE, RANK_SIZE, "")
    cell.subText:SetPoint("TOPLEFT", cell.name, "BOTTOMLEFT", 0, -1)
    cell.subText:SetJustifyH("LEFT")
    cell.subText:SetWordWrap(false)
    cell.subText:SetTextColor(unpack(RANK_COLOUR))

    -- hover: shown only while the mouse is over the row
    cell.hover = cell:CreateTexture(nil, "BACKGROUND", nil, 1)
    cell.hover:SetAllPoints(cell.band)
    setHoverArt(cell.hover)
    cell.hover:Hide()

    cell:SetScript("OnDragStart", function(self)
        -- pet spells pick up by slot and bank (Blizzard_SpellBookItem.lua); player spells by ID;
        -- unlearned spells cannot be picked up
        if self.spellBank then
            C_SpellBook.PickupSpellBookItem(self.slotIndex, self.spellBank)
        elseif self.spellID and not self.unlearned then
            pickupSpell(self.spellID)
        end
    end)
    cell:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.spellID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        elseif self.tipName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tipName, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    cell:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    cell:SetScript("OnHide", function(self) self.hover:Hide() end)
    return cell
end

local function getCell(area, index)
    area.cells = area.cells or {}
    area.cells[index] = area.cells[index] or createSpellCell(area)
    -- the highest index made so far; # is not reliable because empty slots leave holes
    area.cellCount = math.max(area.cellCount or 0, index)
    return area.cells[index]
end

local function hideCell(area, index)
    local cell = area.cells and area.cells[index]
    if cell then
        cell:Hide()
        cell.spellID = nil
        cell.unlearned = nil
        cell.slotIndex, cell.spellBank = nil, nil
    end
end

-- Every cell uses the normal colours. A spell not yet learned still cannot be dragged.
local function paintCell(cell, unlearned)
    cell.unlearned = unlearned
    cell.icon:SetDesaturated(false)
    cell.icon:SetAlpha(1)
    cell.border:SetAlpha(1)
    cell.band:SetAlpha(BAND_ALPHA)
    cell.name:SetTextColor(unpack(NAME_COLOUR))
    cell.subText:SetTextColor(unpack(RANK_COLOUR))
end

-- A passive gets the round frame and a circular icon; any other spell keeps the square frame.
-- Both set the frame's size, because cells are reused and a size from the other kind would stay.
local function setFrame(cell, passive)
    if cell.round == passive then return end
    cell.round = passive
    if passive then
        cell.icon:AddMaskTexture(cell.roundMask)
        cell.border:SetAtlas(PASSIVE_BORDER_ATLAS)
        cell.border:SetSize(PASSIVE_BORDER_SIZE, PASSIVE_BORDER_SIZE)
        cell.border:SetPoint("CENTER", cell.icon, "CENTER", PASSIVE_BORDER_X, PASSIVE_BORDER_Y)
        cell.shadow:Hide()
    else
        cell.icon:RemoveMaskTexture(cell.roundMask)
        if C_Texture.GetAtlasInfo(BORDER_ATLAS) then
            cell.border:SetAtlas(BORDER_ATLAS)
        else
            cell.border:SetTexture(BORDER_TEXTURE)
        end
        cell.border:SetSize(ICON_BORDER, ICON_BORDER)
        cell.border:SetPoint("CENTER", cell.icon, "CENTER", BORDER_X, BORDER_Y)
        cell.shadow:SetShown(C_Texture.GetAtlasInfo(BORDER_SHADOW_ATLAS) ~= nil)
    end
end

-- The name sits above the sub-line when there is one; otherwise it is centred on the icon.
local function layoutCellText(cell, hasSub)
    cell.name:ClearAllPoints()
    if hasSub then
        cell.name:SetPoint("TOPLEFT", cell.icon, "TOPRIGHT", TEXT_GAP, -2)
    else
        cell.name:SetPoint("LEFT", cell.icon, "RIGHT", TEXT_GAP, 0)
    end
end

-- The column width, fixed to the two-page book's. It does not depend on the
-- page the grid is on, so the columns stay in place when the book folds.
local function columnWidth()
    local bookPage = math.floor((AJ.UI.Layouts.wideBook.width - 2 * BOOK_INSET) / 2)
    return (bookPage - 2 * SIDE - 2 * GRID_MARGIN) / COLS
end

-- Splits entries into pages of `size` slots. A level (its header and spells) stays on one
-- page when it fits, so a page normally starts with a level header. A level longer than a
-- page continues on the next page under a "continued" header. A header takes a whole row
-- (COLS slots) and is never the last row of a page.
local function paginate(entries, size)
    local groups = {}
    for _, entry in ipairs(entries) do
        if type(entry) == "table" and entry.separator then
            tinsert(groups, { separator = true, spells = {} })
        elseif type(entry) == "table" then
            tinsert(groups, { header = entry, spells = {} })
        else
            if #groups == 0 then tinsert(groups, { spells = {} }) end
            tinsert(groups[#groups].spells, entry)
        end
    end

    local pages, page, used = {}, {}, 0
    local function startPage()
        if #page > 0 then tinsert(pages, page) end
        page, used = {}, 0
    end
    local function addHeader(header)
        tinsert(page, header)
        tinsert(page, false)
        used = used + COLS
    end

    for _, group in ipairs(groups) do
        if group.separator then
            -- the thin separator takes a row of its own; it is never the last row of a page
            while used % COLS ~= 0 do
                tinsert(page, false)
                used = used + 1
            end
            if used + 2 * COLS > size then startPage() end
            addHeader({ label = "" })
        end
        if group.header then
            -- start a row for the header: the slots are a whole number of rows, so this fits
            while used % COLS ~= 0 do
                tinsert(page, false)
                used = used + 1
            end
            local whole = COLS + math.ceil(#group.spells / COLS) * COLS
            if #page > 0 and whole <= size and whole > size - used then startPage() end
            if used + 2 * COLS > size then startPage() end
            addHeader(group.header)
        end
        for _, id in ipairs(group.spells) do
            if used >= size then
                startPage()
                if group.header then addHeader({ label = continuedLabel(group.header.level) }) end
            end
            tinsert(page, id)
            used = used + 1
        end
    end
    startPage()
    return pages
end

-- The header's label and rule, one per level, reused from a pool.
local function getHeader(area, index)
    area.headers = area.headers or {}
    if not area.headers[index] then
        local header = {}
        header.text = area:CreateFontString(nil, "OVERLAY")
        header.text:SetFont(NAME_FACE, NAME_SIZE + 1, "")
        header.text:SetTextColor(unpack(NAME_COLOUR))
        header.text:SetJustifyH("LEFT")
        header.text:SetWordWrap(false)
        header.rule = area:CreateTexture(nil, "BACKGROUND")
        header.rule:SetColorTexture(unpack(RULE_COLOUR))
        area.headers[index] = header
    end
    return area.headers[index]
end

-- Draws one page: slots holds spell IDs, false (empty slot) or header tables.
-- unlearned[id] marks the spells that cannot be dragged.
local function renderPage(area, slots, unlearned, hidden)
    hidden = hidden or {}
    local colWidth = columnWidth()
    local textWidth = colWidth - (ICON_LEFT + ICON + TEXT_GAP) - BAND_RIGHT_GAP
    local headers = 0
    for index, entry in ipairs(slots) do
        local col, row = (index - 1) % COLS, math.floor((index - 1) / COLS)
        if type(entry) == "table" then
            hideCell(area, index)
            headers = headers + 1
            local header = getHeader(area, headers)
            header.text:ClearAllPoints()
            header.text:SetPoint("BOTTOMLEFT", area, "TOPLEFT", GRID_MARGIN, -row * ROW_HEIGHT - ROW_HEIGHT + 8)
            header.text:SetText(entry.label)
            header.text:Show()
            header.rule:ClearAllPoints()
            header.rule:SetPoint("TOPLEFT", area, "TOPLEFT", GRID_MARGIN, -row * ROW_HEIGHT - ROW_HEIGHT + 4)
            header.rule:SetSize(colWidth * COLS - 2 * GRID_MARGIN, 1)
            header.rule:Show()
        elseif entry then
            local cell = getCell(area, index)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", area, "TOPLEFT", GRID_MARGIN + col * colWidth, -row * ROW_HEIGHT)
            cell:SetSize(colWidth, ROW_HEIGHT)
            cell.name:SetWidth(textWidth)
            cell.subText:SetWidth(textWidth)
            local at = area.source and area.source[entry]
            cell.spellID = (not at or at.hasSpell) and entry or nil
            cell.tipName = at and at.name
            cell.slotIndex, cell.spellBank = at and at.slot, at and at.bank
            cell.icon:SetTexture((at and at.iconID) or C_Spell.GetSpellTexture(entry))
            cell.name:SetText((at and at.name) or C_Spell.GetSpellName(entry) or "")
            local sub = (at and at.subName) or C_Spell.GetSpellSubtext(entry) or ""
            cell.subText:SetText(sub)
            layoutCellText(cell, sub ~= "")
            paintCell(cell, unlearned[entry] == true)
			setFrame(cell, C_Spell.IsSpellPassive(entry))
            cell:SetAlpha(hidden[entry] and HIDDEN_RANK_ALPHA or 1)
            cell:Show()
        else
            hideCell(area, index)
        end
    end
    for i = #slots + 1, area.cellCount or 0 do
        hideCell(area, i)
    end
    for i = headers + 1, #(area.headers or {}) do
        area.headers[i].text:Hide()
        area.headers[i].rule:Hide()
    end
end

-- The "Page X/Y" text: WhatsTraining's font and body colour
local function stylePager(pager)
    pager.PageText:SetFontObject("SystemFont_Med3")
    pager.PageText:SetTextColor(unpack(RANK_COLOUR))
end

local function createSideTab(frame)
    return AJ.UI.Components.CreateSideTab(frame)
end

-- The banner below the skill tabs. Clicking it switches between the learned-spells pages
-- (faction colour, swords) and the "Not yet learned" page (class colour, book).
local function createBanner(frame, onClick, mask, height)
    local clip = CreateFrame("Frame", nil, frame)
    clip:SetSize(BANNER_W, 130)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(frame:GetFrameLevel() + PANE_LEVEL + 10)
    local banner = CreateFrame("Button", nil, clip)
    banner.clip = clip
    banner:SetFrameLevel(clip:GetFrameLevel() + 1)
    banner:RegisterForClicks("LeftButtonUp")
    banner:SetSize(BANNER_W, height or BANNER_H)   -- height: optional, to shorten this banner only
    banner:SetHitRectInsets(0, 0, 34, 0)

    banner.art = banner:CreateTexture(nil, "BACKGROUND")
    banner.art:SetAllPoints()
    banner.art:SetAtlas(BANNER_ATLAS_BG)

    banner.border = banner:CreateTexture(nil, "BORDER")
    banner.border:SetAllPoints()
    banner.border:SetAtlas(BANNER_ATLAS_BORDER)
    banner.border:SetVertexColor(0.85, 0.65, 0.32)
    banner.borderGlow = banner:CreateTexture(nil, "OVERLAY")
    banner.borderGlow:SetAllPoints()
    banner.borderGlow:SetAtlas(BANNER_ATLAS_BORDER)
    banner.borderGlow:SetBlendMode("ADD")
    banner.borderGlow:SetVertexColor(1, 0.8, 0.35)
    banner.borderGlow:SetAlpha(0)

    banner.pageMask = banner:CreateMaskTexture()
    banner.pageMask:SetTexture(mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    banner.pageMask:SetAllPoints(banner)
    banner.art:AddMaskTexture(banner.pageMask)
    banner.border:AddMaskTexture(banner.pageMask)
    banner.borderGlow:AddMaskTexture(banner.pageMask)

    banner.badgeBackground = banner:CreateTexture(nil, "BORDER")
    banner.badgeBackground:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    banner.badgeBackground:SetPoint("CENTER", banner, "TOP", 0, BADGE_Y)
    banner.badgeBackground:SetSize(32, 32)
    banner.icon = banner:CreateTexture(nil, "ARTWORK")
    banner.icon:SetPoint("CENTER", banner.badgeBackground, "CENTER", 0, BANNER_ICON_UP)
    banner.iconMask = banner:CreateMaskTexture()
    banner.iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    banner.iconMask:SetPoint("CENTER", banner.badgeBackground, "CENTER", 0, BANNER_ICON_UP)
    banner.iconMask:SetSize(32 * 0.78, 32 * 0.78)
    banner.icon:AddMaskTexture(banner.iconMask)
    banner.iconBorder = banner:CreateTexture(nil, "OVERLAY")
    banner.iconBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    banner.iconBorder:SetTexCoord(0, 40 / 64, 0, 40 / 64)
    banner.iconBorder:SetSize(32, 32)
    banner.iconBorder:SetPoint("CENTER", banner.badgeBackground)
    banner.glow = banner:CreateTexture(nil, "OVERLAY", nil, 1)
    banner.glow:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    banner.glow:SetTexCoord(0, 40 / 64, 0, 40 / 64)
    banner.glow:SetAllPoints(banner.iconBorder)
    banner.glow:SetBlendMode("ADD")
    banner.glow:SetVertexColor(1, 0.8, 0.35)
    banner.glow:SetAlpha(0)

    local function updateGlow(self, elapsed)
        local alpha, target = self.glow:GetAlpha(), self.glowTarget
        local step = elapsed * 0.25 / 0.15
        alpha = alpha < target and math.min(target, alpha + step) or math.max(target, alpha - step)
        self.glow:SetAlpha(alpha)
        self.borderGlow:SetAlpha(alpha)
        if alpha == target then self:SetScript("OnUpdate", nil) end
    end
    local function releaseBadge(self)
        self.badgeBackground:SetPoint("CENTER", self, "TOP", 0, BADGE_Y)
    end
    banner:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.badgeBackground:SetPoint("CENTER", self, "TOP", 0, BADGE_Y - 2)
        end
    end)
    banner:SetScript("OnMouseUp", releaseBadge)
    banner:SetScript("OnClick", function(self)
        W.PlayUISound(W.Sounds.PAGE)
        onClick(self)
    end)
    banner:SetScript("OnEnter", function(self)
        self.glowTarget = 0.25
        self:SetScript("OnUpdate", updateGlow)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.tip or "", 1, 1, 1)
        GameTooltip:Show()
    end)
    banner:SetScript("OnLeave", function(self)
        self.glowTarget = 0
        self:SetScript("OnUpdate", updateGlow)
        releaseBadge(self)
        GameTooltip_Hide()
    end)
    banner:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self.glow:SetAlpha(0)
        self.borderGlow:SetAlpha(0)
        releaseBadge(self)
        GameTooltip_Hide()
    end)
    return banner
end

-- Paints the banner for the page it switches to. future = true: the "Not yet learned" page.
local function paintBanner(banner, future)
    banner.future = future
    banner.tip = future and "Learned spells" or NOT_LEARNED_NAME
    if future then
        local color = RAID_CLASS_COLORS[AJ.currentClass]
        if color then banner.art:SetVertexColor(color.r, color.g, color.b) end
        banner.icon:SetTexture(BANNER_ICON_FUTURE)
        banner.icon:SetTexCoord(0, 1, 0, 1)
        banner.icon:SetSize(32 * 0.7, 32 * 0.7)
    else
        local color = FACTION_COLORS[AJ.playerFaction]
        if color then banner.art:SetVertexColor(unpack(color)) end
        banner.icon:SetTexture(BANNER_ICON_NOT_LEARNED)
        banner.icon:SetTexCoord(0, 1, 0, 1)
        banner.icon:SetSize(32 * 0.62, 32 * 0.62)
    end
    if GameTooltip:IsOwned(banner) then banner:GetScript("OnEnter")(banner) end
end

-- frame: the book window
-- parts: { book, single, left, right, titles, singleWidth, bookWidth }
-- Returns the page object.
function AJ.CreateSpellBookPage(frame, parts)
    local book, singlePage, leftPage, rightPage = parts.book, parts.single, parts.left, parts.right
    local singleWidth, bookWidth = parts.singleWidth, parts.bookWidth
    local page = {
        expanded = true,
        twoPage = true,
        lineIndex = 1,
        first = 1,
        lines = {},
        tabs = {},
        titles = parts.titles or {},
        showAllRanks = ShowAllRanksSaved(),
        showingFuture = false,
        futureLine = notLearnedLine({}, true),
    }

    -- the grid's top offset for the current view
    local function gridTop()
        return page.showingFuture and FUTURE_TOP or TOP
    end

    -- the areas are children of the window, so the arrow and the tabs sit above the pages
    local leftArea = CreateFrame("Frame", nil, frame)
    leftArea:SetFrameLevel(frame:GetFrameLevel() + PANE_LEVEL)
    local rightArea = CreateFrame("Frame", nil, frame)
    rightArea:SetFrameLevel(frame:GetFrameLevel() + PANE_LEVEL)
    rightArea:SetPoint("TOPLEFT", rightPage, "TOPLEFT", SIDE, -gridTop())
    rightArea:SetPoint("BOTTOMRIGHT", rightPage, "BOTTOMRIGHT", -SIDE, BOTTOM)

    -- the pane the arrow is placed against, as the Character tab's left pane
    local pane = CreateFrame("Frame", nil, frame)
    pane:SetWidth(PANE_W)

    -- shift: sideways offset of the left area, used for the folded page
    local function placeOn(host, shift)
        leftArea:ClearAllPoints()
        leftArea:SetPoint("TOPLEFT", host, "TOPLEFT", SIDE + (shift or 0), -gridTop())
        leftArea:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -SIDE, BOTTOM)
        pane:ClearAllPoints()
        pane:SetPoint("TOPLEFT", host, "TOPLEFT")
        pane:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT")
    end

    local function pageSize()
        return math.max(0, math.floor(leftArea:GetHeight() / ROW_HEIGHT)) * COLS
    end

    -- the line on screen: a learned skill line, or the "Not yet learned" page
    function page:CurrentLine()
        if self.showingFuture then return self.futureLine end
        return self.lines[self.lineIndex]
    end

    function page:Refresh()
        local line = self:CurrentLine()
        for _, title in ipairs(self.titles) do title:SetText(line and line.name or "") end

        local size = pageSize()
        if size == 0 then return end -- not laid out yet; the size hook calls Refresh again
        local pages = paginate(line and line.entries or {}, size)
        local unlearned = line and line.unlearned or {}
        local hidden = line and line.hidden or {}
        leftArea.source = line and line.source or {}   -- pet spells: slot and bank for the pickup
        rightArea.source = leftArea.source
        local step = self.twoPage and 2 or 1
        local total = math.max(1, #pages)

        self.first = math.max(1, math.min(self.first, total))
        self.first = 1 + math.floor((self.first - 1) / step) * step

        renderPage(leftArea, pages[self.first] or {}, unlearned, hidden)
        leftArea:Show()
        if self.twoPage then
            renderPage(rightArea, pages[self.first + 1] or {}, unlearned, hidden)
            rightArea:Show()
        else
            rightArea:Hide()
        end

        for i, tab in ipairs(self.tabs) do
            tab.selected:SetShown(not self.showingFuture and i == self.lineIndex)
        end
        local spread = math.floor((self.first - 1) / step) + 1
        local spreads = math.ceil(total / step)
        self.syncing = true
        self.pager:SetMaxPages(math.max(1, spreads))
        self.pager:SetCurrentPage(spread)
        stylePager(self.pager) -- the template may reset its text when the page changes
        self.syncing = false
    end

    -- the paging control's page is a spread: two pages when expanded, one when folded
    function page:GoToSpread(spread)
        if self.syncing then return end
        self.first = (spread - 1) * (self.twoPage and 2 or 1) + 1
        self:Refresh()
    end

    -- moves the grid areas to the top offset of the current view
    function page:ApplyGridTop()
        rightArea:ClearAllPoints()
        rightArea:SetPoint("TOPLEFT", rightPage, "TOPLEFT", SIDE, -gridTop())
        rightArea:SetPoint("BOTTOMRIGHT", rightPage, "BOTTOMRIGHT", -SIDE, BOTTOM)
        placeOn(self.leftHost, self.leftShift)
    end

    -- the "Not yet learned" page always shows all ranks; the learned pages use the saved setting
    function page:ApplyRanksForView()
        local wanted = self.showingFuture and true or ShowAllRanksSaved()
        if self.showAllRanks == wanted then return end
        self.showAllRanks = wanted
        self:PaintRanks()
        self:Rebuild()
    end

    function page:SelectLine(index)
        self.showingFuture = false
        self.lineIndex, self.first = index, 1
        self:ApplyRanksForView()
        self:ApplyGridTop()
        paintBanner(self.banner, false)
        self:Refresh()
    end

    -- future = true: the "Not yet learned" page; false: the learned skill lines
    function page:SetView(future)
        self.showingFuture = future and true or false
        self.first = 1
        self:ApplyRanksForView()
        self:ApplyGridTop()
        paintBanner(self.banner, self.showingFuture)
        self:Refresh()
    end

    -- puts the paging control at the bottom right of host (the right page, or the folded page)
    function page:PlacePager(host)
        self.pager:ClearAllPoints()
        self.pager:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", PAGER_X, PAGER_Y)
    end

    -- hangs the banner from the top right of host (the right page, or the folded page), as in Banner.lua
    local function placeClip(banner, host, x)
        local clip = banner.clip
        clip:ClearAllPoints()
        clip:SetPoint("TOPRIGHT", host, "TOPRIGHT", x, CLIP_TOP)
        banner:ClearAllPoints()
        banner:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, BANNER_TOP - CLIP_TOP)
    end

    function page:PlaceBanner(host)
        placeClip(self.banner, host, BANNER_X)
        placeClip(self.rankBanner, host, BANNER_X + RANK_BANNER_OFFSET)
    end

    -- open: the two-page book. folded: the single page, with the book hidden.
    function page:SetExpanded(show, transient)
        self.expanded = show and true or false
        self.twoPage = self.expanded
        frame:SetWidth(show and bookWidth or singleWidth)
        book:SetShown(show)
        singlePage:SetShown(not show)
        rightArea:SetShown(show)
        self.leftHost = show and leftPage or singlePage
        self.leftShift = show and 0 or SINGLE_LEFT_SHIFT
        placeOn(self.leftHost, self.leftShift)
        self:PlaceBanner(show and rightPage or singlePage)
        self:PlacePager(show and rightPage or singlePage)

        AJ.UI.Components.SetExpandArrow(self.toggle, show)

        if not transient then SaveFolded(not show) end
        self:Refresh()
    end

    function page:Rebuild()
        local raw = knownLines()
        self.lines = displayLines(raw, self.showAllRanks)
        -- the Pet tab goes last, and only while a pet with a spellbook is out
        local pet = knownPetLine()
        for _, petLine in ipairs(pet and displayLines({ pet }, self.showAllRanks) or {}) do
            tinsert(self.lines, petLine)
        end
        self.futureLine = notLearnedLine(raw, self.showAllRanks)
        if self.lineIndex > #self.lines then self.lineIndex = 1 end
        for i, line in ipairs(self.lines) do
            local tab = self.tabs[i] or createSideTab(frame)
            self.tabs[i] = tab
            tab.index, tab.label = i, line.name
            tab.icon:SetTexture(line.iconID or 134400)
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", TAB_X, TAB_TOP - (i - 1) * TAB_STEP)
            tab:SetScript("OnClick", function(btn)
                W.PlayUISound(W.Sounds.PAGE)
                page:SelectLine(btn.index)
            end)
            tab:SetScript("OnEnter", function(btn)
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:SetText(btn.label, 1, 1, 1)
                GameTooltip:Show()
            end)
            tab:SetScript("OnLeave", GameTooltip_Hide)
            tab:Show()
        end
        for i = #self.lines + 1, #self.tabs do self.tabs[i]:Hide() end

        paintBanner(self.banner, self.showingFuture)
        self:Refresh()
    end

    -- the expand/minimize arrow, shared with the Character frame
    page.toggle = AJ.UI.Components.CreateExpandToggle(frame, pane, function()
        page:SetExpanded(not page.expanded)
    end)

    -- the rank banner, 20px left of the corner banner: shows all ranks or the highest rank only
    page.rankBanner = createBanner(frame, function()
        page.showAllRanks = not page.showAllRanks
        SaveShowAllRanks(page.showAllRanks)
        page:PaintRanks()
        page:Rebuild()
    end, BANNER_RANK_MASK, 98)  -- add a height as the 4th argument to change this banner only

    function page:PaintRanks()
        local banner = self.rankBanner
        banner.tip = "Toggle All Ranks/Max Rank"
        local colour = self.showAllRanks and RANK_BANNER_ALL_COLOUR or RANK_BANNER_MAX_COLOUR
        banner.art:SetVertexColor(unpack(colour))
        banner.icon:SetTexture(self.showAllRanks and RANK_ICON_ALL or RANK_ICON_MAX)
        banner.icon:SetTexCoord(0, 1, 0, 1)
        banner.icon:SetSize(32 * 0.7, 32 * 0.7)
        if GameTooltip:IsOwned(banner) then banner:GetScript("OnEnter")(banner) end
    end
    page:PaintRanks()

    -- the banner under the skill tabs: switches to the "Not yet learned" page and back
    page.banner = createBanner(frame, function()
        page:SetView(not page.showingFuture)
    end, BANNER_MASK)

    -- Blizzard's paging control (arrows and "Page X/Y"), as WhatsTraining uses it.
    -- Its parent gets OnPageChanged when the arrows are clicked.
    local pagerHost = CreateFrame("Frame", nil, frame)
    pagerHost.OnPageChanged = function() page:GoToSpread(page.pager:GetCurrentPage()) end
    page.pager = CreateFrame("Frame", nil, pagerHost, "PagingControlsHorizontalTemplate")
    page.pager:SetFrameLevel(frame:GetFrameLevel() + PANE_LEVEL + 10)
    stylePager(page.pager)
    page.pager.prevPageSound, page.pager.nextPageSound = SOUNDKIT.IG_ABILITY_PAGE_TURN, SOUNDKIT.IG_ABILITY_PAGE_TURN
    function page.pager:GetPageDelta() return 1 end

    -- rebuild when spells change or the book opens; re-lay out when the area gets its size
    local events = CreateFrame("Frame", nil, frame)
    for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_ENTERING_WORLD" }) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_PET", "player")   -- the Pet tab appears and goes with the pet
    events:SetScript("OnEvent", function()
        if frame:IsShown() then page:Rebuild() end
    end)
    frame:HookScript("OnShow", function()
        page:ApplyRanksForView()
        page:Rebuild()
    end)
    leftArea:SetScript("OnSizeChanged", function()
        if frame:IsShown() then page:Refresh() end
    end)

    page:SetExpanded(not IsFoldedSaved(), true)
    page:Rebuild()
    return page
end

-- /jspells: prints each step of the class and quest data, for troubleshooting.
SLASH_JOURNALSPELLS1 = "/jspells"
SlashCmdList.JOURNALSPELLS = function()
    print("Journal diagnostics:")
    print(format("  class=%s, race id=%s", tostring(AJ.currentClass), tostring(AJ.playerRace)))
    print(format("  AddQuestSpells loaded: %s", type(AJ.AddQuestSpells) == "function" and "yes" or "NO"))
    local questCount = 0
    for _ in pairs(AJ.questSpells or {}) do questCount = questCount + 1 end
    print(format("  quest spells stored for this class: %d", questCount))
    local forRace = questSpellLevels()
    local forRaceCount = 0
    for _ in pairs(forRace) do forRaceCount = forRaceCount + 1 end
    print(format("  quest spells for your race: %d", forRaceCount))
    local raw = knownLines()
    local line = notLearnedLine(raw, true)
    local onPage = 0
    for _, entry in ipairs(line.entries) do
        if type(entry) ~= "table" and forRace[entry] then onPage = onPage + 1 end
    end
    print(format("  quest spells on the Not yet learned page: %d", onPage))
    local shown = 0
    for id, level in pairs(forRace) do
        if shown < 3 then
            print(format("    %s (id %d) at level %d", tostring(C_Spell.GetSpellName(id)), id, level))
            shown = shown + 1
        end
    end
end