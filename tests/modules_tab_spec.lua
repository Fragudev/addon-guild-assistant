-- The Modules tab (UI/Tabs/Modules.lua) against a fake of the kit: the reload button shows only when a module was
-- skipped at login, and pressing it reloads the interface through Platform.ReloadUI.
local function load_tab(skipped)
  local ns = {}
  for _, path in ipairs({
    "Core/Constants",
    "Core/Locale",
    "Locales/esES",
    "Core/Validate",
    "Domain/PermissionService",
    "Domain/ModuleRegistry",
    "Domain/Settings",
    "Domain/ModuleService",
    "UI/ViewModel",
    "UI/ViewModelModules",
  }) do
    assert(loadfile("GuildAssistant/" .. path .. ".lua"))("GuildAssistant", ns)
  end

  local buttons, registered = {}, nil
  ns.UI = {
    Register = function(value, draw)
      if value == "modules" then
        registered = draw
      end
    end,
    Role = function()
      return "member"
    end,
  }
  ns.Kit = {
    PageHeader = function() end,
    Card = function()
      return {}
    end,
    Label = function() end,
    Switch = function() end,
    Button = function(_, opts)
      buttons[#buttons + 1] = opts
    end,
  }
  ns.modules = ns.ModuleService.New({
    db = function()
      return { settings = { modules = { off = {} } } }
    end,
    skipped = function()
      return skipped
    end,
  })
  ns.Platform = { ReloadUI = function() end }
  assert(loadfile("GuildAssistant/UI/Tabs/Modules.lua"))("GuildAssistant", ns)
  registered({})
  return ns, buttons
end

local function buttonNamed(buttons, text)
  for _, opts in ipairs(buttons) do
    if opts.text == text then
      return opts
    end
  end
end

describe("Modules tab reload button", function()
  it("is not shown when no module was skipped at login", function()
    local _, buttons = load_tab({})
    assert.is_nil(buttonNamed(buttons, "Reload the interface"))
    assert.is_truthy(buttonNamed(buttons, "Turn all on"))
  end)

  it("is shown when a module was skipped at login, and calls Platform.ReloadUI when pressed", function()
    local ns, buttons = load_tab({ "lootPopup" })
    local reloads = 0
    ns.Platform.ReloadUI = function()
      reloads = reloads + 1
    end
    local button = buttonNamed(buttons, "Reload the interface")
    assert.is_truthy(button)
    button.onClick()
    assert.are.equal(1, reloads)
  end)
end)

describe("Platform.ReloadUI", function()
  it("calls the client's ReloadUI, and does nothing when the client has none", function()
    local ns = {}
    assert(loadfile("GuildAssistant/Core/Platform.lua"))("GuildAssistant", ns)
    local saved = _G.ReloadUI
    local reloads = 0
    _G.ReloadUI = function()
      reloads = reloads + 1
    end
    ns.Platform.ReloadUI()
    _G.ReloadUI = nil
    ns.Platform.ReloadUI()
    _G.ReloadUI = saved
    assert.are.equal(1, reloads)
  end)
end)
