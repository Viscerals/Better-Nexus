-- Nexus: canonical, allocation-light identity and safe UTF-8 text boundary.
-- ASCII case folding is intentional: WoW identity comparison is
-- case-insensitive for ASCII while every valid non-ASCII byte stays exact.

Nexus = Nexus or {}
local Identity = {}
Nexus.Identity = Identity

local function AsciiLower(value)
    return (value:gsub("[A-Z]", function(character)
        return string.char(character:byte() + 32)
    end))
end

local function Decode(value, visitor)
    if type(value) ~= "string" then return false end
    local index, count = 1, #value
    while index <= count do
        local first = value:byte(index)
        local codepoint, width
        if first < 0x80 then
            codepoint, width = first, 1
        elseif first >= 0xC2 and first <= 0xDF then
            local second = value:byte(index + 1)
            if not second or second < 0x80 or second > 0xBF then return false end
            codepoint, width = (first - 0xC0) * 0x40 + second - 0x80, 2
        elseif first >= 0xE0 and first <= 0xEF then
            local second, third = value:byte(index + 1), value:byte(index + 2)
            if not second or not third or second < 0x80 or second > 0xBF
                or third < 0x80 or third > 0xBF
                or (first == 0xE0 and second < 0xA0)
                or (first == 0xED and second > 0x9F) then return false end
            codepoint, width = (first - 0xE0) * 0x1000
                + (second - 0x80) * 0x40 + third - 0x80, 3
        elseif first >= 0xF0 and first <= 0xF4 then
            local second, third, fourth = value:byte(index + 1),
                value:byte(index + 2), value:byte(index + 3)
            if not second or not third or not fourth
                or second < 0x80 or second > 0xBF
                or third < 0x80 or third > 0xBF
                or fourth < 0x80 or fourth > 0xBF
                or (first == 0xF0 and second < 0x90)
                or (first == 0xF4 and second > 0x8F) then return false end
            codepoint, width = (first - 0xF0) * 0x40000
                + (second - 0x80) * 0x1000
                + (third - 0x80) * 0x40 + fourth - 0x80, 4
        else
            return false
        end
        if visitor and visitor(codepoint, index, width) == false then return false end
        index = index + width
    end
    return true
end

local function UnsafeCodepoint(codepoint, allowLineBreaks)
    return (codepoint < 0x20 and not (allowLineBreaks
            and (codepoint == 0x0A or codepoint == 0x0D)))
        or (codepoint >= 0x7F and codepoint <= 0x9F)
        or (codepoint >= 0x300 and codepoint <= 0x36F)
        or (codepoint >= 0x200B and codepoint <= 0x200F)
        or (codepoint >= 0x202A and codepoint <= 0x202E)
        or (codepoint >= 0x2060 and codepoint <= 0x2069)
        or codepoint == 0xFEFF or codepoint == 0xFFFD
end

local function SafeSequence(value, allowWhitespace, allowPipe, allowLineBreaks)
    local previous
    return Decode(value, function(codepoint)
        if UnsafeCodepoint(codepoint, allowLineBreaks)
            or (codepoint == 0x7C and not allowPipe)
            or (not allowWhitespace and (codepoint == 0x20
                or codepoint == 0xA0 or codepoint == 0x2028
                or codepoint == 0x2029)) then return false end
        -- Reject the characteristic double-decoded UTF-8 pair (for example,
        -- U+00C3 U+00A9) rather than silently merging it with the real name.
        if previous and (previous == 0xC2 or previous == 0xC3)
            and codepoint >= 0x80 and codepoint <= 0xBF then return false end
        previous = codepoint
        return true
    end)
end

function Identity.ValidUtf8(value)
    return Decode(value)
end

function Identity.ValidDisplayText(value, maxBytes, allowEmpty, allowLineBreaks)
    return type(value) == "string"
        and (allowEmpty or value ~= "")
        and #value <= (tonumber(maxBytes) or 4096)
        and SafeSequence(value, true, false, allowLineBreaks == true)
end

