local _, ns = ...

-- A surface: a fill and a border drawn with textures only. The default (and, for now, only) mode is "square": one flat
-- rectangle with a one pixel border, which is how every Guild Assistant panel looks. `opts.cut` and `opts.corners` are
-- accepted so a caller can describe a cut-corner surface, but no corner art ships with the addon, so every corner is
-- square and the look does not change. Widgets built on it keep the same calls (SetFill, border:SetColor, Resize).
local Kit = ns.Kit or {}
ns.Kit = Kit

local Shape = {}
Kit.Shape = Shape
Shape.__index = Shape

local CUTS = { none = 0, sm = 4, md = 6, lg = 8 }

-- The r, g, b, a of a theme token or a { r, g, b, a } table, with `alpha` over its own when given.
local function resolve(value, alpha)
  if type(value) == "table" then
    return value[1], value[2], value[3], alpha or value[4] or 1
  end
  return Kit.Theme.Color(value, alpha)
end

-- `opts.cut`: "sm", "md", "lg", "none" or a number of units, kept in `shape.cut`. `opts.corners`: the corners that
-- would be cut, all four by default, kept in `shape.corners`. Both are descriptive only in square mode.
function Shape.New(frame, opts)
  opts = opts or {}
  local cut = opts.cut
  if type(cut) ~= "number" then
    cut = CUTS[cut or "md"] or CUTS.md
  end
  local shape = setmetatable({
    frame = frame,
    mode = "square",
    cut = cut,
    corners = opts.corners or { tl = true, tr = true, bl = true, br = true },
    flat = true,
  }, Shape)
  shape.fill = frame:CreateTexture(nil, "BACKGROUND")
  shape.fill:SetAllPoints(frame)
  shape.border = Kit.Pixel.Border(frame, "border")
  shape:SetFill("panel")
  return shape
end

-- Whether a corner is drawn with a diagonal cut. Never in square mode.
function Shape.IsRound()
  return false
end

-- `spec` is a token, { color = token, alpha = n } or { gradient = name, alpha = n }. There are no gradients in the
-- theme: a gradient name is the token with that name (or "panel"). Always sets the whole fill, because widgets are
-- pooled.
function Shape:SetFill(spec)
  local r, g, b, a
  if type(spec) == "table" and spec.gradient then
    local token = Kit.Theme.colors[spec.gradient] and spec.gradient or "panel"
    r, g, b, a = resolve(token, spec.alpha)
  elseif type(spec) == "table" and spec.color then
    r, g, b, a = resolve(spec.color, spec.alpha)
  else
    r, g, b, a = resolve(spec)
  end
  self.fill:SetColorTexture(r, g, b, a)
end

-- After the frame changes size or scale: snaps the border to a pixel again.
function Shape:Resize()
  self.border:Resize()
end
