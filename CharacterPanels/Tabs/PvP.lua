-- SnapChar – PvP tab (tab 5)
-- Forever's new rank system has no public data function.
-- So we borrow Blizzard's own PvP window (PVPRankFrame) into our frame.
-- It calculates rank, points, countdown and rewards itself. When the original
-- window opens, we give it back.

local ADDON, ns = ...
local L = ns.L


local pvpTab = ns.CreateBorrowTab("PVPRankFrame", function(bf, lp, rp, move)
    move(bf.MainInfoFrame, "TOPLEFT", lp, "TOPLEFT", 0, 0)
    if bf.MainInfoFrame then
        bf.MainInfoFrame:SetPoint("BOTTOMRIGHT", lp, "BOTTOMRIGHT", 0, 0)
        bf.MainInfoFrame:SetFrameLevel(lp:GetFrameLevel() + 2)
    end
    move(bf.DetailFrame, "TOPLEFT", rp, "TOPLEFT", 8, -20)
    if bf.DetailFrame then
        bf.DetailFrame:SetPoint("BOTTOMRIGHT", rp, "BOTTOMRIGHT", -8, 8)
        bf.DetailFrame:SetFrameLevel(rp:GetFrameLevel() + 2)
    end
end)

ns.RegisterTab(5, "pvp", pvpTab, L({ "CHARACTER_FRAME_TAB_PVP", "PVP" }, "Player vs. Player"))

-- Tab icon: Alliance or Horde badge instead of the fist (tooltip stays the same)
local iconFrame = CreateFrame("Frame")
iconFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
iconFrame:SetScript("OnEvent", function(self)
    local faction = UnitFactionGroup("player")
    local badge = faction and ("UI-Character-Info-Honor-Icon-" .. faction)
    if badge and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(badge) then
        local icon = ns.modeTabs[5].icon
        icon:SetAtlas(badge)
        -- crop to the inner area, like the other tab icons
        if ns.CropTabIcon then
            local ulx, uly, _, lly, urx = icon:GetTexCoord()
            ns.CropTabIcon(icon, ulx, urx, uly, lly)
        end
        self:UnregisterAllEvents()
    end
end)