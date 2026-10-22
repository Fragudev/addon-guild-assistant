local function load_identity()
  local ns = {}
  assert(loadfile("GuildAssistant/Core/GuildIdentity.lua"))("GuildAssistant", ns)
  return ns.GuildIdentity
end

local function fake_platform(clubId, name, realm)
  return {
    GetGuildClubId = function()
      return clubId
    end,
    GetGuildName = function()
      return name
    end,
    GetRealmName = function()
      return realm
    end,
  }
end

describe("GuildIdentity.Current", function()
  local GuildIdentity = load_identity()

  it("keys the guild by its club id", function()
    local identity = GuildIdentity.Current(fake_platform(22626971, "Some Guild", "Realm"))
    assert.are.same({ key = "club:22626971", name = "Some Guild", realm = "Realm", source = "club" }, identity)
  end)

  it("accepts a club id that comes as a string", function()
    assert.are.equal("club:123", GuildIdentity.Current(fake_platform("123", "G", "R")).key)
  end)

  it("uses the club id even when the guild name is not known yet", function()
    local identity = GuildIdentity.Current(fake_platform(5, nil, "Realm"))
    assert.are.equal("club:5", identity.key)
    assert.is_nil(identity.name)
  end)

  it("falls back to the guild name and the realm without a club id", function()
    local identity = GuildIdentity.Current(fake_platform(nil, "Some Guild", "Realm"))
    assert.are.same({ key = "name:Some Guild-Realm", name = "Some Guild", realm = "Realm", source = "name" }, identity)
  end)

  it("treats an empty or zero club id as missing", function()
    assert.are.equal("name:G-R", GuildIdentity.Current(fake_platform(0, "G", "R")).key)
    assert.are.equal("name:G-R", GuildIdentity.Current(fake_platform("", "G", "R")).key)
  end)

  it("keeps two guilds with the same name on different realms apart", function()
    local a = GuildIdentity.Current(fake_platform(nil, "Same", "RealmA"))
    local b = GuildIdentity.Current(fake_platform(nil, "Same", "RealmB"))
    assert.are_not.equal(a.key, b.key)
  end)

  it("returns nil when the client has told neither the club id nor the name", function()
    assert.is_nil(GuildIdentity.Current(fake_platform(nil, nil, "Realm")))
    assert.is_nil(GuildIdentity.Current(fake_platform(nil, "", "Realm")))
  end)

  it("returns nil when only the name is known and the realm is not", function()
    assert.is_nil(GuildIdentity.Current(fake_platform(nil, "G", nil)))
  end)
end)
