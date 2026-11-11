local _, ns = ...

-- Account-wide settings (db.settings), read and written through these functions so every default lives in one
-- place and a damaged value never raises:
--   language        "auto" | "es" | "en"   the language of the window (auto follows the game client)
--   blacklistSound  boolean                the sound of the blacklist alert (the chat line and the warning stay)
-- The minimap button keeps its own settings (MinimapButton.Settings) and the window positions theirs. The module
-- switches are here too (settings.modules.off, see ModulesOff).
local Settings = {}

Settings.LANGUAGES = { "auto", "es", "en" }

local function settingsOf(db)
  db.settings = type(db.settings) == "table" and db.settings or {}
  return db.settings
end

-- "auto" | "es" | "en".
function Settings.Language(db)
  local value = settingsOf(db).language
  for _, language in ipairs(Settings.LANGUAGES) do
    if value == language then
      return value
    end
  end
  return "auto"
end

-- Returns true, or false plus "invalid" for something that is not one of Settings.LANGUAGES.
function Settings.SetLanguage(db, value)
  for _, language in ipairs(Settings.LANGUAGES) do
    if value == language then
      settingsOf(db).language = value
      return true
    end
  end
  return false, "invalid"
end

-- true unless the player switched the alert sound off.
function Settings.BlacklistSound(db)
  return settingsOf(db).blacklistSound ~= false
end

function Settings.SetBlacklistSound(db, enabled)
  settingsOf(db).blacklistSound = enabled ~= false
end

-- The modules the player turned off (settings.modules.off, a set of module ids). Account-wide, like every other
-- setting, and created on first use. An entry that is not `true` is dropped; ids of modules this version does not
-- know are kept, so a newer version's switches survive. Returns the live set.
function Settings.ModulesOff(db)
  local settings = settingsOf(db)
  if type(settings.modules) ~= "table" then
    settings.modules = {}
  end
  if type(settings.modules.off) ~= "table" then
    settings.modules.off = {}
  end
  local off = settings.modules.off
  for key, value in pairs(off) do
    if type(key) ~= "string" or value ~= true then
      off[key] = nil
    end
  end
  return off
end

-- Turns a module switch off (`off` true) or back on (`off` false or nil); the other switches are left alone.
function Settings.SetModuleOff(db, id, off)
  Settings.ModulesOff(db)[id] = off == true or nil
end

ns.Settings = Settings
