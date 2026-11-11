-- RANK_MAP on the wire: who may send a rank map, the guards for a co-guild master, conflicts and the snapshot item.
-- The receiver authorizes the sender with the map it holds BEFORE applying the incoming one (docs/PROTOCOL.md).
local function load_addon()
  dofile("GuildAssistant/Libs/LibStub/LibStub.lua")
  dofile("GuildAssistant/Libs/LibDeflate/LibDeflate.lua")
  dofile("GuildAssistant/Libs/LibSerialize/LibSerialize.lua")

  local ns = {}
  for _, path in ipairs({
    "Core/Constants",
    "Core/Locale",
    "Core/Validate",
    "Domain/PermissionService",
    "Domain/RankMapModel",
    "Sync/Codec",
    "Sync/Protocol",
    "Sync/SyncRules",
    "Sync/RankMapSync",
  }) do
    assert(loadfile("GuildAssistant/" .. path .. ".lua"))("GuildAssistant", ns)
  end
  return ns
end

local ns = load_addon()
local Sync, Protocol, Model = ns.RankMapSync, ns.Protocol, ns.RankMapModel

local NOW = 1792454400

-- The guild roster of the receiver: name -> rank name and index.
local ENTRIES = {
  Boss = { rankName = "Leader", rankIndex = 0 },
  Co = { rankName = "Captain", rankIndex = 1 },
  Off = { rankName = "Lieutenant", rankIndex = 2 },
  Mem = { rankName = "Soldier", rankIndex = 5 },
  -- Rank 3 was renamed in the game; only a saved map still knows it is a co-guild master rank.
  Renamed = { rankName = "Sergeanta", rankIndex = 3 },
  -- A rank that is called like the guild master's but is not rank 0.
  Fake = { rankName = "Leader", rankIndex = 4 },
}

local function ctx_of(data, extra)
  local ctx = {
    data = data,
    now = function()
      return NOW
    end,
    entryOf = function(name)
      return ENTRIES[name]
    end,
  }
  for key, value in pairs(extra or {}) do
    ctx[key] = value
  end
  return ctx
end

local function payload(rows, change)
  local p = { rev = 1, updatedAt = NOW - 10, ranks = rows }
  for key, value in pairs(change or {}) do
    p[key] = value
  end
  return p
end

local function message(p)
  return Protocol.Validate(Protocol.Build("RANK_MAP", p, "m1"))
end

local function apply(ctx, p, sender)
  local m = message(p)
  assert(m, "the test payload must validate")
  return Sync.Apply(ctx, m, sender)
end

-- Rows that keep the roles the saved map gives the ranks the tests use.
local KEEP = {
  { i = 1, r = "cogm", n = "Captain" },
  { i = 2, r = "officer", n = "Lieutenant" },
  { i = 5, r = "member", n = "Soldier" },
}