function Identity.ValidWireText(value, maxBytes, allowEmpty, allowLineBreaks)
    return type(value) == "string"
        and (allowEmpty or value ~= "")
        and #value <= (tonumber(maxBytes) or 4096)
        and SafeSequence(value, true, true, allowLineBreaks == true)
end

local function ValidPlayer(value)
    if type(value) ~= "string" or value == "" or #value > 80
        or value:find("@", 1, true) or not SafeSequence(value, false) then
        return false
    end
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 0x80 and not ((byte >= 0x30 and byte <= 0x39)
            or (byte >= 0x41 and byte <= 0x5A)
            or (byte >= 0x61 and byte <= 0x7A)
            or byte == 0x27 or byte == 0x2D or byte == 0x5F) then
            return false
        end
    end
    if value:sub(1, 1) == "-" or value:sub(-1) == "-"
        or value:find("--", 1, true) then
        return false
    end
    local first = value:byte(1)
    return first >= 0x80 or (first >= 0x30 and first <= 0x39)
        or (first >= 0x41 and first <= 0x5A)
        or (first >= 0x61 and first <= 0x7A) or first == 0x5F
end

function Identity.ValidPlayer(value)
    return ValidPlayer(value)
end

function Identity.PlayerKey(value, keepRealm)
    if not ValidPlayer(value) then return nil end
    local text = keepRealm and value or (value:match("^([^-]+)") or value)
    return AsciiLower(text)
end

function Identity.DisplayPlayer(value)
    if not ValidPlayer(value) then return nil end
    return value:match("^([^-]+)") or value
end

function Identity.SamePlayer(left, right)
    local leftKey, rightKey = Identity.PlayerKey(left), Identity.PlayerKey(right)
    return leftKey ~= nil and leftKey == rightKey
end

function Identity.SameTransportSender(declared, actual)
    local declaredFull = Identity.PlayerKey(declared, true)
    local actualFull = Identity.PlayerKey(actual, true)
    if not declaredFull or not actualFull then return false end
    if declared:find("-", 1, true) and actual:find("-", 1, true) then
        return declaredFull == actualFull
    end
    return Identity.SamePlayer(declared, actual)
end

local function RealmKey(value, trustedLocal)
    if type(value) ~= "string" then return nil end
    if trustedLocal then value = value:gsub("%s+", "") end
    if value == "" or #value > 96 or value:find("@", 1, true)
        or value:sub(1, 1) == "-" or value:sub(-1) == "-"
        or value:find("--", 1, true)
        or not SafeSequence(value, false) then return nil end
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 0x80 and not ((byte >= 0x30 and byte <= 0x39)
            or (byte >= 0x41 and byte <= 0x5A)
            or (byte >= 0x61 and byte <= 0x7A)
            or byte == 0x27 or byte == 0x28 or byte == 0x29
            or byte == 0x2D or byte == 0x5F) then
            return nil
        end
    end
    return AsciiLower(value)
end

function Identity.OwnerKey(name, realm)
    local player = Identity.PlayerKey(name)
    local normalizedRealm = RealmKey(tostring(realm or "unknown"), true)
    return player and normalizedRealm and (player .. "@" .. normalizedRealm) or nil
end

-- Durable ownership may be derived from transport only when the actual sender
-- carries its own realm. A short sender is valid presentation/envelope input,
-- but it cannot borrow the local realm or become owner authority.
function Identity.CanonicalOwnerFromTransport(sender)
    if not ValidPlayer(sender) then return nil end
    local name, realm = sender:match("^([^-]+)%-(.+)$")
    if not name or not realm then return nil end
    local player = Identity.PlayerKey(name, true)
    local normalizedRealm = RealmKey(realm, false)
    return player and normalizedRealm
        and (player .. "@" .. normalizedRealm) or nil
end

