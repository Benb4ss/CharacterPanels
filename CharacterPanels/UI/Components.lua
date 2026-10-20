local _, AJ = ...

local UI = AJ.UI
local W = UI.Widgets
local C = UI.Components

local PlayUISound = W.PlayUISound

local SOUND_PAGE = W.Sounds.PAGE

-- Layer 2: pieces composed from widgets and shared by more than one window.
--
-- Windows come in two looks, chosen once at load:
--   modern   WoW Forever. Laid out like Blizzard's Spellbook: its frame
--            (ButtonFrameTemplate, gold border, round portrait), its page
--            art, and a toolbar with icon tabs and a search box. This is the
--            panel standard.
--   classic  Classic Era. The grey frame of that client (BasicFrameTemplate),
--            the quest log's parchment pieced together, and text tabs
--            hanging under the window as under its Character window.
-- Sections never check which one is active: they ask for a window, a page or
-- a book and lay their content out inside what they get.
--
-- Which look it is, is decided in Widgets.lua (W.MODERN).
local TAB_TEMPLATE = W.TAB_TEMPLATE
local MODERN = W.MODERN

-- Modern look. Tune these when adjusting how the panels sit on screen.
local WINDOW_SCALE = 1.2       -- panels are drawn 20% larger
local WINDOW_FIT_MARGIN = 20   -- room kept around a window when shrinking it to fit
local PORTRAIT_ICON = "Interface\\AddOns\\CharacterPanels\\Assets\\Icon.tga"
local HEADER_HEIGHT = 33       -- frame top to content top; leaves the gap the Spellbook has above its tabs
local CONTENT_MARGIN = 3       -- gap between the frame's inner border and the content

-- The toolbar is the dark strip between the title bar and the pages. It
-- holds the section tabs (icons, as in the Spellbook) and the search box.
-- Its controls are drawn at the client's normal size, not enlarged with the
-- window, so they match the Spellbook's.
local TOOLBAR_HEIGHT = 34
local TOOLBAR_TAB_X = 54       -- first tab, from the content's left edge; clears the portrait
local TOOLBAR_SEARCH_X = -10   -- search box, from the content's right edge
local TOOLBAR_SEARCH_Y = 7     -- and above the pages
local TOOLBAR_LEVEL = 10       -- frame levels above the window, over the page art
local SEARCH_WIDTH = 184       -- the Spellbook's search box
local SEARCH_HEIGHT = 20
local MENU_BUTTON_ROOM = 20    -- kept at the toolbar's right end for the menu button
local MENU_BUTTON_LIFT = 2     -- raises it to the middle of the search box
local TAB_MARK_X, TAB_MARK_Y = 3, 5   -- a tab's mark, from the tab's top right corner
-- The light of a tab that breathes: the gold frame the tab system itself
-- draws round the tab that is selected, set exactly where it sets it (the
-- tab's SquareBackgroundActive), so it lies true over the icon. A glow sized
-- to the whole button did not: the button is wider than its icon.
local TOOLBAR_TAB_PULSE = "spellbook-Tab-Frame-Glow-C60"
local TOOLBAR_TAB_PULSE_Y = 1
local TOOLBAR_TAB_SCALE = 1.2        -- toolbar tabs are drawn 25% larger (tune here)
local TOOLBAR_TAB_SELECTED_ALPHA = 0.7   -- the built-in gold frame of the selected tab: 0 = hidden, 1 = full
local TOOLBAR_TAB_LIFT = 4             -- the tabs sit this many pixels higher (positive = up)
local TOOLBAR_TAB_PULSE_BRIGHT = 0     -- the peak of the tab's breathing glow: 0 = off (the default is PULSE_BRIGHT)

-- Page art: the Spellbook's own pages. Drawn as an open book, so the two
-- halves meet in the middle and bring their own gutter. The art keeps an
-- empty band above the paper, which sits behind the toolbar.
local PAGE_ART_LEFT = "spellbook-Page-Left-C60"
local PAGE_ART_RIGHT = "spellbook-Page-Right-C60"   -- also used alone, as the minimized Spellbook does
local PAGE_TOP_PADDING = 8     -- keeps page content off the paper's torn top edge
local PAGE_TOP = TOOLBAR_HEIGHT + PAGE_TOP_PADDING   -- content top to writable page top

-- Talents-style dividers, drawn on the top of a page. Each one has its own
-- atlas, anchor and offsets, so each can be moved alone. Offsets are from the
-- anchor on the page: + right, + up.
--local DIVIDER_SCALE = 0.65
local DIVIDERS = {
    single    = { atlas = "Talents-divider-left-c60",  point = "TOP", scale = 0.68,      x = 14, y = 60 },
    bookLeft  = { atlas = "Talents-divider-right-c60", point = "TOPLEFT",scale = 0.6, x = -2, y = 62 },
    bookRight = { atlas = "Talents-divider-left-c60",  point = "TOPRIGHT",scale = 0.6,  x = 2, y = 62 },
}

local function DrawDivider(owner, spec)
    if not owner or not spec then return end

    -- A texture on the page itself, so the page's buttons and other child frames draw over it.
    local divider = owner:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas(spec.atlas, true)
    divider:SetScale(spec.scale or 1)
    divider:SetPoint(spec.point, owner, spec.point, spec.x, spec.y)
    divider:Show()
    return divider
end

-- Classic look. The grey frame is left as the client draws it: its art
-- reaches 5 below the frame's own bottom edge, and its background stops 2
-- inside each edge. Everything of ours stays inside the frame; only the
-- tabs hang below it.
local BOOK_INSET = 6           -- the book, from the frame's sides and bottom (the shade's own margin)
local BOOK_TOP = 26            -- and from its top, under the title bar
local PAGE_INSET = 14          -- a single page, from the frame's sides and bottom
local PAGE_TOP_INSET = 36      -- and from its top
-- The first tab, from the frame's bottom left corner: where the client
-- hangs the tabs of its own windows of this kind (CharacterFrameTab1). The
-- chosen tab's art rises 4 above the others, up to BOOK_INSET and no further.
local BOTTOM_TAB_X = 11
local BOTTOM_TAB_Y = 2
local BOTTOM_TAB_OVERLAP = -16 -- each tab tucks under the one before it
local BOTTOM_TAB_MAX_CUT = 10  -- the most a tab is narrowed to fit a narrow window (CharacterFrame_TabBoundsCheck's own limit)
-- A tab's mark: the game's own sign that someone has something for you,
-- drawn, at the tab's top right corner. (The letter "!" after the label was
-- tried first and could hardly be seen: user, 2026-10-09.)
local BOTTOM_TAB_MARK = "Interface\\GossipFrame\\AvailableQuestIcon"
local BOTTOM_TAB_MARK_SIZE = 16
-- The light of a tab that breathes: the tab's own highlight, set where the
-- template sets it.
local BOTTOM_TAB_PULSE = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-RealHighlight"
local BOTTOM_TAB_PULSE_INSET = { 3, 5, -3, 0 }
local BOTTOM_TAB_MARK_X, BOTTOM_TAB_MARK_Y = -1, -3
local TAB_MIN_WIDTH = 36
local TAB_MAX_WIDTH = 88

