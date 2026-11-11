local _, ns = ...

-- SavedVariables layout and migrations. Plain tables (no AceDB yet). The root of GuildAssistantDB is:
--   { schemaVersion, settings = { minimap, pvp, language, blacklistSound, layer, position, windows },
--     guilds = { [guildKey] = <guild data, below> }, chars = { [identityKey] = <character data, below> } }
-- Settings are account-wide so they work before the guild is known. The data of a guild never mixes with another's:
-- at runtime ns.db is a view { global = guilds[key], settings, chars, root } built on activation (Core/Init.lua),
-- so the code reads ns.db.global without knowing about the guild key. The view is never saved.
--   guilds[guildKey] = { meta = { name, realm }, roster, events, loot, templates,
--                 sync = { seen, tombstones }, pvpStats = {}, pvpResets = {},
--                 blacklist = {}, readinessRulesByRoster = { [rosterId] = { rev, updatedAt, updatedBy, rules } },
--                 rosters = { [id] = { id, name, rev, ... } }, members = { [key] = { role, rosterId, rev, ... } },
--                 recipes = { [memberKey] = { [professionId] = { name, ids, rev, receivedAt } } },
--                 rankMap = { rev, updatedAt, by, ranks } (absent until a gm or cogm saves one, see RankMapModel),
--                 pvpSeason = { seasons, activeId, missions, prizes, officers, grants, voids, rejects, queue, finals,
--                               deliveries } (see PvPSeasonSync),
--                 installs = { [name] = { version, incompatible, seenAt } } (see InstallDirectory),
--                 announcements = { items, tombstones, openedAt } and announcementsSeen = { [id] = popupRev }
--                 (see AnnouncementService),
--                 intel = { players, kos, ignore, zones } (see IntelService), guildKos = { [key] = entry } (see
--                 GuildKosService; its removals are tombstones "K:<key>") }
--   db.chars[identityKey] = { profile = {}, readiness = {}, publish = {}, pvp = {}, recipes = {},
--                             pvpSync = { rev }, pvpLog = { events = {}, version }, pvpClaims = { [seasonId] = {
--                             [claimId] = { claim, state } } } }
-- The characters are account-wide (one table per identity key), so their migrations run over db.chars, not per guild.
local Store = {}

local function ensureTable(parent, key)
  if type(parent[key]) ~= "table" then
    parent[key] = {}
  end
  return parent[key]
end

local PVP_SEASON_TABLES = {
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
}

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for key, inner in pairs(value) do
    copy[key] = deepCopy(inner)
  end
  return copy
end

-- Runs `fn(guild)` on the data table of every guild (the migrations from v14 on work inside each guilds[key]).
local function forEachGuild(db, fn)
  for _, guild in pairs(ensureTable(db, "guilds")) do
    if type(guild) == "table" then
      fn(guild)
    end
  end
end

