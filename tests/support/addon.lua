-- Loads the addon files in the exact order the TOC lists them, so a file missing
-- from the TOC (or listed in the wrong order) fails the specs.
return function(ns)
  local toc = assert(io.open("GuildAssistant/GuildAssistant.toc", "r"))
  for line in toc:lines() do
    local path = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if path then
      path = "GuildAssistant/" .. path:gsub("\\", "/")
      assert(loadfile(path))("GuildAssistant", ns)
    end
  end
  toc:close()
  return ns
end