-- The quest log's parchment comes in four pieces, cut the way the client
-- cuts them for its own quest log (236 + 62 across, 182 + 160 down). The
-- bottom pieces start at their very top, where they carry on from the top
-- pieces, and stop short of the dark footer drawn into them.
local PAPER_LEFT_SHARE = 236 / 298
local PAPER_TOP_SHARE = 182 / 342
local PAPER_LEFT_U = 0.078125      -- the left pieces, past the frame art at their edge
local PAPER_RIGHT_U = 0.5          -- the right pieces, up to theirs
local PAPER_TOP_V = 0.2890625      -- the top pieces, under the title art
local PAPER_BOTTOM_V = 0.625       -- the bottom pieces, above the footer art

local function RegisterEscapeClose(frame)
    if not frame or not frame.GetName then return end
    local name = frame:GetName()
    if not name or not UISpecialFrames then return end
    for _, existing in ipairs(UISpecialFrames) do
        if existing == name then return end
    end
    table.insert(UISpecialFrames, name)
end


local function ShowLeftPanel(frame)
    if frame then frame:Show() end
end

local function HideLeftPanel(frame)
    if frame then frame:Hide() end
end

local function CreateClassicWindow(name, title, width, height, x, y, openSound, closeSound)
    local frame = CreateFrame("Frame", name, UIParent, "BasicFrameTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x or 16, y or -118)
    frame:SetClampedToScreen(true)
    frame:SetMovable(false)
    frame:EnableMouse(true)
    frame:SetFrameStrata("DIALOG")

    local shade = frame:CreateTexture(nil, "BACKGROUND")
    shade:SetTexture("Interface\\Buttons\\WHITE8X8")
    shade:SetColorTexture(0.08, 0.06, 0.04, 0.92)
    shade:SetPoint("TOPLEFT", BOOK_INSET, -BOOK_TOP)
    shade:SetPoint("BOTTOMRIGHT", -BOOK_INSET, BOOK_INSET)
    frame.shade = shade



    -- The template brings a title of its own, empty; ours is written over
    -- its place in white, and the template's is left unused.
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleText:SetPoint("TOP", 0, -5)
    titleText:SetText(title)
    frame.TitleText = titleText

    -- Create hidden so the initial addon load does not play a close sound.
    frame:Hide()
    RegisterEscapeClose(frame)
    frame:HookScript("OnShow", function() PlayUISound(openSound) end)
    frame:HookScript("OnHide", function() PlayUISound(closeSound) end)

    return frame
end

-- The standard scale, or less when the window would not fit the screen. The
-- panel manager's own checkFit is not used: it resets the scale to 1 on every
-- show, which undoes WINDOW_SCALE.
local function WindowScale(width, height)
    local fitWidth = UIParent:GetWidth() / (width + WINDOW_FIT_MARGIN)
    local fitHeight = UIParent:GetHeight() / (height + WINDOW_FIT_MARGIN)
    return math.min(WINDOW_SCALE, fitWidth, fitHeight)
end

-- Places a toolbar control at the client's normal size inside a scaled
-- window. Offsets are given in the window's units.
local function PlaceInToolbar(control, frame, point, relativePoint, x, y)
    local scale = frame:GetScale()
    control:SetScale(1 / scale)
    -- The page art reaches up behind the toolbar; keep the controls above it.
    control:SetFrameLevel(frame:GetFrameLevel() + TOOLBAR_LEVEL)
    control:SetPoint(point, frame.Inset, relativePoint, x * scale, y * scale)
end

-- Blizzard's current panel. The frame brings its own border, title, close
-- button and portrait; the content area is its Inset.
-- `options.search` adds the search box to the toolbar (frame.searchBox), with
-- that text as its hint. `options.menu` adds the small arrow button beside it
-- that opens a menu, as in the Spellbook: a function that fills the menu.
local function CreateModernWindow(name, title, width, height, x, y, openSound, closeSound, options)
    local frame = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x or 16, y or -118)
    frame:SetScale(WindowScale(width, height))
    frame:SetClampedToScreen(true)
    frame:SetMovable(false)
    frame:EnableMouse(true)
    frame:SetToplevel(true)

    -- No button strip along the bottom, and a short header instead of the
    -- template's tall one.
    ButtonFrameTemplate_HideButtonBar(frame)
    FrameTemplate_SetAtticHeight(frame, HEADER_HEIGHT)

    frame:SetPortraitToAsset(PORTRAIT_ICON)
    frame:SetTitle(title)

    -- The right end of the toolbar: the menu button at the edge, the search
    -- box to its left.
    local toolbarY = TOOLBAR_SEARCH_Y - CONTENT_MARGIN - TOOLBAR_HEIGHT
    local searchRight = TOOLBAR_SEARCH_X

    if options and options.menu then
        local menuButton = CreateFrame("DropdownButton", nil, frame, "UIPanelArrowDropdownButtonTemplate")
        PlaceInToolbar(menuButton, frame, "BOTTOMRIGHT", "TOPRIGHT", TOOLBAR_SEARCH_X, toolbarY + MENU_BUTTON_LIFT)
        menuButton:SetupMenu(function(_, root) options.menu(root) end)
        frame.menuButton = menuButton
        searchRight = searchRight - MENU_BUTTON_ROOM
    end

    if options and options.search then
        local searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
        searchBox:SetSize(SEARCH_WIDTH, SEARCH_HEIGHT)
        searchBox.Instructions:SetText(options.search)
        PlaceInToolbar(searchBox, frame, "BOTTOMRIGHT", "TOPRIGHT", searchRight, toolbarY)
        frame.searchBox = searchBox
    end

    -- Create hidden so the initial addon load does not play a close sound.
    frame:Hide()
    RegisterEscapeClose(frame)
    frame:HookScript("OnShow", function() PlayUISound(openSound) end)
    frame:HookScript("OnHide", function() PlayUISound(closeSound) end)

    return frame
