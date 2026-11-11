describe("Constants", function()
  local ns

  before_each(function()
    ns = {}
    assert(loadfile("GuildAssistant/Core/Constants.lua"))("GuildAssistant", ns)
  end)

  it("exposes the addon message prefix", function()
    assert.are.equal("GUILDASST", ns.Constants.ADDON_PREFIX)
  end)

  it("is at schema version 18", function()
    assert.are.equal(18, ns.Constants.SCHEMA_VERSION)
  end)

  it("keeps a position message inside its size limit and the directory inside the rate limit", function()
    local constants = ns.Constants
    assert.are.equal("GUILDASSTPOS", constants.POSITION_PREFIX)
    assert.are_not.equal(constants.ADDON_PREFIX, constants.POSITION_PREFIX)
    -- The longest message: "P1:" + a map of up to four digits + two coordinates of up to five digits + two colons.
    local longest = #("P1:%d:%d:%d"):format(constants.LAYER_MAP_MAX, constants.POSITION_SCALE, constants.POSITION_SCALE)
    assert.is_true(longest <= constants.POSITION_MAX_BYTES)
    assert.is_true(constants.POSITION_HEARTBEAT_SECONDS > constants.POSITION_TICK_SECONDS)
    assert.is_true(constants.POSITION_TTL > constants.POSITION_HEARTBEAT_SECONDS)
  end)

  it("takes roles from the guild rank index and matches no rank name", function()
    assert.are.equal(0, ns.Constants.GUILD_MASTER_RANK_INDEX)
    assert.is_nil(ns.Constants.ROLE_SOURCE)
    assert.is_nil(ns.Constants.ASSIGNABLE_ROLES)
    assert.is_nil(ns.Constants.RANK_ROLES)
    assert.is_false(ns.Constants.BETA_ADMIN_ENABLED)
    assert.is_nil(ns.Constants.BETA_ADMIN_NAMES)
  end)

  it("defines PvP ranks with names and thresholds that keep going up", function()
    local ranks = ns.Constants.PVP_RANKS
    assert.are.equal(14, #ranks)
    local previous = -1
    for i, rank in ipairs(ranks) do
      assert.is_true(type(rank.name) == "string" and rank.name ~= "", "rank " .. i .. " has no name")
      assert.is_true(type(rank.kills) == "number" and rank.kills % 1 == 0, "rank " .. i .. " needs whole kills")
      assert.is_true(rank.kills > previous, "rank " .. i .. " does not go up")
      previous = rank.kills
    end
    assert.are.equal(0, ranks[1].kills)
  end)
end)

describe("Addon load", function()
  it("loads every file listed in the TOC and registers the /ga slash command", function()
    dofile("tests/support/addon.lua")({})
    assert.is_function(SlashCmdList.GUILDASSISTANT)
  end)

  local function run(command)
    dofile("tests/support/addon.lua")({})
    local printed = {}
    local original = _G.print
    _G.print = function(text)
      printed[#printed + 1] = text
    end
    local ok, err = pcall(SlashCmdList.GUILDASSISTANT, command)
    _G.print = original
    assert(ok, err)
    return table.concat(printed, "\n")
  end

  it("prints the version for a bare /ga while the addon is disabled", function()
    assert.is_truthy(run(""):find("version dev", 1, true))
  end)

  it("lists the three commands for /ga help", function()
    local text = run("help")
    assert.is_truthy(text:find("/ga debug", 1, true))
    assert.is_nil(text:find("/ga event", 1, true))
  end)

  it("points to help for a command that is not there, including the ones that moved into the window", function()
    for _, command in ipairs({
      "frobnicate",
      "version",
      "profile",
      "ready",
      "sync",
      "publish",
      "event",
      "attendance",
      "assign",
      "export",
      "import",
      "loot",
      "report",
      "template",
      "minimap",
      "blacklist",
      "role",
    }) do
      local text = run(command)
      assert.is_truthy(text:find("unknown command '" .. command .. "'", 1, true), command)
      assert.is_truthy(text:find("/ga help", 1, true), command)
    end
  end)

  it("keeps the interim PvP season commands out of the help, and says the addon is disabled", function()
    assert.is_nil(run("help"):find("/ga pvp", 1, true))
    assert.is_truthy(run("pvp season"):find("addon disabled", 1, true))
  end)

  it("lists the layer probe in the debug usage", function()
    assert.is_truthy(run("debug"):find("layer <action>", 1, true))
  end)

  it("answers the layer probe actions while the addon is disabled", function()
    assert.is_truthy(run("debug layer"):find("usage: /ga debug layer start", 1, true))
    assert.is_truthy(run("debug layer start"):find("probe unavailable", 1, true))
    assert.is_truthy(run("debug layer stop"):find("probe is not running", 1, true))
    assert.is_truthy(run("debug layer log"):find("no log yet", 1, true))
    assert.is_truthy(run("debug layer clear"):find("log cleared", 1, true))
    assert.is_truthy(run("debug layer status"):find("layer: unknown", 1, true))
  end)
end)