function Identity.CanonicalOwnerKey(value)
    if type(value) ~= "string" or #value > 177 then return nil end
    local name, realm = value:match("^([^@]+)@([^@]+)$")
    if not name or not realm or name:find("-", 1, true)
        or value:find("@", (value:find("@", 1, true) or 0) + 1, true) then
        return nil
    end
    local player, normalizedRealm = Identity.PlayerKey(name), RealmKey(realm, false)
    return player and normalizedRealm and (player .. "@" .. normalizedRealm) or nil
end

function Identity.TransportOwns(ownerKey, actualSender)
    local claimed = Identity.CanonicalOwnerKey(ownerKey)
    local transport = Identity.CanonicalOwnerFromTransport(actualSender)
    return claimed ~= nil and transport ~= nil and claimed == transport
end

function Identity.OwnerKeyMatchesAuthor(ownerKey, author)
    if ownerKey == nil then return true end
    local canonical = Identity.CanonicalOwnerKey(ownerKey)
    local name = canonical and canonical:match("^([^@]+)@") or nil
    local authorKey = Identity.PlayerKey(author)
    return name ~= nil and authorKey ~= nil and name == authorKey
end

local function ExactOwnerIdentity(ownerKey, value)
    if value == nil then return true, false end
    if not Identity.OwnerKeyMatchesAuthor(ownerKey, value) then
        return false, true
    end
    if type(value) == "string" and value:find("-", 1, true)
        and Identity.CanonicalOwnerFromTransport(value) ~= ownerKey then
        return false, true
    end
    return true, true
end

local function ExactOwnerRealm(ownerKey, realm)
    if realm == nil then return true end
    if type(realm) ~= "string" then return false end
    local name = ownerKey and ownerKey:match("^([^@]+)@") or nil
    return name ~= nil and Identity.CanonicalOwnerKey(
        Identity.OwnerKey(name, realm)) == ownerKey
end

-- Validate one durable record identity tuple without granting authority by
-- itself. The only current non-verified consumer is immutable bundled-source
-- admission, where provenance is supplied separately by BuildCatalog.
function Identity.CoherentRecordOwnerKey(record)
    if type(record) ~= "table" then return nil end
    -- Compact DPS aliases are transport input, not durable Community fields.
    -- Rejecting them here prevents a summary or mixed-shape record from hiding
    -- a contradiction through alias precedence.
    if record.a ~= nil or record.o ~= nil or record.p ~= nil or record.r ~= nil
        or record.relaySender ~= nil or record.claimedOwnerKey ~= nil then
        return nil
    end
    local ownerKey = Identity.CanonicalOwnerKey(record.ownerKey)
    if not ownerKey or ownerKey:match("@unknown$") then return nil end
    local authorOk, hasAuthor = ExactOwnerIdentity(ownerKey, record.author)
    local playerOk, hasPlayer = ExactOwnerIdentity(ownerKey, record.player)
    if not authorOk or not playerOk or not (hasAuthor or hasPlayer)
        or not ExactOwnerRealm(ownerKey, record.realm) then return nil end
    return ownerKey
end

-- Durable record ownership requires both an explicit verification decision and
-- one coherent canonical name@realm tuple.  Presentation names, local-looking
-- flags, and malformed/unknown realm metadata never satisfy this predicate.
function Identity.VerifiedOwnerKey(record)
    if type(record) ~= "table" or record.ownerVerified ~= true then return nil end
    return Identity.CoherentRecordOwnerKey(record)
end

-- Keep Saved-mirror marker interpretation type-stable across mutation,
-- projection, relation, and renderer boundaries. Explicit false retains
-- ordinary-build compatibility; any other non-boolean value is malformed.
function Identity.SavedMirrorKind(record)
    if type(record) ~= "table" then return nil end
    local marker = record.importedSavedBuild
    if marker == true then return "saved" end
    if marker == nil or marker == false then return "ordinary" end
    return "invalid"
end