end

local CreateWindow = MODERN and CreateModernWindow or CreateClassicWindow

-- Fills the window's content area with a region. `classic` holds the offsets
-- the grey frame needs: { left, top, right, bottom }. `top` lowers the
-- region's top on the modern look.
local function FillContent(region, frame, classic, top)
    if MODERN then
        region:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", CONTENT_MARGIN, -CONTENT_MARGIN - top)
        region:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -CONTENT_MARGIN, CONTENT_MARGIN)
    else
        region:SetPoint("TOPLEFT", classic[1], classic[2])
        region:SetPoint("BOTTOMRIGHT", classic[3], classic[4])
    end
end

local function CreateModernPaper(parent, art, divider)
    local panel = CreateFrame("Frame", nil, parent)

    local paper = panel:CreateTexture(nil, "BACKGROUND")
    paper:SetAtlas(art)
    -- The panel is the writable paper; the art reaches up past it to the top
    -- of the content area, where its band begins.
    paper:SetPoint("TOPLEFT", 0, PAGE_TOP)
    paper:SetPoint("BOTTOMRIGHT")
    panel.paper = paper

    DrawDivider(panel, divider)
    return panel
end

local function CreateClassicPaper(parent)
    local panel = CreateFrame("Frame", nil, parent)

    -- Build the parchment from the same four texture pieces Blizzard uses
    -- for Classic quest-detail panels. This avoids QuestBG's baked-in blank
    -- area and gives us a real full-page parchment at any panel size.
    local tl = panel:CreateTexture(nil, "BACKGROUND")
    tl:SetTexture("Interface\\QuestFrame\\UI-QuestDetails-TopLeft")
    tl:SetTexCoord(PAPER_LEFT_U, 1.0, PAPER_TOP_V, 1.0)
    tl:SetPoint("TOPLEFT")

    local tr = panel:CreateTexture(nil, "BACKGROUND")
    tr:SetTexture("Interface\\QuestFrame\\UI-QuestDetails-TopRight")
    tr:SetTexCoord(0.0, PAPER_RIGHT_U, PAPER_TOP_V, 1.0)
    tr:SetPoint("TOPRIGHT")

    local bl = panel:CreateTexture(nil, "BACKGROUND")
    bl:SetTexture("Interface\\QuestFrame\\UI-QuestDetails-BotLeft")
    bl:SetTexCoord(PAPER_LEFT_U, 1.0, 0.0, PAPER_BOTTOM_V)
    bl:SetPoint("BOTTOMLEFT")

    local br = panel:CreateTexture(nil, "BACKGROUND")
    br:SetTexture("Interface\\QuestFrame\\UI-QuestDetails-BotRight")
    br:SetTexCoord(0.0, PAPER_RIGHT_U, 0.0, PAPER_BOTTOM_V)
    br:SetPoint("BOTTOMRIGHT")

    panel.paperTL = tl
    panel.paperTR = tr
    panel.paperBL = bl
    panel.paperBR = br


    local function LayoutPaper(self)
        local w, h = self:GetWidth(), self:GetHeight()
        if not w or not h or w <= 1 or h <= 1 then return end

        -- Whole pixels, so no line of the page's background shows through
        -- where two pieces meet.
        local leftW = math.floor(w * PAPER_LEFT_SHARE + 0.5)
        local rightW = w - leftW
        local topH = math.floor(h * PAPER_TOP_SHARE + 0.5)
        local bottomH = h - topH

        self.paperTL:SetSize(leftW, topH)
        self.paperTR:SetSize(rightW, topH)
        self.paperBL:SetSize(leftW, bottomH)
        self.paperBR:SetSize(rightW, bottomH)
    end

    panel:SetScript("OnSizeChanged", LayoutPaper)
    panel:SetScript("OnShow", LayoutPaper)
	
	     --DrawDivider(panel, DIVIDER_LEFT, "TOP", "TOP", PAGE_DIVIDER_X, PAGE_DIVIDER_Y)

    return panel
