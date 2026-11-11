-- Domain/ModuleService: the personal switches of the modules, stored on the character record (char.modules.off), with
-- the requirement cascade and the reload hint.
local function load_service()
  local ns = {}
  for _, path in ipairs({ "Domain/ModuleRegistry", "Domain/Settings", "Domain/ModuleService" }) do
    assert(loadfile("GuildAssistant/" .. path .. ".lua"))("GuildAssistant", ns)
  end
  return ns
end

describe("ModuleService", function()
  local ns, char, changes, skipped, service

  before_each(function()
    ns = load_service()
    char = {}
    changes = 0
    skipped = {}
    service = ns.ModuleService.New({
      character = function()
        return char
      end,
      skipped = function()
        return skipped
      end,
      onChange = function()
        changes = changes + 1
      end,
    })
  end)

  it("has every module on when nothing was saved", function()
    assert.is_true(service:IsEnabled("pvp"))
    assert.is_true(service:IsEnabled("professions"))
  end)

  it("has every module on before the character is loaded, and refuses to switch one", function()
    local early = ns.ModuleService.New({
      character = function()
        return nil
      end,
    })
    assert.is_true(early:IsEnabled("pvp"))
    local ok, reason = early:SetEnabled("pvp", false)
    assert.is_false(ok)
    assert.are.equal("unavailable", reason)
  end)

  it("turns a module off and on, and saves it on this character", function()
    assert.is_true(service:SetEnabled("professions", false))
    assert.is_false(service:IsEnabled("professions"))
    assert.is_true(char.modules.off.professions)
    assert.is_true(service:SetEnabled("professions", true))
    assert.is_true(service:IsEnabled("professions"))
    assert.is_nil(char.modules.off.professions)
  end)

  it("refuses an id it does not know and changes nothing", function()
    local ok, reason = service:SetEnabled("future", false)
    assert.is_false(ok)
    assert.are.equal("unknown", reason)
    assert.are.equal(0, changes)
  end)

  it("turns off the modules that need the one switched off, and says which", function()
    assert.are.same({ "raid", "loot" }, service:Cascade("raid", false))
    assert.is_true(service:SetEnabled("raid", false))
    assert.is_false(service:IsEnabled("loot"))
    assert.is_true(char.modules.off.loot)
  end)

  it("turns on the modules a module needs when it is switched on", function()
    service:SetEnabled("raid", false)
    assert.are.same({ "loot", "raid" }, service:Cascade("loot", true))
    assert.is_true(service:SetEnabled("loot", true))
    assert.is_true(service:IsEnabled("raid"))
    assert.is_true(service:IsEnabled("loot"))
  end)

  it("lists nothing to change when the switch already has that value", function()
    assert.are.same({}, service:Cascade("professions", true))
    assert.are.same({}, service:Cascade("raid", true))
  end)

  it("tells the listeners once per change, and not for a switch that stays as it is", function()
    service:SetEnabled("pvp", false)
    assert.are.equal(1, changes)
    service:SetEnabled("pvp", false)
    assert.are.equal(1, changes)
    service:SetEnabled("map", false)
    assert.are.equal(2, changes)
  end)

  it("keeps a module's data when it is turned off: only the switch is written", function()
    char.pvp = { kills = 3 }
    service:SetEnabled("pvp", false)
    assert.are.same({ kills = 3 }, char.pvp)
  end)

  it("drops the entries of the switches that are not true, and keeps the ids of a newer version", function()
    char.modules = { off = { professions = false, raid = "yes", future = true } }
    assert.is_true(service:IsEnabled("professions"))
    assert.is_true(service:IsEnabled("raid"))
    assert.is_true(char.modules.off.future)
    assert.is_nil(char.modules.off.professions)
  end)

  describe("NeedsReload", function()
    it("is false for a module that started at login", function()
      assert.is_false(service:NeedsReload("professions"))
    end)

    it("is true for a module that is on now but whose steps were skipped at login", function()
      skipped = { "recipes" }
      assert.is_true(service:NeedsReload("professions"))
      assert.is_false(service:NeedsReload("pvp"))
    end)

    it("is false for a module that is off, since turning it on is what needs the reload", function()
      skipped = { "recipes" }
      service:SetEnabled("professions", false)
      assert.is_false(service:NeedsReload("professions"))
    end)

    it("is false for a module without steps", function()
      skipped = { "recipes" }
      assert.is_false(service:NeedsReload("raid"))
    end)
  end)
end)
