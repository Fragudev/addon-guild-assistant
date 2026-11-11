-- The structural pieces ported with the kit: the scrollbar drag, the gutter that appears only when there is something
-- to scroll, the scrolling sidebar with item badges, the seats of a party and the field border.
local fake = dofile("tests/support/fake_frames.lua")

local function load_kit()
  local ns = {}
  for _, path in ipairs({
    "Core/Constants",
    "Core/Locale",
    "UI/Kit/Theme",
    "UI/Kit/Pixel",
    "UI/Kit/Shape",
    "UI/Kit/Util",
    "UI/Kit/Calendar",
    "UI/Kit/Icons",
    "UI/Kit/Core",
    "UI/Kit/Text",
    "UI/Kit/Controls",
    "UI/Kit/Data",
    "UI/Kit/Shell",
  }) do
    assert(loadfile("GuildAssistant/" .. path .. ".lua"))("GuildAssistant", ns)
  end
  return ns.Kit
end

-- Every widget under `root` whose kind is `kind`.
local function find_all(root, kind, found)
  found = found or {}
  if root.kind == kind then
    found[#found + 1] = root
  end
  for _, item in ipairs(root.items or {}) do
    find_all(item.obj, kind, found)
  end
  return found
end

describe("Kit structure", function()
  local Kit, root

  before_each(function()
    fake.install()
    Kit = load_kit()
    root = Kit.Stack(_G.UIParent, { gap = 10 })
  end)

  after_each(function()
    fake.uninstall()
  end)

  describe("scroll area", function()
    it("drags the thumb with the mouse and jumps to a click on the track", function()
      local cursorY = 700
      local saved = _G.GetCursorPosition
      _G.GetCursorPosition = function()
        return 0, cursorY
      end
      local scroll = Kit.ScrollArea(_G.UIParent, { gap = 0 })
      for index = 1, 20 do
        Kit.Button(scroll, { text = tostring(index) })
      end
      -- view 200, content 600: the thumb is 66 high and travels 134 units for a range of 400. The frame top is 700.
      scroll:Layout(400, 200)
      assert.is_true(scroll.bar:IsShown())
      local bar = scroll.bar.scripts
      -- Press on the thumb (at its top) and drag 67 units down: half the travel, half the range.
      bar.OnMouseDown(scroll.bar, "LeftButton")
      cursorY = 700 - 67
      bar.OnUpdate(scroll.bar)
      assert.are.equal(200, scroll:GetScroll())
      -- Past the end it stops at the range.
      cursorY = 0
      bar.OnUpdate(scroll.bar)
      assert.are.equal(400, scroll:GetScroll())
      bar.OnMouseUp(scroll.bar)
      assert.is_nil(scroll.bar.scripts.OnUpdate)
      -- A click on the track above the thumb centres the thumb there.
      cursorY = 700 - 33
      bar.OnMouseDown(scroll.bar, "LeftButton")
      assert.are.equal(0, scroll:GetScroll())
      bar.OnMouseUp(scroll.bar)
      -- Another button does nothing; the wheel over the bar scrolls too.
      bar.OnMouseDown(scroll.bar, "RightButton")
      assert.is_nil(scroll.bar.scripts.OnUpdate)
      bar.OnMouseWheel(scroll.bar, -1)
      assert.are.equal(40, scroll:GetScroll())
      _G.GetCursorPosition = saved
    end)

    it("keeps the gutter only while there is something to scroll with autoGutter", function()
      local scroll = Kit.ScrollArea(_G.UIParent, { gap = 0, autoGutter = true })
      local button = Kit.Button(scroll, { text = "only" })
      scroll:Layout(200, 300)
      assert.are.equal(200, button.width)
      for index = 1, 20 do
        Kit.Button(scroll, { text = tostring(index) })
      end
      scroll:Layout(200, 300)
      assert.is_true(button.width < 200)
      assert.is_true(scroll.range > 0)
    end)
  end)

  describe("sidebar", function()
    it("scrolls the rows of a short sidebar above the pinned user card and keeps the given offset", function()
      local items = {}
      for index = 1, 20 do
        items[index] = { value = "tab" .. index, text = "Tab " .. index, icon = "home" }
      end
      local sidebar = Kit.Sidebar(_G.UIParent, {
        groups = { { items = items } },
        value = "tab1",
        user = { name = "Ann", detail = "Member" },
        scroll = 120,
      })
      assert.are.equal(300, sidebar:Layout(200, 300))
      assert.are.equal("ScrollArea", sidebar.nav.kind)
      -- The rows get what the card leaves (300 - 60) and can scroll the rest.
      assert.are.equal(240, sidebar.nav.view)
      assert.is_true(sidebar.nav.range > 0)
      assert.are.equal(120, sidebar.nav:GetScroll())
      -- A tall window needs no scroll: the offset falls back to 0.
      sidebar:Layout(200, 2000)
      assert.are.equal(0, sidebar.nav.range)
      assert.are.equal(0, sidebar.nav:GetScroll())
    end)

    describe("sidebar badge", function()
      local function sidebar(badge)
        return Kit.Sidebar(_G.UIParent, {
          groups = {
            {
              items = {
                { value = "home", text = "Home", icon = "home" },
                { value = "groups", text = "Groups", icon = "users", badge = badge },
              },
            },
          },
          value = "home",
          onSelect = function() end,
        })
      end

      it("shows the badge of an item and leaves the others alone", function()
        local bar = sidebar("3")
        bar:Layout(200, 400)
        local rows = find_all(bar, "NavRow")
        assert.is_false(rows[1].badge:IsShown())
        assert.are.equal("", rows[1].badge:GetText())
        assert.is_true(rows[2].badge:IsShown())
        assert.are.equal("3", rows[2].badge:GetText())
      end)

      it("keeps the label of a row without badge as wide as it always was", function()
        local bar = sidebar("3")
        local rows = find_all(bar, "NavRow")
        local function rightOffset(row)
          local last
          for _, point in ipairs(row.label.points) do
            if point[1] == "RIGHT" then
              last = point
            end
          end
          return last[2]
        end
        assert.are.equal(-8, rightOffset(rows[1]))
        assert.is_true(rightOffset(rows[2]) < -8)
      end)

      it("changes the badge without building the sidebar again, and clears it", function()
        local bar = sidebar(nil)
        local row = find_all(bar, "NavRow")[2]
        assert.is_false(row.badge:IsShown())
        bar:SetItemBadge("groups", "7")
        assert.are.equal("7", row.badge:GetText())
        assert.is_true(row.badge:IsShown())
        assert.are.equal("7", row.opts.badge)
        bar:SetItemBadge("groups", nil)
        assert.is_false(row.badge:IsShown())
        bar:SetItemBadge("nowhere", "1")
        bar:SetItemBadge("groups", "")
        assert.is_false(row.badge:IsShown())
      end)

      it("does not touch a row that was released with the sidebar", function()
        local bar = sidebar("2")
        bar:Release()
        assert.has_no.errors(function()
          bar:SetItemBadge("groups", "9")
        end)
      end)

      it("draws a row of the voting frame as before, with no badge", function()
        local row = Kit.NavRow(root, { text = "A", icon = "home", selected = true })
        assert.is_false(row.badge:IsShown())
        assert.is_nil(row.opts.badge)
      end)
    end)

    describe("seats", function()
      local saved
      before_each(function()
        saved = _G.CLASS_ICON_TCOORDS
        _G.CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
      end)
      after_each(function()
        _G.CLASS_ICON_TCOORDS = saved
      end)

      local function seated(opts)
        local widget = Kit.Seats(root, opts)
        widget:Layout(300)
        return widget
      end

      it("draws a member with the class icon framed in the class color and a mark of the known role", function()
        local widget = seated({ seats = { { filled = true, class = "WARRIOR", role = "tank" } }, size = 20 })
        local seat = widget.seats[1]
        assert.is_true(seat.icon.texture:find("UI%-CHARACTERCREATE%-CLASSES") ~= nil)
        assert.are.same({ 0.02, 0.23, 0.02, 0.23 }, {
          math.floor(seat.icon.texcoord[1] * 100 + 0.5) / 100,
          math.floor(seat.icon.texcoord[2] * 100 + 0.5) / 100,
          math.floor(seat.icon.texcoord[3] * 100 + 0.5) / 100,
          math.floor(seat.icon.texcoord[4] * 100 + 0.5) / 100,
        })
        local r, g, b = unpack(Kit.Theme.ClassColor("WARRIOR"))
        assert.are.same({ r, g, b, 1 }, seat.edge.color)
        assert.is_true(seat.badge:IsShown())
        assert.is_true(seat.badge.texture:find("role%-tank$") ~= nil)
        assert.is_true(seat.badgeBack:IsShown())
      end)

      it("draws a member without a known role or class with no mark, and as a person", function()
        local widget = seated({ seats = { { filled = true, class = "WARRIOR" }, { filled = true } } })
        assert.is_false(widget.seats[1].badge:IsShown())
        assert.is_true(widget.seats[2].icon.texture:find("user$") ~= nil)
        assert.is_false(widget.seats[2].badge:IsShown())
      end)

      it("hides the seats past the list", function()
        local widget = seated({ seats = { { filled = true } } })
        assert.is_true(widget.seats[1].edge:IsShown())
        assert.is_false(widget.seats[2].edge:IsShown())
        assert.is_false(widget.seats[2].icon:IsShown())
        assert.is_false(widget.seats[2].badge:IsShown())
      end)

      it("draws a free seat with the dim mark of the role it needs, and an empty frame otherwise", function()
        local widget = seated({ seats = { { filled = false, role = "heal" }, { filled = false } } })
        assert.is_true(widget.seats[1].icon.texture:find("role%-heal$") ~= nil)
        assert.is_false(widget.seats[1].badge:IsShown())
        assert.is_false(widget.seats[2].icon:IsShown())
        assert.is_true(widget.seats[2].edge:IsShown())
      end)

      it("measures the seats and shows the tooltip", function()
        local five = {}
        for index = 1, 5 do
          five[index] = { filled = index <= 2 }
        end
        local widget = seated({ seats = five, size = 18, tooltip = "2 of 5 members" })
        assert.are.equal(18 + 4, widget:Layout(300))
        assert.are.equal(5 * 18 + 4 * 4 + 4, widget:NaturalWidth())
        assert.has_no.errors(function()
          widget.frame.scripts.OnEnter()
          widget.frame.scripts.OnLeave()
        end)
      end)
    end)
  end)

  describe("field border", function()
    it("is the border at rest, the accent with the focus, and danger for an error that wins over the focus", function()
      assert.are.equal("border", Kit.FieldBorder(false, false))
      assert.are.equal("accent", Kit.FieldBorder(false, true))
      assert.are.equal("danger", Kit.FieldBorder(true, false))
      assert.are.equal("danger", Kit.FieldBorder(true, true))
    end)

    it("colors the border of an edit box from the focus and the error", function()
      local box = Kit.EditBox(root, { text = "x" })
      box.frame:SetFocus()
      assert.are.same({ Kit.Theme.Color("accent") }, box.border.textures[1].color)
      box:SetError(true)
      assert.are.same({ Kit.Theme.Color("danger") }, box.border.textures[1].color)
    end)
  end)

  describe("row", function()
    it("asks for the sum of its fixed and auto children, so it can be auto inside another row", function()
      local row = Kit.Row(root, { gap = 10 })
      Kit.Button(row, { text = "A", layout = { width = 60 } })
      Kit.Button(row, { text = "B", layout = { width = 40 } })
      assert.are.equal(110, row:NaturalWidth())
    end)
  end)
end)
