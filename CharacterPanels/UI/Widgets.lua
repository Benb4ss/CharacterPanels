local _, AJ = ...

-- Layer 1: small building blocks. Nothing here knows about windows.
local W = AJ.UI.Widgets

W.Sounds = {
    SPELLBOOK_OPEN = (SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN) or 829,
    SPELLBOOK_CLOSE = (SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE) or 830,
    CHARACTER_OPEN = (SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN) or 839,
    CHARACTER_CLOSE = (SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE) or 840,
    PAGE = (SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN) or 836,
    SELECT = (SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_SELECT) or 877,
}

-- Windows come in two looks (see Components.lua). Classic Era builds its
-- bottom tabs from CharacterFrameTabButtonTemplate; mainline-based clients
-- (WoW Forever) do not load that template, and its absence is how the modern
-- client is recognised. Decided once, here, because the pieces below draw
-- with art only one of the two clients has.
local CLASSIC_TAB_TEMPLATE = "CharacterFrameTabButtonTemplate"
local MAINLINE_TAB_TEMPLATE = "PanelTabButtonTemplate"

local function ResolveTabTemplate()
    if not C_XMLUtil or not C_XMLUtil.GetTemplateInfo then
        return CLASSIC_TAB_TEMPLATE
    end
    local ok, info = pcall(C_XMLUtil.GetTemplateInfo, CLASSIC_TAB_TEMPLATE)
    if ok and info then
        return CLASSIC_TAB_TEMPLATE
    end
    return MAINLINE_TAB_TEMPLATE
end

W.TAB_TEMPLATE = ResolveTabTemplate()
W.MODERN = W.TAB_TEMPLATE == MAINLINE_TAB_TEMPLATE

local function PlayUISound(soundKitID)
    if PlaySound and soundKitID then
        PlaySound(soundKitID)
    end
end

local function AddRule(parent, left, right, y)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    rule:SetColorTexture(0.28, 0.16, 0.07, 0.45)
    rule:SetPoint("TOPLEFT", left, y)
    rule:SetPoint("TOPRIGHT", right, y)
    rule:SetHeight(1)
    return rule
end

-- The ink of a page. On the classic look it is the quest log's: that
-- client writes its quest log in the fonts' own black, titles and text
-- alike, and the journal's pages are that same parchment.
local CLASSIC_INK = { 0, 0, 0 }

local function ApplyQuestTextColor(fontString, useTitleColor)
    if not fontString then return end

    if not W.MODERN then
        fontString:SetTextColor(CLASSIC_INK[1], CLASSIC_INK[2], CLASSIC_INK[3])
        return
    end

    if GetMaterialTextColors then
        local bodyColor, titleColor = GetMaterialTextColors("Parchment")
        local color = useTitleColor and titleColor or bodyColor
        if color then
            fontString:SetTextColor(color[1], color[2], color[3])
            return
        end
    end

    if useTitleColor then
        fontString:SetTextColor(0.20, 0.08, 0.02)
    else
        fontString:SetTextColor(0.10, 0.06, 0.02)
    end
end

local function CreatePageArrowButton(parent, direction)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(32, 32)

    local base = direction == "prev" and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
    button:SetNormalTexture(base .. "Up")
    button:SetPushedTexture(base .. "Down")
    button:SetDisabledTexture(base .. "Disabled")
    button:SetHighlightTexture(base .. "Highlight")

    local normal = button:GetNormalTexture()
    if normal then normal:SetTexCoord(0, 1, 0, 1) end
    local pushed = button:GetPushedTexture()
    if pushed then pushed:SetTexCoord(0, 1, 0, 1) end
    local disabled = button:GetDisabledTexture()
    if disabled then disabled:SetTexCoord(0, 1, 0, 1) end
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:SetBlendMode("ADD")
        highlight:SetTexCoord(0, 1, 0, 1)
    end

    return button
end

