local _, ns = ...

-- Gate: the addon activates for any member of a guild, and keeps that guild's data apart from every other guild's.
local AccessGuard = {}

-- Returns true plus the guild identity (see GuildIdentity.Current), or false plus a reason code:
-- "not_in_guild" | "guild_unknown" (in a guild, but the client has not returned its identity yet: stay inactive
-- silently and ask again on the next guild event)
function AccessGuard.Evaluate(platform)
  if not platform.IsInGuild() then
    return false, "not_in_guild"
  end
  local identity = ns.GuildIdentity.Current(platform)
  if not identity then
    return false, "guild_unknown"
  end
  return true, identity
end

-- The same guild seen through the other key rule: the club id may be unavailable for a moment after login, so a
-- name key and a club key with the same guild name are not a guild change.
function AccessGuard.SameGuild(a, b)
  if a.key == b.key then
    return true
  end
  return a.source ~= b.source and a.name ~= nil and a.name == b.name
end

local Session = {}
Session.__index = Session

-- The access decisions of one play session, driven by the guild events. deps:
--   platform, dbError() -> truthy when the saved data is from a newer addon version,
--   activate(identity), deactivate(), inactive(reason)  state changes,
--   notify(reason) at most once for a reason that keeps the addon off (not_in_guild | incompatible_data),
--   notifyChange(identity or nil) once, when the player leaves or switches guild while the addon is active.
-- The services are wired to the guild they started with and are not re-wired live: after a change the addon stays
-- off until /reload.
function AccessGuard.NewSession(deps)
  return setmetatable({ deps = deps, noticed = false }, Session)
end

function Session:Change(identity)
  self.changed = true
  self.deps.deactivate()
  self.deps.notifyChange(identity)
end

function Session:Evaluate()
  local deps = self.deps
  if self.changed then
    return
  end
  local ok, result = AccessGuard.Evaluate(deps.platform)
  if ok and deps.dbError() then
    ok, result = false, "incompatible_data"
  end

  if self.identity then
    -- Active: only a definite change turns it off. An identity the client has not returned yet keeps it on.
    if ok then
      if not AccessGuard.SameGuild(self.identity, result) then
        self:Change(result)
      end
    elseif result == "not_in_guild" then
      self:Change(nil)
    end
    return
  end

  if ok then
    self.identity = result
    deps.activate(result)
    return
  end

  deps.inactive(result)
  if result ~= "guild_unknown" and not self.noticed then
    self.noticed = true
    deps.notify(result)
  end
end

ns.AccessGuard = AccessGuard
