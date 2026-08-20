local H = dofile("tests/harness.lua")
dofile("logic/Version.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")

local mutation = {catalog=0,send=0,diagnostic=0}
local root = {future={keep=true}}
NexusDB = root
Nexus.BuildCatalog = {
    All=function() mutation.catalog = mutation.catalog + 1; return {} end,
    Put=function() mutation.catalog = mutation.catalog + 1 end,
}
SendChatMessage = function() mutation.send = mutation.send + 1 end
Nexus.SyncDiagnosticProbe = function()
    mutation.diagnostic = mutation.diagnostic + 1
end

local function PeerKey(value)
    value = tostring(value or ""):gsub("%s+", "")
    return (value:match("^([^%-]+)") or value):lower()
end

local safeTreeCalls = 0
local P = Nexus.SyncInternals.Protocol.New({
    limits={
        maxTransferIdBytes=160, maxHashBytes=192, maxVersionBytes=32,
        maxBuildIdBytes=96, maxBuildEchoes=256, maxWireFields=8,
    },
    parseVersion=Nexus.Version.Parse,
    ownerKeyMatchesAuthor=function(ownerKey, author)
        if ownerKey == nil then return true end
        if type(ownerKey) ~= "string" or #ownerKey > 160
            or ownerKey:find("[%c|]") then return false end
        local ownerName, realm = ownerKey:match("^([^@]+)@([^@]+)$")
        return ownerName ~= nil and realm ~= nil
            and PeerKey(ownerName) == PeerKey(author)
    end,
    isSafeTree=function(value, depth, nodes)
        safeTreeCalls = safeTreeCalls + 1
        return Nexus.Codec.IsSafeTree(value, depth, nodes)
    end,
})

assert(P.EscapedLen("a|b") == 4
    and P.FiniteNumber(0) and not P.FiniteNumber(0/0)
    and P.ValidText("plain", 5, false)
    and not P.ValidText("bad\n", 8, false)
    and P.ValidField("field", 8, false)
    and not P.ValidField("bad|field", 16, false)
    and P.ValidIdentifier("build_1:a+b", 32)
    and not P.ValidIdentifier("build 1", 32)
    and P.ValidTransferIdentifier("H\195\169ro:build")
    and not P.ValidTransferIdentifier("Hero build")
    and P.ValidPeerName("Hero-Realm") and not P.ValidPeerName("Hero Realm")
    and P.ValidHash("0,abc,12") and not P.ValidHash("0,xyz")
    and P.ValidVersion("1.20.0-beta.1")
    and not P.ValidVersion("1.20.0 beta")
    and P.ValidIntegerText("0", 0) and not P.ValidIntegerText("-1", 0),
    "pure protocol scalar validation changed")

local hashes = P.SplitHashes("a,0,ff")
assert(#hashes == 3 and hashes[1] == "a" and hashes[3] == "ff",
    "hash splitting changed")
local fields = P.SplitWire("A|B|C|D|E|F|G|H")
assert(fields and #fields == 8 and fields[8] == "H"
    and P.SplitWire("A|B|C|D|E|F|G|H|I") == nil,
    "wire field limit changed")

local build = {
    id="build-1", title="Arcane", author="Hero-Realm",
    ownerKey="hero@realm", class="MAGE", lastModified=123,
    description="D", autoDps=true, link="https://example.invalid/b",
    echoes={
        {spellId=200100,quality=3,stacks=2},
        {spellId=200101,quality=0,stacks=1,locked=true},
    },
}
local compact = P.CompactEncode(build)
local json = Nexus.Codec.JSONEncode(compact)
local goldenJson = [=[{"a":"Hero-Realm","c":"MAGE","d":"D","e":[[200100,3,2],[200101,0,1,1]],"id":"build-1","lk":"https://example.invalid/b","m":123,"o":"hero@realm","t":"Arcane","x":1}]=]
local goldenBase64 = "eyJhIjoiSGVyby1SZWFsbSIsImMiOiJNQUdFIiwiZCI6IkQiLCJlIjpbWzIwMDEwMCwzLDJdLFsyMDAxMDEsMCwxLDFdXSwiaWQiOiJidWlsZC0xIiwibGsiOiJodHRwczovL2V4YW1wbGUuaW52YWxpZC9iIiwibSI6MTIzLCJvIjoiaGVyb0ByZWFsbSIsInQiOiJBcmNhbmUiLCJ4IjoxfQ=="
assert(json == goldenJson and Nexus.Codec.Base64Encode(json) == goldenBase64,
    "compact JSON/base64 wire bytes changed: " .. tostring(json))
local decoded = P.ValidatePayload(compact)
assert(decoded and decoded.id == build.id and decoded.title == build.title
    and decoded.author == build.author and decoded.ownerKey == build.ownerKey
    and decoded.class == build.class and decoded.lastModified == 123
    and decoded.description == "D" and decoded.autoDps == true
    and decoded.link == build.link and #decoded.echoes == 2
    and decoded.echoes[1].spellId == 200100
    and decoded.echoes[1].quality == 3 and decoded.echoes[1].stacks == 2
    and decoded.echoes[2].locked == true,
    "compact payload round trip changed")

local verbose = P.ValidatePayload({
    id="legacy-1", title="Legacy", author="Hero", ownerKey="hero@realm",
    class="MAGE", lastModified=55,
    echoes={{spellId=200200,quality=2,stacks=3,locked=true}},
})
assert(verbose and verbose.id == "legacy-1" and verbose.echoes[1].locked,
    "accepted verbose legacy payload changed")
assert(P.ValidatePayload({id="bad owner",t="Bad",a="Hero",e={{1,1,1}}}) == nil
    and P.ValidatePayload({id="ok",t="Bad",a="Other",
        o="hero@realm",e={{1,1,1}}}) == nil,
    "malformed payload was accepted")
assert(safeTreeCalls == 4, "payload safety callback count changed")

assert(NexusDB == root and root.future.keep
    and mutation.catalog == 0 and mutation.send == 0 and mutation.diagnostic == 0,
    "pure protocol calls mutated external state")

local function Read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end
local syncSource = Read("core/Sync.lua")
local protocolSource = Read("core/SyncProtocol.lua")
for _, name in ipairs({
    "EscapedLen", "FiniteNumber", "ValidText", "ValidField",
    "ValidIdentifier", "ValidTransferIdentifier", "ValidPeerName",
    "ValidHash", "ValidVersion", "ValidIntegerText", "SplitHashes",
    "CompactEncode", "CompactDecode", "ValidateNetworkPayload",
    "ValidateNetworkDpsPayload", "SplitWire",
}) do
    assert(not syncSource:find("local function " .. name, 1, true),
        "Sync retained old protocol implementation " .. name)
    assert(protocolSource:find("function P." .. name, 1, true),
        "SyncProtocol does not own " .. name)
    assert(syncSource:find("local " .. name .. " = Protocol." .. name, 1, true),
        "Sync does not delegate " .. name)
end
local toc = Read("Nexus.toc")
local codecAt = assert(toc:find("core\\Codec.lua", 1, true))
local protocolAt = assert(toc:find("core\\SyncProtocol.lua", codecAt, true))
local transportAt = assert(toc:find("core\\SyncTransport.lua", protocolAt, true))
local syncAt = assert(toc:find("core\\Sync.lua", transportAt, true))
assert(codecAt < protocolAt and protocolAt < transportAt
    and transportAt < syncAt,
    "Sync load order is not Codec -> Protocol -> Transport -> Sync")

print("Sync protocol validation and compact payload parity -- OK")
