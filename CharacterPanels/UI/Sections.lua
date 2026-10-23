local _, AJ = ...

-- Placeholder tabs. Each names the page size it opens in (see Layouts.lua).
-- To change a tab's size, change its name in TAB_LAYOUTS.

local UI = AJ.UI
local W = UI.Widgets

local IMAGE = "Interface\\AddOns\\Journal\\Assets\\Placeholder.tga"
local ICON = "Interface\\AddOns\\Journal\\Assets\\Icon.tga"
-- The fade: opaque in the middle, transparent toward the edges (Assets/RadialFade.tga)
local FADE = "Interface\\AddOns\\Journal\\Assets\\RadialFade.tga"
local PRIEST_IMAGE = "Interface\\AddOns\\Journal\\Assets\\Priest.tga"
local IMAGE_SIZE = 160
local TAB_COUNT = 0

-- The size of each tab, by its number. Any name in UI.Layouts works here.
local TAB_LAYOUTS = {
    [1] = "singleLeft",
    [2] = "singleRight",
}

local function Title(page, text)
    local title = page:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(text)
    W.ApplyQuestTextColor(title, true)
    W.AddRule(page, 16, -16, -43)
    return title
end

-- Placeholder text, under `anchor` if given, otherwise at the top of the page.
local function Body(page, text, width, anchor)
    local body = page:CreateFontString(nil, "ARTWORK", "QuestFont")
    if anchor then
        body:SetPoint("TOP", anchor, "BOTTOM", 0, -16)
    else
        body:SetPoint("TOP", 0, -70)
    end
    body:SetWidth(width)
    body:SetJustifyH("CENTER")
    body:SetText(text)
    W.ApplyQuestTextColor(body, false)
    return body
end

-- A picture that fades out from the inside toward its edges: a radial mask
-- over the image.
local function FadedImage(page, texture, size, yOffset)
    local image = page:CreateTexture(nil, "ARTWORK")
    image:SetSize(size, size)
    image:SetPoint("TOP", 0, yOffset)
    image:SetTexture(texture)
    local mask = page:CreateMaskTexture()
    mask:SetTexture(FADE)
    mask:SetAllPoints(image)
    image:AddMaskTexture(mask)
    return image
end

-- The placeholder picture, faded, with its text under it.
local function Picture(page, pageWidth)
    local image = FadedImage(page, PRIEST_IMAGE, IMAGE_SIZE, -70)
    Body(page, "Placeholder text.", pageWidth - 40, image)
end

local function Build(section, name)
    local frame, left, right = UI:CreateLayoutWindow(name, "Journal_" .. section.key .. "Frame", section.label)
    local leftWidth, rightWidth = UI:PageWidths(name)

    if not right then
        -- One page: the title centred at the top, then the picture and text.
        local header = left:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
        header:SetPoint("TOP", 0, -15)
        header:SetText(section.label)
        W.ApplyQuestTextColor(header, true)
        Picture(left, leftWidth)
        return frame
    end

    Title(left, section.label)
    Picture(left, leftWidth)

    Title(right, "Placeholder")
    Body(right, "Placeholder text.", rightWidth - 40)

    return frame
end

for index = 1, TAB_COUNT do
    local Section = UI:NewSection("tab" .. index, {
        label = "Tab " .. index,
        icon = ICON,
        order = index * 50,
    })
    function Section:Create()
        return Build(self, TAB_LAYOUTS[index])
    end
end