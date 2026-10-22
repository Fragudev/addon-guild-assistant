local function load_guard()
  local ns = {}
  assert(loadfile("GuildAssistant/Core/GuildIdentity.lua"))("GuildAssistant", ns)
  assert(loadfile("GuildAssistant/Core/AccessGuard.lua"))("GuildAssistant", ns)
  return ns.AccessGuard
end

local function fake_platform(overrides)
  local p = {
    inGuild = true,
    clubId = 123,
    guildName = "Some Guild",
    realm = "Realm",
  }
  for k, v in pairs(overrides or {}) do
    p[k] = v
  end
  -- The accessors read the fields, so a test can change the guild between two evaluations.
  local platform = {}
  platform.state = p
  platform.IsInGuild = function()
    return p.inGuild
  end
  platform.GetGuildClubId = function()
    return p.clubId
  end
  platform.GetGuildName = function()
    return p.guildName
  end
  platform.GetRealmName = function()
    return p.realm
  end
  return platform
end

describe("AccessGuard.Evaluate", function()
  local guard = load_guard()

  it("allows a member of any guild and returns its identity", function()
    local ok, identity = guard.Evaluate(fake_platform())
    assert.is_true(ok)
    assert.are.equal("club:123", identity.key)
  end)

  it("allows a member whose guild is only known by name", function()
    local ok, identity = guard.Evaluate(fake_platform({ clubId = false }))
    assert.is_true(ok)
    assert.are.equal("name:Some Guild-Realm", identity.key)
  end)

  it("does not look at the faction or the realm ruleset", function()
    assert.is_true((guard.Evaluate(fake_platform({ realm = "ClassicNormal" }))))
  end)

  it("rejects players without a guild", function()
    local ok, reason = guard.Evaluate(fake_platform({ inGuild = false }))
    assert.is_false(ok)
    assert.are.equal("not_in_guild", reason)
  end)

  it("reports an unknown guild when the client has not returned its identity yet", function()
    local ok, reason = guard.Evaluate(fake_platform({ clubId = false, guildName = false }))
    assert.is_false(ok)
    assert.are.equal("guild_unknown", reason)
  end)
end)

describe("AccessGuard.SameGuild", function()
  local guard = load_guard()

  it("compares keys", function()
    assert.is_true(guard.SameGuild({ key = "club:1" }, { key = "club:1" }))
    assert.is_false(guard.SameGuild({ key = "club:1", source = "club" }, { key = "club:2", source = "club" }))
  end)

  it("does not call a switch from the name key to the club key of the same name a change", function()
    local byName = { key = "name:G-R", source = "name", name = "G" }
    local byClub = { key = "club:1", source = "club", name = "G" }
    assert.is_true(guard.SameGuild(byName, byClub))
    assert.is_true(guard.SameGuild(byClub, byName))
    assert.is_false(guard.SameGuild(byName, { key = "club:2", source = "club", name = "Other" }))
  end)
end)

describe("AccessGuard session", function()
  local guard = load_guard()

  local function new_session(platform, dbError)
    local env = { platform = platform, activated = {}, notices = {}, changes = {}, inactive = {}, deactivated = 0 }
    env.session = guard.NewSession({
      platform = platform,
      dbError = function()
        return dbError
      end,
      activate = function(identity)
        env.activated[#env.activated + 1] = identity.key
      end,
      inactive = function(reason)
        env.inactive[#env.inactive + 1] = reason
      end,
      deactivate = function()
        env.deactivated = env.deactivated + 1
      end,
      notify = function(reason)
        env.notices[#env.notices + 1] = reason
      end,
      notifyChange = function(identity)
        env.changes[#env.changes + 1] = identity and identity.key or "none"
      end,
    })
    return env
  end

  it("activates once for a guild member", function()
    local env = new_session(fake_platform())
    env.session:Evaluate()
    env.session:Evaluate()
    assert.are.same({ "club:123" }, env.activated)
    assert.are.same({}, env.notices)
  end)

  it("tells a player without a guild once", function()
    local env = new_session(fake_platform({ inGuild = false }))
    env.session:Evaluate()
    env.session:Evaluate()
    assert.are.same({}, env.activated)
    assert.are.same({ "not_in_guild" }, env.notices)
  end)

  it("stays off silently while the guild is unknown and activates when it is known", function()
    local platform = fake_platform({ clubId = false, guildName = false })
    local env = new_session(platform)
    env.session:Evaluate()
    env.session:Evaluate()
    assert.are.same({}, env.activated)
    assert.are.same({}, env.notices)
    assert.are.same({ "guild_unknown", "guild_unknown" }, env.inactive)
    platform.state.clubId = 77
    env.session:Evaluate()
    assert.are.same({ "club:77" }, env.activated)
  end)

  it("activates when the player joins a guild after login", function()
    local platform = fake_platform({ inGuild = false })
    local env = new_session(platform)
    env.session:Evaluate()
    platform.state.inGuild = true
    env.session:Evaluate()
    assert.are.same({ "club:123" }, env.activated)
  end)

  it("keeps the saved data from a newer version off, with one notice", function()
    local env = new_session(fake_platform(), "newer_schema")
    env.session:Evaluate()
    env.session:Evaluate()
    assert.are.same({}, env.activated)
    assert.are.same({ "incompatible_data" }, env.notices)
  end)

  it("deactivates once and shows one notice when the player switches guild", function()
    local platform = fake_platform()
    local env = new_session(platform)
    env.session:Evaluate()
    platform.state.clubId = 999
    env.session:Evaluate()
    env.session:Evaluate()
    assert.are.equal(1, env.deactivated)
    assert.are.same({ "club:999" }, env.changes)
    assert.are.same({ "club:123" }, env.activated)
  end)

  it("deactivates once when the player leaves the guild, and does not come back by itself", function()
    local platform = fake_platform()
    local env = new_session(platform)
    env.session:Evaluate()
    platform.state.inGuild = false
    env.session:Evaluate()
    platform.state.inGuild = true
    env.session:Evaluate()
    assert.are.equal(1, env.deactivated)
    assert.are.same({ "none" }, env.changes)
    assert.are.same({ "club:123" }, env.activated)
  end)

  it("stays active while the client briefly does not return the guild", function()
    local platform = fake_platform()
    local env = new_session(platform)
    env.session:Evaluate()
    platform.state.clubId = false
    platform.state.guildName = false
    env.session:Evaluate()
    assert.are.equal(0, env.deactivated)
    assert.are.same({}, env.changes)
  end)

  it("does not treat the club id appearing after a name key as a guild change", function()
    local platform = fake_platform({ clubId = false })
    local env = new_session(platform)
    env.session:Evaluate()
    assert.are.same({ "name:Some Guild-Realm" }, env.activated)
    platform.state.clubId = 123
    env.session:Evaluate()
    assert.are.equal(0, env.deactivated)
  end)
end)