end

-- A single parchment page filling the window, below the toolbar.
local function CreatePage(frame)
    local page
    if MODERN then
        page = CreateModernPaper(frame, PAGE_ART_RIGHT, DIVIDERS.single)
    else
        page = CreateClassicPaper(frame)
    end
    FillContent(page, frame, { PAGE_INSET, -PAGE_TOP_INSET, -PAGE_INSET, PAGE_INSET }, PAGE_TOP)
    return page
end

-- The open book shared by the Journal and Profession windows: two parchment
-- pages side by side.
local function CreateBook(frame)
    local book = CreateFrame("Frame", nil, frame)
    FillContent(book, frame, { BOOK_INSET, -BOOK_TOP, -BOOK_INSET, BOOK_INSET }, 0)

    if MODERN then
        local leftPage = CreateModernPaper(book, PAGE_ART_LEFT, DIVIDERS.bookLeft)
        leftPage:SetPoint("TOPLEFT", 0, -PAGE_TOP)
        leftPage:SetPoint("BOTTOMRIGHT", book, "BOTTOM")

        local rightPage = CreateModernPaper(book, PAGE_ART_RIGHT, DIVIDERS.bookRight)
        rightPage:SetPoint("TOPLEFT", book, "TOP", 0, -PAGE_TOP)
        rightPage:SetPoint("BOTTOMRIGHT")

        return book, leftPage, rightPage
    end

    local leftPage = CreateClassicPaper(book)
    leftPage:SetPoint("TOPLEFT", 2, -2)
    leftPage:SetPoint("BOTTOMLEFT", 2, 0)
    leftPage:SetWidth(316)

    local rightPage = CreateClassicPaper(book)
    rightPage:SetPoint("TOPRIGHT", -2, -2)
    rightPage:SetPoint("BOTTOMRIGHT", -2, 0)
    rightPage:SetWidth(316)

    local spine = book:CreateTexture(nil, "ARTWORK")
    spine:SetTexture("Interface\\Buttons\\WHITE8X8")
    spine:SetColorTexture(0.18, 0.10, 0.05, 0.45)
    spine:SetPoint("TOP", 0, -2)
    spine:SetPoint("BOTTOM", 0, 0)
    spine:SetWidth(8)

    local spineLight = book:CreateTexture(nil, "ARTWORK")
    spineLight:SetTexture("Interface\\Buttons\\WHITE8X8")
    spineLight:SetColorTexture(0.58, 0.43, 0.25, 0.18)
    spineLight:SetPoint("TOP", 1, -2)
    spineLight:SetPoint("BOTTOM", 1, 0)
    spineLight:SetWidth(1)

    return book, leftPage, rightPage
