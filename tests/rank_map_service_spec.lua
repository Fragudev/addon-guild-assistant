-- The rank map store and its questions: current map of the guild data set, editor draft, who changes role.
local ns = {}
for _, path in ipairs({
  "Core/Constants",
  "Core/Validate",
  "Domain/PermissionService",
  "Domain/RankMapModel",
  "Domain/RankMapService",
}) do
  assert(loadfile("GuildAssistant/" .. path .. ".lua"))("GuildAssistant", ns)
end
local Service = ns.RankMapService

local function roster_with(entries)
  local names = {}
  for name in pairs(entries) do
    names[#names + 1] = name
  end
  table.sort(names)
  return {
    Names = function()
      return names
    end,
    Lookup = function(_, name)
      return entries[name]
    end,
  }
end

describe("RankMapService:Current", function()
  it("reads the map of the guild data set that is current at each call", function()
    local first = { rev = 1, ranks = { [1] = { role = "rl" } } }
    local data = { rankMap = first }
    local service = Service.New({
      read = function()
        return data and data.rankMap
      end,
    })
    assert.are.equal(first, service:Current())
    assert.are.equal(first, service:Provider()())
    data = {}
    assert.is_nil(service:Current())
    data = nil
    assert.is_nil(service:Current())
  end)

  it("ignores a damaged record", function()
    local service = Service.New({
      read = function()
        return "oops"
      end,
    })
    assert.is_nil(service:Current())
  end)
end)

describe("RankMapService:Draft", function()
  local ranks = { [0] = "Leader", [1] = "Captain", [2] = "Lieutenant", [3] = "Mystery" }

  it("starts every rank as a member when nothing was saved", function()
    local service = Service.New({
      read = function()
        return nil
      end,
    })
    local draft = service:Draft(ranks)
    assert.are.equal("member", draft[1].role)
    assert.are.equal("member", draft[2].role)
    assert.are.equal("member", draft[3].role)
  end)

  it("lets the saved rows win and ignores a saved row of a rank that is gone", function()
    local service = Service.New({
      read = function()
        return { ranks = { [2] = { role = "officer" }, [8] = { role = "rl" } } }
      end,
    })
    local draft = service:Draft(ranks)
    assert.are.equal("officer", draft[2].role)
    assert.are.equal("Lieutenant", draft[2].name)
    assert.is_nil(draft[8])
  end)
end)

describe("RankMapService:Preview", function()
  local guild = roster_with({
    Boss = { rankName = "Leader", rankIndex = 0 },
    Ann = { rankName = "Lieutenant", rankIndex = 2 },
    Bob = { rankName = "Lieutenant", rankIndex = 2 },
    Cat = { rankName = "Soldier", rankIndex = 5 },
  })
  local saved = { ranks = { [2] = { role = "officer" } } }
  local service = Service.New({
    read = function()
      return saved
    end,
  })

  it("lists nobody when the draft changes nothing", function()
    local draft = service:Draft({ [0] = "Leader", [2] = "Lieutenant", [5] = "Soldier" })
    assert.are.same({}, service:Preview(guild, draft))
  end)

  it("lists who changes role, sorted by name, and never the guild master", function()
    local changes = service:Preview(guild, {
      [0] = { role = "alter" },
      [2] = { role = "member" },
      [5] = { role = "member" },
    })
    assert.are.same({
      { name = "Ann", rankName = "Lieutenant", from = "officer", to = "member" },
      { name = "Bob", rankName = "Lieutenant", from = "officer", to = "member" },
    }, changes)
  end)
end)
