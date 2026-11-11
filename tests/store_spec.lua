local function load_store_current()
  local ns = {}
  assert(loadfile("GuildAssistant/Core/Constants.lua"))("GuildAssistant", ns)
  assert(loadfile("GuildAssistant/Core/Validate.lua"))("GuildAssistant", ns)
  assert(loadfile("GuildAssistant/Core/Store.lua"))("GuildAssistant", ns)
  return ns.Store, ns.Constants
end

-- Migrations 2 to 12 work on the old db.global layout: their specs load up to schema 12, migration 13 has its own.
local function load_store()
  local Store, Constants = load_store_current()
  local legacy = {
    Load = function(raw)
      return Store.Load(raw, 12)
    end,
    GetChar = Store.GetChar,
  }
  return legacy, Constants
end

describe("Store.Load", function()
  local Store = load_store()

  it("migrates a v1 database and keeps its content", function()
    local raw = { schemaVersion = 1, keep = "me" }
    local db = Store.Load(raw)
    assert.are.equal(raw, db)
    assert.are.equal("me", db.keep)
    assert.is_nil(db.schemaVersion)
    assert.are.equal(12, db.global.schemaVersion)
  end)

  it("is idempotent", function()
    local db = Store.Load({ schemaVersion = 1 })
    db.global.roster["A-B"] = { level = 60 }
    local again = Store.Load(db)
    assert.are.equal(60, again.global.roster["A-B"].level)
    assert.are.equal(12, again.global.schemaVersion)
  end)

  it("refuses data from a newer schema and leaves it untouched", function()
    local raw = { global = { schemaVersion = 99, roster = { x = 1 } } }
    local db, err = Store.Load(raw)
    assert.is_nil(db)
    assert.are.equal("newer_schema", err)
    assert.are.equal(99, raw.global.schemaVersion)
    assert.are.equal(1, raw.global.roster.x)
  end)

  it("recovers from corrupted values instead of raising", function()
    local db = Store.Load({ schemaVersion = "banana", global = "oops", chars = 5 })
    assert.are.equal(12, db.global.schemaVersion)
    assert.is_table(db.global.roster)
    assert.is_table(db.chars)
  end)

  it("treats a non-table saved variable as empty", function()
    local db = Store.Load("garbage")
    assert.are.equal(12, db.global.schemaVersion)
  end)
end)

describe("Store.GetChar", function()
  local Store = load_store()

  it("creates profile and readiness once per identity key", function()
    local db = Store.Load(nil)
    local char = Store.GetChar(db, "Guildmate-ClassicBetaPvP")
    char.profile.level = 60
    assert.is_table(char.readiness)
    assert.is_nil(char.consent)
    assert.is_table(char.publish)
    assert.is_table(char.pvp)
    assert.are.equal(60, Store.GetChar(db, "Guildmate-ClassicBetaPvP").profile.level)
  end)
end)

describe("Store migration to schema 3", function()
  local Store = load_store()

  it("adds the templates table to a v2 database and keeps everything else", function()
    local raw = {
      global = {
        schemaVersion = 2,
        roster = { ["A-B"] = { level = 60 } },
        events = { e = { title = "Raid" } },
        loot = {},
        sync = { seen = {}, tombstones = { t = { at = 1, rev = 2 } } },
      },
      chars = { ["Me-Realm"] = { profile = { level = 60 } } },
    }
    local db = Store.Load(raw)
    assert.are.equal(raw, db)
    assert.are.equal(12, db.global.schemaVersion)
    assert.are.same({}, db.global.templates)
    assert.are.equal(60, db.global.roster["A-B"].level)
    assert.are.equal("Raid", db.global.events.e.title)
    assert.are.equal(2, db.global.sync.tombstones.t.rev)
    assert.are.equal(60, db.chars["Me-Realm"].profile.level)
  end)

  it("does not touch templates that already exist", function()
    local db = Store.Load({ global = { schemaVersion = 3, templates = { Boss = { slots = {} } } } })
    assert.is_table(db.global.templates.Boss)
  end)

  it("creates the templates table for a fresh database", function()
    assert.are.same({}, Store.Load(nil).global.templates)
  end)
end)