end

-- The open book with uneven pages: the left page is `leftWidth` wide and the
-- right page takes what is left of the book. For a window that is between a
-- single page and the full book.
local function CreateSplitBook(frame, leftWidth)
    local book = CreateFrame("Frame", nil, frame)
    FillContent(book, frame, { BOOK_INSET, -BOOK_TOP, -BOOK_INSET, BOOK_INSET }, 0)

    if MODERN then
                local leftPage = CreateModernPaper(book, PAGE_ART_LEFT, DIVIDERS.bookLeft)
        leftPage:SetPoint("TOPLEFT", 0, -PAGE_TOP)
        leftPage:SetPoint("BOTTOMRIGHT", book, "BOTTOMLEFT", leftWidth, 0)

                local rightPage = CreateModernPaper(book, PAGE_ART_RIGHT, DIVIDERS.bookRight)
        rightPage:SetPoint("TOPLEFT", book, "TOPLEFT", leftWidth, -PAGE_TOP)
        rightPage:SetPoint("BOTTOMRIGHT")

        return book, leftPage, rightPage
    end

    local leftPage = CreateClassicPaper(book)
    leftPage:SetPoint("TOPLEFT", 2, -2)
    leftPage:SetPoint("BOTTOMLEFT", 2, 0)
    leftPage:SetWidth(leftWidth)

    local rightPage = CreateClassicPaper(book)
    rightPage:SetPoint("TOPLEFT", leftWidth, -2)
    rightPage:SetPoint("BOTTOMRIGHT", -2, 0)

    local spine = book:CreateTexture(nil, "ARTWORK")
    spine:SetTexture("Interface\\Buttons\\WHITE8X8")
    spine:SetColorTexture(0.18, 0.10, 0.05, 0.45)
    spine:SetPoint("TOPLEFT", leftWidth - 4, -2)
    spine:SetPoint("BOTTOMLEFT", leftWidth - 4, 0)
    spine:SetWidth(8)

    return book, leftPage, rightPage
end

local function SetTabVisual(tab, selected)
    if selected then
        if PanelTemplates_SelectTab then
            PanelTemplates_SelectTab(tab)
        else
            tab:LockHighlight()
        end
    else
        if PanelTemplates_DeselectTab then
            PanelTemplates_DeselectTab(tab)
        else
            tab:UnlockHighlight()
        end
    end
end

local function ResizeTopTab(tab)
    if PanelTemplates_TabResize then
        PanelTemplates_TabResize(tab, 0, nil, TAB_MIN_WIDTH, TAB_MAX_WIDTH)
        return
    end

    local textWidth = 0
    if tab.Text and tab.Text.GetStringWidth then
        textWidth = tab.Text:GetStringWidth() or 0
    elseif tab.GetFontString and tab:GetFontString() then
        textWidth = tab:GetFontString():GetStringWidth() or 0
    end
    tab:SetWidth(math.max(72, textWidth + 30))
end

-- Narrows a bottom tab by `cut`, the way the client narrows the Character
-- window's tabs when they outgrow it: the label moves in over the tab's ends.
local function NarrowTab(tab, cut)
    if cut > 0 and PanelTemplates_TabResize then
        PanelTemplates_TabResize(tab, -cut, nil, TAB_MIN_WIDTH - cut, TAB_MAX_WIDTH)
    end
end

-- Keeps a row of bottom tabs within its window: a narrow window (the single
-- page of a trip) is not as wide as the tabs laid end to end. Each tab gives
-- up the same share, and no more than the client's own limit.
local function FitBottomTabs(frame, count)
    local total = BOTTOM_TAB_X + (count - 1) * BOTTOM_TAB_OVERLAP
    for index = 1, count do total = total + frame.ajTabs[index]:GetWidth() end

    local excess = total - frame:GetWidth()
    local cut = excess > 0 and math.min(BOTTOM_TAB_MAX_CUT, math.ceil(excess / count)) or 0
    for index = 1, count do
        local tab = frame.ajTabs[index]
        tab.ajCut = cut
        NarrowTab(tab, cut)
    end
end

-- A tab that breathes: a soft light over it that comes and goes, for a
-- section where something is under way (see Section:IsUnderWay in UI.lua).
-- `draw` gives the light its art and its place on the tab, which differ
-- with the look.
local PULSE_SECONDS = 1.6           -- one breath in, or out
local PULSE_FAINT, PULSE_BRIGHT = 0.05, 0.55

