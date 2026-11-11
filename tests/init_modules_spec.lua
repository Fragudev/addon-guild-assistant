-- Core/Init.lua wires the whole addon at load time, so these specs load every file in TOC order, replace the
-- client-facing pieces with spies and drive the real event handlers. The module switches are read from the account
-- settings, so a switch saved before the login applies at the activation.
local function build()
  local frames, printed = {}, {}
  local saved = {
    CreateFrame = _G.CreateFrame,
    print = _G.print,
    C_Timer = _G.C_Timer,
    GuildAssistantDB = _G.GuildAssistantDB,
  }

  _G.CreateFrame = function()
    local frame = { events = {} }
    function frame:RegisterEvent(event)
      self.events[event] = true
    end
    function frame:UnregisterEvent(event)
      self.events[event] = nil
    end
    function frame:SetScript(name, fn)
      self[name] = fn
    end
    frames[#frames + 1] = frame
    return frame
  end
  _G.print = function(text)
    printed[#printed + 1] = text
  end
  _G.C_Timer = {
    After = function() end,
    NewTicker = function() end,
  }
  _G.GuildAssistantDB = nil

  local ns = {}
  dofile("tests/support/addon.lua")(ns)

  local platform = ns.Platform
  platform.Now = function()
    return 1000
  end
  platform.ServerTime = os.time
  platform.IsInGuild = function()
    return true
  end
  platform.GetGuildName = function()
    return "Test Guild"
  end
  platform.GetRealmName = function()
    return "Realm"
  end
  platform.GetGuildClubId = function()
    return nil
  end
  platform.GetLegacyIdentityKey = function()
    return "Me-Realm"
  end
  platform.LootWindowAvailable = function()
    return true
  end

  local calls = {}
  local function spy(owner, name, label)
    owner[name] = function()
      calls[#calls + 1] = label
    end
  end
  ns.Comm.Start = function()
    calls[#calls + 1] = "comm"
    ns.comm = ns.comm or {}
    return ns.comm
  end
  spy(ns.MinimapButton, "Create", "minimap")
  spy(ns.MinimapButton, "Refresh", "minimapRefresh")
  spy(ns.LootPopup, "Start", "lootPopup")
  spy(ns.VotingFrame, "Start", "votingFrame")
  ns.GuildRoster.New = function()
    calls[#calls + 1] = "roster"
    return {
      Request = function() end,
      Rebuild = function() end,
      Reset = function() end,
    }
  end
  ns.ProfileService.Refresh = function() end
  ns.EventService.Purge = function() end

  local env = { ns = ns, frames = frames, printed = printed, calls = calls }

  -- The addon frame is the first one created by Init.lua that listens to PLAYER_LOGIN.
  function env.mainFrame()
    for _, frame in ipairs(frames) do
      if frame.events.PLAYER_LOGIN then
        return frame
      end
    end
  end

  function env.fire(event, ...)
    env.mainFrame().OnEvent(env.mainFrame(), event, ...)
  end

  -- The saved database: the switches are in its account settings, so one saved before the login applies at the
  -- activation.
  function env.root()
    return ns.root
  end

  function env.restore()
    _G.CreateFrame = saved.CreateFrame
    _G.print = saved.print
    _G.C_Timer = saved.C_Timer
    _G.GuildAssistantDB = saved.GuildAssistantDB
  end
  return env
end

describe("Init modules", function()
  local env

  before_each(function()
    env = build()
  end)

  after_each(function()
    env.restore()
  end)

  it("skips the activation steps of a module that is off, and lists them in ns.skippedSteps", function()
    env.fire("ADDON_LOADED", "GuildAssistant")
    env.ns.Settings.SetModuleOff(env.root(), "loot", true)
    env.fire("PLAYER_LOGIN")
    assert.is_true(env.ns.active)
    local ran = table.concat(env.calls, ",")
    assert.is_nil(ran:find("lootPopup", 1, true))
    assert.is_nil(ran:find("votingFrame", 1, true))
    assert.is_truthy(ran:find("comm", 1, true))
    assert.are.same({ "lootPopup", "votingFrame", "bossLoot" }, env.ns.skippedSteps)
  end)

  it("does not start the features of a module that is off", function()
    env.fire("ADDON_LOADED", "GuildAssistant")
    env.ns.Settings.SetModuleOff(env.root(), "pvp", true)
    env.ns.Settings.SetModuleOff(env.root(), "layers", true)
    env.fire("PLAYER_LOGIN")
    assert.is_true(env.ns.active)
    assert.is_nil(env.ns.pvpTracker)
    assert.is_nil(env.ns.pvpSeason)
    assert.is_nil(env.ns.layerTracker)
    assert.is_truthy(env.ns.autoPublisher)
  end)

  it("lists no skipped step when every module is on", function()
    env.fire("ADDON_LOADED", "GuildAssistant")
    env.fire("PLAYER_LOGIN")
    assert.are.same({}, env.ns.skippedSteps)
  end)

  it("asks for a reload when a module that was skipped at login is switched on", function()
    env.fire("ADDON_LOADED", "GuildAssistant")
    env.ns.Settings.SetModuleOff(env.root(), "loot", true)
    env.fire("PLAYER_LOGIN")
    assert.is_false(env.ns.modules:NeedsReload("loot"))
    env.ns.modules:SetEnabled("loot", true)
    assert.is_true(env.ns.modules:NeedsReload("loot"))
  end)
end)
