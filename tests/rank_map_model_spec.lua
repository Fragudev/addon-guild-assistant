-- Rank mapping: which addon role a guild rank has, by rank index (docs/PROTOCOL.md, RANK_MAP).
local function load_model()
  local ns = {}
  for _, path in ipairs({
    "Core/Constants",
    "Core/Validate",
    "Domain/PermissionService",
    "Domain/RankMapModel",
  }) do
    assert(loadfile("GuildAssistant/" .. path .. ".lua"))("GuildAssistant", ns)
  end
  return ns.RankMapModel, ns
end

local Model = load_model()

local function map(ranks)
  return { rev = 1, updatedAt = 100, by = "Boss", ranks = ranks }
end

describe("RankMapModel.Resolve", function()
  it("makes index 0 the guild master whatever the map says", function()
    assert.are.equal("gm", Model.Resolve(nil, 0))
    assert.are.equal("gm", Model.Resolve(map({ [0] = { role = "alter" } }), 0))
    assert.are.equal("gm", Model.Resolve(map({}), 0))
  end)

  it("gives a mapped index its role, whatever the rank is called now", function()
    local rankMap = map({ [2] = { role = "cogm", name = "Captain" } })
    assert.are.equal("cogm", Model.Resolve(rankMap, 2))
  end)

  it("makes every rank a member when there is no map at all, and never matches a name", function()
    for index = 1, 7 do
      assert.are.equal("member", Model.Resolve(nil, index))
    end
    assert.are.equal("member", Model.Resolve(nil, nil))
  end)

  it("makes an index the map does not cover a member", function()
    local rankMap = map({ [2] = { role = "rl" } })
    assert.are.equal("rl", Model.Resolve(rankMap, 2))
    assert.are.equal("member", Model.Resolve(rankMap, 4))
  end)

  it("ignores a stored role that is not assignable", function()
    assert.are.equal("member", Model.Resolve(map({ [2] = { role = "gm" } }), 2))
    assert.are.equal("member", Model.Resolve(map({ [2] = { role = "boss" } }), 2))
    assert.are.equal("member", Model.Resolve(map({ [2] = "cogm" }), 2))
    assert.are.equal("member", Model.Resolve("junk", 2))
  end)
end)

describe("RankMapModel.IsAssignable", function()
  it("allows every role but gm", function()
    for _, role in ipairs({ "cogm", "officer", "rl", "roster", "member", "alter" }) do
      assert.is_true(Model.IsAssignable(role), role)
    end
    assert.is_false(Model.IsAssignable("gm"))
    assert.is_false(Model.IsAssignable("admin"))
    assert.is_false(Model.IsAssignable(nil))
  end)
end)

