local _, AJ = ...

-- The window manager. It owns the list of tabs and what they have in common:
-- building them on first open, switching between them and wiring their tabs.
-- It knows no tab by name.
--
-- Adding a tab (see Sections.lua):
--   local Section = UI:NewSection("key", { label = "Tab", icon = "...", order = 10 })
--   function Section:Create() ... return frame end
-- Optional: Section:Refresh() is called each time the tab is opened.

local UI = {}
AJ.UI = UI
UI.Widgets = {}
UI.Components = {}
local C = UI.Components

local sections = {}
local ordered = {}

local function CompareSections(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.index < b.index
end

function UI:NewSection(key, section)
    section = section or {}
    if type(key) ~= "string" or key == "" then
        error("UI:NewSection needs a key", 2)
    end
    if sections[key] then
        error("UI section '" .. key .. "' is already registered", 2)
    end

    section.key = key
    section.label = section.label or key
    section.index = #ordered + 1
    section.order = section.order or section.index * 10

    sections[key] = section
    table.insert(ordered, section)
    table.sort(ordered, CompareSections)
    return section
end

function UI:GetSections()
    return ordered
end

-- The tabs, in tab order. Components reads this when a window gives none of its own.
function UI:GetTabs()
    return ordered
end

local function ReportError(message)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(message) end
end

-- Builds a section's window the first time it is needed. A section that
-- fails reports its error and is left out; the others keep working.
local function EnsureBuilt(section)
    if section.ready then return true end

    local ok, frame = xpcall(function() return section:Create() end, ReportError)
    if not ok or not frame then return false end

    section.frame = frame
    C.CreateTabs(frame, section.key)
    -- HookScript, not SetScript: CreateWindow already hooks OnShow.
    --frame:HookScript("OnShow", function() C.ApplyFrameTabs(frame, section.key) end)
    section.ready = true
    return true
end

-- Redraws the tabs of every window built so far.
function UI:UpdateTabs()
    for _, section in ipairs(ordered) do
        if section.ready then C.ApplyFrameTabs(section.frame, section.key) end
    end
end

function UI:HideAll()
    for _, section in ipairs(ordered) do
        if section.frame and section.frame:IsShown() then
            C.HideLeftPanel(section.frame)
        end
    end
end

-- The round portrait at the top left of every window shows the player
local function SetPlayerPortrait(frame)
    local tex = frame.portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)
    if tex then SetPortraitTexture(tex, "player") end
end

function UI:Open(key)
    local section = sections[key]
    if not section then return end

    if not EnsureBuilt(section) then
        AJ:Print(AJ:Fill("could not open %s.", section.label))
        return
    end

    if section.Refresh then section:Refresh() end
    SetPlayerPortrait(section.frame)
    self:HideAll()
    C.ShowLeftPanel(section.frame)
end

function UI:Refresh(key)
    local section = sections[key]
    if section and section.ready and section.Refresh then
        section:Refresh()
    end
end

function UI:Toggle(key)
    local section = sections[key]
    if not section then return end

    if section.ready and section.frame:IsShown() then
        C.HideLeftPanel(section.frame)
    else
        self:Open(key)
    end
end