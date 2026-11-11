local _, ns = ...

-- The rank map of the guild data set (db.global.rankMap) and the questions the interface asks about it
-- (docs/PROTOCOL.md, RANK_MAP). Pure: the stored map comes from `deps.read`, the roster from the caller. Saving and
-- receiving go through RankMapSync, which is where the authority checks live. There is one map per guild data set, so
-- characters in other guilds never share one.
local RankMapService = {}
RankMapService.__index = RankMapService

local Model = ns.RankMapModel

-- deps: read = function() -> the stored rank map or nil (the current guild data set is looked up at every call).
function RankMapService.New(deps)
  return setmetatable({ read = deps.read }, RankMapService)
end

-- The rank map of the current guild, or nil while none was saved (every rank but the guild master's is a member).
function RankMapService:Current()
  local rankMap = self.read()
  if type(rankMap) == "table" and type(rankMap.ranks) == "table" then
    return rankMap
  end
  return nil
end

-- The function PermissionService reads (ns.rankMap).
function RankMapService:Provider()
  return function()
    return self:Current()
  end
end

-- The rows an editor starts from (RankMapModel.Draft) for the saved map of the current guild.
function RankMapService:Draft(currentRanks)
  return Model.Draft(self:Current(), currentRanks)
end

-- Who changes role if `ranks` replaced the saved map (RankMapModel.Preview).
function RankMapService:Preview(guildRoster, ranks)
  return Model.Preview(guildRoster, self:Current(), ranks)
end

ns.RankMapService = RankMapService
