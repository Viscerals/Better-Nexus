-- Package B / issue #22 Repair Wave 1: MASTER-RC-004, mutation authority.
--
-- Root: "bundled owner text grants local and remote delete authority."
-- Required repaired outcome: "authority only from the exact admitted
--  owner/provenance contract; fixed owner-required refusals preserving
--  bytes/root/indexes."
--
-- Architecture at 3b5de54f, docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md:
--   line 193  "Bundled package row | Content fields and immutable bundled
--             source position only. ... Bundled author text never proves local
--             ownership."
--   line 188  "Input fields such as ownerVerified, isMine, sourceIdentity,
--             provenanceIdentity, evidenceKey, fingerprint, and derived hashes
--             are claims, not proof."
--   line 202  "Tests submit internally coherent spoofed tuples for every source
--             and require zero verified-owner or mutation privilege."
--
-- The defect: FinishRowVerdict sets
--   verdict.trustedOwner = verdict.verifiedOwner
--       or (source == "bundled" and Identity.CoherentRecordOwnerKey(snapshot))
-- so a bundled row whose author/player/ownerKey merely agree with each other is
-- trusted for delete ownership with no verification at all, and SetTombstone
-- accepts it on both the local and remote paths.
--
-- PROV-03/04/05 are guards: they pass before the repair and must keep passing
-- after it, so the fix cannot be a blanket refusal.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end
GetNormalizedRealmName = function() return "Ebonhold" end
GetRealmName = GetNormalizedRealmName

local function Catalog() return Nexus.BuildCatalog end

-- An internally coherent bundled row: author, player and ownerKey all agree,
-- and there is no verification flag anywhere. Coherence is not proof.
local function SpoofedBundledRow(id, owner)
    return {
        id=id, title="Spoofed " .. id, author=owner, player=owner,
        ownerKey=owner:lower() .. "@ebonhold", realm="ebonhold",
        class="MAGE", postedAt=10, lastModified=10,
        echoes=S.Echoes(2, 0),
    }
end

local function BindSpoofedBundle(id, owner)
    UnitName = function() return owner end
    local bundle = S.Bundle({[id]=SpoofedBundledRow(id, owner)})
    local db = S.Database()
    S.Bind(db, bundle)
    Check(Catalog().RootState().state == "ROOT_ADMITTED",
        "fixture did not admit a root")
    return db
end

-- PROV-01 EXPECTED RED: local delete from bundled author text alone.
Case("PROV-01",
    "a coherent bundled owner tuple grants no local delete authority",
function()
    BindSpoofedBundle("prov01", "Spoofer")
    local ok, why = Catalog().SetTombstone("prov01", {stamp=1},
        {source="local"})
    Check(ok == false and why == "LOCAL_OWNER_REQUIRED",
        "bundled author text proved local ownership: ok=" .. tostring(ok)
            .. " why=" .. tostring(why))
end)

-- PROV-02 EXPECTED RED: remote delete from bundled author text alone.
Case("PROV-02",
    "a coherent bundled owner tuple grants no remote delete authority",
function()
    BindSpoofedBundle("prov02", "Spoofer")
    local ok, why = Catalog().SetTombstone("prov02", {stamp=1},
        {source="remote", sender="Spoofer-Ebonhold"})
    Check(ok == false and why == "REMOTE_OWNER_REQUIRED",
        "bundled author text proved remote ownership: ok=" .. tostring(ok)
            .. " why=" .. tostring(why))
end)

-- PROV-03 GUARD: a genuinely verified local owner still deletes. The repair
-- must not become a blanket refusal.
Case("PROV-03",
    "GUARD: a verified local overlay owner still holds delete authority",
function()
    UnitName = function() return "Boganic" end
    local db = S.Database({prov03=S.LocalBuild("prov03", 2)})
    S.Bind(db)
    Check(Catalog().RootState().state == "ROOT_ADMITTED",
        "fixture did not admit a root")
    -- The row-to-tombstone transaction is one retained catalog mutation
    -- (MASTER-RC-006); its committed ticket is the authority evidence.
    local ok, why, ticket = Catalog().SetTombstone("prov03", {stamp=1},
        {source="local"})
    if ok == nil and why == "ROOT_MUTATION_PENDING" then
        S.PumpCatalogToIdle("verified local delete")
        ok = type(ticket) == "table" and ticket.committed == true
        why = ticket and ticket.reason or why
    end
    Check(ok == true,
        "a verified local owner lost delete authority: " .. tostring(why))
end)

-- PROV-04 GUARD: the refusal is fixed and preserves durable bytes and root.
Case("PROV-04",
    "GUARD: an owner-required refusal preserves bytes, root, and generation",
function()
    local db = BindSpoofedBundle("prov04", "Spoofer")
    local before = Catalog().RootState()
    local bytes = S.Encode(db)
    local ok = Catalog().SetTombstone("prov04", {stamp=1}, {source="local"})
    Check(ok == false, "the spoofed row was accepted")
    local after = Catalog().RootState()
    Check(S.Encode(db) == bytes,
        "a refused delete changed a durable byte")
    Check(after.state == before.state
        and after.generation == before.generation
        and after.durableBundleGeneration == before.durableBundleGeneration,
        "a refused delete moved the root state or a generation")
end)

-- PROV-05 GUARD: a coherent tuple on a non-bundled source already grants
-- nothing, and must continue to.
Case("PROV-05",
    "GUARD: a coherent overlay tuple without verification grants nothing",
function()
    UnitName = function() return "Spoofer" end
    local unverified = {
        id="prov05", title="Unverified", author="Spoofer", player="Spoofer",
        ownerKey="spoofer@ebonhold", realm="ebonhold", class="MAGE",
        postedAt=10, lastModified=10, echoes=S.Echoes(2, 0),
    }
    local db = S.Database({prov05=unverified})
    S.Bind(db)
    Check(Catalog().RootState().state == "ROOT_ADMITTED",
        "fixture did not admit a root")
    local ok, why = Catalog().SetTombstone("prov05", {stamp=1},
        {source="local"})
    Check(ok == false and why == "LOCAL_OWNER_REQUIRED",
        "an unverified overlay tuple proved ownership: ok=" .. tostring(ok)
            .. " why=" .. tostring(why))
end)

S.Finish("catalog authority provenance and mutation authority")
