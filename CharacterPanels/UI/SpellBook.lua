local _, AJ = ...

-- The spellbook: a tab that opens in the wide book, or folds to one page with
-- the arrow, as the Character tab does. Skill lines are side tabs on the right
-- edge (SpellBookPage.lua).

local UI = AJ.UI
local W = UI.Widgets
local C = UI.Components

local Section = UI:NewSection("spellbook", { label = "Spellbook", order = 15 })

-- The toolbar icon: the book icon, as a file path
local ICON = "Interface\\Icons\\INV_Misc_Book_08"
Section.icon = ICON

-- The page title: the spell name font, larger
local TITLE_FACE = GameFontNormal:GetFont()     -- same font file as the spell names
local TITLE_SIZE = 20
local TITLE_COLOUR = { 0.18, 0.08, 0.04 }   -- RGB, each 0 to 1; change to your colour
local DIVIDER_ATLAS = "spellbook-divider"       -- Blizzard's title separator

-- The light behind the title: the same backplate as the spell rows, drawn fainter
local TITLE_GLOW_ATLAS = "spellbook-item-backplate"
local TITLE_GLOW_ALPHA = 0.3                    -- spell rows are 1.0
local GLOW_RIGHT = -236                         -- where the glow stops, from the page's right edge (tuned)

-- The separator: Blizzard's art line at its native height, stretched across the page
local DIVIDER_SCALE = 0.6   -- raise to make the line taller, lower to make it thinner

local function AddDivider(page)
    if not C_Texture.GetAtlasInfo(DIVIDER_ATLAS) then
        W.AddRule(page, 16, -16, -43)
        return
    end
    local tex = page:CreateTexture(nil, "ARTWORK")
    tex:SetAtlas(DIVIDER_ATLAS, true)              -- native size, to measure its height
    local h = tex:GetHeight() * DIVIDER_SCALE
    tex:SetHeight(h)
    tex:ClearAllPoints()
    tex:SetPoint("LEFT", page, "TOPLEFT", 26, -43 - h / 2)
    tex:SetPoint("RIGHT", page, "TOPRIGHT", -26, -43 - h / 2)
end

-- The faint light behind the title. BACKGROUND sublevel 7 puts it above the page
-- paper and below the title text.
local function AddTitleGlow(page)
    if not C_Texture.GetAtlasInfo(TITLE_GLOW_ATLAS) then return end
    local glow = page:CreateTexture(nil, "BACKGROUND", nil, 7)
    glow:SetAtlas(TITLE_GLOW_ATLAS)
    glow:SetAlpha(TITLE_GLOW_ALPHA)
    glow:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -10)
    glow:SetPoint("BOTTOMRIGHT", page, "TOPRIGHT", GLOW_RIGHT, -46)
    return glow
end

-- The page's title: the skill line name, filled in by the page code
local function Title(page)
    AddTitleGlow(page)
    local title = page:CreateFontString(nil, "ARTWORK")
    title:SetFont(TITLE_FACE, TITLE_SIZE, "")
    title:SetPoint("TOPLEFT", 46, -16)
    title:SetTextColor(unpack(TITLE_COLOUR))
    AddDivider(page)
    return title
end

function Section:Create()
    local bookWidth = UI.Layouts.wideBook.width
    local singleWidth = UI.Layouts.single.width
    local frame = C.CreateWindow("JournalSpellbookFrame", self.label, bookWidth, 508, 16, -104,
        W.Sounds.SPELLBOOK_OPEN, W.Sounds.SPELLBOOK_CLOSE)
    frame:Hide()

    local singlePage = C.CreatePage(frame)
    local book, left, right = C.CreateBook(frame)
    local singleTitle = Title(singlePage)
    local leftTitle = Title(left)
    -- the right page has a separator, but no title text, so no glow
    AddDivider(right)

    self.spells = AJ.CreateSpellBookPage(frame, {
        book = book,
        single = singlePage,
        left = left,
        right = right,
        titles = { singleTitle, leftTitle },
        singleWidth = singleWidth,
        bookWidth = bookWidth,
    })
    return frame
end