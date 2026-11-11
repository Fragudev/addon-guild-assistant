-- The two name rules of the Intel feature that the PvP bounties use (a bounty names one player). The Intel feature
-- itself is not part of this build: the addon loads these from Domain/IntelModel when it is. Specs install this stub
-- on their `ns` with `dofile("tests/support/intel_stub.lua")(ns)`.
local NAME_MAX = 40

return function(ns)
  local IntelModel = {}

  -- The key of a name: a "-Realm" suffix dropped, lowercase, no whitespace. Nil when nothing is left.
  function IntelModel.Key(name)
    if type(name) ~= "string" then
      return nil
    end
    local key = ns.Validate.NameKey(name:match("^([^%-]*)"))
    return key ~= "" and key or nil
  end

  -- The name as it is kept: realm suffix dropped, edges trimmed. Nil when it is empty, too long or holds ":" or "|".
  function IntelModel.CleanName(name)
    if type(name) ~= "string" then
      return nil
    end
    local clean = name:match("^([^%-]*)"):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if not ns.Validate.Text(clean, NAME_MAX) or clean:find(":", 1, true) then
      return nil
    end
    return clean
  end

  ns.IntelModel = IntelModel
  return IntelModel
end
