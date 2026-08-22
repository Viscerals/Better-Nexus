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

function Identity.TruncateUtf8Bytes(text, maxBytes)
    if type(text) ~= "string" or not Identity.ValidUtf8(text) then return nil end
    local limit = tonumber(maxBytes) or #text
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

local function PublicScalarText(value, maxBytes)
    local kind = type(value)
    if value == nil then return "nil", "", true end
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
        return kind, nil, false
    end
    local text = kind == "number" and value ~= value and "nan"
        or tostring(value)
    return kind, text, #text <= (maxBytes or 177)
end

local function HexBytes(text)
    local out = {}
    for index=1,#text do
        out[index] = string.format("%02x", text:byte(index))
    end
    return table.concat(out)
end

local function PublicTyped(value, maxBytes)
    local kind, text, bounded = PublicScalarText(value, maxBytes)
    if text == nil then return kind .. ":7:invalid" end
    if not bounded then
        return kind .. ":" .. tostring(#text) .. ":oversized"
    end
    -- Public identity is computed inside bounded projection work.  Retain the
    -- exact scalar when safe, and an injective bounded hex form otherwise.
    -- Oversized/unsupported shapes are rejected from public projection below.
    if not Identity.ValidDisplayText(text, maxBytes or 177, true) then
        return kind .. ":" .. tostring(#text) .. ":invalid:" .. HexBytes(text)
    end
    return kind .. ":" .. tostring(#text) .. ":" .. text
end

local function PublicRecordShape(record, field)
    local fields = {{field,80},{"realm",96},{"ownerKey",177},
        {"claimedOwnerKey",177},{"relaySender",80}}
    if field == "author" then
        fields[#fields + 1] = {"id",96}
        fields[#fields + 1] = {"buildId",96}
    end
    for _, item in ipairs(fields) do
        local _, text, bounded = PublicScalarText(record[item[1]], item[2])
        if text == nil or not bounded then return false end
    end
    return true
end

local function PublicBaseName(record, field)
    local raw = type(record) == "table" and record[field] or nil
    return Identity.DisplayPlayer(raw) or "Unknown"
end

local function PublicPlayerKey(record, field)
    return Identity.PlayerKey(type(record) == "table" and record[field] or nil)
end

-- Stable public identity for presentation snapshots. Unlike SamePlayer(), this
-- never grants authority: verified owners are exact name@realm identities and
-- all other rows retain their complete ambiguity/provenance tuple.
function Identity.PublicRecordKey(record, field)
    if type(record) ~= "table" then return "invalid" end
    local verified = Identity.VerifiedOwnerKey(record)
    if verified then return "verified:" .. verified end
    local parts = {"legacy",PublicTyped(record[field], 80),
        PublicTyped(record.realm, 96),PublicTyped(record.ownerKey, 177),
        PublicTyped(record.claimedOwnerKey, 177),
        PublicTyped(record.relaySender, 80)}
    -- Community rows are records rather than per-character aggregates.  Their
    -- durable catalog identity must remain part of the public key even when
    -- author/provenance fields are otherwise identical.
    if field == "author" then
        parts[#parts + 1] = PublicTyped(record.id, 96)
        parts[#parts + 1] = PublicTyped(record.buildId, 96)
    end
    return table.concat(parts, "|")
end

local function VerifiedPublicLabel(record, field, ownerKey)
    local realm = ownerKey and ownerKey:match("@(.+)$") or nil
    return PublicBaseName(record, field) .. "-" .. tostring(realm or "unknown")
end

local function SafePublicToken(value, maxBytes)
    return PublicTyped(value, maxBytes)
end

local function AmbiguousPublicLabel(record, field)
    local base = PublicBaseName(record, field)
    local raw = record[field]
    local fullPlayer = Identity.PlayerKey(raw, true)
    if fullPlayer and fullPlayer:find("-", 1, true) then
        base = raw
    else
        local realm = type(record.realm) == "string"
            and Identity.OwnerKey(base, record.realm) and record.realm or nil
        if realm and realm:lower() ~= "unknown" then base = base .. "-" .. realm end
    end
    local discriminator = table.concat({
        SafePublicToken(record.id, 96),
        SafePublicToken(record.buildId, 96),
        SafePublicToken(raw, 80),
        SafePublicToken(record.realm, 96),
        SafePublicToken(record.ownerKey, 177),
        SafePublicToken(record.claimedOwnerKey, 177),
        SafePublicToken(record.relaySender, 80),
    }, "|")
    return base .. " (legacy/unverified " .. discriminator .. ")"
end

function Identity.NewPublicPresentation(field, options)
    return {field=field,options=type(options) == "table" and options or {},
        verifiedNames={},indexed=0,shadowed=0,visible=0,invalid=0}
end

function Identity.IndexPublicRecord(context, record)
    if type(context) ~= "table" or type(record) ~= "table" then
        if type(context) == "table" then context.invalid = context.invalid + 1 end
        return false
    end
    if not PublicRecordShape(record, context.field) then
        context.invalid = context.invalid + 1
        return false
    end
    local name = PublicPlayerKey(record, context.field)
    if name and Identity.VerifiedOwnerKey(record) then
        context.verifiedNames[name] = true
    end
    context.indexed = context.indexed + 1
    return true
end

function Identity.PresentPublicRecord(context, record)
    if type(context) ~= "table" or type(record) ~= "table" then return nil end
    local field, options = context.field, context.options
    if not PublicRecordShape(record, field) then return nil end
    local name = PublicPlayerKey(record, field)
    local ownerKey = Identity.VerifiedOwnerKey(record)
    local hidden = options.shadowAmbiguous == true and ownerKey == nil
        and name ~= nil and context.verifiedNames[name] == true
    if hidden then context.shadowed = context.shadowed + 1; return nil end
    record.publicIdentityKey = Identity.PublicRecordKey(record, field)
    record.publicIdentityVerified = ownerKey ~= nil
    if type(record[field]) == "string" then
        local label = ownerKey and VerifiedPublicLabel(record, field, ownerKey)
            or AmbiguousPublicLabel(record, field)
        if field == "author" then record.displayAuthor = label
        else record.displayPlayer = label end
    end
    context.visible = context.visible + 1
    return record
end

-- Apply one shared public presentation policy to an owned batch of snapshots.
-- Ambiguous evidence is only shadowed from ordinary public rows when an exact
-- verified owner with the same short name is already visible; the durable
-- source remains untouched. Distinct builds can opt out of shadowing while
-- still receiving collision-safe author labels.
function Identity.PresentPublicRecords(rows, field, options)
    rows = type(rows) == "table" and rows or {}
    local context = Identity.NewPublicPresentation(field, options)
    for _, record in ipairs(rows) do
        Identity.IndexPublicRecord(context, record)
    end

    local out = {}
    for _, record in ipairs(rows) do
        local presented = Identity.PresentPublicRecord(context, record)
        if presented then out[#out + 1] = presented end
    end
    return out, {shadowed=context.shadowed,visible=context.visible,
        invalid=context.invalid}
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
    return Identity.TruncateUtf8Bytes(text, limit)
end