local function CreateSlot(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    bg:SetAllPoints()
    button.bg = bg

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon = icon

    local dark = button:CreateTexture(nil, "OVERLAY")
    dark:SetColorTexture(0, 0, 0, 0.52)
    dark:SetPoint("TOPLEFT", 3, -3)
    dark:SetPoint("BOTTOMRIGHT", -3, 3)
    button.dark = dark

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints()

    local selected = button:CreateTexture(nil, "OVERLAY")
    selected:SetTexture("Interface\\Buttons\\CheckButtonGlow")
    selected:SetBlendMode("ADD")
    selected:SetPoint("TOPLEFT", -6, 6)
    selected:SetPoint("BOTTOMRIGHT", 6, -6)
    selected:Hide()
    button.selected = selected

    return button
end

-- Wraps text in the parchment's title color, for a title inside a block of
-- body text.
local function TitleText(text)
    local r, g, b = 0.20, 0.08, 0.02
    if not W.MODERN then
        r, g, b = CLASSIC_INK[1], CLASSIC_INK[2], CLASSIC_INK[3]
    elseif GetMaterialTextColors then
        local _, titleColor = GetMaterialTextColors("Parchment")
        if titleColor then r, g, b = titleColor[1], titleColor[2], titleColor[3] end
    end
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

-- A frame that scrolls when what it holds outgrows it, with the client's slim
-- scroll bar, shown only while there is something to scroll. Pages of the
-- journal are turned, not scrolled; this is for the few places chosen to
-- scroll instead (a catch's notes, see CreateScrollNotes; the list of past
-- trips, see CreateScrollList). Anchor the
-- returned frame leaving SCROLL_BAR_ROOM free on its right for the bar.
-- Returns the frame and the child that holds the content.
local SCROLL_BAR_ROOM = 24
local SLIM_SCROLL_BAR = "MinimalScrollBar"
local SLIM_SCROLL_BAR_X = 10        -- the bar, from the frame's right edge: inside SCROLL_BAR_ROOM
local SLIM_SCROLL_BAR_INSET = 4     -- and short of its top and bottom
local scrollFrameCount = 0

local function HasTemplate(name)
    if not C_XMLUtil or not C_XMLUtil.GetTemplateInfo then return false end
    local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
    return ok and info ~= nil
end

local function CreateScrollFrame(parent)
    local scroll
    if not W.MODERN and HasTemplate(SLIM_SCROLL_BAR) and ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        -- Classic Era's ScrollFrameTemplate brings that client's wide bar on
        -- a black band, made for its grey windows. On parchment the journal
        -- uses the slim bar the modern look has, which Era also ships (its
        -- AddOns list scrolls with it), put together the way the template
        -- does it.
        scroll = CreateFrame("ScrollFrame", nil, parent)
        local bar = CreateFrame("EventFrame", nil, scroll, SLIM_SCROLL_BAR)
        bar:SetHideIfUnscrollable(true)
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", SLIM_SCROLL_BAR_X, -SLIM_SCROLL_BAR_INSET)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", SLIM_SCROLL_BAR_X, SLIM_SCROLL_BAR_INSET)
        scroll.ScrollBar = bar
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
        bar:Update()
    elseif HasTemplate("ScrollFrameTemplate") then
        scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
        scroll.ScrollBar:SetHideIfUnscrollable(true)
    else
        -- Older clients only have the classic bar, which finds its parts by
        -- the frame's name.
        scrollFrameCount = scrollFrameCount + 1
        scroll = CreateFrame("ScrollFrame", "JournalScrollFrame" .. scrollFrameCount, parent, "UIPanelScrollFrameTemplate")
        scroll.scrollBarHideable = true
        ScrollFrame_OnScrollRangeChanged(scroll, 0, 0)
    end

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    return scroll, child
end

-- Wraps text in a softer ink, for the remark under a title. The classic
-- look's small lettering is thinner and reads pale in that ink, so there it
-- is darker.
local MUTED_INK = W.MODERN and "6b5236" or "4a3620"

local function MutedText(text)
    return "|cff" .. MUTED_INK .. text .. "|r"
end

-- The little drawings that go with a scribble in the margin.
local MARGIN_MARKS = {
    risky = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    boot = "Interface\\Icons\\INV_Boots_05",
    home = "Interface\\Icons\\INV_Misc_Rune_01",
    new = "Interface\\Icons\\Spell_Nature_Rejuvenation",
    hook = "Interface\\AddOns\\Journal\\Assets\\Icon.tga",
    slow = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    old = "Interface\\Icons\\INV_Misc_Spyglass_02",
    first = "Interface\\Icons\\INV_Misc_Book_09",
    -- Beside a catch: it has a tale on its page; it was hard won.
    tale = "Interface\\Icons\\INV_Scroll_03",
    hardWon = "Interface\\AddOns\\Journal\\Assets\\Icon.tga",
}

-- A scribble in the margin: a small drawing and a few words, as one piece of
-- text. `margin` is { mark, text }.
local function MarginText(margin)
    return string.format("|T%s:14|t %s", MARGIN_MARKS[margin.mark], margin.text)
end

------------------------------------------------------------------------------
-- Rows and pages: what the journal's lists are made of
------------------------------------------------------------------------------