local function AddTabPulse(tab, draw, bright)
    local light = tab:CreateTexture(nil, "OVERLAY")
    draw(light)
    light:SetAlpha(PULSE_FAINT)
    light:Hide()

    local breath = light:CreateAnimationGroup()
    breath:SetLooping("BOUNCE")
    local fade = breath:CreateAnimation("Alpha")
    fade:SetFromAlpha(PULSE_FAINT)
    fade:SetToAlpha(bright or PULSE_BRIGHT)
    fade:SetDuration(PULSE_SECONDS)
    fade:SetSmoothing("IN_OUT")

    tab.pulse, tab.pulseBreath = light, breath
end

-- Asked again every time the window is shown: an animation started while
-- its window was hidden does not run, so it is started here if it is not
-- running yet.
local function SetTabPulsing(tab, pulsing)
    tab.pulse:SetShown(pulsing)
    if not pulsing then
        tab.pulseBreath:Stop()
    elseif not tab.pulseBreath:IsPlaying() then
        tab.pulseBreath:Play()
    end
end

-- What a tab says besides which window is open: the mark of something
-- unread, and its breathing while there is a reason to go there (something
-- unread, or something under way) and its window is not the one open.
local function ApplyTabSigns(tab, activeKey)
    local section = tab.section
    local news = section ~= nil and section.HasNews ~= nil and section:HasNews() == true
    local underWay = section ~= nil and section.IsUnderWay ~= nil and section:IsUnderWay() == true
    tab.mark:SetShown(news)
    SetTabPulsing(tab, tab.key ~= activeKey and (news or underWay))
end

-- The tab system's glow on the selected tab is made of several textures, drawn
-- by the tab template. Each texture is found by its art name (glow, active,
-- highlight, selected) and set to TOOLBAR_TAB_SELECTED_ALPHA; the icon is kept.


local function IsSelectedGlow(region)
    if not region.GetObjectType or region:GetObjectType() ~= "Texture" then return false end
    local art = (region.GetAtlas and region:GetAtlas()) or (region.GetTexture and region:GetTexture()) or ""
    art = tostring(art):lower()
    return art:find("glow") ~= nil or art:find("active") ~= nil
        or art:find("highlight") ~= nil or art:find("selected") ~= nil
end

-- The class colour for a class file, from the custom table if set.
local function ClassColor(classFile)
    if not classFile then return end
    local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFile])
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
    if color then return color.r, color.g, color.b end
end

local function SetToolbarTabSelectedAlpha(tab)
    local _, classFile = UnitClass("player")
    local r, g, b = ClassColor(classFile)
    r, g, b = r or 1, g or 1, b or 1

    for _, region in ipairs({ tab:GetRegions() }) do
        if region ~= tab.icon and IsSelectedGlow(region) then
            region:SetDesaturated(true)
            region:SetVertexColor(r, g, b)
            region:SetAlpha(TOOLBAR_TAB_SELECTED_ALPHA)
        end
    end
    local highlight = tab.GetHighlightTexture and tab:GetHighlightTexture()
    if highlight then
        highlight:SetDesaturated(true)
        highlight:SetVertexColor(r, g, b)
        highlight:SetAlpha(TOOLBAR_TAB_SELECTED_ALPHA)
    end
end

local function ApplyFrameTabs(frame, activeKey)
    if not frame or not frame.ajTabs then return end
    if frame.ajTabSystem then
        for tabID, tab in ipairs(frame.ajTabs) do
            if tab.key == activeKey then
                frame.ajTabSystem:SetTabVisuallySelected(tabID)
                SetToolbarTabSelectedAlpha(tab)
            end
            ApplyTabSigns(tab, activeKey)
        end
        return
    end
    for _, tab in ipairs(frame.ajTabs) do
        SetTabVisual(tab, tab.key == activeKey)
        ApplyTabSigns(tab, activeKey)
    end
end

-- Modern look: icon tabs in the toolbar, built with the tab system the
-- Spellbook uses. Each window keeps its own section's tab lit; clicking
-- another one opens that section's window.
--
-- A window apart from the journal's sections gives its own `tabs`, a list of
-- { key, label, icon }, and `onSelect`, called with the key of the tab
-- clicked; it lights the right one itself with ApplyFrameTabs.
local function OpenTalents()
    PlayerSpellsUtil.ToggleClassTalentFrame()
end