describe("Store migration to schema 4", function()
  local Store = load_store()

  it("adds the settings table with the minimap section to a v3 database and keeps everything else", function()
    local raw = {
      global = { schemaVersion = 3, templates = { Boss = { slots = {} } }, events = { e = { title = "Raid" } } },
      chars = { ["Me-Realm"] = { profile = { level = 60 } } },
    }
    local db = Store.Load(raw)
    assert.are.equal(raw, db)
    assert.are.equal(12, db.global.schemaVersion)
    assert.are.same({ minimap = {}, pvp = {} }, db.global.settings)
    assert.is_table(db.global.templates.Boss)
    assert.are.equal("Raid", db.global.events.e.title)
    assert.are.equal(60, db.chars["Me-Realm"].profile.level)
  end)

  it("does not touch settings that already exist", function()
    local db = Store.Load({ global = { schemaVersion = 3, settings = { minimap = { angle = 90, hide = true } } } })
    assert.are.same({ angle = 90, hide = true }, db.global.settings.minimap)
  end)

  it("creates the settings for a fresh database", function()
    assert.are.same({ minimap = {}, pvp = {} }, Store.Load(nil).global.settings)
  end)
end)

describe("Store migration to schema 5", function()
  local Store = load_store()

  it("gives the characters already saved a pvp table and keeps everything else", function()
    local raw = {
      global = { schemaVersion = 4, settings = { minimap = {} } },
      chars = { ["Me-Realm"] = { profile = { level = 60 } }, ["Broken-Realm"] = "oops" },
    }
    local db = Store.Load(raw)
    assert.are.equal(raw, db)
    assert.are.equal(12, db.global.schemaVersion)
    assert.are.same({}, db.chars["Me-Realm"].pvp)
    assert.are.equal(60, db.chars["Me-Realm"].profile.level)
    assert.are.equal("oops", db.chars["Broken-Realm"])
  end)

  it("does not touch counters that already exist", function()
    local pvp = { honor = { world = 3, bg = 1 } }
    local db = Store.Load({ global = { schemaVersion = 4 }, chars = { ["Me-Realm"] = { pvp = pvp } } })
    assert.are.equal(pvp, db.chars["Me-Realm"].pvp)
    assert.are.equal(3, db.chars["Me-Realm"].pvp.honor.world)
  end)

  it("repairs a pvp value that is not a table", function()
    local db = Store.Load({ global = { schemaVersion = 4 }, chars = { ["Me-Realm"] = { pvp = 5 } } })
    assert.are.same({}, db.chars["Me-Realm"].pvp)
  end)

  it("is idempotent", function()
    local db = Store.Load({ global = { schemaVersion = 4 }, chars = { ["Me-Realm"] = {} } })
    db.chars["Me-Realm"].pvp.honor = { world = 2, bg = 0 }
    local again = Store.Load(db)
    assert.are.equal(2, again.chars["Me-Realm"].pvp.honor.world)
  end)
end)

describe("Store migration to schema 6", function()
  local Store = load_store()

  it("creates the received PvP counters and the reset floors", function()
    local db = Store.Load({ global = { schemaVersion = 5 } })
    assert.are.same({}, db.global.pvpStats)
    assert.are.same({}, db.global.pvpResets)
  end)

  it("keeps what is already there and repairs what is not a table", function()
    local stats = { ["Ann-Realm"] = { rev = 2 } }
    local db = Store.Load({ global = { schemaVersion = 5, pvpStats = stats, pvpResets = 7 } })
    assert.are.equal(stats, db.global.pvpStats)
    assert.are.same({}, db.global.pvpResets)
  end)

  it("gives every character a revision for its PvP record", function()
    local db = Store.Load({})
    assert.are.equal(0, Store.GetChar(db, "Me-Realm").pvpSync.rev)
    db.chars["Me-Realm"].pvpSync.rev = 4
    assert.are.equal(4, Store.GetChar(db, "Me-Realm").pvpSync.rev)
    db.chars["Me-Realm"].pvpSync = { rev = -3 }
    assert.are.equal(0, Store.GetChar(db, "Me-Realm").pvpSync.rev)
    db.chars["Me-Realm"].pvpSync = { rev = "x" }
    assert.are.equal(0, Store.GetChar(db, "Me-Realm").pvpSync.rev)
  end)
end)