-- The tooltip of something the journal has noted: its name, what it means
-- (`remark`), and what the journal saw (`evidence`, a list of lines). The
-- last two are optional. Evidence is history; the page never shows it.
local function ShowNoteTooltip(owner, title, remark, evidence)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 0.82, 0)
    if remark then GameTooltip:AddLine(remark, 1, 1, 1, true) end
    for index, line in ipairs(evidence or {}) do
        if index == 1 and remark then GameTooltip:AddLine(" ") end
        GameTooltip:AddLine(line, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

-- An icon in one of the Spellbook's two frames, built the way the Spellbook
-- builds them: the round grey frame of its passives for an ordinary entry,
-- the bronze frame of its spells for one the player singled out. Every list
-- and grid uses this, so an entry looks the same wherever it is shown.
local ICON_FRAMES = {
    plain = {
        border = "talents-node-circle-gray",
        mask = "talents-node-circle-mask",
        hover = "spellbook-item-iconframe-passive-hover",
        borderOffsets = { 0, 0, 0, 0 },      -- left, top, right, bottom
    },
    singled = {
        border = "spellbook-item-iconframe",
        mask = "spellbook-item-spellicon-mask",
        hover = "spellbook-item-iconframe-hover",
        borderOffsets = { -11, 1, 1, -7 },
    },
}

-- The Spellbook draws these at 40; our windows are enlarged, so they are
-- scaled back down to come out the size the Spellbook's are on screen.
local FRAMED_ICON_SCALE = 1 / 1.2

-- Classic Era has none of that art. There an icon sits in the slot its own
-- Spellbook draws behind a spell, and one the player singled out wears the
-- gold border of a thing in use. The same piece, with the same methods.
-- The art is drawn for an icon of 36; ours is smaller, so that the slots of
-- two rows keep some paper between them, and the art is scaled with it.
local CLASSIC_ICON_SIZE = 28
local CLASSIC_ICON_ART = CLASSIC_ICON_SIZE / 36
local CLASSIC_ICON_SLOT = "Interface\\Spellbook\\UI-Spellbook-SpellBackground"
local CLASSIC_ICON_SLOT_SIZE = 62 * CLASSIC_ICON_ART       -- the slot's art, around the icon
local CLASSIC_ICON_SLOT_OFFSET = 3 * CLASSIC_ICON_ART
local CLASSIC_ICON_SINGLED = "Interface\\Buttons\\UI-ActionButton-Border"
local CLASSIC_ICON_SINGLED_SIZE = 62 * CLASSIC_ICON_ART    -- that border's art, around the same icon
local CLASSIC_ICON_HOVER = "Interface\\Buttons\\ButtonHilight-Square"

local function CreateClassicFramedIcon(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(CLASSIC_ICON_SIZE, CLASSIC_ICON_SIZE)

    local slot = holder:CreateTexture(nil, "BACKGROUND")
    slot:SetTexture(CLASSIC_ICON_SLOT)
    slot:SetSize(CLASSIC_ICON_SLOT_SIZE, CLASSIC_ICON_SLOT_SIZE)
    slot:SetPoint("TOPLEFT", -CLASSIC_ICON_SLOT_OFFSET, CLASSIC_ICON_SLOT_OFFSET)

    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    holder.icon = icon

    local border = holder:CreateTexture(nil, "OVERLAY", nil, 1)
    border:SetTexture(CLASSIC_ICON_SINGLED)
    border:SetBlendMode("ADD")
    border:SetVertexColor(1.0, 0.82, 0.0)
    border:SetSize(CLASSIC_ICON_SINGLED_SIZE, CLASSIC_ICON_SINGLED_SIZE)
    border:SetPoint("CENTER")
    border:Hide()

    local glow = holder:CreateTexture(nil, "OVERLAY", nil, 2)
    glow:SetTexture(CLASSIC_ICON_HOVER)
    glow:SetBlendMode("ADD")
    glow:SetAllPoints()
    glow:Hide()

    function holder:SetLit(lit)
        glow:SetShown(lit == true)
    end

    function holder:Set(texture, singled)
        self.singled = singled == true
        icon:SetTexture(texture)
        border:SetShown(self.singled)
    end

    return holder
end

local function CreateFramedIcon(parent)
    if not W.MODERN then return CreateClassicFramedIcon(parent) end

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(40, 40)
    holder:SetScale(FRAMED_ICON_SCALE)

    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("CENTER")
    holder.icon = icon

    local mask = holder:CreateMaskTexture()
    mask:SetPoint("TOPLEFT", icon, "TOPLEFT")
    mask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT")
    icon:AddMaskTexture(mask)

    local border = holder:CreateTexture(nil, "OVERLAY", nil, 1)
    local glow = holder:CreateTexture(nil, "OVERLAY", nil, 2)
    glow:SetAllPoints()
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.25)
    glow:Hide()

    -- Lights the frame up, as the Spellbook does under the cursor.
    function holder:SetLit(lit)
        glow:SetShown(lit == true)
    end

    -- `singled` picks the bronze frame.
    function holder:Set(texture, singled)
        local art = singled and ICON_FRAMES.singled or ICON_FRAMES.plain
        self.singled = singled == true
        icon:SetTexture(texture)
        mask:SetAtlas(art.mask)
        border:SetAtlas(art.border)
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", art.borderOffsets[1], art.borderOffsets[2])
        border:SetPoint("BOTTOMRIGHT", art.borderOffsets[3], art.borderOffsets[4])
        glow:SetAtlas(art.hover)
    end

    return holder
end

-- A small map beside a title, that opens the world map on a water: the one
-- action a page has on the place it speaks of. `tip` is the sentence of its
-- tooltip; `getWater` returns the water to open when it is clicked. Show it
-- with :SetWater(water), which keeps it hidden for a water the client has no
-- map of, and on a look that has no such button.
local MAP_BUTTON_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local MAP_BUTTON_SIZE = 24      -- fits a page's title line, above its rule
-- Only on the modern look. No window of Classic Era's leads to the map, and
-- a journal that did would be a convenience the rest of that game does not
-- offer; there the water's name is all the page says. Set to true to bring
-- the button to every client.
local MAP_BUTTON_EVERYWHERE = false

local function CreateMapButton(parent, tip, getWater)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(MAP_BUTTON_SIZE, MAP_BUTTON_SIZE)

    local icon = CreateFramedIcon(button)
    icon:SetScale(MAP_BUTTON_SIZE / 40)    -- a framed icon is drawn at 40
    icon:SetPoint("CENTER")
    icon:Set(MAP_BUTTON_ICON)

    button:SetScript("OnEnter", function(self)
        icon:SetLit(true)
        ShowNoteTooltip(self, "Show on the map", tip)
    end)
    button:SetScript("OnLeave", function()
        icon:SetLit(false)
        HideTooltip()
    end)
    button:SetScript("OnClick", function()
        PlayUISound(W.Sounds.SELECT)
        AJ:OpenMap(getWater())
    end)

    -- Whether to show it for a water: sections ask this instead of the
    -- client, so the button stays away where the look has no place for it.
    function button:SetWater(water)
        self:SetShown((W.MODERN or MAP_BUTTON_EVERYWHERE) and water ~= nil and AJ:HasMap(water))
    end

    return button
end

-- One entry of a list or of a grid: an icon in a frame, a title and a line under it, with
-- room at the right for a mark. Fill it with :SetEntry, a table of:
--   icon        texture; without one the text starts at the left edge
--   title, line
--   singled     use the bronze frame (a catch the player chose to remember)
--   selected    show it as the chosen entry
--   link        item link for the tooltip, or
--   tip         a sentence for the tooltip (under the title)
--   margin      { mark, text, tip, evidence }: the mark at the right
--   marginStyle "icon" (a small drawing) or "words"; either way its
--               tooltip says what the mark means and what is behind it
--   marks       in place of `margin`, a list of such marks shown side by
--               side as small drawings (a catch with a tale that was also
--               hard won carries two)
--   onClick     called with the entry
local MARK_SIZE = 20    -- a mark's drawing
local MARK_INSET = 8    -- from the row's right edge
local MARK_GAP = 4      -- between two marks

local function CreateEntryRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(42)

    local chosen = row:CreateTexture(nil, "BACKGROUND")
    chosen:SetColorTexture(0.35, 0.20, 0.05, 0.14)
    chosen:SetAllPoints()
    chosen:Hide()
    row.chosen = chosen

    -- Under the cursor a row with an icon lights its frame, as in the
    -- Spellbook; one without an icon gets a faint band instead.
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetColorTexture(1.0, 0.82, 0.0, 0.08)
    hover:SetAllPoints()
    row.hover = hover

    local framed = CreateFramedIcon(row)
    framed:SetPoint("LEFT", 6, 0)
    row.framed = framed

    local title = row:CreateFontString(nil, "ARTWORK", "QuestFont")
    title:SetJustifyH("LEFT")
    ApplyQuestTextColor(title, true)
    row.title = title

    local line = row:CreateFontString(nil, "ARTWORK", "QuestFontNormalSmall")
    line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    line:SetJustifyH("LEFT")
    line:SetTextColor(0.42, 0.32, 0.21)
    row.line = line

    -- The mark at the right: a small drawing, or the scribble written out.
    -- Either explains itself under the cursor.
    local function ShowMark(self)
        local margin = row.entry.margin
        ShowNoteTooltip(self, margin.text, margin.tip, margin.evidence)
    end

    local markIcon = CreateFrame("Frame", nil, row)
    markIcon:SetSize(20, 20)
    markIcon:SetPoint("RIGHT", -8, 0)
    markIcon:EnableMouse(true)
    markIcon.texture = markIcon:CreateTexture(nil, "ARTWORK")
    markIcon.texture:SetAllPoints()
    markIcon:SetScript("OnEnter", ShowMark)
    markIcon:SetScript("OnLeave", HideTooltip)
    row.markIcon = markIcon

    local markWords = row:CreateFontString(nil, "ARTWORK", "QuestFontNormalSmall")
    markWords:SetPoint("RIGHT", -8, 0)
    markWords:SetJustifyH("RIGHT")
    markWords:SetTextColor(0.45, 0.22, 0.10)
    row.markWords = markWords

    -- Text takes no cursor of its own, so a frame over the words does.
    local markWordsArea = CreateFrame("Frame", nil, row)
    markWordsArea:SetAllPoints(markWords)
    markWordsArea:EnableMouse(true)
    markWordsArea:SetScript("OnEnter", ShowMark)
    markWordsArea:SetScript("OnLeave", HideTooltip)
    row.markWordsArea = markWordsArea

    -- Marks side by side, from the right edge inwards; made as they are
    -- first needed.
    row.markIcons = {}
    local function MarkIcon(index)
        local icon = row.markIcons[index]
        if not icon then
            icon = CreateFrame("Frame", nil, row)
            icon:SetSize(MARK_SIZE, MARK_SIZE)
            icon:SetPoint("RIGHT", -MARK_INSET - (index - 1) * (MARK_SIZE + MARK_GAP), 0)
            icon:EnableMouse(true)
            icon.texture = icon:CreateTexture(nil, "ARTWORK")
            icon.texture:SetAllPoints()
            icon:SetScript("OnEnter", function(self)
                local mark = self.mark
                ShowNoteTooltip(self, mark.text, mark.tip, mark.evidence)
            end)
            icon:SetScript("OnLeave", HideTooltip)
            row.markIcons[index] = icon
        end
        return icon
    end

    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry then return end
        self.framed:SetLit(true)
        if entry.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(entry.link)
            GameTooltip:Show()
        elseif entry.tip then
            ShowNoteTooltip(self, entry.title, entry.tip)
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.framed:SetLit(false)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        if self.entry and self.entry.onClick then self.entry.onClick(self.entry) end
    end)

    function row:SetEntry(entry)
        self.entry = entry

        self.framed:SetShown(entry.icon ~= nil)
        if entry.icon then self.framed:Set(entry.icon, entry.singled) end

        self.hover:SetAlpha(entry.icon and 0 or 1)

        -- The title takes the width left over, and wraps if it must. With a
        -- line under it, it sits at the top; alone, it is centred on the
        -- icon however many lines it takes.
        local marks = entry.marks or {}
        local left, right = entry.icon and 46 or 10, entry.margin and -34 or -4
        if #marks > 0 then right = -(MARK_INSET + #marks * (MARK_SIZE + MARK_GAP) + 2) end
        self.title:ClearAllPoints()
        -- The classic pages are narrower and their lettering larger: there a
        -- title with a line under it keeps to one line, so it never runs
        -- into that line or the row below.
        if not W.MODERN then self.title:SetWordWrap(entry.line == nil) end
        if entry.line then
            self.title:SetPoint("TOPLEFT", left, -6)
            self.title:SetPoint("TOPRIGHT", right, -6)
        else
            self.title:SetPoint("LEFT", left, 0)
            self.title:SetPoint("RIGHT", right, 0)
        end
        self.title:SetText(entry.title)
        self.line:SetText(entry.line or "")
        self.chosen:SetShown(entry.selected == true)

        local margin, asIcon = entry.margin, entry.marginStyle ~= "words"
        self.markIcon:SetShown(margin ~= nil and asIcon)
        self.markWords:SetShown(margin ~= nil and not asIcon)
        self.markWordsArea:SetShown(margin ~= nil and not asIcon)
        if margin then
            self.markIcon.texture:SetTexture(MARGIN_MARKS[margin.mark])
            self.markWords:SetText(margin.text)
        end

        for index, mark in ipairs(marks) do
            local icon = MarkIcon(index)
            icon.mark = mark
            icon.texture:SetTexture(MARGIN_MARKS[mark.mark])
            icon:Show()
        end
        for index = #marks + 1, #self.markIcons do self.markIcons[index]:Hide() end
    end

    return row
