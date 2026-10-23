local _, AJ = ...

-- Shared helpers for the Journal's windows: the small utilities (secret-value
-- checks, text, textures) and the side-panel look (insets, background, border,
-- the stat list's placement). Everything is exported as AJ.Helpers.
--
-- Reads: AJ.settings (panel insets, stat list settings). Writes: AJ.Helpers only.
-- Requires: CharacterStatsPaneScrollBox (Blizzard, read when a panel refreshes).
-- Loaded before Character.lua; Character.lua reads these names from AJ.Helpers.

local FONT_SHRINK = 1
local BG_CROP_BOTTOM = 0.15

-- The ornate border's corner size in pixels: the slice margin of
-- common-insideframe, measured in game. Every border uses it unless the
-- caller passes its own corner.
local BORDER_CORNER = 106

-- Helpers (from SnapChar)
----------------------------------------------------------------------
local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function AnySecret(...)
    for i = 1, select("#", ...) do
        if IsSecret((select(i, ...))) then return true end
    end
    return false
end

-- Shows a value. Secret values pass straight through; nil shows a dash.
local function SetVal(fs, fmt, v)
    if IsSecret(v) then
        fs:SetFormattedText(fmt, v)
    elseif v == nil then
        fs:SetText("–")
    else
        fs:SetFormattedText(fmt, v)
    end
end

local function Atlas(parent, atlas, layer, sub, useSize)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    t:SetAtlas(atlas, useSize)
    return t
end

-- First texture with this atlas in a Blizzard frame, searching children
local function FindRegionByAtlas(frame, atlas)
    if not frame then return nil end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.GetAtlas and r:GetAtlas() == atlas then return r end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        local found = FindRegionByAtlas(child, atlas)
        if found then return found end
    end
end

-- Nine-slice margins from a Blizzard texture, so ornaments are not stretched
local function CopySlice(dst, src, fallback)
    if not dst.SetTextureSliceMargins then return end
    local l, t, r, b
    if src and src.GetTextureSliceMargins then
        local ok, a1, a2, a3, a4 = pcall(src.GetTextureSliceMargins, src)
        if ok then l, t, r, b = a1, a2, a3, a4 end
    end
    if not l or (l == 0 and t == 0 and r == 0 and b == 0) then
        if not fallback then return end
        l, t, r, b = fallback, fallback, fallback, fallback
    end
    dst:SetTextureSliceMargins(l, t, r, b)
    if dst.SetTextureSliceMode then
        local mode = src and src.GetTextureSliceMode and src:GetTextureSliceMode()
        if mode == nil and Enum and Enum.UITextureSliceMode then mode = Enum.UITextureSliceMode.Stretched end
        if mode ~= nil then dst:SetTextureSliceMode(mode) end
    end
end

-- Cuts the bottom rim off a background texture
local function CropBottom(tex, crop)
    local ulx, uly, llx, lly, urx = tex:GetTexCoord()
    if not (ulx and lly) then return end
    tex:SetTexCoord(ulx, urx, uly, uly + (lly - uly) * (1 - crop))
end

-- Client string if it exists, else the English fallback
local function L(keys, fallback)
    if type(keys) == "string" then keys = { keys } end
    for _, k in ipairs(keys) do
        local v = _G[k]
        if type(v) == "string" and v ~= "" then return v end
    end
    return fallback
end

local function WithColon(text)
    if text:find("[:：]%s*$") then return text end
    if type(STAT_FORMAT) == "string" then return STAT_FORMAT:format(text) end
    return text .. ":"
end

local function Shrink(fs)
    local font, size, flags = fs:GetFont()
    if font and size then fs:SetFont(font, size - FONT_SHRINK, flags) end
end
local classBackgrounds = {}

-- The side panels are three parts, each at its own insets (pixels from the
-- panel's top left and bottom right corners):
--   border  the ornate border
--   stat    the stat background
--   class   the class background
-- /journalpanel changes them in game.
local PANEL_DEFAULT = {
    border = { left = 6, right = 12, top = -2, bottom = -2 },
    stat   = { left = 10, right = 16, top = 12, bottom = 0 },
    class  = { left = 10, right = 20, top = 2, bottom = 0 },
	lborder = { left = 20, right = 14, top = 10, bottom = 20 },
    lstat   = { left = 24, right = 18, top = 14, bottom = 24 },
	profborder = { left = 4, right = 13, top = 0, bottom = 12 }, --168
	profstat   = { left = 8, right = 16, top = 4, bottom = 16 }, --172
}
local PANEL_GROUPS = { border = true, stat = true, class = true, lborder = true, lstat = true, profborder = true, profstat = true }
local PANEL_SIDES = { left = true, right = true, top = true, bottom = true }
local panelTextures = {}   -- { tex, host, group } for every texture of a panel

local FitClassBackground   -- declared early, because ApplyPanelInsets calls it

local function PanelInset(group)
    local saved = AJ.settings and AJ.settings.panelInset or {}
    local g = saved[group] or {}
    local function pick(side)
        return g[side] or saved[side] or PANEL_DEFAULT[group][side]   -- saved[side]: older settings
    end
    return { left = pick("left"), right = pick("right"), top = pick("top"), bottom = pick("bottom") }
end

local function PlaceInset(tex, host, group)
    local i = PanelInset(group)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", host, "TOPLEFT", i.left, -i.top)
    tex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -i.right, i.bottom)
end

local function TrackPanel(tex, host, group)
    panelTextures[#panelTextures + 1] = { tex = tex, host = host, group = group }
    PlaceInset(tex, host, group)
    return tex
end

-- Sets the corner size of an ornate border texture. The four corners keep
-- this size and the edges between them stretch. The corners cannot be
-- larger than half the box's width or height, so a box that small cannot
-- show a full corner.
local function SetBorderCorner(tex, corner)
    if not tex.SetTextureSliceMargins then return end
    local c = corner or BORDER_CORNER
    tex:SetTextureSliceMargins(c, c, c, c)
    if tex.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
        tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    end
end

-- An ornate border around `host`, placed by the panel inset for `group`,
-- on the given layer (BORDER unless stated).
local function FrameBorder(host, atlas, group, layer, corner)
    local tex = TrackPanel(Atlas(host, atlas, layer or "BORDER"), host, group)
    SetBorderCorner(tex, corner)
    return tex
end

local function ApplyPanelInsets()
    for _, p in ipairs(panelTextures) do PlaceInset(p.tex, p.host, p.group) end
    for _, c in ipairs(classBackgrounds) do
        if c.coords then FitClassBackground(c) end
    end
end

-- The stat list: its height in pixels (nil = the whole panel), and the insets
-- of its rows. /journalpanel list height <n>, row left|right <n>
local function StatListHeight()
    return (AJ.settings and AJ.settings.statListHeight) or 380
end

-- The rows stop short of the panel's edges: names stay at the left of a row,
-- the numbers at its right, so a larger right inset brings them together.
local function StatRowInset()
    local saved = AJ.settings and AJ.settings.statRowInset or {}
    return saved.left or 10, saved.right or 10
end

-- Where the stat list starts, from the panel's top left corner: `left` to the
-- right, `top` down. /journalpanel list left|top <n>
local function StatListOffset()
    local saved = AJ.settings and AJ.settings.statListOffset or {}
    return saved.left or 2, saved.top or 10
end

-- Places the stat list in its panel: the whole panel, or the height chosen.
-- Moved down, its top edge comes down and its bottom stays on the panel's.
local function PlaceList(listHost, panelHost)
    local h = StatListHeight()
    local ox, oy = StatListOffset()
    listHost:ClearAllPoints()
    listHost:SetPoint("TOPLEFT", panelHost, "TOPLEFT", ox, -oy)
    if h then
        listHost:SetPoint("TOPRIGHT", panelHost, "TOPRIGHT", ox, -oy)
        listHost:SetHeight(h)
    else
        listHost:SetPoint("BOTTOMRIGHT", panelHost, "BOTTOMRIGHT", ox, 0)
    end
end

local function AddClassBackground(parent)
    local t = parent:CreateTexture(nil, "BACKGROUND", nil, -6)
    t:Hide()
    local c = { tex = t, host = parent }
    classBackgrounds[#classBackgrounds + 1] = c
    -- refit whenever the panel changes size (folding, or a row opening it)
    parent:HookScript("OnSizeChanged", function()
        if c.coords then FitClassBackground(c) end
    end)
    return t
end

-- The class background keeps its scale: it fills the panel's width at its own
-- height, and is cut at the bottom when the panel is shorter (the equipment
-- manager's is, for its buttons). It is stretched only when the panel is taller.
function FitClassBackground(c)
    local t, host = c.tex, c.host
    local i = PanelInset("class")
    local hw = host:GetWidth() - i.left - i.right
    local hh = host:GetHeight() - i.top + i.bottom
    if not (hw and hh and hw > 0 and hh > 0) then return end
    local ulx, uly, llx, lly, urx, ury, lrx, lry = unpack(c.coords or { 0, 0, 0, 1, 1, 0, 1, 1 })
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", host, "TOPLEFT", i.left, -i.top)
    if c.nw and c.nh and c.nw > 0 and c.nh > 0 then
        local picH = c.nh * (hw / c.nw)   -- the picture at the panel's width
        if picH <= hh then
            t:SetSize(hw, picH)
            t:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
        else
            local f = hh / picH           -- the part of the picture that fits, from the top
            t:SetSize(hw, hh)
            t:SetTexCoord(ulx, uly, llx, uly + (lly - uly) * f, urx, ury, lrx, ury + (lry - ury) * f)
        end
    else
        t:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -i.right, i.bottom)
        t:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
    end
end

local function UpdateClassBackgrounds()
    local src = CharacterStatsPaneScrollBox and CharacterStatsPaneScrollBox.ClassBackground
    local atlas = src and src.GetAtlas and src:GetAtlas()
    local tex = src and src:GetTexture()
    for _, c in ipairs(classBackgrounds) do
        local t = c.tex
        if atlas or tex then
            t:ClearAllPoints()
            if atlas then t:SetAtlas(atlas, true) else t:SetTexture(tex) end
            c.nw, c.nh = t:GetWidth(), t:GetHeight()   -- the picture's own size
            if not (c.nw and c.nw > 0) and src then c.nw, c.nh = src:GetWidth(), src:GetHeight() end
            c.coords = { src:GetTexCoord() }
            t:SetVertexColor(src:GetVertexColor())
            t:SetAlpha(src:GetAlpha())
            t:SetBlendMode(src:GetBlendMode())
            t:Show()
            FitClassBackground(c)
        else
            t:Hide()
        end
    end
end

-- Blizzard's filigree ornament at the top centre of a border
local TOP_DETAIL_ATLAS = "QuestLog-frame-filigree"

local function FrameTopDetail(host, border)
    -- its own frame, above the host's child frames, so the stat list's header can't cover it
    local layer = CreateFrame("Frame", nil, host)
    layer:SetAllPoints(host)
    layer:SetFrameLevel(host:GetFrameLevel() + 50)
    local t = Atlas(layer, TOP_DETAIL_ATLAS, "OVERLAY")
    t:SetSize(48, 19)                                -- Blizzard's size
    t:SetPoint("TOP", border, "TOP", 0, 1)           -- Blizzard's anchor and offset
    t:SetVertexColor(border:GetVertexColor())
    t:SetAlpha(border:GetAlpha())
    return t
end

-- The side panel's look: the ornate border, the stat background and the class
-- background, inside the panel
local function DressPanel(host)
    local frameTex = FrameBorder(host, "common-insideframe", "border", "BORDER")
    FrameTopDetail(host, frameTex)
    local bg = TrackPanel(Atlas(host, "UI-Character-Info-Stat-BG", "BACKGROUND", -8), host, "stat")
    CropBottom(bg, BG_CROP_BOTTOM)
    AddClassBackground(host)
    return frameTex
end

-- The right panel of a tab, as the stat list has it: the same place, height
-- and insets, so every tab's right panel matches
local function MakeSideBox(rp, lp, frame)
    local ph = CreateFrame("Frame", nil, rp)
    ph:SetPoint("TOPLEFT", lp, "TOPRIGHT", 4, -6)
    ph:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 6)
    -- at the panel's own level: the text and controls the tab adds later sit above it
    ph:SetFrameLevel(rp:GetFrameLevel())
    local box = CreateFrame("Frame", nil, ph)
    box:SetFrameLevel(rp:GetFrameLevel())
    PlaceList(box, ph)
    DressPanel(box)
    return box
end

-- The same box with the stat background only: no ornate border and no class
-- background (the Settings tab)
local function BackgroundBox(rp, lp, frame)
    local ph = CreateFrame("Frame", nil, rp)
    ph:SetPoint("TOPLEFT", lp, "TOPRIGHT", 4, -6)
    ph:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 6)
    local box = CreateFrame("Frame", nil, ph)
    PlaceList(box, ph)
    local bg = TrackPanel(Atlas(box, "UI-Character-Info-Stat-BG", "BACKGROUND", -8), box, "stat")
    CropBottom(bg, BG_CROP_BOTTOM)
    return box
end

-- One tab's pane, shared by every list and panel tab: a frame over both halves
-- of the window (folded, it covers only the left page), the left page in the
-- General background with its border, and the right panel beside it.
-- opts: pageWidth (the left page's width), level (the frame's level above the
-- window's), pad = { x, top, bottom } (the text inset of the right panel), and
-- look ("background" for the plain panel of the Settings tab; otherwise the
-- full side panel). Returns { frame, lp, lbox, rp }: lbox is where the tab adds
-- its own parts to the left page, rp is the right panel's frame.
local function MakeTabPane(f, left, right, opts)
    local frame = CreateFrame("Frame", nil, f)
    frame:SetPoint("TOPLEFT", left, "TOPLEFT")
    frame:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
    frame:SetFrameLevel(f:GetFrameLevel() + opts.level)
    frame:Hide()
    frame:SetClipsChildren(true)   -- folded: the right half, and anything in it, is not drawn

    local lp = CreateFrame("Frame", nil, frame)
    lp:SetPoint("TOPLEFT")
    lp:SetPoint("BOTTOMLEFT")
    lp:SetWidth(opts.pageWidth)
    local lbox = CreateFrame("Frame", nil, lp)
    lbox:SetAllPoints(lp)
    local lbg = TrackPanel(Atlas(lbox, "UI-Character-Info-General-BG", "BACKGROUND", -8), lbox, "lstat")
    CropBottom(lbg, BG_CROP_BOTTOM)
	local lframe = FrameBorder(lbox, "common-insideframe", "lborder", "BORDER")
	FrameTopDetail(lbox, lframe)

    local rp = CreateFrame("Frame", nil, frame)
    rp:SetPoint("TOPLEFT", lp, "TOPRIGHT", opts.pad.x, -opts.pad.top)
    rp:SetPoint("BOTTOMRIGHT", -opts.pad.x, opts.pad.bottom)
    if opts.look == "background" then
        BackgroundBox(rp, lp, frame)
    else
        MakeSideBox(rp, lp, frame)
    end

    return { frame = frame, lp = lp, lbox = lbox, rp = rp }
end


AJ.Helpers = {
    AddClassBackground = AddClassBackground,
    AnySecret = AnySecret,
    ApplyPanelInsets = ApplyPanelInsets,
    Atlas = Atlas,
    BG_CROP_BOTTOM = BG_CROP_BOTTOM,
    BackgroundBox = BackgroundBox,
    CopySlice = CopySlice,
    FrameBorder = FrameBorder,
    SetBorderCorner = SetBorderCorner,
    CropBottom = CropBottom,
    DressPanel = DressPanel,
    FindRegionByAtlas = FindRegionByAtlas,
    IsSecret = IsSecret,
    L = L,
    MakeSideBox = MakeSideBox,
    MakeTabPane = MakeTabPane,
    PANEL_GROUPS = PANEL_GROUPS,
    PANEL_SIDES = PANEL_SIDES,
    PanelInset = PanelInset,
    PlaceList = PlaceList,
    SetVal = SetVal,
    Shrink = Shrink,
    StatListHeight = StatListHeight,
    StatListOffset = StatListOffset,
    StatRowInset = StatRowInset,
    TrackPanel = TrackPanel,
    UpdateClassBackgrounds = UpdateClassBackgrounds,
    WithColon = WithColon,
	FrameTopDetail = FrameTopDetail,
}