describe("Store migration to schema 7", function()
  local Store = load_store()

  it("creates the PvP settings table and keeps the other settings", function()
    local raw = { global = { schemaVersion = 6, settings = { minimap = { angle = 90 }, pvp = nil } } }
    local db = Store.Load(raw)
    assert.are.equal(12, db.global.schemaVersion)
    assert.are.same({}, db.global.settings.pvp)
    assert.are.equal(90, db.global.settings.minimap.angle)
  end)

  it("is idempotent and keeps the choices already made", function()
    local raw = { global = { schemaVersion = 6, settings = { pvp = { feedWorld = false, feedBg = true } } } }
    local db = Store.Load(raw)
    assert.are.same({ feedWorld = false, feedBg = true }, db.global.settings.pvp)
    local again = Store.Load(db, 12)
    assert.are.same({ feedWorld = false, feedBg = true }, again.global.settings.pvp)
    -- Running the migration again over an already migrated database changes nothing.
    db.global.schemaVersion = 6
    assert.are.same({ feedWorld = false, feedBg = true }, Store.Load(db).global.settings.pvp)
  end)

  it("repairs a settings value that is not a table", function()
    local db = Store.Load({ global = { schemaVersion = 6, settings = { pvp = "oops" } } })
    assert.are.same({}, db.global.settings.pvp)
  end)
end)

describe("Store migration to schema 8", function()
  local Store = load_store()

  it("creates the blacklist and keeps the rest", function()
    local raw =
      { global = { schemaVersion = 7, roster = { x = 1 }, sync = { tombstones = { ["B:x"] = { rev = 2 } } } } }
    local db = Store.Load(raw)
    assert.are.equal(12, db.global.schemaVersion)
    assert.are.same({}, db.global.blacklist)
    assert.are.same({ x = 1 }, db.global.roster)
    assert.are.equal(2, db.global.sync.tombstones["B:x"].rev)
  end)

  it("is idempotent and keeps the entries already saved", function()
    local entry = { name = "Bad Guy", reason = "ninja", rev = 1 }
    local db = Store.Load({ global = { schemaVersion = 7, blacklist = { badguy = entry } } })
    assert.are.equal(entry, db.global.blacklist.badguy)
    -- Running the migration again over an already migrated database changes nothing.
    db.global.schemaVersion = 7
    assert.are.equal(entry, Store.Load(db).global.blacklist.badguy)
  end)

  it("repairs a blacklist that is not a table", function()
    local db = Store.Load({ global = { schemaVersion = 7, blacklist = "oops" } })
    assert.are.same({}, db.global.blacklist)
  end)

  it("gives a new database an empty blacklist", function()
    assert.are.same({}, Store.Load(nil).global.blacklist)
  end)
end)

describe("Store migration to schema 9", function()
  local Store = load_store()

  it("adds an empty readinessRules table and keeps what is there", function()
    local db = Store.Load({ global = { schemaVersion = 8, blacklist = { x = { name = "X" } } } })
    assert.are.equal(12, db.global.schemaVersion)
    assert.are.same({}, db.global.readinessRules)
    assert.are.equal("X", db.global.blacklist.x.name)
  end)

  it("keeps rules that were already saved", function()
    local rules = { rev = 2, rules = { { id = "level" } } }
    local db = Store.Load({ global = { schemaVersion = 8, readinessRules = rules } })
    assert.are.equal(2, db.global.readinessRules.rev)
  end)
end)

describe("Store migration to schema 10", function()
  local Store = load_store()

  it("adds the empty rosters and members tables and keeps what is there", function()
    local db = Store.Load({ global = { schemaVersion = 9, events = { e = { title = "Raid" } } } })
    assert.are.equal(12, db.global.schemaVersion)
    assert.are.same({}, db.global.rosters)
    assert.are.same({}, db.global.members)
    assert.are.equal("Raid", db.global.events.e.title)
  end)

  it("keeps rosters and assignments that were already saved", function()
    local rosters = { r1 = { id = "r1", name = "Main" } }
    local members = { ["Ann-Realm"] = { role = "rl", rosterId = "r1" } }
    local db = Store.Load({ global = { schemaVersion = 9, rosters = rosters, members = members } })
    assert.are.equal("Main", db.global.rosters.r1.name)
    assert.are.equal("rl", db.global.members["Ann-Realm"].role)
  end)

  it("leaves the events without a roster: they are legacy events", function()
    local db = Store.Load({ global = { schemaVersion = 9, events = { e = { title = "Raid" } } } })
    assert.is_nil(db.global.events.e.rosterId)
  end)
end)