describe("RankMapModel.Drift", function()
  local saved = map({
    [1] = { role = "cogm", name = "Captain" },
    [2] = { role = "officer", name = "Lieutenant" },
  })

  it("reports nothing without a map or when the names match", function()
    assert.are.same({}, Model.Drift(nil, { [0] = "Leader", [1] = "Captain" }))
    assert.are.same({}, Model.Drift(saved, { [0] = "Leader", [1] = "Captain", [2] = "Lieutenant" }))
  end)

  it("reports a renamed rank with both names", function()
    local drift = Model.Drift(saved, { [0] = "Leader", [1] = "Captain", [2] = "Sergeant" })
    assert.are.same({ { index = 2, savedName = "Lieutenant", currentName = "Sergeant" } }, drift)
  end)

  it("reports a rank that appeared and one that disappeared", function()
    local drift = Model.Drift(saved, { [0] = "Leader", [1] = "Captain", [2] = "Lieutenant", [3] = "Newbie" })
    assert.are.same({ { index = 3, savedName = nil, currentName = "Newbie" } }, drift)
    drift = Model.Drift(saved, { [0] = "Leader", [1] = "Captain" })
    assert.are.same({ { index = 2, savedName = "Lieutenant", currentName = nil } }, drift)
  end)

  it("lists the findings in index order and never looks at index 0", function()
    local drift = Model.Drift(saved, { [0] = "Renamed GM", [1] = "X", [2] = "Y", [4] = "Z" })
    assert.are.equal(3, #drift)
    assert.are.equal(1, drift[1].index)
    assert.are.equal(2, drift[2].index)
    assert.are.equal(4, drift[3].index)
  end)
end)

describe("RankMapModel.Defaults", function()
  it("pre-fills each rank as a member, which is what it is while no map is saved", function()
    local ranks = Model.Defaults({ [0] = "Leader", [1] = "Captain", [2] = "Lieutenant", [3] = "Mystery" })
    assert.are.same({ role = "member", name = "Captain" }, ranks[1])
    assert.are.same({ role = "member", name = "Lieutenant" }, ranks[2])
    assert.are.same({ role = "member", name = "Mystery" }, ranks[3])
    assert.is_nil(ranks[0])
  end)

  it("never pre-fills a rank with gm, even when it is called like the guild master", function()
    local ranks = Model.Defaults({ [0] = "Leader", [1] = "Leader" })
    assert.are.equal("member", ranks[1].role)
  end)
end)

describe("RankMapModel wire form", function()
  it("round-trips a map through the wire rows, in index order", function()
    local rankMap = map({ [3] = { role = "rl", name = "Raid Lead" }, [1] = { role = "cogm", name = "Captain" } })
    local wire = Model.ToWire(rankMap)
    assert.are.equal(1, wire.rev)
    assert.are.equal(100, wire.updatedAt)
    assert.are.same({ { i = 1, r = "cogm", n = "Captain" }, { i = 3, r = "rl", n = "Raid Lead" } }, wire.ranks)
    local back = Model.FromWire(wire)
    assert.are.same(rankMap.ranks, back.ranks)
  end)

  it("validates the rows strictly", function()
    local ok = { rev = 1, updatedAt = 5, ranks = { { i = 1, r = "cogm", n = "A" } } }
    assert.is_truthy(Model.ValidateWire(ok))
    local function bad(rows)
      return Model.ValidateWire({ rev = 1, updatedAt = 5, ranks = rows })
    end
    assert.is_nil(bad({ { i = 0, r = "alter", n = "A" } })) -- index 0 is fixed
    assert.is_nil(bad({ { i = 10, r = "alter", n = "A" } }))
    assert.is_nil(bad({ { i = 1.5, r = "alter", n = "A" } }))
    assert.is_nil(bad({ { i = 1, r = "gm", n = "A" } }))
    assert.is_nil(bad({ { i = 1, r = "boss", n = "A" } }))
    assert.is_nil(bad({ { i = 1, r = "alter", n = "" } }))
    assert.is_nil(bad({ { i = 1, r = "alter", n = ("x"):rep(33) } }))
    assert.is_nil(bad({ { i = 1, r = "alter", n = "|cffff0000red" } }))
    assert.is_nil(bad({ { i = 1, r = "alter", n = "A" }, { i = 1, r = "member", n = "B" } })) -- duplicate index
    assert.is_nil(bad("rows"))
    local many = {}
    for index = 1, 10 do
      many[index] = { i = (index % 9) + 1, r = "alter", n = "N" .. index }
    end
    assert.is_nil(bad(many)) -- more than 9 rows
    assert.is_nil(Model.ValidateWire({ rev = 0, updatedAt = 5, ranks = {} }))
    assert.is_nil(Model.ValidateWire({ rev = 1, updatedAt = -1, ranks = {} }))
  end)

  it("drops unknown fields and keeps the clean rows", function()
    local clean = Model.ValidateWire({
      rev = 2,
      updatedAt = 5,
      by = "Evil",
      ranks = { { i = 2, r = "officer", n = "Lieutenant", extra = 1 } },
    })
    assert.are.same({ rev = 2, updatedAt = 5, ranks = { { i = 2, r = "officer", n = "Lieutenant" } } }, clean)
  end)

  it("cuts a rank name to the wire limit without breaking a character", function()
    local name = ("á"):rep(20) -- 40 bytes
    local wire = Model.ToWire(map({ [1] = { role = "alter", name = name } }))
    assert.is_true(#wire.ranks[1].n <= 32)
    assert.are.equal(("á"):rep(16), wire.ranks[1].n)
    assert.is_truthy(Model.ValidateWire(wire))
  end)
end)