end

-- One entry of a page of notes: a title and a few lines under it. Fill it
-- with :SetEntry({ title, text, evidence, heading }).
--   title     optional: without one the entry is a paragraph, carrying on
--             under the title of the entry before it
--   heading   the title opens a part of the page instead of naming an
--             entry: it is written in the page's title lettering, smaller
--             than the page's own title
--   evidence  optional lines for a tooltip: what the journal saw. A note
--             that has them lights up under the cursor
-- The text is as wide as the row. Where the height must be known at once
-- (see CreateScrollNotes), give the width with :SetTextWidth first.
local NOTE_TITLE_GAP = 3
local NOTE_HEADING_SIZE = 14    -- the page's title is 18
local NOTE_HEADING_HEIGHT = 19  -- a heading and the space under it

local function CreateNoteRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(60)

    local hover = row:CreateTexture(nil, "BACKGROUND")
    hover:SetColorTexture(1.0, 0.82, 0.0, 0.08)
    hover:SetPoint("TOPLEFT", -4, 3)
    hover:SetPoint("BOTTOMRIGHT", 4, -3)
    hover:Hide()

    local title = row:CreateFontString(nil, "ARTWORK", "QuestFont")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetJustifyH("LEFT")
    ApplyQuestTextColor(title, true)
    row.title = title

    local heading = row:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
    heading:SetPoint("TOPLEFT", 0, 0)
    heading:SetJustifyH("LEFT")
    local headingFont, _, headingFlags = heading:GetFont()
    heading:SetFont(headingFont, NOTE_HEADING_SIZE, headingFlags)
    ApplyQuestTextColor(heading, true)
    row.heading = heading

    local text = row:CreateFontString(nil, "ARTWORK", "QuestFont")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetSpacing(2)
    ApplyQuestTextColor(text, false)
    row.text = text

    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not (entry and entry.evidence) then return end
        hover:Show()
        ShowNoteTooltip(self, entry.title, nil, entry.evidence)
    end)
    row:SetScript("OnLeave", function()
        hover:Hide()
        HideTooltip()
    end)

    function row:SetTextWidth(width)
        self.textWidth = width
    end

    function row:SetEntry(entry)
        self.entry = entry
        local isHeading = entry.heading == true and entry.title ~= nil
        self.heading:SetText(isHeading and entry.title or "")
        self.title:SetText(not isHeading and entry.title or "")

        self.text:ClearAllPoints()
        if isHeading then
            self.text:SetPoint("TOPLEFT", 0, -NOTE_HEADING_HEIGHT)
        elseif entry.title then
            self.text:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -NOTE_TITLE_GAP)
        else
            self.text:SetPoint("TOPLEFT", 0, 0)
        end
        if self.textWidth then
            self.text:SetWidth(self.textWidth)
        else
            self.text:SetPoint("RIGHT", self, "RIGHT", 0, 0)
        end
        self.text:SetText(entry.text)

        hover:Hide()
        self:EnableMouse(entry.evidence ~= nil)
    end

    -- The height the entry takes, once it has been given a text width.
    function row:MeasureHeight()
        local height = self.text:GetStringHeight()
        if self.heading:GetText() ~= "" then
            height = height + NOTE_HEADING_HEIGHT
        elseif self.entry.title then
            height = height + self.title:GetStringHeight() + NOTE_TITLE_GAP
        end
        return height
    end

    return row
