-- The /ga slash command: the command words are case-insensitive, the text after them keeps its case.
local function load_slash(seen, identity)
  local function probe(name)
    return {
      Handle = function(action)
        seen[#seen + 1] = name .. ":" .. action
      end,
    }
  end
  local ns = {
    L = function(text)
      return text
    end,
    active = true,
    ViewModel = {
      HelpLines = function()
        return { "help line" }
      end,
    },
    pvpSeasonCommands = {
      Run = function(_, text)
        seen[#seen + 1] = "pvp:" .. text
        return { "pvp line" }
      end,
    },
    intelCommands = {
      Run = function(_, text)
        seen[#seen + 1] = "intel:" .. text
        return { "intel line" }
      end,
    },
    PvPProbe = probe("pvp"),
    LayerProbe = probe("layer"),
    Probe = probe("lockdown"),
    GetVersion = function()
      return "1.2.3"
    end,
    GuildIdentity = {
      Current = function()
        return identity.key and { key = identity.key, source = identity.source } or nil
      end,
    },
    Platform = {
      GetRealmName = function()
        return "RealmPvP"
      end,
      GetGuildName = function()
        return "Some Guild"
      end,
      GetGuildClubId = function()
        return identity.clubId
      end,
      GetFaction = function()
        return "Horde"
      end,
      IsChatMessagingLockedDown = function()
        return false
      end,
    },
  }
  _G.SlashCmdList = {}
  assert(loadfile("GuildAssistant/Commands/Slash.lua"))("GuildAssistant", ns)
  return ns
end

describe("/ga", function()
  local seen, printed, identity, realPrint, realGetBuildInfo

  before_each(function()
    seen = {}
    printed = {}
    identity = { clubId = 123, key = "club:123", source = "club" }
    load_slash(seen, identity)
    realPrint = _G.print
    realGetBuildInfo = _G.GetBuildInfo
    _G.GetBuildInfo = function()
      return "1.0", "1", "date", 16001
    end
    _G.print = function(line)
      printed[#printed + 1] = line
    end
  end)

  after_each(function()
    _G.print = realPrint
    _G.GetBuildInfo = realGetBuildInfo
  end)

  local function run(msg)
    _G.SlashCmdList.GUILDASSISTANT(msg)
  end

  it("takes the command word in any case and passes the rest of the text unchanged", function()
    run("PVP Grant Yonemon Gg M-1 40")
    assert.are.same({ "pvp:Grant Yonemon Gg M-1 40" }, seen)
  end)

  it("shows the identity the guild key is built from, with the type of the club id", function()
    run("debug identity")
    local output = table.concat(printed, "\n")
    assert.is_truthy(output:find("clubId: 123 (number)", 1, true))
    assert.is_truthy(output:find("guild key: club:123 (resolved by the club id)", 1, true))
    assert.is_truthy(output:find("faction: Horde", 1, true))
  end)

  it("tells a text club id from a number and falls back when the guild key is unknown", function()
    identity.clubId, identity.key = "123", nil
    run("debug identity")
    local output = table.concat(printed, "\n")
    assert.is_truthy(output:find("clubId: 123 (string)", 1, true))
    assert.is_truthy(output:find("guild key: unknown", 1, true))
  end)

  it("keeps the lowercase commands working as before", function()
    run("pvp Grant Yonemon Gg M-1 40")
    run("intel show")
    run("debug layer status")
    run("help")
    run("nonsense")
    assert.are.same({ "pvp:Grant Yonemon Gg M-1 40", "intel:show", "layer:status" }, seen)
    local output = table.concat(printed, "\n")
    assert.is_truthy(output:find("help line", 1, true))
    assert.is_truthy(output:find("unknown command 'nonsense'", 1, true))
  end)

  it("answers help in any case", function()
    run("HELP")
    assert.is_truthy(table.concat(printed, "\n"):find("help line", 1, true))
  end)

  it("sends /ga intel and its alias /ga spy to the Intel commands, keeping the text", function()
    run("Intel kos Bob gank Reason Here")
    run("SPY show")
    assert.are.same({ "intel:kos Bob gank Reason Here", "intel:show" }, seen)
    assert.are.same({ "intel line", "intel line" }, printed)
  end)

  it("says the addon is off for the Intel commands when it has not started", function()
    local ns = load_slash(seen)
    ns.active = false
    ns.GetVersion = function()
      return "1.0"
    end
    run("intel show")
    assert.are.same({}, seen)
    assert.is_truthy(printed[1]:find("addon disabled", 1, true))
  end)

  it("takes the debug subcommand and action in any case, and passes the action lowercase", function()
    run("Debug LAYER Status")
    run("DEBUG Pvp Start")
    run("debug LockDown Send")
    assert.are.same({ "layer:status", "pvp:start", "lockdown:send" }, seen)
  end)

  it("reports an unknown command with the text as the user typed it", function()
    run("Frobnicate")
    assert.is_truthy(table.concat(printed, "\n"):find("unknown command 'Frobnicate'", 1, true))
  end)
end)
