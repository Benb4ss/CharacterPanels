local ADDON_NAME, AJ = ...
_G.Journal = AJ
AJ.ADDON_NAME = ADDON_NAME

-- The core: the namespace, the saved data, a print helper and the slash
-- command. Everything else is in this folder.

local SCHEMA_VERSION = 1

local DEFAULTS = {
    schemaVersion = SCHEMA_VERSION,
    settings = {},
    characters = {},
}

local function CopyDefaults(dst, src)
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            CopyDefaults(dst[key], value)
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
AJ.VERSION = (getMetadata and getMetadata(ADDON_NAME, "Version")) or "unknown"

BINDING_HEADER_JOURNAL = "Journal"
BINDING_NAME_JOURNAL_CHARACTER = "Toggle character"
BINDING_NAME_JOURNAL_SPELLBOOK = "Toggle spellbook"
BINDING_NAME_JOURNAL_PROFESSIONS = "Toggle professions"

function AJ:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc66CharacterPanels:|r " .. tostring(message))
end

-- Fills a sentence with figures or names.
function AJ:Fill(text, ...)
    return string.format(text, ...)
end

-- Server time in seconds.
function AJ:Now()
    if GetServerTime then return GetServerTime() end
    return math.floor((GetTime and GetTime()) or 0)
end

function AJ:GetCharacterKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "UnknownRealm"
    return name .. "-" .. realm
end

local function Start()
    CharacterPanelsDB = CharacterPanelsDB or {}
    CopyDefaults(CharacterPanelsDB, DEFAULTS)
    AJ.db = CharacterPanelsDB
    AJ.settings = CharacterPanelsDB.settings

    local key = AJ:GetCharacterKey()
    AJ.characterKey = key
    CharacterPanelsDB.characters[key] = CharacterPanelsDB.characters[key] or {}
    AJ.char = CharacterPanelsDB.characters[key]

    AJ:Print(AJ:Fill("loaded (version %s).", tostring(AJ.VERSION)))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    Start()
end)

SLASH_JOURNAL1 = "/journal"
SlashCmdList.JOURNAL = function()
    AJ.UI:Toggle("character")
end