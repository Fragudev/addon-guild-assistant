-- Kit.Shape: the surface under the popups. The default mode is a flat square panel with a one pixel border, which is
-- how every panel of the addon is drawn; asking for a cut changes nothing on screen.
local fake = dofile("tests/support/fake_frames.lua")

local function load_kit()
  local ns = {}
  for _, path in ipairs({
    "Core/Constants",
    "Core/Locale",
    "UI/Kit/Theme",
    "UI/Kit/Pixel",
    "UI/Kit/Shape",
  }) do
    assert(loadfile("GuildAssistant/" .. path .. ".lua"))("GuildAssistant", ns)
  end
  return ns.Kit
end

describe("Kit.Shape", function()
  local Kit, frame

  before_each(function()
    fake.install()
    Kit = load_kit()
    frame = _G.CreateFrame("Frame", nil, _G.UIParent)
    frame:SetSize(200, 100)
  end)

  after_each(function()
    fake.uninstall()
  end)

  it("draws a square flat surface by default: one fill texture over the frame and a four sided border", function()
    local shape = Kit.Shape.New(frame)
    assert.are.equal("square", shape.mode)
    assert.is_true(shape.flat)
    assert.is_truthy(shape.fill.allPoints)
    -- One fill and the four edges of the pixel border: nothing else, so there is no diagonal or corner tile.
    assert.are.equal(5, #frame.children)
    assert.are.equal(4, #shape.border.textures)
    for _, key in ipairs({ "tl", "tr", "bl", "br" }) do
      assert.is_false(shape:IsRound(key))
    end
  end)

  it("stays square when a cut is asked for", function()
    for _, cut in ipairs({ "sm", "md", "lg", "none", 5 }) do
      local other = _G.CreateFrame("Frame", nil, _G.UIParent)
      local shape = Kit.Shape.New(other, { cut = cut, corners = { tl = true } })
      assert.is_true(shape.flat)
      assert.are.equal(5, #other.children)
      assert.is_false(shape:IsRound("tl"))
    end
    assert.are.equal(8, Kit.Shape.New(frame, { cut = "lg" }).cut)
    assert.are.equal(4, Kit.Shape.New(frame, { cut = "sm" }).cut)
    assert.are.equal(6, Kit.Shape.New(frame).cut)
  end)

  it("fills with a token, with a color and an alpha, and with a gradient name as the token of that name", function()
    local shape = Kit.Shape.New(frame)
    shape:SetFill("control")
    assert.are.same({ Kit.Theme.Color("control") }, shape.fill.color)
    shape:SetFill({ color = "danger", alpha = 0.12 })
    assert.are.same({ Kit.Theme.Color("danger", 0.12) }, shape.fill.color)
    shape:SetFill({ gradient = "bg" })
    assert.are.same({ Kit.Theme.Color("bg") }, shape.fill.color)
    shape:SetFill({ gradient = "nope", alpha = 0.5 })
    assert.are.same({ Kit.Theme.Color("panel", 0.5) }, shape.fill.color)
  end)

  it("paints the panel color by default, like the panels it replaces", function()
    local shape = Kit.Shape.New(frame)
    assert.are.same({ Kit.Theme.Color("panel") }, shape.fill.color)
  end)

  it("colors, hides and shows the whole border", function()
    local shape = Kit.Shape.New(frame)
    shape.border:SetColor("danger")
    for _, texture in ipairs(shape.border.textures) do
      assert.are.same({ Kit.Theme.Color("danger") }, texture.color)
    end
    shape.border:SetShown(false)
    for _, texture in ipairs(shape.border.textures) do
      assert.is_false(texture:IsShown())
    end
    shape.border:SetShown(true)
    assert.is_true(shape.border.textures[1]:IsShown())
  end)

  it("snaps the border to a pixel on Resize", function()
    local shape = Kit.Shape.New(frame)
    frame.GetEffectiveScale = function()
      return 2
    end
    _G.GetPhysicalScreenSize = function()
      return 1920, 1080
    end
    shape:Resize()
    _G.GetPhysicalScreenSize = nil
    assert.is_true(shape.border.textures[1].height < 1)
  end)
end)
