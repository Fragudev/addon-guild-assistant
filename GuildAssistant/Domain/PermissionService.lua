local _, ns = ...

-- Who may do what. A message never gets to say what its sender is allowed to
-- do: roles are worked out by the receiver from its own data.
--
-- The role is the guild rank, in order of authority: gm, cogm, officer, rl (raid leader), roster, member, alter.
-- The guild master is always `gm`, recognised by the rank index 0 and never by name. Every other rank gets its role
-- from the rank map of the guild a gm or cogm saved (RankMapModel, by rank index, so a rename keeps the role); a rank
-- the map does not list is a `member`. No rank name is ever matched, so any guild can call its ranks what it wants.
--
-- The rank says what a player can do, the roster (RosterService) says where. Each action gives, per role, a scope:
--   "all": on every roster      "own": only on the roster of the player      absent: not allowed.
local PermissionService = {}

local ORDER = { "gm", "cogm", "officer", "rl", "roster", "member", "alter" }
local RANK = {}
for index, role in ipairs(ORDER) do
  RANK[role] = index - 1
end

local ALL, OWN = "all", "own"

-- Every rank can do these, on anything (they are about the player's own data or open to the whole guild).
local EVERYONE = { gm = ALL, cogm = ALL, officer = ALL, rl = ALL, roster = ALL, member = ALL, alter = ALL }
-- Only the guild master and the co-guild master.
local GLOBAL_ONLY = { gm = ALL, cogm = ALL }

local ACTIONS = {
  -- The Admin group of the sidebar: officer, rl and above.
  admin_view = { gm = ALL, cogm = ALL, officer = ALL, rl = ALL },
  events_view = { gm = ALL, cogm = ALL, officer = OWN, rl = OWN, roster = OWN },
  event_signup = { gm = ALL, cogm = ALL, officer = OWN, rl = OWN, roster = OWN },
  raidcheck_view = { gm = ALL, cogm = ALL, officer = OWN, rl = OWN, roster = OWN },
  -- Creating and changing events, attendance, assignments and templates.
  raid_manage = { gm = ALL, cogm = ALL, officer = OWN, rl = OWN },
  loot_view = { gm = ALL, cogm = ALL, officer = OWN, rl = OWN, roster = OWN },
  -- Opening a session, voting and awarding.
  loot_manage = { gm = ALL, cogm = ALL, officer = OWN, rl = OWN },
  -- Putting yourself forward as a candidate: roster and above, on the roster of the event.
  loot_apply = { gm = ALL, cogm = ALL, officer = OWN, rl = OWN, roster = OWN },
  -- Raid rosters and the assignment of members to them. Officer reads, rl will assign to its own roster (later phases).
  members_view = { gm = ALL, cogm = ALL, officer = ALL, rl = OWN },
  members_manage = { gm = ALL, cogm = ALL, rl = OWN },
  rules_view = { gm = ALL, cogm = ALL, officer = ALL, rl = OWN },
  -- Setting the readiness rules the roster is measured against.
  rules_edit = { gm = ALL, cogm = ALL, rl = OWN },
  pvp_admin = GLOBAL_ONLY,
  -- The Ranks tab (rank mapping): the Admin group reads it, only gm and cogm change it (RankMapSync adds the guards).
  ranks_manage = GLOBAL_ONLY,
  -- The Installed check tab: who runs the addon and which version. Only gm and cogm see it.
  install_check = GLOBAL_ONLY,
  -- Publishing, editing and deleting guild announcements. The receiver applies an announcement only from a sender
  -- who has this action (AnnouncementSync).
  announce_manage = GLOBAL_ONLY,

  edit_own_profile = EVERYONE,
  -- Sharing the own layer and taking part in a layer swap.
  layer_share = EVERYONE,
  -- Posting a group, applying to one and inviting an applicant (docs/PROTOCOL.md).
  lfg_use = EVERYONE,
  -- Sharing the own map position and showing the others.
  position_share = EVERYONE,
  pvp_publish = EVERYONE,
  pvp_claim = EVERYONE,
  -- Everybody shares the recipes of their own character (plan 3.10).
  recipes_publish = EVERYONE,
  -- The blacklist is open to add to and closed to remove from: anyone can warn the guild about a player, only the
  -- guild master and the co-guild master can take the warning back.
  blacklist_add = EVERYONE,
  blacklist_remove = GLOBAL_ONLY,
  -- Changing the reason of a player who is already listed: the member who added the entry may (see
  -- BlacklistService.CanEdit), and so may gm and cogm, for any entry.
  blacklist_edit_any = GLOBAL_ONLY,
  -- Intel (docs/PROTOCOL.md): sharing the sightings of enemy players, and the guild Kill On Sight list. Every member
  -- adds; the member who added an entry changes and removes it (GuildKosService.CanEdit, CanRemove), and so may gm
  -- and cogm, for any entry.
  intel_share = EVERYONE,
  kos_add = EVERYONE,
  kos_edit_any = GLOBAL_ONLY,
  kos_remove_any = GLOBAL_ONLY,
  moderate = GLOBAL_ONLY,
  -- PvP seasons (docs/PVP_MISSIONS_PLAN.md section 3): every member claims, gm and cogm do everything else.
  pvp_claim_decide = GLOBAL_ONLY,
  pvp_delivery_mark = GLOBAL_ONLY,
  pvp_grant_direct = GLOBAL_ONLY,
  pvp_grant_void = GLOBAL_ONLY,
  pvp_season_manage = GLOBAL_ONLY,
  pvp_mission_manage = GLOBAL_ONLY,
  pvp_prize_manage = GLOBAL_ONLY,
}

-- true for the guild master: rank index 0.
function PermissionService.IsGuildMasterIndex(rankIndex)
  return rankIndex == ns.Constants.GUILD_MASTER_RANK_INDEX
end

-- The rank map of the guild the player is in (docs/PROTOCOL.md, RANK_MAP), or nil while a gm or cogm has saved none.
-- Init installs the provider `ns.rankMap`; without one every rank but the guild master's is a `member`.
local function currentRankMap()
  return ns.rankMap and ns.rankMap() or nil
end

-- The roles a rank can be given in the rank map: every role but `gm`, which only the rank index 0 has.
PermissionService.ASSIGNABLE = { "cogm", "officer", "rl", "roster", "member", "alter" }
local ASSIGNABLE_SET = {}
for _, role in ipairs(PermissionService.ASSIGNABLE) do
  ASSIGNABLE_SET[role] = true
end

-- The role of a guild rank: index 0 is `gm`; an index the rank map covers gives its role, whatever the rank is
-- called; anything else is a `member`. `rankMap` defaults to the one of the current guild.
function PermissionService.RoleFor(rankIndex, rankMap)
  if PermissionService.IsGuildMasterIndex(rankIndex) then
    return "gm"
  end
  rankMap = rankMap or currentRankMap()
  local ranks = type(rankMap) == "table" and rankMap.ranks or nil
  local row = type(ranks) == "table" and type(rankIndex) == "number" and ranks[rankIndex] or nil
  if type(row) == "table" and ASSIGNABLE_SET[row.role] then
    return row.role
  end
  return "member"
end

-- Role of a guild roster entry ({ rankName, rankIndex }), or nil when it has no rank. The guild master is `gm`
-- whatever the rank is called. `rankMap` (optional) is the rank map to use instead of the one of the current guild.
function PermissionService.RoleOfEntry(entry, rankMap)
  if type(entry) ~= "table" or type(entry.rankIndex) ~= "number" then
    return nil
  end
  return PermissionService.RoleFor(entry.rankIndex, rankMap)
end

-- Role of `name` according to the local guild roster, or nil when the roster does not know them (not in the guild,
-- or the roster has not loaded yet). nil never grants anything.
-- options (optional): { rankMap = rank map }.
function PermissionService.RoleOf(guildRoster, name, options)
  return PermissionService.RoleOfEntry(guildRoster:Lookup(name), options and options.rankMap)
end

-- Own role. Without a rank (not in a guild) there is no role. The guild master is recognised by the rank index of
-- GetGuildInfo or by IsGuildLeader, whichever the client gives; the other roles come from the rank map.
function PermissionService.OwnRole(platform, options)
  local rankName, rankIndex = platform.GetOwnGuildRank()
  if type(rankName) ~= "string" or rankName == "" then
    return nil
  end
  if platform.IsGuildLeader and platform.IsGuildLeader() == true then
    return "gm"
  end
  return PermissionService.RoleFor(rankIndex, options and options.rankMap)
end

-- Order of authority: 0 for gm up to 6 for alter, nil for anything else. For `Rank(role) <= Rank("rl")` checks.
function PermissionService.Rank(role)
  return RANK[role]
end

-- gm and cogm see and act on every roster.
function PermissionService.IsGlobal(role)
  return role == "gm" or role == "cogm"
end

-- Where `role` may do `action`: "all", "own" or "none". "own" needs a roster: without one it is "none".
function PermissionService.Scope(role, action, ownRosterId)
  local actionScopes = ACTIONS[action]
  local scope = actionScopes and role ~= nil and actionScopes[role] or nil
  if scope == ALL then
    return "all"
  elseif scope == OWN and ownRosterId ~= nil then
    return "own"
  end
  return "none"
end

-- Does the role have the action at any scope? A role that has it on its own roster only still counts: the callers
-- that need more than that check IsGlobal, or the roster with RosterService.MayAct.
function PermissionService.Can(role, action)
  local actionScopes = ACTIONS[action]
  return actionScopes ~= nil and role ~= nil and actionScopes[role] ~= nil
end

-- Does the role have the action on every roster? For what an `own` scope must not do yet (see the callers).
function PermissionService.CanAll(role, action)
  return PermissionService.Scope(role, action) == "all"
end

ns.PermissionService = PermissionService