end

-- Notes of different lengths in one column that scrolls, for the one page
-- where an entry can gather more than a page holds (a catch's notes). Fill
-- it with :SetItems(list of { title, text, evidence }).
local SCROLL_NOTE_GAP = 14      -- between one note and the next

local function CreateScrollNotes(parent)
    local scroll, child = CreateScrollFrame(parent)
    scroll.rows = {}
    scroll.items = {}

    local function Layout()
        local width = scroll:GetWidth()
        local offset = 0
        for index, entry in ipairs(scroll.items) do
            local row = scroll.rows[index]
            if not row then
                row = CreateNoteRow(child)
                scroll.rows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -offset)
            row:SetWidth(width)
            row:SetTextWidth(width)
            row:SetEntry(entry)
            local height = row:MeasureHeight()
            row:SetHeight(height)
            row:Show()
            offset = offset + height + SCROLL_NOTE_GAP
        end
        for index = #scroll.items + 1, #scroll.rows do scroll.rows[index]:Hide() end
        child:SetHeight(math.max(1, offset - SCROLL_NOTE_GAP))
    end

    -- The notes are as wide as the frame, whatever size that ends up being.
    scroll:HookScript("OnSizeChanged", function(_, width)
        child:SetWidth(width)
        Layout()
    end)

    -- `keepPlace` leaves the reader where they were.
    function scroll:SetItems(items, keepPlace)
        self.items = items
        Layout()
        if not keepPlace then self:SetVerticalScroll(0) end
    end

    return scroll
