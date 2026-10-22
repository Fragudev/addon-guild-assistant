local _, ns = ...

-- Which guild the player is in, as the key under which that guild's data is saved (db.guilds[key]).
--   "club:<clubId>"        when C_Club.GetGuildClubId() answers (stable across renames and transfers)
--   "name:<name>-<realm>"  otherwise (a renamed guild starts a new data set; the realm keeps equal names apart)
local GuildIdentity = {}

local function present(value)
  return type(value) == "string" and value ~= ""
end

local function validClubId(value)
  if type(value) == "number" then
    return value > 0
  end
  return present(value)
end

-- Returns { key, name, realm, source = "club" | "name" } or nil when the client has not told the guild yet (common for
-- a few seconds after login, even when IsInGuild() is true). `name` can be nil when only the club id is known.
function GuildIdentity.Current(platform)
  local name = platform.GetGuildName()
  if not present(name) then
    name = nil
  end
  local realm = platform.GetRealmName()
  if not present(realm) then
    realm = nil
  end

  local clubId = platform.GetGuildClubId()
  if validClubId(clubId) then
    return { key = ("club:%s"):format(tostring(clubId)), name = name, realm = realm, source = "club" }
  end
  if name and realm then
    return { key = ("name:%s-%s"):format(name, realm), name = name, realm = realm, source = "name" }
  end
  return nil
end

ns.GuildIdentity = GuildIdentity