-- Each entry upgrades a db to that version. All of them must be idempotent. Up to version 12 the guild data lived in
-- db.global; version 13 drops it (no installs existed) and moves to db.guilds / db.settings.
local MIGRATIONS = {
  [1] = function() end,
  [2] = function(db)
    local global = ensureTable(db, "global")
    ensureTable(global, "roster")
    ensureTable(global, "events")
    ensureTable(global, "loot")
    local sync = ensureTable(global, "sync")
    ensureTable(sync, "seen")
    ensureTable(sync, "tombstones")
    ensureTable(db, "chars")
    -- v1 kept the version at the top level.
    db.schemaVersion = nil
  end,
  -- v3: reusable assignment templates.
  [3] = function(db)
    ensureTable(ensureTable(db, "global"), "templates")
  end,
  -- v4: account-wide settings, starting with the minimap button (see MinimapButton.Settings).
  [4] = function(db)
    ensureTable(ensureTable(ensureTable(db, "global"), "settings"), "minimap")
  end,
  -- v5: per-character PvP counters (char.pvp, filled by PvPService.Ensure). Nothing global changes; GetChar
  -- creates the table for each character, so this only makes sure the characters already saved have it.
  [5] = function(db)
    for _, char in pairs(ensureTable(db, "chars")) do
      if type(char) == "table" then
        ensureTable(char, "pvp")
      end
    end
  end,
  -- v6: PvP counters received from the guild (pvpStats[ownerKey]) and the minimum revision accepted for a
  -- member after an admin reset (pvpResets[ownerKey]); GetChar creates the revision of the own record.
  [6] = function(db)
    local global = ensureTable(db, "global")
    ensureTable(global, "pvpStats")
    ensureTable(global, "pvpResets")
  end,
  -- v7: account-wide PvP settings table (db.global.settings.pvp). The kill feed switches that lived there are
  -- gone: every kill is shared; the table is kept so older data migrates unchanged.
  [7] = function(db)
    ensureTable(ensureTable(ensureTable(db, "global"), "settings"), "pvp")
  end,
  -- v8: the guild blacklist (blacklist[nameKey], see BlacklistService). Its removals are tombstones "B:<key>" in
  -- sync.tombstones, which already exists.
  [8] = function(db)
    ensureTable(ensureTable(db, "global"), "blacklist")
  end,
  -- v9: the guild's readiness rules (readinessRules = { rev, updatedAt, updatedBy, rules }, see ReadinessRules).
  -- Empty until an admin sets them; the starting checklist applies meanwhile.
  [9] = function(db)
    ensureTable(ensureTable(db, "global"), "readinessRules")
  end,
  -- v10: raid rosters (rosters[id]) and the role and roster of each member (members[key]), both set by the guild
  -- master (see RosterService). Existing events and templates have no rosterId: they stay as they are (legacy).
  [10] = function(db)
    local global = ensureTable(db, "global")
    ensureTable(global, "rosters")
    ensureTable(global, "members")
  end,
  -- v11: recipes received from the guild (recipes[memberKey][professionId], see RecipeService); the own character keeps
  -- its scans in char.recipes, which GetChar creates.
  [11] = function(db)
    ensureTable(ensureTable(db, "global"), "recipes")
    for _, char in pairs(ensureTable(db, "chars")) do
      if type(char) == "table" then
        ensureTable(char, "recipes")
      end
    end
  end,
  -- v12: the PvP season ledger (see PvPSeasonSync) and the per-character mission log. activeId stays nil until an
  -- admin creates a season.
  [12] = function(db)
    local global = ensureTable(db, "global")
    local season = ensureTable(global, "pvpSeason")
    for _, name in ipairs(PVP_SEASON_TABLES) do
      ensureTable(season, name)
    end
    for _, char in pairs(ensureTable(db, "chars")) do
      if type(char) == "table" then
        ensureTable(char, "pvpMissions")
      end
    end
  end,
  -- v13: one table of data per guild (guilds[guildKey], see Store.ForGuild) and account-wide settings at the root.
  [13] = function(db)
    ensureTable(db, "guilds")
    local settings = ensureTable(db, "settings")
    ensureTable(settings, "minimap")
    ensureTable(settings, "pvp")
    ensureTable(db, "chars")
    db.global = nil
  end,
  -- v14: readiness rules per roster (readinessRulesByRoster[rosterId], see ReadinessRules). Every existing roster
  -- starts with a copy of the guild-wide record (readinessRules, or the starting list while none was set); the old key
  -- stays but nothing reads it any more. A roster created later has no record and uses the starting list.
  [14] = function(db)
    forEachGuild(db, function(guild)
      local byRoster = ensureTable(guild, "readinessRulesByRoster")
      local old = type(guild.readinessRules) == "table" and guild.readinessRules or {}
      local rules = type(old.rules) == "table" and #old.rules > 0 and old.rules or ns.Constants.DEFAULT_RULES
      for id in pairs(ensureTable(guild, "rosters")) do
        if type(byRoster[id]) ~= "table" then
          byRoster[id] = {
            rev = type(old.rev) == "number" and old.rev or 0,
            updatedAt = type(old.updatedAt) == "number" and old.updatedAt or 0,
            updatedBy = old.updatedBy,
            rules = deepCopy(rules),
          }
        end
      end
    end)
  end,
  -- v15: sharing the position became the default. Until now every client saved share = false without the player
  -- choosing it, so an explicit choice cannot be told apart: it is turned on once, and the player is told at login
  -- (PositionModel.TakeShareNotice). Turning it off afterwards stays off. The setting is account-wide.
  [15] = function(db)
    local settings = ensureTable(db, "settings")
    local position = settings.position
    if type(position) == "table" and position.share == false then
      position.share = true
      settings.positionShareNotice = true
    end
  end,
  -- v16: NameKey lowers the accented capitals of UTF-8 names too. Blacklist keys saved before kept them (a capital
  -- A-acute in "Angel"), so they are rebuilt from the saved name, and so are the removal marks "B:<key>". When two keys
  -- end up equal, the one with the higher revision stays. Applied inside every guild.
  [16] = function(db)
    local function rekey(map, prefix)
      local moves = {}
      for key, value in pairs(map) do
        if type(key) == "string" and key:sub(1, #prefix) == prefix then
          local fresh = prefix .. ns.Validate.NameKey(key:sub(#prefix + 1))
          if fresh ~= key then
            moves[#moves + 1] = { from = key, to = fresh, value = value }
          end
        end
      end
      table.sort(moves, function(a, b)
        return a.from < b.from
      end)
      for _, move in ipairs(moves) do
        map[move.from] = nil
        local current = map[move.to]
        local currentRev = type(current) == "table" and current.rev or -1
        local movedRev = type(move.value) == "table" and move.value.rev or -1
        if type(currentRev) ~= "number" or type(movedRev) ~= "number" or movedRev > currentRev then
          map[move.to] = move.value
        end
      end
    end
    forEachGuild(db, function(guild)
      rekey(ensureTable(guild, "blacklist"), "")
      rekey(ensureTable(ensureTable(guild, "sync"), "tombstones"), "B:")
    end)
  end,
  -- v17: the rank map of each guild (guild.rankMap = { rev, updatedAt, by, ranks }, see RankMapModel). There is none
  -- until a gm or cogm saves one; every rank outside the map is a member until then. A damaged value is dropped.
  [17] = function(db)
    forEachGuild(db, function(guild)
      if guild.rankMap ~= nil and type(guild.rankMap) ~= "table" then
        guild.rankMap = nil
      end
    end)
  end,
  -- v18: who in each guild runs the addon and which version (installs, see InstallDirectory), for the Installed check
  -- tab. Nothing else is touched.
  [18] = function(db)
    forEachGuild(db, function(guild)
      ensureTable(guild, "installs")
    end)
  end,
  -- v19: the PvP log does not belong to a season any more. char.pvpMissions = { seasonId, kills, claims } becomes
  -- char.pvpLog = { events, version } (the kill rows and the battleground wins, in time order, newest
  -- PVP_LOG_EVENTS_MAX kept) and char.pvpClaims[seasonId]. Nothing is lost and the old table is removed, so running it
  -- again changes nothing. Characters are account-wide: every one in db.chars is migrated, whatever its guild.
  [19] = function(db)
    local maxEvents = ns.Constants.PVP_LOG_EVENTS_MAX
    for _, char in pairs(ensureTable(db, "chars")) do
      if type(char) == "table" then
        local log = ensureTable(char, "pvpLog")
        local events = ensureTable(log, "events")
        if type(log.version) ~= "number" then
          log.version = 1
        end
        local claims = ensureTable(char, "pvpClaims")
        local old = char.pvpMissions
        if type(old) == "table" then
          for _, row in ipairs(type(old.kills) == "table" and old.kills or {}) do
            if type(row) == "table" and type(row.at) == "number" then
              if row.bgWin then
                events[#events + 1] = { kind = "bg", result = "win", at = row.at, mapId = row.mapId }
              else
                row.kind = row.kind or "kill"
                row.honor = true
                events[#events + 1] = row
              end
            end
          end
          local order = {}
          for index, row in ipairs(events) do
            order[row] = index
          end
          table.sort(events, function(a, b)
            if a.at ~= b.at then
              return a.at < b.at
            end
            return order[a] < order[b]
          end)
          while #events > maxEvents do
            table.remove(events, 1)
          end
          if type(old.seasonId) == "string" and type(old.claims) == "table" then
            local held = ensureTable(claims, old.seasonId)
            for id, entry in pairs(old.claims) do
              if held[id] == nil then
                held[id] = entry
              end
            end
          end
          char.pvpMissions = nil
        end
      end
    end
  end,
  -- v20: the announcements of each guild (announcements = { items, tombstones, openedAt }, see AnnouncementService)
  -- and the popups this account has already seen in that guild (announcementsSeen[id] = popupRev). Announcement ids
  -- are only unique inside a guild, so both live in the guild data. Nothing else is touched.
  [20] = function(db)
    forEachGuild(db, function(guild)
      local announcements = ensureTable(guild, "announcements")
      ensureTable(announcements, "items")
      ensureTable(announcements, "tombstones")
      ensureTable(guild, "announcementsSeen")
    end)
  end,
  -- v21: Intel: the enemy player records with the personal Kill On Sight and Ignore lists (guild.intel) and the guild
  -- Kill On Sight list (guild.guildKos, whose removals are tombstones "K:<key>"). Both live inside every guild's data.
  -- The notice that sharing sightings is on by default is left by Settings.Intel when it first creates the account
  -- settings of Intel; nothing else is touched, so running this again changes nothing.
  [21] = function(db)
    forEachGuild(db, function(guild)
      local intel = ensureTable(guild, "intel")
      for _, name in ipairs({ "players", "kos", "ignore", "zones" }) do
        ensureTable(intel, name)
      end
      ensureTable(guild, "guildKos")
    end)
  end,
}

local function versionOf(db)
  local global = type(db.global) == "table" and db.global or nil
  local version = (global and global.schemaVersion) or db.schemaVersion
  if type(version) == "number" and version >= 0 and version % 1 == 0 then
    return version
  end
  return 0
end

-- Returns db, or nil plus "newer_schema" when the saved data comes from a newer addon version.
-- In that case the raw table is left untouched so the local data survives a downgrade.
function Store.Load(raw, targetVersion)
  targetVersion = targetVersion or ns.Constants.SCHEMA_VERSION
  local db = type(raw) == "table" and raw or {}

  local version = versionOf(db)
  if version > targetVersion then
    return nil, "newer_schema"
  end

  for target = version + 1, targetVersion do
    MIGRATIONS[target](db)
  end
  if targetVersion >= 13 then
    db.schemaVersion = targetVersion
  else
    ensureTable(db, "global").schemaVersion = targetVersion
  end
  return db
end

-- The data table of one guild, created with every sub-table the code reads. Two guild keys never share a table.
function Store.ForGuild(db, guildKey)
  local guild = ensureTable(ensureTable(db, "guilds"), guildKey)
  for _, name in ipairs({
    "roster",
    "events",
    "loot",
    "templates",
    "pvpStats",
    "pvpResets",
    "blacklist",
    "readinessRules",
    "readinessRulesByRoster",
    "rosters",
    "members",
    "recipes",
    "installs",
    "announcementsSeen",
    "guildKos",
  }) do
    ensureTable(guild, name)
  end
  local announcements = ensureTable(guild, "announcements")
  ensureTable(announcements, "items")
  ensureTable(announcements, "tombstones")
  local intel = ensureTable(guild, "intel")
  for _, name in ipairs({ "players", "kos", "ignore", "zones" }) do
    ensureTable(intel, name)
  end
  local sync = ensureTable(guild, "sync")
  ensureTable(sync, "seen")
  ensureTable(sync, "tombstones")
  local season = ensureTable(guild, "pvpSeason")
  for _, name in ipairs(PVP_SEASON_TABLES) do
    ensureTable(season, name)
  end
  return guild
end

local function nameKeyOf(identity)
  if identity.name and identity.realm then
    return ("name:%s-%s"):format(identity.name, identity.realm)
  end
  return nil
end

-- The key under which the data of the guild described by `identity` (GuildIdentity.Current) is saved. The club id can
-- be unavailable at one login and available at the next, so one guild must not end up with two data sets:
--   1. a club key whose entry exists: use it;
--   2. a club key without an entry, but an entry under the name key: move it to the club key (never over an existing
--      entry) and use it;
--   3. only a name key: use the club entry whose saved meta has the same name and realm, else the name key.
function Store.ResolveGuildKey(db, identity)
  local guilds = ensureTable(db, "guilds")
  local nameKey = nameKeyOf(identity)
  if identity.source == "club" then
    if guilds[identity.key] == nil and nameKey and type(guilds[nameKey]) == "table" then
      guilds[identity.key] = guilds[nameKey]
      guilds[nameKey] = nil
    end
    return identity.key
  end
  local matches = {}
  for key, guild in pairs(guilds) do
    local meta = type(guild) == "table" and guild.meta
    if
      type(key) == "string"
      and key:sub(1, 5) == "club:"
      and type(meta) == "table"
      and meta.name == identity.name
      and meta.realm == identity.realm
    then
      matches[#matches + 1] = key
    end
  end
  table.sort(matches)
  return matches[1] or identity.key
end

-- The runtime view of the saved root for one guild. Never assign it back to the SavedVariable. With `identity`, the
-- name and realm of the guild are saved in guild.meta (kept when the client does not return them).
function Store.View(db, guildKey, identity)
  local guild = Store.ForGuild(db, guildKey)
  if identity then
    local meta = ensureTable(guild, "meta")
    meta.name = identity.name or meta.name
    meta.realm = identity.realm or meta.realm
  end
  return {
    global = guild,
    settings = db.settings,
    chars = db.chars,
    root = db,
    guildKey = guildKey,
    schemaVersion = db.schemaVersion,
  }
end

function Store.GetChar(db, identityKey)
  local char = ensureTable(db.chars, identityKey)
  ensureTable(char, "profile")
  ensureTable(char, "readiness")
  ensureTable(char, "publish")
  ensureTable(char, "pvp")
  ensureTable(char, "recipes")
  local log = ensureTable(char, "pvpLog")
  ensureTable(log, "events")
  if type(log.version) ~= "number" then
    log.version = 1
  end
  ensureTable(char, "pvpClaims")
  local sync = ensureTable(char, "pvpSync")
  if type(sync.rev) ~= "number" or sync.rev < 0 or sync.rev % 1 ~= 0 then
    sync.rev = 0
  end
  return char
end

ns.Store = Store