describe("Store migration to schema 11", function()
  local Store = load_store()

  it("adds the received recipes table and gives every saved character a recipes table", function()
    local db = Store.Load({ global = { schemaVersion = 10 }, chars = { ["Ann-Realm"] = { profile = {} } } })
    assert.are.equal(12, db.global.schemaVersion)
    assert.are.same({}, db.global.recipes)
    assert.are.same({}, db.chars["Ann-Realm"].recipes)
  end)

  it("keeps recipes that were already saved", function()
    local recipes = { ["Ann-Realm"] = { [171] = { name = "Alchemy", ids = { 1 }, rev = 1 } } }
    local db = Store.Load({ global = { schemaVersion = 10, recipes = recipes }, chars = {} })
    assert.are.equal("Alchemy", db.global.recipes["Ann-Realm"][171].name)
  end)

  it("creates the recipes table of a new character", function()
    local db = Store.Load({})
    assert.are.same({}, Store.GetChar(db, "New-Realm").recipes)
  end)
end)

describe("Store migration to schema 12", function()
  local Store = load_store()

  it("adds the empty PvP season ledger and gives every saved character a mission log", function()
    local db = Store.Load({ global = { schemaVersion = 11 }, chars = { ["Ann-Realm"] = { profile = {} } } })
    assert.are.equal(12, db.global.schemaVersion)
    local season = db.global.pvpSeason
    for _, name in ipairs({
      "seasons",
      "missions",
      "prizes",
      "officers",
      "grants",
      "voids",
      "rejects",
      "queue",
      "finals",
      "deliveries",
    }) do
      assert.are.same({}, season[name])
    end
    assert.is_nil(season.activeId)
    assert.are.same({}, db.chars["Ann-Realm"].pvpMissions)
  end)

  it("is idempotent and keeps a ledger that was already saved", function()
    local ledger = { seasons = { s1 = { id = "s1", name = "One" } }, activeId = "s1", grants = { s1 = { g1 = {} } } }
    local db = Store.Load({ global = { schemaVersion = 11, pvpSeason = ledger }, chars = {} })
    assert.are.equal("One", db.global.pvpSeason.seasons.s1.name)
    assert.are.equal("s1", db.global.pvpSeason.activeId)
    assert.are.same({ g1 = {} }, db.global.pvpSeason.grants.s1)
    db.global.schemaVersion = 11
    assert.are.equal("One", Store.Load(db).global.pvpSeason.seasons.s1.name)
  end)

  it("creates the mission log of a new character", function()
    local db = Store.Load({})
    local char = Store.GetChar(db, "New-Realm")
    assert.are.same({}, char.pvpMissions.kills)
    assert.are.same({}, char.pvpMissions.claims)
  end)
end)

describe("Store migration to schema 13 (one table per guild)", function()
  local Store, Constants = load_store_current()

  it("is the current schema", function()
    assert.are.equal(17, Constants.SCHEMA_VERSION)
  end)

  it("builds the root layout from an empty database", function()
    local db = Store.Load(nil)
    assert.are.equal(17, db.schemaVersion)
    assert.are.same({}, db.guilds)
    assert.are.same({ minimap = {}, pvp = {} }, db.settings)
    assert.are.same({}, db.chars)
    assert.is_nil(db.global)
  end)

  it("drops the old global table, keeps the characters and is idempotent", function()
    local raw = {
      global = { schemaVersion = 12, roster = { x = 1 }, settings = { minimap = { angle = 90 } } },
      chars = { ["Me-Realm"] = { profile = { level = 60 } } },
    }
    local db = Store.Load(raw)
    assert.are.equal(raw, db)
    assert.is_nil(db.global)
    assert.are.equal(17, db.schemaVersion)
    assert.are.equal(60, db.chars["Me-Realm"].profile.level)
    db.settings.language = "es"
    local again = Store.Load(db)
    assert.are.equal("es", again.settings.language)
    assert.are.equal(17, again.schemaVersion)
  end)

  it("refuses data from a newer schema", function()
    local raw = { schemaVersion = 99, guilds = { ["club:1"] = {} } }
    local db, err = Store.Load(raw)
    assert.is_nil(db)
    assert.are.equal("newer_schema", err)
    assert.are.equal(99, raw.schemaVersion)
  end)
end)

