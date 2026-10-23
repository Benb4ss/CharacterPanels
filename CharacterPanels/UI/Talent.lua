
local _, AJ = ...

local UI = AJ.UI
local W = UI.Widgets

local TABS = {
    { key = "character",   label = "Character Info",   icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "professions", label = "Professions", icon = "Professions-up-c60" }, --Interface\\Icons\\INV_SideTab_Professions_c60"
    { key = "spellbook",   label = "Spellbook",   icon = "Spellbook-up-c60" }, --Interface\\Icons\\INV_Misc_Book_08
	{ key = "legacy",      label = "Legacy",      icon = "Legacy-up-c60" },
}

local legacyPreload = CreateFrame("Frame")
local legacyTexture = legacyPreload:CreateTexture(nil, "ARTWORK")
legacyTexture:SetSize(200, 275)
legacyTexture:SetAtlas("Legacy-up-c60")


local professionsPreload = CreateFrame("Frame")
local professionsTexture = professionsPreload:CreateTexture(nil, "ARTWORK")
professionsTexture:SetSize(250, 250)
professionsTexture:SetAtlas("Professions-up-c60")

local spellbookPreload = CreateFrame("Frame")
local spellbookTexture = spellbookPreload:CreateTexture(nil, "ARTWORK")
spellbookTexture:SetSize(250, 250)
spellbookTexture:SetAtlas("Spellbook-up-c60")



local TAB_TEMPLATE = "TabSystemButtonArtTemplate"
local TAB_W, TAB_H = 151, 32
local TAB_GAP = 1

local strip
local tabs = {}
local host


local function FrameOf(key)
    for _, section in ipairs(UI:GetSections()) do
        if section.key == key then
            return section.frame
        end
    end
end

local function UpdateTabs()
    if not strip or not host then
        return
    end

    for _, tab in ipairs(tabs) do
        local frame = FrameOf(tab.key)
        tab:SetTabSelected(frame ~= nil and frame:IsShown())
    end
end

local function Open(key)
    if InCombatLockdown() then
        AJ:Print("Panels cannot be opened in combat.")
        return
    end

	W.PlayUISound(W.Sounds.PAGE)

	if key == "legacy" then
		ToggleLegacySystemUI()
		return
	end

	PlayerSpellsFrame:Hide()
	UI:Open(key)
	UpdateTabs()
end

local function Build()
    if strip or not PlayerSpellsFrame
        or not PlayerSpellsFrame.TalentsFrame then
        return
    end

    host = PlayerSpellsFrame.TalentsFrame

    strip = CreateFrame(
        "Frame",
        "CharacterPanelsTalentTabs",
        host
    )
strip:SetFrameStrata("DIALOG")
strip:EnableMouse(true)
    strip:SetSize(
        #TABS * TAB_W + (#TABS - 1) * TAB_GAP,
        TAB_H
    )

    strip:SetPoint("TOPLEFT", host, "TOPLEFT", 68, -18)
    strip:SetFrameLevel(host:GetFrameLevel() + 100)
	strip:EnableMouse(true)



for i, info in ipairs(TABS) do
    local tab = CreateFrame(
        "Button",
        nil,
        strip,
        TAB_TEMPLATE
    )

    tab:SetFrameStrata("DIALOG")
    tab:SetFrameLevel(strip:GetFrameLevel() + 1)
    tab:EnableMouse(true)

    tab:SetSize(
        TAB_W,
        TAB_H
    )

        tab:SetPoint(
            "LEFT",
            strip,
            "LEFT",
            (i - 1) * (TAB_W + TAB_GAP),
            0
        )

        tab.isTabOnTop = true
        tab.selectedFontObject = GameFontNormal
        tab.unselectedFontObject = GameFontHighlight
		
		local hoverFont = CreateFont("CharacterPanelsTab_" .. info.key .. "_Hover")
		hoverFont:CopyFontObject(GameFontHighlight)
		hoverFont:SetTextColor(1, 0.82, 0, 1)
		tab:SetHighlightFontObject(hoverFont)

		tab:HandleRotation()
		tab:SetText("     " .. info.label)

		local icon = tab:CreateTexture(nil, "ARTWORK")
		if info.key == "legacy" then
			icon:SetSize(26, 35)
			icon:SetPoint("LEFT", tab, "LEFT", 12, 0)
		elseif info.key == "professions" then
			icon:SetSize(32, 32)
			icon:SetPoint("LEFT", tab, "LEFT", 12, 0)
		elseif info.key == "spellbook" then
			icon:SetSize(36, 36)
			icon:SetPoint("LEFT", tab, "LEFT", 12, 0)
		else
			icon:SetSize(26, 26)
			icon:SetPoint("LEFT", tab, "LEFT", 12, -2)
		end
		--icon:SetPoint("LEFT", tab, "LEFT", 12, -2)

		if info.key == "legacy" or info.key == "professions" or info.key == "spellbook" then
			icon:SetAtlas(info.icon)
		else
			icon:SetTexture(info.icon)
		end

        tab.key = info.key
		local oldOnEnter = tab:GetScript("OnEnter")
		local oldOnLeave = tab:GetScript("OnLeave")
		tab:SetScript("OnEnter", function(self, ...)
			if oldOnEnter then oldOnEnter(self, ...) end
			icon:SetScale(1.08)
		end)
		tab:SetScript("OnLeave", function(self, ...)
			if oldOnLeave then oldOnLeave(self, ...) end
			icon:SetScale(1)
		end)
        tab:SetScript("OnClick", function()
            Open(info.key)
        end)
		tab:EnableMouse(true)
		tab:SetFrameLevel(strip:GetFrameLevel() + 1)

        tabs[i] = tab
    end

    host:HookScript("OnShow", UpdateTabs)

    -- Any panel opened through UI:Open closes the talent frame.
    -- Skipped in combat, as in Open().
    hooksecurefunc(UI, "Open", function()
        if not InCombatLockdown() and PlayerSpellsFrame:IsShown() then
            PlayerSpellsFrame:Hide()
        end
    end)

    UpdateTabs()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")

loader:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED"
        and name ~= "Blizzard_PlayerSpells" then
        return
    end

    Build()
end)