end

-- Rows of one height in one column that scrolls, for a list chosen to be
-- scrolled instead of paged. It is filled the way CreatePagedList is:
--   options.createRow   function(parent) returning a frame with :SetEntry
--   options.rowHeight
-- and :SetItems(list of entries).
local function CreateScrollList(parent, options)
    local scroll, child = CreateScrollFrame(parent)
    scroll.rows = {}
    scroll.items = {}

    local rowHeight = options.rowHeight

    local function Layout()
        for index, entry in ipairs(scroll.items) do
            local row = scroll.rows[index]
            if not row then
                row = options.createRow(child)
                row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
                row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
                scroll.rows[index] = row
            end
            row:SetEntry(entry)
            row:Show()
        end
        for index = #scroll.items + 1, #scroll.rows do scroll.rows[index]:Hide() end
        child:SetHeight(math.max(1, #scroll.items * rowHeight))
    end

    -- The rows are as wide as the frame, whatever size that ends up being.
    scroll:HookScript("OnSizeChanged", function(_, width)
        child:SetWidth(width)
    end)

    -- Shows these entries. The reader is left where they were; pass `index`
    -- to bring that entry into view.
    function scroll:SetItems(items, index)
        self.items = items
        Layout()

        local furthest = math.max(0, #items * rowHeight - self:GetHeight())
        local offset = math.min(self:GetVerticalScroll() or 0, furthest)
        if index then
            local top = (index - 1) * rowHeight
            if top < offset or top + rowHeight > offset + self:GetHeight() then
                offset = math.min(top, furthest)
            end
        end
        self:SetVerticalScroll(offset)
    end

    return scroll
end

-- The page arrows and "Page N" at the foot of a paged frame, laid out as the
-- Spellbook lays out its own: the arrows at the two ends of the page's foot,
-- the page's number between them. `list` needs a `page` number and a :Render
-- method; the controls change the first and call the second. Returns an
-- update function: (page, pages).
local PAGE_CONTROLS_HEIGHT = 28

local function AddPageControls(list)
    local controls = CreateFrame("Frame", nil, list)
    controls:SetHeight(PAGE_CONTROLS_HEIGHT)
    controls:SetPoint("BOTTOMLEFT", 0, 0)
    controls:SetPoint("BOTTOMRIGHT", 0, 0)

    local label = controls:CreateFontString(nil, "ARTWORK", "QuestFont")
    label:SetPoint("CENTER")
    ApplyQuestTextColor(label, false)

    local function Turn(by)
        PlayUISound(W.Sounds.PAGE)
        list.page = list.page + by
        list:Render()
    end

    local previous = CreatePageArrowButton(controls, "prev")
    previous:SetSize(26, 26)
    previous:SetPoint("LEFT")
    previous:SetScript("OnClick", function() Turn(-1) end)

    local following = CreatePageArrowButton(controls, "next")
    following:SetSize(26, 26)
    following:SetPoint("RIGHT")
    following:SetScript("OnClick", function() Turn(1) end)

    list.previous, list.following = previous, following

    return function(page, pages)
        controls:SetShown(pages > 1)
        label:SetText("Page " .. page)
        previous:SetEnabled(page > 1)
        following:SetEnabled(page < pages)
    end
end

-- A list shown a page at a time, the way a book is read: no scrolling. The
-- page arrows appear only when there is more than one page.
--   options.createRow     function(parent) returning a frame with :SetEntry
--   options.rows          rows on a page
--   options.rowHeight
--   options.headingHeight what a heading takes (see below; default rowHeight)
--   options.columns       entries across (default 1: each row spans the list)
--   options.columnWidth   for more than one column
-- Fill it with :SetItems(list of entries).
--
-- A list of one column may be in parts: an entry { heading = "..." } names
-- the part that begins under it (see CreateSectionRow). A heading is lower
-- than an entry, so a page holds as much as fits its height, not a set
-- number of rows. A heading is never left alone at the foot of a page, and a
-- part that runs on to another page is named again at the head of it: every
-- page of a list in parts begins with the name of what it shows.
local function CreatePagedList(parent, options)
    local columns = options.columns or 1
    local rowHeight = options.rowHeight
    local headingHeight = options.headingHeight or rowHeight
    local pageHeight = options.rows * rowHeight
    local perPage = options.rows * columns

    local list = CreateFrame("Frame", nil, parent)
    list.rows = {}
    list.items = {}
    list.pages = { {} }
    list.page = 1

    local UpdateControls = AddPageControls(list)

    local function HeightOf(entry)
        return entry.heading and headingHeight or rowHeight
    end

    -- The entries of each page, in order. A page is a list of { entry, index },
    -- `index` being the entry's place in the items (nil for a heading said
    -- again at the head of a page).
    local function Paginate(items)
        local pages, page, used = {}, {}, 0
        local heading

        local function Turn()
            table.insert(pages, page)
            page, used = {}, 0
        end
        local function Put(entry, index)
            table.insert(page, { entry = entry, index = index })
            used = used + HeightOf(entry)
        end

        for index, entry in ipairs(items) do
            if columns > 1 then
                if #page >= perPage then Turn() end
                Put(entry, index)
            elseif entry.heading then
                heading = entry
                -- Room for the heading and for one entry under it.
                if #page > 0 and used + headingHeight + rowHeight > pageHeight then Turn() end
                Put(entry, index)
            else
                if #page > 0 and used + rowHeight > pageHeight then
                    Turn()
                    if heading then Put(heading) end
                end
                Put(entry, index)
            end
        end
        table.insert(pages, page)
        return pages
    end

    function list:PageCount()
        return #self.pages
    end

    local function Row(index)
        local row = list.rows[index]
        if not row then
            row = options.createRow(list)
            list.rows[index] = row
        end
        return row
    end

    function list:Render()
        local pages = #self.pages
        self.page = math.max(1, math.min(self.page, pages))
        local shown = self.pages[self.page]

        local offset = 0
        for index, slot in ipairs(shown) do
            local row = Row(index)
            row:ClearAllPoints()
            if columns == 1 then
                row:SetPoint("TOPLEFT", 0, -offset)
                row:SetPoint("RIGHT", self, "RIGHT", 0, 0)
                offset = offset + HeightOf(slot.entry)
            else
                local column = (index - 1) % columns
                local line = math.floor((index - 1) / columns)
                row:SetPoint("TOPLEFT", column * options.columnWidth, -line * rowHeight)
                row:SetWidth(options.columnWidth)
            end
            row:SetEntry(slot.entry)
            row:Show()
        end
        -- A page of plain rows always has its full set, shown or not.
        for index = #shown + 1, math.max(#self.rows, perPage) do Row(index):Hide() end

        UpdateControls(self.page, pages)
    end

    -- Shows these entries. The page is kept, so a refresh does not send the
    -- reader back to the start; pass `index` to turn to the page holding it.
    function list:SetItems(items, index)
        self.items = items
        self.pages = Paginate(items)
        if index then
            for number, page in ipairs(self.pages) do
                for _, slot in ipairs(page) do
                    if slot.index == index then self.page = number end
                end
            end
        end
        self:Render()
    end

    return list
end

-- Notes of different lengths, set close together and read a page at a time:
-- each page takes as many as fit `pageHeight`. A note is as tall as its text
-- measures at the page's width, so the space between two notes is always the
-- same. Before the frame has a width (it has none until it is first laid
-- out) heights are reckoned from the length of the text instead (see
-- NoteHeight), so pages can be counted at once; they are drawn again, by
-- measure, as soon as the width is known.
-- Fill it with :SetItems(list of { title, text, evidence }); see CreateNoteRow.
local NOTE_GAP = 12             -- between one note and the next
local NOTE_LINE_HEIGHT = 16
local NOTE_CHARS_PER_LINE = 40  -- about what fits across a page

local function NoteHeight(entry)
    local isHeading = entry.heading == true and entry.title ~= nil
    local lines = (entry.title and not isHeading) and 1 or 0
    for part in (tostring(entry.text) .. "\n"):gmatch("(.-)\n") do
        lines = lines + math.max(1, math.ceil(#part / NOTE_CHARS_PER_LINE))
    end
    return lines * NOTE_LINE_HEIGHT + (isHeading and NOTE_HEADING_HEIGHT or 0)
end

local function CreatePagedNotes(parent, pageHeight)
    local list = CreateFrame("Frame", nil, parent)
    list.rows = {}
    list.items = {}
    list.page = 1

    local UpdateControls = AddPageControls(list)

    -- A row that is never shown, to measure a note with.
    local measure = CreateNoteRow(list)
    measure:Hide()

    local function Height(entry)
        local width = list:GetWidth()
        if not width or width <= 1 then return NoteHeight(entry) end
        measure:SetTextWidth(width)
        measure:SetEntry(entry)
        return measure:MeasureHeight()
    end

    -- The index of the first note of each page.
    local function PageStarts(items)
        local starts, used = { 1 }, 0
        for index, entry in ipairs(items) do
            local height = Height(entry)
            if used > 0 and used + height > pageHeight then
                table.insert(starts, index)
                used = 0
            end
            used = used + height + NOTE_GAP
        end
        return starts
    end

    function list:PageCount()
        return #PageStarts(self.items)
    end

    function list:Render()
        local starts = PageStarts(self.items)
        self.page = math.max(1, math.min(self.page, #starts))
        local first = starts[self.page]
        local last = (starts[self.page + 1] or #self.items + 1) - 1

        local offset, used = 0, 0
        for index = first, last do
            used = used + 1
            local row = self.rows[used]
            if not row then
                row = CreateNoteRow(self)
                self.rows[used] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -offset)
            row:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            row:SetEntry(self.items[index])
            local height = Height(self.items[index])
            row:SetHeight(height)
            row:Show()
            offset = offset + height + NOTE_GAP
        end
        for index = used + 1, #self.rows do self.rows[index]:Hide() end

        UpdateControls(self.page, #starts)
    end

    -- Once the frame has its width, or when it changes, the notes are set
    -- again by measure.
    list:HookScript("OnSizeChanged", function(self)
        if #self.items > 0 then self:Render() end
    end)

    -- Shows these notes. The page is kept unless `fromStart`.
    function list:SetItems(items, fromStart)
        self.items = items
        if fromStart then self.page = 1 end
        self:Render()
    end

    return list
end

-- The heading of a part of a page, in the title lettering but smaller.
local function CreateHeading(parent)
    local heading = parent:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
    heading:SetJustifyH("LEFT")
    local font, _, flags = heading:GetFont()
    heading:SetFont(font, NOTE_HEADING_SIZE, flags)
    ApplyQuestTextColor(heading, true)
    return heading
end

-- A row of a list in parts: an entry (see CreateEntryRow), or the heading
-- that names the part beginning under it. Fill it with :SetEntry, given an
-- entry or { heading = "..." }. A list names its parts only when it has more
-- than one.
local SECTION_ROW_HEIGHT = 44
local SECTION_HEADING_HEIGHT = 26   -- a heading's own row: its lettering and the space under it

local function CreateSectionRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(SECTION_ROW_HEIGHT)

    local entryRow = CreateEntryRow(row)
    entryRow:SetPoint("TOPLEFT")
    entryRow:SetPoint("RIGHT")
    row.entryRow = entryRow

    -- From the top of its row, so that a page that opens on a heading opens
    -- level with the first thing on the page beside it.
    local heading = CreateHeading(row)
    heading:SetPoint("TOPLEFT", 6, -4)

    function row:SetEntry(entry)
        self.entry = entry
        self:SetHeight(entry.heading and SECTION_HEADING_HEIGHT or SECTION_ROW_HEIGHT)
        heading:SetText(entry.heading or "")
        entryRow:SetShown(entry.heading == nil)
        if not entry.heading then entryRow:SetEntry(entry) end
    end

    return row
end

-- How many rows of an entry list a page holds under its title, down to its
-- page arrows. The classic look's pages are taller.
W.LIST_ROWS = W.MODERN and 7 or 8

-- How wide a window of a single page is. On the classic look it must hold
-- the row of text tabs under it, which is wider than the modern page.
W.SINGLE_PAGE_WIDTH = W.MODERN and 448 or 484

W.CreateHeading = CreateHeading
W.CreateSectionRow = CreateSectionRow
W.SECTION_HEADING_HEIGHT = SECTION_HEADING_HEIGHT
W.MarginText = MarginText
W.MARGIN_MARKS = MARGIN_MARKS
W.TitleText = TitleText
W.MutedText = MutedText
W.CreateScrollNotes = CreateScrollNotes
W.CreateScrollList = CreateScrollList
W.SCROLL_BAR_ROOM = SCROLL_BAR_ROOM
W.CreateFramedIcon = CreateFramedIcon
W.CreateMapButton = CreateMapButton
W.ShowNoteTooltip = ShowNoteTooltip
W.HideTooltip = HideTooltip
W.CreateEntryRow = CreateEntryRow
W.CreatePagedNotes = CreatePagedNotes
W.CreatePagedList = CreatePagedList
W.PlayUISound = PlayUISound
W.AddRule = AddRule
W.ApplyQuestTextColor = ApplyQuestTextColor
W.CreateSlot = CreateSlot
W.CreatePageArrowButton = CreatePageArrowButton