describe("Store.ForGuild", function()
  local Store = load_store_current()

  it("creates every table the code reads", function()
    local guild = Store.ForGuild(Store.Load(nil), "club:1")
    for _, name in ipairs({
      "roster",
      "events",
      "loot",
      "templates",
      "pvpStats",
      "pvpResets",
      "blacklist",
      "readinessRules",
      "rosters",
      "members",
      "recipes",
    }) do
      assert.is_table(guild[name], name)
    end
    assert.is_table(guild.sync.seen)
    assert.is_table(guild.sync.tombstones)
    assert.is_table(guild.pvpSeason.seasons)
    assert.is_table(guild.pvpSeason.deliveries)
  end)

  it("keeps the data of two guilds apart", function()
    local db = Store.Load(nil)
    local a = Store.ForGuild(db, "club:1")
    local b = Store.ForGuild(db, "name:Other-Realm")
    a.roster["Ann-Realm"] = { level = 60 }
    a.events.e1 = { title = "Raid" }
    a.loot.l1 = {}
    a.sync.tombstones.t = {}
    a.members.m = {}
    assert.are_not.equal(a, b)
    for _, name in ipairs({ "roster", "events", "loot", "members" }) do
      assert.are_not.equal(a[name], b[name], name)
      assert.is_nil(next(b[name]), name)
    end
    assert.is_nil(next(b.sync.tombstones))
    assert.are.equal(a, Store.ForGuild(db, "club:1"))
  end)

  it("repairs a guild table that is damaged", function()
    local db = Store.Load({ guilds = { ["club:1"] = { roster = "oops", sync = 5 } } })
    local guild = Store.ForGuild(db, "club:1")
    assert.is_table(guild.roster)
    assert.is_table(guild.sync.seen)
  end)
end)

describe("Store.View", function()
  local Store = load_store_current()

  it("exposes one guild, the account settings and the characters, and is never part of the root", function()
    local db = Store.Load(nil)
    local view = Store.View(db, "club:1")
    assert.are.equal(db.guilds["club:1"], view.global)
    assert.are.equal(db.settings, view.settings)
    assert.are.equal(db.chars, view.chars)
    assert.are.equal(db, view.root)
    assert.are.equal(17, view.schemaVersion)
    for _, value in pairs(db) do
      assert.are_not.equal(view, value)
    end
  end)

  it("shares the account settings between two guilds but not their data", function()
    local db = Store.Load(nil)
    local a, b = Store.View(db, "club:1"), Store.View(db, "club:2")
    a.settings.language = "es"
    assert.are.equal("es", b.settings.language)
    a.global.events.e = { title = "Raid" }
    assert.is_nil(b.global.events.e)
  end)
end)