local function LocalOwnsLegacyEvidence(record, current)
    if record.a ~= nil or record.o ~= nil or record.p ~= nil or record.r ~= nil
        or record.relaySender ~= nil or record.claimedOwnerKey ~= nil then
        return false
    end
    if record.ownerVerified ~= nil or record.autoDps == true
        or record.isMine ~= true then return false end
    local rawLegacyOwner = record.ownerKey
    if rawLegacyOwner ~= nil then
        local legacyOwner = Identity.CanonicalOwnerKey(rawLegacyOwner)
        if not legacyOwner or legacyOwner:match("@unknown$")
            or legacyOwner ~= current then return false end
    end
    local authorOk, hasAuthor = ExactOwnerIdentity(current, record.author)
    local playerOk, hasPlayer = ExactOwnerIdentity(current, record.player)
    if not authorOk or not playerOk or not (hasAuthor or hasPlayer)
        or not ExactOwnerRealm(current, record.realm) then return false end
    return true
end

-- Ordinary durable ownership is verified-only. Legacy rows remain readable,
-- but local-looking flags or owner text cannot grant mutation, association,
-- publication, relay, or delete authority without an explicit verification.
function Identity.LocalOwnsRecord(record, currentOwnerKey)
    if Identity.SavedMirrorKind(record) ~= "ordinary" then return false end
    local current = Identity.CanonicalOwnerKey(currentOwnerKey)
    if not current or current:match("@unknown$") then return false end
    return Identity.VerifiedOwnerKey(record) == current
end

-- Saved-loadout mirrors may coexist for same-named characters on different
-- realms. Public ownership is therefore verified-only; an unverified mirror
-- may remain visible but cannot become editable or publishable.
function Identity.LocalOwnsSavedMirror(record, currentOwnerKey)
    if Identity.SavedMirrorKind(record) ~= "saved" then
        return false
    end
    local current = Identity.CanonicalOwnerKey(currentOwnerKey)
    if not current or current:match("@unknown$") then return false end
    return Identity.VerifiedOwnerKey(record) == current
end

-- Public build ownership is type-dispatched before any compatibility branch.
-- Saved and ordinary rows both require explicit verification; malformed marker
-- values never fall through to a local-looking compatibility branch.
function Identity.LocalOwnsBuild(record, currentOwnerKey)
    local kind = Identity.SavedMirrorKind(record)
    if kind == "saved" then
        return Identity.LocalOwnsSavedMirror(record, currentOwnerKey)
    end
    if kind ~= "ordinary" then return false end
    return Identity.LocalOwnsRecord(record, currentOwnerKey)
end

-- A live Saved-slot reconciliation may adopt a pre-verification mirror only
-- when it already carries the exact explicit canonical owner tuple. This is a
-- storage-compatibility bridge, not mutation or projection authority.
function Identity.CanAdoptSavedMirror(record, currentOwnerKey)
    if Identity.LocalOwnsSavedMirror(record, currentOwnerKey) then return true end
    if Identity.SavedMirrorKind(record) ~= "saved" then
        return false
    end
    local current = Identity.CanonicalOwnerKey(currentOwnerKey)
    if not current or current:match("@unknown$") then return false end
    return record.ownerVerified == nil
        and Identity.CanonicalOwnerKey(record.ownerKey) == current
        and LocalOwnsLegacyEvidence(record, current)
end

function Identity.SanitizeText(value, maxBytes)
    local ok, text = pcall(tostring, value)
    text = ok and tostring(text or "") or "unprintable"
    if not Identity.ValidUtf8(text) then return "invalid" end
    text = text:gsub("[%c|]", " "):gsub("%s+", " ")
        :gsub("^%s+", ""):gsub("%s+$", "")
    if not SafeSequence(text, true) then return "invalid" end
    local limit = tonumber(maxBytes) or 96
    if #text <= limit then return text end
    local start = limit
    while start > 0 and text:byte(start) >= 0x80
        and text:byte(start) <= 0xBF do start = start - 1 end
    local width = text:byte(start) and (text:byte(start) < 0x80 and 1
        or text:byte(start) < 0xE0 and 2
        or text:byte(start) < 0xF0 and 3 or 4) or 0
    local last = start + width - 1 <= limit and start + width - 1
        or start - 1
    return text:sub(1, math.max(0, last))
end