local function rows_with(change)
  local rows = {}
  for _, row in ipairs(KEEP) do
    rows[#rows + 1] = { i = row.i, r = change[row.i] or row.r, n = row.n }
  end
  return rows
end

-- The map the receiver holds when a co-guild master is in play: rank 1 is cogm, so the roster entry "Co" is one.
local function held_map(overrides)
  local map = {
    rev = 1,
    updatedAt = NOW - 100,
    by = "Boss",
    byGuildMaster = true,
    ranks = {
      [1] = { role = "cogm", name = "Captain" },
      [2] = { role = "officer", name = "Lieutenant" },
      [3] = { role = "cogm", name = "Sergeanta" },
      [5] = { role = "member", name = "Soldier" },
    },
  }
  for key, value in pairs(overrides or {}) do
    map[key] = value
  end
  return map
end

describe("RankMapSync.Apply authority", function()
  it("accepts a rank map from rank index 0 and keeps it for the guild", function()
    local data = {}
    local ok = apply(ctx_of(data), payload(rows_with({ [2] = "member" })), "Boss")
    assert.is_true(ok)
    local saved = data.rankMap
    assert.are.equal(1, saved.rev)
    assert.are.equal("Boss", saved.by)
    assert.are.equal("member", saved.ranks[2].role)
    assert.are.equal("Lieutenant", saved.ranks[2].name)
  end)

  it("drops a rank map from a rank that is only a co-guild master by its name while no map is saved", function()
    local data = {}
    local ok, why = apply(ctx_of(data), payload(rows_with({ [2] = "rl" })), "Co")
    assert.is_false(ok)
    assert.are.equal("forbidden", why)
    assert.is_nil(data.rankMap)
  end)

  it("accepts a rank map from a co-guild master by the map the receiver holds", function()
    local data = { rankMap = held_map() }
    local rows = rows_with({})
    rows[#rows + 1] = { i = 3, r = "cogm", n = "Sergeanta" }
    local ok = apply(ctx_of(data), payload(rows, { rev = 2 }), "Renamed")
    assert.is_true(ok)
    assert.are.equal(2, data.rankMap.rev)
  end)

  it("drops a rank map from an officer, a member and somebody the roster does not know", function()
    local data = { rankMap = held_map() }
    local ctx = ctx_of(data)
    assert.are.same({ false, "forbidden" }, { apply(ctx, payload(rows_with({}), { rev = 2 }), "Off") })
    assert.are.same({ false, "forbidden" }, { apply(ctx, payload(rows_with({}), { rev = 2 }), "Mem") })
    assert.are.same({ false, "unknown_sender" }, { apply(ctx, payload(rows_with({}), { rev = 2 }), "Stranger") })
    assert.are.equal(1, data.rankMap.rev)
  end)

  it("never lets the incoming map authorize its own sender", function()
    local data = {}
    -- The officer's own rank (2) is made co-guild master by the very map the officer sends.
    local ok, why = apply(ctx_of(data), payload(rows_with({ [2] = "cogm" })), "Off")
    assert.is_false(ok)
    assert.are.equal("forbidden", why)
    -- Nor does a map that makes a renamed rank cogm authorize somebody who is only that by the incoming map.
    local rows = rows_with({})
    rows[#rows + 1] = { i = 3, r = "cogm", n = "Sergeanta" }
    ok, why = apply(ctx_of(data), payload(rows), "Renamed")
    assert.is_false(ok)
    assert.are.equal("forbidden", why)
    assert.is_nil(data.rankMap)
  end)

  it("recognises the guild master by the rank index and never by the name", function()
    local data = {}
    local ok, why = apply(ctx_of(data), payload(rows_with({})), "Fake")
    assert.is_false(ok)
    assert.are.equal("forbidden", why)
  end)

  it("ignores a rank map when there is no guild data set", function()
    local ok, why = apply(ctx_of(nil), payload(rows_with({})), "Boss")
    assert.is_false(ok)
    assert.are.equal("no_guild", why)
  end)

  it("refuses a message that is not a rank map", function()
    local ok, why = Sync.Apply(ctx_of({}), { t = "HELLO", p = {} }, "Boss")
    assert.is_false(ok)
    assert.are.equal("unsupported", why)
  end)
end)

describe("RankMapSync.Apply guards for a co-guild master", function()
  it("drops the whole message when the sender changes the row of their own rank", function()
    local data = { rankMap = held_map() }
    local ok, why = apply(ctx_of(data), payload(rows_with({ [1] = "officer", [2] = "rl" }), { rev = 2 }), "Co")
    assert.is_false(ok)
    assert.are.equal("self_row", why)
    assert.are.equal(1, data.rankMap.rev)
  end)

  it("drops a map that leaves the sender's own rank out, since an unlisted rank is a member", function()
    local data = { rankMap = held_map() }
    local ok, why = apply(ctx_of(data), payload(rows_with({}), { rev = 2 }), "Renamed")
    assert.is_false(ok)
    assert.are.equal("self_row", why)
    assert.are.equal(1, data.rankMap.rev)
  end)

  it("lets a co-guild master change other ranks, even to cogm, by design", function()
    local data = { rankMap = held_map() }
    assert.is_true((apply(ctx_of(data), payload(rows_with({ [2] = "cogm", [5] = "alter" }), { rev = 2 }), "Co")))
    assert.are.equal("cogm", data.rankMap.ranks[2].role)
    assert.are.equal("alter", data.rankMap.ranks[5].role)
  end)

  it("lets the guild master change any row, the co-guild master's included", function()
    local data = { rankMap = held_map() }
    assert.is_true((apply(ctx_of(data), payload(rows_with({ [1] = "officer" }), { rev = 2 }), "Boss")))
    assert.are.equal("officer", data.rankMap.ranks[1].role)
  end)

  it("never accepts gm as a role of a rank, from anybody", function()
    local data = {}
    local bad = { rev = 1, updatedAt = NOW - 10, ranks = { { i = 1, r = "gm", n = "Captain" } } }
    assert.is_nil(message(bad))
    local ok, why = Sync.Apply(ctx_of(data), { t = "RANK_MAP", p = bad }, "Boss")
    assert.is_false(ok)
    assert.are.equal("invalid", why)
    local fixed = { rev = 1, updatedAt = NOW - 10, ranks = { { i = 0, r = "alter", n = "Leader" } } }
    ok, why = Sync.Apply(ctx_of(data), { t = "RANK_MAP", p = fixed }, "Boss")
    assert.is_false(ok)
    assert.are.equal("invalid", why)
    assert.is_nil(data.rankMap)
  end)
end)

describe("RankMapSync.Apply conflicts", function()
  local function held(rev, updatedAt, by)
    return {
      rankMap = held_map({
        rev = rev,
        updatedAt = updatedAt,
        by = by,
        byGuildMaster = by == "Boss" or nil,
        ranks = { [1] = { role = "cogm", name = "Captain" }, [2] = { role = "officer", name = "O" } },
      }),
    }
  end

  it("keeps the newer revision and drops an older or equal one", function()
    local data = held(3, NOW - 50, "Boss")
    local ctx = ctx_of(data)
    assert.are.same({ false, "stale" }, { apply(ctx, payload(rows_with({ [2] = "rl" }), { rev = 2 }), "Boss") })
    assert.are.same(
      { false, "stale" },
      { apply(ctx, payload(rows_with({ [2] = "rl" }), { rev = 3, updatedAt = NOW - 50 }), "Boss") }
    )
    assert.are.equal("officer", data.rankMap.ranks[2].role)
    assert.is_true((apply(ctx, payload(rows_with({ [2] = "rl" }), { rev = 4 }), "Boss")))
    assert.are.equal("rl", data.rankMap.ranks[2].role)
  end)

  it("breaks a tie on the revision by the later time, then by the sender", function()
    local data = held(3, NOW - 50, "Co")
    local ctx = ctx_of(data)
    assert.is_true((apply(ctx, payload(rows_with({ [2] = "rl" }), { rev = 3, updatedAt = NOW - 40 }), "Boss")))
    assert.are.equal("Boss", data.rankMap.by)
    -- Same revision and time: the larger sender name wins ("Co" > "Boss"), a replay of the held one does not.
    assert.is_true((apply(ctx, payload(rows_with({ [2] = "member" }), { rev = 3, updatedAt = NOW - 40 }), "Co")))
    assert.are.equal("Co", data.rankMap.by)
    assert.are.same(
      { false, "stale" },
      { apply(ctx, payload(rows_with({ [2] = "member" }), { rev = 3, updatedAt = NOW - 40 }), "Co") }
    )
  end)

  it("lets the guild master override a co-guild master's map whatever its revision and time", function()
    local data = { rankMap = held_map({ rev = 1, byGuildMaster = false, by = "Co" }) }
    local ctx = ctx_of(data)
    -- A hostile co-guild master pushes the revision as far as one step allows, again and again, with a future time.
    assert.is_true((apply(ctx, payload(rows_with({ [2] = "member" }), { rev = 2, updatedAt = NOW + 100000 }), "Co")))
    assert.is_true((apply(ctx, payload(rows_with({ [2] = "member" }), { rev = 3, updatedAt = NOW + 100000 }), "Co")))
    assert.is_true((apply(ctx, payload(rows_with({ [1] = "member" }), { rev = 1, updatedAt = NOW - 100 }), "Boss")))
    assert.are.equal("member", data.rankMap.ranks[1].role)
    assert.are.equal("Boss", data.rankMap.by)
    assert.is_true(data.rankMap.byGuildMaster)
    -- Two maps of the guild master: last write wins as usual.
    assert.are.same(
      { false, "stale" },
      { apply(ctx, payload(rows_with({ [1] = "officer" }), { rev = 1, updatedAt = NOW - 200 }), "Boss") }
    )
  end)

  it("drops a co-guild master's map that jumps the revision", function()
    local data = held(3, NOW - 50, "Boss")
    local ctx = ctx_of(data)
    assert.are.same(
      { false, "rev_jump" },
      { apply(ctx, payload(rows_with({ [2] = "rl" }), { rev = 2147483647 }), "Co") }
    )
    assert.are.same({ false, "rev_jump" }, { apply(ctx, payload(rows_with({}), { rev = 9 }), "Co") })
    assert.is_true((apply(ctx, payload(rows_with({ [2] = "rl" }), { rev = 4 }), "Co")))
  end)

  it("clamps a time that claims to be in the future", function()
    local data = {}
    apply(ctx_of(data), payload(rows_with({}), { updatedAt = NOW + 100000 }), "Boss")
    assert.are.equal(NOW + 300, data.rankMap.updatedAt)
  end)

  it("keeps the map in the data set it was given and touches nothing else in it", function()
    local data = { blacklist = { x = 1 } }
    assert.is_true((apply(ctx_of(data), payload(rows_with({})), "Boss")))
    assert.are.equal(1, data.rankMap.rev)
    assert.are.same({ x = 1 }, data.blacklist)
  end)
end)

describe("RankMapSync payloads and snapshot", function()
  local saved = {
    rev = 4,
    updatedAt = NOW - 5,
    by = "Boss",
    ranks = { [1] = { role = "cogm", name = "Captain" }, [2] = { role = "officer", name = "Lieutenant" } },
  }

  it("builds the payload of a saved map", function()
    local p = Sync.Payload(saved)
    assert.are.equal(4, p.rev)
    assert.are.same({ { i = 1, r = "cogm", n = "Captain" }, { i = 2, r = "officer", n = "Lieutenant" } }, p.ranks)
    assert.is_nil(Sync.Payload(nil))
    assert.is_nil(Sync.Payload({ rev = 0, ranks = {} }))
  end)

  it("builds a snapshot item that a receiver applies under the sender of the snapshot", function()
    local item = Sync.SnapshotItem(saved)
    assert.are.equal("RANK_MAP", item.t)
    local data = {}
    local ok = Sync.ApplyItem(ctx_of(data), item, "Boss")
    assert.is_true(ok)
    assert.are.equal(4, data.rankMap.rev)
    local other = {}
    local denied, why = Sync.ApplyItem(ctx_of(other), item, "Off")
    assert.is_false(denied)
    assert.are.equal("forbidden", why)
    assert.is_nil(Sync.SnapshotItem(nil))
  end)

  it("tells who may author it: rank index 0 and a co-guild master by the map held", function()
    assert.is_true(Sync.MayAuthor({ rankName = "Anything", rankIndex = 0 }, nil))
    assert.is_true(Sync.MayAuthor({ rankName = "Sergeanta", rankIndex = 3 }, held_map()))
    assert.is_false(Sync.MayAuthor({ rankName = "Captain", rankIndex = 1 }, nil))
    assert.is_false(Sync.MayAuthor({ rankName = "Lieutenant", rankIndex = 2 }, held_map()))
    assert.is_false(Sync.MayAuthor({ rankName = "Leader", rankIndex = 4 }, held_map()))
    assert.is_false(Sync.MayAuthor(nil, nil))
  end)
end)

describe("Model consistency", function()
  it("keeps the wire limit of rows in step with the guild rank limit", function()
    assert.are.equal(9, Model.MAX_INDEX)
  end)
end)