describe("Store.ResolveGuildKey", function()
  local Store = load_store_current()
  local club = { key = "club:7", source = "club", name = "G", realm = "R" }
  local byName = { key = "name:G-R", source = "name", name = "G", realm = "R" }

  it("uses the club entry when it exists", function()
    local db = Store.Load(nil)
    db.guilds["club:7"] = { marker = "club" }
    db.guilds["name:G-R"] = { marker = "name" }
    assert.are.equal("club:7", Store.ResolveGuildKey(db, club))
    assert.are.equal("name", db.guilds["name:G-R"].marker)
  end)

  it("moves the name entry to the club key when the club id appears late", function()
    local db = Store.Load(nil)
    local data = { marker = "name" }
    db.guilds["name:G-R"] = data
    assert.are.equal("club:7", Store.ResolveGuildKey(db, club))
    assert.are.equal(data, db.guilds["club:7"])
    assert.is_nil(db.guilds["name:G-R"])
  end)

  it("never overwrites an existing club entry and starts fresh when there is nothing to move", function()
    local db = Store.Load(nil)
    assert.are.equal("club:7", Store.ResolveGuildKey(db, club))
    assert.is_nil(db.guilds["club:7"])
  end)

  it("uses the club entry with the same saved name and realm when only the name key is available", function()
    local db = Store.Load(nil)
    Store.View(db, "club:7", club).global.roster.A = {}
    Store.View(db, "club:8", { key = "club:8", name = "Other", realm = "R" })
    assert.are.equal("club:7", Store.ResolveGuildKey(db, byName))
    assert.is_nil(db.guilds["name:G-R"])
  end)

  it("uses the name key when no club entry matches", function()
    local db = Store.Load(nil)
    Store.View(db, "club:8", { key = "club:8", name = "Other", realm = "R" })
    assert.are.equal("name:G-R", Store.ResolveGuildKey(db, byName))
  end)

  it("saves the name and realm of the guild and keeps them when the client stops returning them", function()
    local db = Store.Load(nil)
    Store.View(db, "club:7", club)
    Store.View(db, "club:7", { key = "club:7", source = "club" })
    assert.are.same({ name = "G", realm = "R" }, db.guilds["club:7"].meta)
  end)
end)