local function CreateToolbarTabs(frame, activeKey, tabs, onSelect)
    local Select = onSelect or function(key) UI:Open(key) end


    -- Toolbar actions: tabs that do something instead of opening a section.
    -- They sit after the sections and are drawn by the same tab system.
    -- The icon is the player's spec icon (not yet checked against Blizzard source).
    local function SpecIcon()
        local specIndex = GetSpecialization and GetSpecialization()
        local _, _, _, icon = GetSpecializationInfo(specIndex or 1)
        return icon or PORTRAIT_ICON
    end
    local actions = {
        { key = "talents", label = "Talents", icon = 132222, onPress = OpenTalents },
    }

    local sections = {}
    for _, info in ipairs(tabs or UI:GetTabs()) do sections[#sections + 1] = info end
    for _, action in ipairs(actions) do sections[#sections + 1] = action end

    local system = CreateFrame("Frame", nil, frame, "TabSystemTemplate")
    system.minTabWidth = 1
    PlaceInToolbar(system, frame, "BOTTOMLEFT", "TOPLEFT", TOOLBAR_TAB_X, -CONTENT_MARGIN - TOOLBAR_HEIGHT + TOOLBAR_TAB_LIFT)
    system:SetTabSelectedCallback(function(tabID, isUserAction)
        local info = sections[tabID]
        if info.onPress then
            if isUserAction then
                PlayUISound(SOUND_PAGE)
                info.onPress()
            end
            return false   -- an action tab does not stay selected (unconfirmed, see below)
        end
        if isUserAction then
            PlayUISound(SOUND_PAGE)
            Select(info.key)
        end
        return true
    end)

    frame.ajTabSystem = system
    frame.ajTabs = {}
    for _, info in ipairs(sections) do
        local tabID = system:AddTab(nil, info.icon or PORTRAIT_ICON)
        local tab = system:GetTabButton(tabID)
        tab:SetScale(TOOLBAR_TAB_SCALE)
        tab.key = info.key
        tab.section = info
        tab:SetTooltipText(info.label)

        -- The game's own sign that someone has something for you, at the
        -- corner of a tab whose section has something new to show (see
        -- Section:HasNews in UI.lua). No number: nothing is counted.
        local mark = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        mark:SetText("!")
        mark:SetPoint("TOPRIGHT", TAB_MARK_X, TAB_MARK_Y)
        mark:Hide()
        tab.mark = mark
        AddTabPulse(tab, function(light)
            light:SetAtlas(TOOLBAR_TAB_PULSE, true)
            light:SetPoint("BOTTOM", 0, TOOLBAR_TAB_PULSE_Y)
        end, TOOLBAR_TAB_PULSE_BRIGHT)

        frame.ajTabs[tabID] = tab
    end

    ApplyFrameTabs(frame, activeKey)
end

-- Classic look: one text tab per registered section under the window, or
-- per tab of a window that gives its own (see CreateToolbarTabs).
local function CreateBottomTabs(frame, activeKey, tabs, onSelect)
    if not frame then return end
    local sections = tabs or UI:GetTabs()
    local Select = onSelect or function(key) UI:Open(key) end
    frame.ajTabs = frame.ajTabs or {}

    for i, info in ipairs(sections) do
        local tab = frame.ajTabs[i]
        if not tab then
            -- Classic's CharacterFrameTabButtonTemplate depends on the button
            -- having a global name. PanelTemplates_TabResize/SelectTab build the
            -- names of the tab texture regions by concatenating GetName(), so an
            -- anonymous tab crashes inside Blizzard_SharedXML.
            local frameName = frame:GetName() or "JournalFrame"
            local tabName = frameName .. "Tab" .. i
            tab = CreateFrame("Button", tabName, frame, TAB_TEMPLATE)
            tab:SetID(i)
            tab:SetScript("OnClick", function(self)
                PlayUISound(SOUND_PAGE)
                Select(self.key)
            end)
            -- The template sizes the tab to its label again every time it
            -- is shown; what FitBottomTabs took off is taken off again.
            tab:HookScript("OnShow", function(self) NarrowTab(self, self.ajCut or 0) end)

            -- The section has something new to show (see CreateToolbarTabs
            -- for the modern look's). No number: nothing is counted.
            local mark = tab:CreateTexture(nil, "OVERLAY")
            mark:SetTexture(BOTTOM_TAB_MARK)
            mark:SetSize(BOTTOM_TAB_MARK_SIZE, BOTTOM_TAB_MARK_SIZE)
            mark:SetPoint("TOPRIGHT", BOTTOM_TAB_MARK_X, BOTTOM_TAB_MARK_Y)
            mark:Hide()
            tab.mark = mark
            AddTabPulse(tab, function(light)
                light:SetTexture(BOTTOM_TAB_PULSE)
                light:SetBlendMode("ADD")
                light:SetPoint("TOPLEFT", BOTTOM_TAB_PULSE_INSET[1], BOTTOM_TAB_PULSE_INSET[2])
                light:SetPoint("BOTTOMRIGHT", BOTTOM_TAB_PULSE_INSET[3], BOTTOM_TAB_PULSE_INSET[4])
            end)

            frame.ajTabs[i] = tab
        end

        tab.key = info.key
        tab.section = info
        tab:SetText(info.label)
        ResizeTopTab(tab)
    end
    FitBottomTabs(frame, #sections)

    local previousTab
    for i = 1, #sections do
        local tab = frame.ajTabs[i]
        tab:ClearAllPoints()
        if not previousTab then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", BOTTOM_TAB_X, BOTTOM_TAB_Y)
        else
            tab:SetPoint("LEFT", previousTab, "RIGHT", BOTTOM_TAB_OVERLAP, 0)
        end
        previousTab = tab
    end

    ApplyFrameTabs(frame, activeKey)
end

----------------------------------------------------------------------
-- Side tabs: the icon tabs on a window's right edge. Every window builds its
-- side tabs here, so they all look the same. Change the look in these values only.
----------------------------------------------------------------------
local SIDE_TAB_W, SIDE_TAB_H = 48, 54          -- the tab
local SIDE_ICON_SIZE = 44                      -- the icon, a square centred on the tab
local SIDE_ICON_X, SIDE_ICON_Y = -2, 0         -- nudges the icon: + right, + up
local SIDE_MASK_SCALE = 1.22                   -- the bevel mask, as a share of the icon
local SIDE_ICON_EDGE = 0.03                    -- cuts the icon files' built-in light edge

-- Builds one side tab: its background, icon, mask, selected light and hover light.
-- The caller sets the icon's texture, places the tab and shows its selection.
local function CreateSideTab(parent)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(SIDE_TAB_W, SIDE_TAB_H)

    local back = tab:CreateTexture(nil, "BACKGROUND")
    back:SetAtlas("common-sidetab")
    back:SetAllPoints()

    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetSize(SIDE_ICON_SIZE, SIDE_ICON_SIZE)
    tab.icon:SetPoint("CENTER", tab, "CENTER", SIDE_ICON_X, SIDE_ICON_Y)
    tab.icon:SetTexCoord(SIDE_ICON_EDGE, 1, 0, 1)

    local src = _G.CharacterFrameModeTab2 and _G.CharacterFrameModeTab2.Mask
    if src then
        local mask = tab:CreateMaskTexture()
        local atlas = src.GetAtlas and src:GetAtlas()
        if atlas then mask:SetAtlas(atlas) else mask:SetTexture(src:GetTexture()) end
        local size = SIDE_ICON_SIZE * SIDE_MASK_SCALE
        mask:SetSize(size, size)
        mask:SetPoint("CENTER", tab.icon, "CENTER")
        tab.icon:AddMaskTexture(mask)
    end

    tab.selected = tab:CreateTexture(nil, "OVERLAY")
    tab.selected:SetAtlas("common-sidetab-selected")
    tab.selected:SetAllPoints()
    tab.selected:Hide()

    local hover = tab:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAtlas("common-sidetab-hover")
    hover:SetAllPoints()
    return tab
end
C.CreateSideTab = CreateSideTab

----------------------------------------------------------------------
-- Expand/minimize button: the arrow at the top right of a window's book, which
-- folds it to one page. Every window builds it here, so it looks and sits the same.
----------------------------------------------------------------------
local EXPAND_SIZE = 30                 -- the button, in pixels
local EXPAND_X, EXPAND_Y = 0, 24     -- its centre from the anchor's top right: + right, + up
local EXPAND_LEVEL = 30                -- frame levels above the window

-- `anchor` is the frame whose top right corner the arrow sits on. `onClick` runs
-- on each press; the window decides what folding does.
local function CreateExpandToggle(frame, anchor, onClick)
    local toggle = CreateFrame("Button", nil, frame)
    toggle:SetFrameLevel(frame:GetFrameLevel() + EXPAND_LEVEL)
    toggle:SetSize(EXPAND_SIZE, EXPAND_SIZE)
    toggle:SetPoint("CENTER", anchor, "TOPRIGHT", EXPAND_X, EXPAND_Y)
    toggle:SetNormalTexture(130869)
    toggle:SetPushedTexture(130868)
    toggle:SetHighlightTexture(130757, "ADD")
    toggle:SetScript("OnClick", onClick)
    return toggle
end

-- Points the arrow for the state: left when open, right when folded.
local function SetExpandArrow(toggle, expanded)
    if not toggle then return end
    local l, r = 0, 1
    if not expanded then l, r = 1, 0 end
    for _, tex in ipairs({ toggle:GetNormalTexture(), toggle:GetPushedTexture(), toggle:GetHighlightTexture() }) do
        if tex then tex:SetTexCoord(l, r, 0, 1) end
    end
end

C.CreateExpandToggle = CreateExpandToggle
C.SetExpandArrow = SetExpandArrow



C.ShowLeftPanel = ShowLeftPanel
C.HideLeftPanel = HideLeftPanel
C.CreateWindow = CreateWindow
C.CreatePage = CreatePage
C.CreateBook = CreateBook
C.CreateSplitBook = CreateSplitBook
C.CreateTabs = MODERN and CreateToolbarTabs or CreateBottomTabs
C.ApplyFrameTabs = ApplyFrameTabs
