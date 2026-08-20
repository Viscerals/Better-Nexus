-- Stage 36.7 identity UTF-8 and sender-binding regression.
--
-- Reuses existing Stage 28/record characterizations, then adds focused
-- deterministic checks for Sync/DPS sender binding with accented identities.

local failures = {}
local function Check(ok, name)
    if not ok then failures[#failures + 1] = name end
end

dofile("tests/run_stage28_share_identity_characterization.lua")
dofile("tests/run_record_identity_integrity.lua")

local Identity = Nexus and Nexus.Identity or {}
local Protocol = Nexus and Nexus.SyncInternals and Nexus.SyncInternals.Protocol or nil
local DpsCapture = Nexus and Nexus.DpsCapture or nil

local accented = "Valentin" .. string.char(0xC3, 0xA9)
local ascii = "Valentine"
local malformed = "Valentin" .. string.char(0xC3)
local wrongRealm = "Valentin" .. string.char(0xC3, 0xA9) .. "@" .. "otherrealm"

Check(type(Protocol) == "table" and type(Protocol.New) == "function"
    and type(Identity.PlayerKey) == "function",
    "protocol/identity module ownership bindings unavailable")
if type(Protocol) == "table" and type(Identity.PlayerKey) == "function" then
    local protocol = Protocol.New({
        limits = {
            maxTransferIdBytes = 80, maxHashBytes = 256,
            maxVersionBytes = 40, maxBuildIdBytes = 96,
            maxBuildEchoes = 120, bucketCount = 8, maxWireFields = 8,
        },
        parseVersion = function() return { major = 7 } end,
        ownerKeyMatchesAuthor = Identity.OwnerKeyMatchesAuthor
            or function() return false end,
        isSafeTree = function() return true end,
        validText = Identity.ValidWireText,
        validPeerName = Identity.ValidPlayer,
        canonicalOwnerKey = Identity.CanonicalOwnerKey,
    })

    local validBuild = {
        id = "stage36-identity-valid-01",
        t = "UTF-8 Identity",
        a = accented,
        o = Identity.OwnerKey(accented, "Ebonhold"),
        c = "MAGE",
        m = 1,
        e = {
            { tonumber(200100), 3, 1 },
            { tonumber(200102), 2, 1, 1 },
        },
    }
    local badOwnerBuild = {
        id = "stage36-identity-invalid-01",
        t = "UTF-8 Identity",
        a = accented,
        o = Identity.OwnerKey(ascii, "Ebonhold"),
        c = "MAGE",
        m = 1,
        e = validBuild.e,
    }
    local badPeerBuild = {
        id = "stage36-identity-invalid-02",
        t = "UTF-8 Identity",
        a = malformed,
        o = Identity.OwnerKey(accented, "Ebonhold"),
        c = "MAGE",
        m = 1,
        e = validBuild.e,
    }

    Check(type(protocol.ValidateNetworkPayload) == "function"
        and type(protocol.ValidateNetworkPayload(validBuild)) == "table",
        "valid accented wire identity was rejected")
    Check(not protocol.ValidateNetworkPayload(badOwnerBuild),
        "accented identity with altered owner key was accepted")
    Check(not protocol.ValidateNetworkPayload(badPeerBuild),
        "malformed accented peer name was accepted")
    local transportAccented = accented .. "-ebonhold"
    Check(Identity.SameTransportSender(transportAccented, transportAccented),
        "exact accented transport identity did not match")
    Check(not Identity.SameTransportSender(transportAccented, ascii .. "-ebonhold"),
        "accented transport identity matched altered ASCII name")
    Check(Identity.OwnerKey(accented, "ebonhold-cluster")
        == string.format("%s@ebonhold-cluster", accented:lower()),
        "accented owner key was normalized incorrectly")
    Check(Identity.OwnerKey(accented, "Rogue-Lite(Live)")
        == string.format("%s@rogue-lite(live)", accented:lower())
        and Identity.CanonicalOwnerKey(
            string.format("%s@rogue-lite(live)", accented:lower()))
            == string.format("%s@rogue-lite(live)", accented:lower()),
        "production Ebonhold realm format was rejected")
    Check(Identity.PlayerKey(wrongRealm) == nil,
        "realm-qualified owner text was not rejected in PlayerKey")
end

if type(DpsCapture) == "table" then
    local accents = {
        player = accented,
        class = "MAGE",
        owner = Identity.OwnerKey(accented, "Ebonhold"),
    }
    Check(type(DpsCapture.ReceiveRecord) == "function",
        "DPS receiver is unavailable for identity binding checks")
    if type(DpsCapture.ReceiveRecord) == "function" then
        local category = "dummy"
        local echoes = {
            { spellId = 200500, stacks = 1, quality = 1 },
            { spellId = 200110, stacks = 1, quality = 0 },
        }
        local key = assert(DpsCapture.GetEchoKey(echoes), "echo fingerprint failed")
        local valid = {
            v = 7, c = category, d = 35000000, u = 45, t = 123456,
            p = accents.player, k = accents.class,
            o = accents.owner, r = "ebonhold",
            e = echoes, f = key, l = 80,
        }
        Check(DpsCapture.ReceiveRecord(valid, accents.player) == true,
            "accented direct DPS record was rejected")
        local mismatchSender = {
            v = 7, c = category, d = 35000000, u = 45, t = 123457,
            p = accents.player, k = accents.class,
            o = accents.owner, r = "ebonhold",
            e = echoes, f = "unused-" .. key, l = 80,
        }
        Check(DpsCapture.ReceiveRecord(mismatchSender, ascii) == false,
            "DPS sender binding accepted mismatched transport identity")
    end
end

if #failures > 0 then
    error("Stage 36.7 identity UTF-8 regression failed ("
        .. #failures .. "): " .. table.concat(failures, "; "))
end

print("Stage 36.7 identity UTF-8 and sender binding -- OK")