-- From schema 14 on the migrations work inside every guilds[key], and the account-wide settings at the root.
describe("Store migrations 14 to 17", function()
  local Store, Constants = load_store_current()

  local function at13(guilds, extra)
    local raw = { schemaVersion = 13, guilds = guilds, settings = { minimap = {}, pvp = {} }, chars = {} }
    for key, value in pairs(extra or {}) do
      raw[key] = value
    end
    return raw
  end

  local function rosters()
    return { r1 = { id = "r1", name = "A" }, r2 = { id = "r2", name = "B" } }
  end

  describe("v14 readiness rules per roster", function()
    it("copies the guild rules into every roster of every guild and leaves the old key alone", function()
      local old =
        { rev = 4, updatedAt = 90, updatedBy = "Boss-Realm", rules = { { id = "level", check = "level", min = 60 } } }
      local db = Store.Load(at13({
        ["club:1"] = { rosters = rosters(), readinessRules = old },
        ["club:2"] = { rosters = { r9 = { id = "r9", name = "Z" } } },
      }))
      assert.are.equal(Constants.SCHEMA_VERSION, db.schemaVersion)
      local first = db.guilds["club:1"].readinessRulesByRoster
      for _, id in ipairs({ "r1", "r2" }) do
        assert.are.same({ 4, 90, "Boss-Realm" }, { first[id].rev, first[id].updatedAt, first[id].updatedBy })
        assert.are.same(old.rules, first[id].rules)
      end
      assert.are_not.equal(first.r1.rules, first.r2.rules)
      assert.are.equal(old, db.guilds["club:1"].readinessRules)
      -- The other guild never sees the rules of the first, and starts from the starting list.
      local second = db.guilds["club:2"].readinessRulesByRoster
      assert.are.same(Constants.DEFAULT_RULES, second.r9.rules)
      assert.are.equal(0, second.r9.rev)
      assert.is_nil(second.r1)
    end)

    it("adds an empty table to a guild without rosters", function()
      local db = Store.Load(at13({ ["club:1"] = {} }))
      assert.are.same({}, db.guilds["club:1"].readinessRulesByRoster)
    end)

    it("is idempotent and keeps a record that was already there", function()
      local mine = { rev = 9, rules = { { id = "x" } } }
      local db = Store.Load(at13({ ["club:1"] = { rosters = rosters(), readinessRulesByRoster = { r1 = mine } } }))
      assert.are.equal(mine, db.guilds["club:1"].readinessRulesByRoster.r1)
      assert.is_table(db.guilds["club:1"].readinessRulesByRoster.r2)
      db.schemaVersion = 13
      assert.are.equal(mine, Store.Load(db).guilds["club:1"].readinessRulesByRoster.r1)
    end)

    it("gives a new guild the table through ForGuild", function()
      local db = Store.Load(nil)
      assert.are.same({}, Store.ForGuild(db, "club:5").readinessRulesByRoster)
    end)
  end)

  describe("v15 position sharing on by default", function()
    it("turns sharing on once for an existing account and leaves a notice", function()
      local db = Store.Load(at13({}, { settings = { position = { share = false } } }))
      assert.is_true(db.settings.position.share)
      assert.is_true(db.settings.positionShareNotice)
    end)

    it("leaves no notice when sharing was on or never saved", function()
      local on = Store.Load(at13({}, { settings = { position = { share = true } } }))
      assert.is_nil(on.settings.positionShareNotice)
      assert.is_nil(Store.Load(nil).settings.positionShareNotice)
    end)

    it("does not turn it on again after the player turned it off", function()
      local db = Store.Load(at13({}, { settings = { position = { share = false } } }))
      db.settings.position.share = false
      db.settings.positionShareNotice = nil
      db.schemaVersion = 15
      local again = Store.Load(db)
      assert.is_false(again.settings.position.share)
      assert.is_nil(again.settings.positionShareNotice)
    end)
  end)

  describe("v16 accented capitals in blacklist keys", function()
    local A_ACUTE_UPPER, A_ACUTE = "\195\129", "\195\161"

    it("rebuilds a key saved with an accented capital and its removal mark, in every guild", function()
      local function guild()
        return {
          blacklist = {
            [A_ACUTE_UPPER .. "ngel"] = { name = A_ACUTE_UPPER .. "ngel", rev = 2 },
            plain = { name = "Plain", rev = 1 },
          },
          sync = { tombstones = { ["B:" .. A_ACUTE_UPPER .. "lex"] = { rev = 3 }, ["L:x"] = { rev = 1 } } },
        }
      end
      local db = Store.Load(at13({ ["club:1"] = guild(), ["club:2"] = guild() }, { schemaVersion = 15 }))
      for _, key in ipairs({ "club:1", "club:2" }) do
        local blacklist = db.guilds[key].blacklist
        assert.is_nil(blacklist[A_ACUTE_UPPER .. "ngel"])
        assert.are.equal(A_ACUTE_UPPER .. "ngel", blacklist[A_ACUTE .. "ngel"].name)
        assert.is_table(blacklist.plain)
        local tombstones = db.guilds[key].sync.tombstones
        assert.is_nil(tombstones["B:" .. A_ACUTE_UPPER .. "lex"])
        assert.are.equal(3, tombstones["B:" .. A_ACUTE .. "lex"].rev)
        assert.are.equal(1, tombstones["L:x"].rev)
      end
    end)

    it("keeps the higher revision when both keys exist", function()
      local db = Store.Load(at13({
        ["club:1"] = {
          blacklist = {
            [A_ACUTE_UPPER .. "ngel"] = { name = "old", rev = 5 },
            [A_ACUTE .. "ngel"] = { name = "new", rev = 2 },
          },
        },
      }, { schemaVersion = 15 }))
      assert.are.equal("old", db.guilds["club:1"].blacklist[A_ACUTE .. "ngel"].name)
    end)
  end)

  describe("v17 rank map", function()
    it("leaves a guild without a rank map as it is and keeps the one already saved", function()
      local saved = { rev = 2, updatedAt = 5, by = "Boss-Realm", ranks = { [1] = { role = "cogm", name = "Two" } } }
      local db = Store.Load(at13({ ["club:1"] = {}, ["club:2"] = { rankMap = saved } }, { schemaVersion = 16 }))
      assert.is_nil(db.guilds["club:1"].rankMap)
      assert.are.same(saved, db.guilds["club:2"].rankMap)
    end)

    it("drops a damaged rank map without raising", function()
      local db = Store.Load(at13({ ["club:1"] = { rankMap = "oops" } }, { schemaVersion = 16 }))
      assert.is_nil(db.guilds["club:1"].rankMap)
    end)

    it("keeps the maps of two guilds apart", function()
      local db = Store.Load(nil)
      Store.ForGuild(db, "club:1").rankMap = { rev = 1, ranks = {} }
      assert.is_nil(Store.ForGuild(db, "club:2").rankMap)
    end)
  end)
end)
