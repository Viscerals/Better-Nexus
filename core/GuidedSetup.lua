-- Nexus: core/GuidedSetup.lua
-- Session-only state and evidence of the guided setup coach
-- (ui/GuidedSetup.lua, issue #131). Real outcome sites report through
-- G.Note: Wishlist Editor saves and import drafts, and Echo Journal, role
-- picker and editor assignments. A step completes only from a receipt bound
-- to the current owner, assignment epoch, world session, destination and
-- Wishlist key, plus a fresh read back of that destination's opaque
-- assignment-action token and its assigned Wishlist. Reads happen only inside
-- an explicit call (a click, a Show or a receipt); nothing is polled. Nothing
-- here assigns, uploads, sends, spends, requests slots or changes Auto.
--
-- The guide's place is the one thing kept across a reload (the design's
-- "GUIDE RECORD (separate store, per character)"): the step, the path, the
-- skipped steps, whether the simulated preview was tried, and the Wishlist
-- key and Saved Build destination the player chose, in one bounded record of
-- the current character's row (PLACE_KEY), written only through the counted
-- StoreAuthorityOwner.UpdateStateV1 while Store.StateWriteStatus reports a
-- durable row for the owner the guide is bound to. No result is kept: no
-- receipt, request, read back, replacement acceptance or Keep Auto choice,
-- so a resumed guide reads every outcome again and never shows a step done
-- from an earlier session. A loading, read-only, future or unreadable saved
-- root, another character, or a record of another version keeps the place in
-- this session only and is left exactly as it is.
Nexus = Nexus or {}
local G = {}
Nexus.GuidedSetup = G

G.STEPS = {'welcome', 'wishlist', 'target', 'assign', 'manual', 'auto', 'summary'}
G.INDEX = {}
for i, id in ipairs(G.STEPS) do G.INDEX[id] = i end
-- A look-around (the explore path) sets nothing up, so it shows only the
-- lesson, Auto and the summary after Welcome.
G.EXPLORE = {'welcome', 'manual', 'auto', 'summary'}
-- Steps the player may skip. Welcome needs a choice; the summary ends.
G.SKIPPABLE = {wishlist = true, target = true, assign = true, manual = true, auto = true}
G.SIM_ANSWER = 1
local SAVED = {assigned = true, firstRun = true, unassigned = true, kept = true}
local LIMIT = 8
local S, serial, receipts = nil, 0, {}

-- The private receipt counter: one clock domain, never a wall or game time.
local function Tick() serial = serial + 1; return serial end
local function Try(fn, ...)
    if type(fn) ~= 'function' then return false end
    return pcall(fn, ...)
end
local function Dest(v)
    if v == 'first' then return 'first' end
    v = tonumber(v)
    if v and v >= 1 and v <= 1000 and v == math.floor(v) then return v end
    return nil
end
------------------------------------------------------------------------
-- The kept place. One flat record per character row, version 1:
--   {version=1, step=<G.STEPS id>, path='new'|'existing'|'explore'|nil,
--    skipped='wishlist,assign'|nil, manual=1..3|nil,
--    wishlist=<Wishlist key, <= 128 bytes>|nil, target=1..1000|'first'|nil}
-- Unknown fields of a version-1 record are kept as they are; a record of any
-- other version or shape is never read as a place and never written.
------------------------------------------------------------------------
local PLACE_KEY, PLACE_VERSION, PLACE_TEXT = 'guidedSetupPlaceV1', 1, 128
local PLACE_FIELDS = {'step', 'path', 'skipped', 'manual', 'wishlist', 'target'}
local PATHS = {new = true, existing = true, explore = true}
G.PLACE_KEY = PLACE_KEY

local function OwnRecord(v)
    return type(v) == 'table' and getmetatable(v) == nil and rawget(v, 'version') == PLACE_VERSION
end

-- The validated place in a record, field by field ("own"), or nil with
-- "absent" (no record) or "foreign" (another version or shape). Reads the
-- detached Store.State snapshot only: it creates, shapes and writes nothing,
-- and a read-only root's session row has no record.
local function ReadPlace()
    local store = Nexus.Store
    local ok, row = Try(store and store.State)
    if not ok or type(row) ~= 'table' then return nil, 'absent' end
    local raw = rawget(row, PLACE_KEY)
    if raw == nil then return nil, 'absent' end
    if not OwnRecord(raw) then return nil, 'foreign' end
    local place = {}
    local step, path = rawget(raw, 'step'), rawget(raw, 'path')
    if type(step) == 'string' and G.INDEX[step] then place.step = step end
    if type(path) == 'string' and PATHS[path] then place.path = path end
    local skipped = rawget(raw, 'skipped')
    if type(skipped) == 'string' and #skipped <= 64 then
        local seen, ids = {}, {}
        for id in skipped:gmatch('[^,]+') do if G.SKIPPABLE[id] then seen[id] = true end end
        for _, id in ipairs(G.STEPS) do if seen[id] then ids[#ids + 1] = id end end
        if #ids > 0 then place.skipped = table.concat(ids, ',') end
    end
    local manual = rawget(raw, 'manual')
    if type(manual) == 'number' and manual >= 1 and manual <= 3 and manual == math.floor(manual) then
        place.manual = manual
    end
    local wish = rawget(raw, 'wishlist')
    if type(wish) == 'string' and wish ~= '' and #wish <= PLACE_TEXT then place.wishlist = wish end
    local target = rawget(raw, 'target')
    if target == 'first' or type(target) == 'number' then place.target = Dest(target) end
    return place, 'own'
end

-- The place of a guide state, in the record's shape.
local function PlaceOf(s)
    local ids = {}
    for _, id in ipairs(G.STEPS) do if s.skipped[id] and G.SKIPPABLE[id] then ids[#ids + 1] = id end end
    local wish = s.wishlist and s.wishlist.key
    if type(wish) ~= 'string' or wish == '' or #wish > PLACE_TEXT then wish = nil end
    return {step = G.STEPS[s.index] or 'welcome', path = s.path,
        skipped = #ids > 0 and table.concat(ids, ',') or nil,
        manual = s.manualAck and tonumber(s.manualPick) or nil,
        wishlist = wish, target = s.target and Dest(s.target.destination) or nil}
end

local function SamePlace(a, b)
    for _, k in ipairs(PLACE_FIELDS) do if a[k] ~= b[k] then return false end end
    return true
end

-- Writes the place of `s` for the owner it is bound to, through the counted
-- UpdateStateV1 and only into the live durable row (IsDurableStateRowV1).
-- Nothing is written when the place equals the one kept, or when nothing was
-- ever kept and there is still nothing to keep. A foreign record found at
-- write time detaches the guide (session only) and stays untouched.
local function Save(s)
    if not (s and s.bound) then return false end
    local store, internals = Nexus.Store, Nexus.MainInternals
    local owner = type(internals) == 'table' and internals.StoreAuthorityOwner or nil
    if not (store and type(store.StateWriteStatus) == 'function' and type(owner) == 'table'
        and type(owner.UpdateStateV1) == 'function' and type(owner.IsDurableStateRowV1) == 'function') then
        return false
    end
    local okS, st = Try(store.StateWriteStatus)
    if not (okS and type(st) == 'table' and st.mode == 'durable' and st.ownerKey == s.bound) then return false end
    if G.Context().owner ~= s.bound then return false end
    local place = PlaceOf(s)
    if s.saved and SamePlace(place, s.saved) then return true end
    if not s.saved and place.step == 'welcome' and not (place.path or place.skipped or place.manual
        or place.wishlist or place.target) then return true end
    local ok, done, result = pcall(owner.UpdateStateV1, function(row)
        if not owner.IsDurableStateRowV1(row) then return 'session' end
        local current = rawget(row, PLACE_KEY)
        if current ~= nil and not OwnRecord(current) then return 'foreign' end
        if current == nil then current = {version = PLACE_VERSION}; row[PLACE_KEY] = current end
        for _, k in ipairs(PLACE_FIELDS) do current[k] = place[k] end
        return 'written'
    end)
    if not (ok and done) then return false end
    if result == 'foreign' then s.bound = false; return false end
    if result ~= 'written' then return false end
    s.saved = place
    return true
end

local function Changed(receipt)
    -- A navigation or choice (no receipt) keeps the place; a receipt from an
    -- outcome site writes nothing here (its own write may still be running).
    local s = S
    if s and receipt == nil then s.touched = true; Save(s) end
    if type(G.onChange) == 'function' then pcall(G.onChange, receipt) end
end

-- Owner, assignment-action epoch (owner and saved root) and world session.
function G.Context()
    local store, a, panel = Nexus.Store, Nexus.GameAdapter, Nexus.Panel
    local okO, owner = Try(store and store.CurrentOwnerKey)
    local okE, snap = Try(a and a.AssignmentActionSnapshot)
    local okS, session = Try(panel and panel.DestinationSessionCount)
    return {owner = okO and owner or nil,
        epoch = okE and type(snap) == 'table' and snap.epoch or nil,
        session = okS and session or nil}
end

local function Fresh()
    return {index = 1, skipped = {}, manualAck = false, context = G.Context()}
end
function G.State() if not S then S = Fresh() end return S end
function G.StepId() return G.STEPS[G.State().index] or 'welcome' end
-- A replay starts at Welcome with every choice and result cleared. It never
-- resets a Wishlist, a Saved Build or Auto; those are only read again. The
-- reset place is kept like any other.
function G.Replay()
    local prev = S
    S = Fresh(); S.replay = prev ~= nil
    if prev then S.bound, S.saved = prev.bound, prev.saved end
    Changed(); return S
end

-- A kept place applied to a guide not yet used this session: the step (on its
-- path), the skipped marks and a tried preview. The Wishlist and Saved Build
-- are choices to re-adopt from what Nexus lists now (Readopt), never results.
local function Apply(s, place)
    s.path = place.path
    local order = place.path == 'explore' and G.EXPLORE or G.STEPS
    s.index = 1
    if place.path and place.step then
        for _, v in ipairs(order) do if v == place.step then s.index = G.INDEX[v] end end
    end
    for id in (place.skipped or ''):gmatch('[^,]+') do s.skipped[id] = true end
    if place.manual then s.manualPick, s.manualAck = place.manual, true end
    if place.wishlist or place.target then s.resume = {wishlist = place.wishlist, target = place.target} end
    s.replay, s.notice = true, 'restored'
end

-- A kept choice is taken again only while Nexus lists it now: the Wishlist by
-- its key, the destination while it is offered and not blocked. A list that
-- is not read yet waits; a choice that is gone is dropped. Nothing else (no
-- replacement acceptance, request or result) comes back.
local function Readopt(s)
    local r = s.resume
    if r.wishlist and not s.wishlist then
        local list = G.WishlistOptions()
        if list then
            for _, c in ipairs(list) do
                if c.key == r.wishlist then
                    s.wishlist = {key = c.key, name = tostring(c.name or ''), slot = tonumber(c.slot),
                        source = 'existing', needsRoles = c.lockEvidenceStatus == 'unavailable'}
                    break
                end
            end
            r.wishlist = nil
        end
    else r.wishlist = nil end
    if r.target and not s.target then
        local opts = G.TargetOptions()
        if opts then
            for _, o in ipairs(opts) do
                if o.destination == r.target and not o.blocked then s.target = {destination = o.destination, name = o.name} end
            end
            r.target = nil
        end
    else r.target = nil end
    if not (r.wishlist or r.target) then s.resume = nil end
end

-- Binds the guide to the current owner's kept place, once, when the coach is
-- shown (ui/GuidedSetup.lua Render). While saved data is still loading it
-- waits. A durable row of the same owner binds: its place is applied unless
-- the guide was already used this session (then that place is kept instead).
-- Any other state (read-only, unavailable, another owner, a foreign record)
-- keeps the place in this session only. Returns "saved", "session" or
-- "loading". It writes only a place the player already made this session.
-- A context that moved since the guide was made (it may first have been read
-- while saved data was loading) is settled first, so the choices taken again
-- here are not cleared by the next Recheck.
function G.Resume()
    local s = G.State()
    if s.bound == nil then G.Recheck() end
    if s.bound == nil then
        local store = Nexus.Store
        local okS, st = Try(store and store.StateWriteStatus)
        if okS and type(st) == 'table' and st.mode == 'loading' then return 'loading' end
        local owner = G.Context().owner
        if not (okS and type(st) == 'table' and st.mode == 'durable' and st.ownerKey ~= nil and st.ownerKey == owner) then
            s.bound = false
        else
            local place, kind = ReadPlace()
            if kind == 'foreign' then
                s.bound = false
            else
                s.bound, s.saved = owner, place
                if place and not s.touched then Apply(s, place) end
                if s.touched then Save(s) end
            end
        end
    end
    if s.resume then Readopt(s) end
    return G.PlaceKept()
end

-- "saved" (kept across a reload), "session" (this session only) or
-- "loading" (not decided yet).
function G.PlaceKept()
    local s = S
    if s and s.bound then return 'saved' end
    if s and s.bound == false then return 'session' end
    return 'loading'
end

-- The steps of the current path, and the current step's place in them.
function G.Order()
    return G.State().path == 'explore' and G.EXPLORE or G.STEPS
end
function G.Position()
    local order, id = G.Order(), G.StepId()
    for i, v in ipairs(order) do if v == id then return i, #order end end
    return 1, #order
end

-- Checklist navigation: moves the guide to a step of the current path only.
function G.GoTo(id)
    for _, v in ipairs(G.Order()) do
        if v == id then
            local s = G.State()
            s.index, s.notice = G.INDEX[id], nil
            Changed(); return true
        end
    end
    return false
end

-- A changed owner, saved root (epoch) or world session clears every piece of
-- evidence; the step position, path and lesson stay. Never restored later.
-- Keep Auto is evidence too: the mode it read belongs to the old character or
-- session, so the new context needs its own choice before Auto continues.
-- The kept place belongs to one character: after an owner change this guide
-- keeps its place in this session only and writes no character's record, also
-- when it was used but not yet bound (a place made under one character is
-- never written into another's row). Only the first read of an identity (no
-- owner before) leaves it free to bind. After a saved-root change it binds
-- again to that root on the next Resume.
function G.Recheck()
    local s, now = G.State(), G.Context()
    local was = s.context.owner
    local why = (now.owner ~= was and 'owner')
        or (now.epoch ~= s.context.epoch and 'epoch')
        or (now.session ~= s.context.session and 'session') or nil
    if why then
        s.wishlist, s.draft, s.saveSeen, s.awaitSave = nil, nil, nil, nil
        s.target, s.request, s.notice, s.context = nil, nil, why, now
        s.autoKept, s.resume = nil, nil
        if why == 'owner' and (s.bound ~= nil or was ~= nil) then s.bound = false
        elseif why == 'epoch' and s.bound then s.bound, s.saved = nil, nil end
    end
    return why
end

function G.WishlistOptions()
    local a = Nexus.GameAdapter
    local ok, list = Try(a and a.GetWishlistCandidates)
    if not ok or type(list) ~= 'table' then return nil end
    local out = {}
    for _, c in ipairs(list) do
        if type(c) == 'table' and type(c.key) == 'string' and c.key ~= '' then out[#out + 1] = c end
    end
    return out
end

-- A coach choice of an identity the server lists now; it writes nothing.
function G.ChooseWishlist(c)
    local s = G.State(); G.Recheck()
    if type(c) ~= 'table' then return false, 'gone' end
    for _, live in ipairs(G.WishlistOptions() or {}) do
        if live.key == c.key and tostring(live.name or '') == tostring(c.name or '')
            and tonumber(live.slot) == tonumber(c.slot) then
            s.wishlist = {key = live.key, name = tostring(live.name or ''), slot = tonumber(live.slot),
                source = 'existing', needsRoles = live.lockEvidenceStatus == 'unavailable'}
            s.draft, s.saveSeen, s.awaitSave, s.request = nil, nil, nil, nil
            s.skipped.wishlist = nil
            if s.target then s.target.confirmedAction = nil end
            Changed(); return true
        end
    end
    return false, 'gone'
end

-- The guide opened the editor or the import dialog: the next save or draft
-- reported after this point belongs to this step.
function G.AwaitSave()
    local s = G.State()
    s.awaitSave, s.saveSeen, s.draft = Tick(), nil, nil
end

-- A canceled editor/import route must not claim a later unrelated save.
function G.CancelAwaitSave()
    local s = G.State()
    s.awaitSave = nil
end

-- Fresh read back of one destination: its action token and assigned plan.
function G.ReadAssignment(dest)
    local a = Nexus.GameAdapter
    dest = Dest(dest)
    if not (a and dest) then return {state = 'unknown'} end
    local okA, action = Try(a.AssignmentActionToken, dest)
    local r = {action = okA and action or nil}
    local ok, cand, evidence, key, okT, stored
    if dest == 'first' then
        okT, stored = Try(a.FirstRunToken)
        ok, cand = Try(a.GetFirstRunWishlist)
        evidence = 'actionable'
        if ok and cand == nil and okT and (stored == 'none' or stored == 'unassigned') then r.state = 'none'; return r end
    else
        okT, stored = Try(a.LoadoutAssignmentToken, dest)
        ok, cand, evidence, key = Try(a.GetLoadoutWishlistState, dest)
        if ok and cand == nil and okT and stored == 'none' then r.state = 'none'; return r end
    end
    if not ok or type(cand) ~= 'table' then r.state = 'unknown'; return r end
    r.key = type(key) == 'string' and key or cand.key
    r.name = tostring(cand.name or '')
    r.state = (evidence == 'actionable' and 'assigned') or (evidence == 'evidence-pending' and 'roles') or 'unknown'
    return r
end

-- Every Saved Build slot the server lists, read now. A slot without a row is
-- not available (blocked 'missing'). An empty slot (no Echoes) is offered,
-- as the original guided design offers it, but it is `empty`: it cannot
-- follow a Wishlist until the player saves Echoes into it in the game's own
-- build window, whose confirmation asks first (Ebonhold's Saved Build save
-- popup; the game's Accept is the save). The guide never saves, loads or
-- activates a slot. `route` says how the Echo Journal chooser can reach a
-- destination now:
--   'journal' - the chooser assigns to it now (out.journal);
--   'select'  - a populated Saved Build that is not the active one: the
--               player makes it active in My Builds themselves first;
--   'save'    - an empty slot: the player saves Echoes into it there first;
--   'first'   - the first-run target while a Saved Build is active, which
--               the chooser does not assign to.
-- Blocked options have no route.
function G.TargetOptions()
    local a = Nexus.GameAdapter
    local ok, slots = Try(a and a.Slots)
    if not ok or type(slots) ~= 'table' or slots.activeKnown == false then return nil end
    local okS, sel = Try(a.SelectedSavedBuild, slots)
    sel = okS and tonumber(sel) or nil
    local out, max = {}, math.min(10, tonumber(slots.maxSlots) or 5)
    for slot = 1, max do
        local row = type(slots.bySlot) == 'table' and slots.bySlot[slot] or nil
        local o = {destination = slot, name = type(row) == 'table' and tostring(row.name or '') or '', selected = sel == slot}
        if type(row) ~= 'table' or type(row.echoes) ~= 'table' then o.blocked = 'missing'
        elseif #row.echoes == 0 then o.empty = true end
        out[#out + 1] = o
    end
    out[#out + 1] = {destination = 'first', name = '', selected = sel == nil}
    -- Where the Echo Journal chooser assigns now (ui/JournalTab.lua): an
    -- empty or missing active slot takes no assignment.
    local current = sel and out[sel]
    out.journal = current and ((current.blocked or current.empty) and 'blocked' or sel) or 'first'
    out.journalName = current and current.name or ''
    for _, o in ipairs(out) do
        if not o.blocked then
            if o.destination == out.journal then o.route = 'journal'
            elseif o.empty then o.route = 'save'
            elseif o.destination == 'first' then o.route = 'first'
            else o.route = 'select' end
        end
    end
    return out
end

-- A coach choice of a destination; nothing is loaded, activated or saved.
-- An empty slot may be chosen (it is offered); TargetFacts then says it is
-- not ready until the player saves Echoes into it in the game.
function G.ChooseTarget(dest)
    local s = G.State(); G.Recheck(); dest = Dest(dest)
    local opts = G.TargetOptions()
    if not opts then return false, 'notLoaded' end
    for _, o in ipairs(opts) do
        if o.destination == dest then
            if o.blocked then return false, o.blocked end
            s.target, s.request = {destination = dest, name = o.name}, nil
            s.skipped.target = nil
            Changed(); return true
        end
    end
    return false, 'missing'
end

-- The chosen destination read now. `ready`: its consequence is known and,
-- for a replacement, accepted; an empty slot is never ready (it cannot
-- follow a Wishlist yet). `route` (TargetOptions, read now): how the chooser
-- can reach it. `canContinue`: the next step can do its job: the slot is
-- ready and either already follows the chosen Wishlist (the Assign step only
-- observes it) or the chooser assigns to it now. A ready destination the
-- chooser does not reach keeps Continue waiting on the player's own action
-- in My Builds instead of an Assign step that could only refuse.
function G.TargetFacts()
    local s = G.State(); local t = s.target
    if not t then return nil end
    local read = G.ReadAssignment(t.destination)
    local f = {read = read, destination = t.destination, name = t.name}
    local opts = G.TargetOptions()
    local live
    for _, o in ipairs(opts or {}) do if o.destination == t.destination then live = o end end
    f.empty = live ~= nil and live.empty == true
    f.missing = live ~= nil and live.blocked ~= nil
    f.route = live and not live.blocked and live.route or nil
    f.journal, f.journalName = opts and opts.journal or nil, opts and opts.journalName or nil
    if s.wishlist and (read.state == 'assigned' or read.state == 'roles') then
        f.already = read.key == s.wishlist.key
        f.replaces = not f.already
    end
    -- A replacement is accepted only against the assignment seen when accepted.
    f.confirmed = f.replaces == true and t.confirmedAction ~= nil and t.confirmedAction == read.action
    f.ready = s.wishlist ~= nil and not f.empty and not f.missing and read.state ~= 'unknown'
        and (not f.replaces or f.confirmed)
    f.canContinue = f.ready and (f.already == true or f.route == 'journal')
    return f
end
function G.ConfirmReplace()
    local s, f = G.State(), G.TargetFacts()
    if not (f and f.replaces and f.read.action) then return false end
    s.target.confirmedAction, s.request = f.read.action, nil
    Changed(); return true
end
function G.CancelReplace()
    local s = G.State()
    s.target, s.request = nil, nil
    Changed(); return true
end

-- Bind one request to the current context, destination, Wishlist key and the
-- destination's action token, before the player chooses in the real chooser.
function G.ArmAssign()
    local s = G.State(); G.Recheck()
    local f = G.TargetFacts()
    if f and f.empty then return false, 'empty' end
    if not (s.wishlist and f and f.ready) then return false, 'notReady' end
    local opts = G.TargetOptions()
    if not opts then return false, 'notLoaded' end
    if opts.journal ~= f.destination then return false, 'route', opts.journal, opts.journalName end
    s.request = {serial = Tick(), destination = f.destination, key = s.wishlist.key, baseAction = f.read.action}
    s.skipped.assign = nil
    Changed(); return true
end
function G.Disarm() G.State().request = nil end

-- Guide-private operation origins. A real assignment operation the player
-- starts (a chooser row click, before any confirmation or role choice) gets an
-- opaque token bound to the request armed at that moment, with its context,
-- destination and Wishlist key. Only this file reads a token: an unknown,
-- foreign or missing one binds nothing. Session memory only; nothing is saved.
local origins = setmetatable({}, {__mode = 'k'})
local claims = setmetatable({}, {__mode = 'k'})

-- The token for an operation starting now, or nil when no request for this
-- destination is armed. It reads guide state only and changes nothing in the
-- game; the caller carries it unchanged to every result of that operation.
function G.BeginAssign(destination, key)
    local s = S
    if not s then return nil end
    G.Recheck()
    local req, dest = s.request, Dest(destination)
    if not (req and dest and req.destination == dest) then return nil end
    local token = {}
    origins[token] = {request = req, destination = dest,
        key = type(key) == 'string' and key ~= '' and key or nil,
        owner = s.context.owner, epoch = s.context.epoch, session = s.context.session}
    return token
end

-- The receipt seam. Called by real outcome sites only; it records and reads.
function G.Note(kind, fields)
    fields = type(fields) == 'table' and fields or {}
    local ctx = G.Context()
    local r = {kind = kind, serial = Tick(), owner = ctx.owner, epoch = ctx.epoch, session = ctx.session,
        origin = fields.origin, reason = fields.reason, cancelled = fields.cancelled == true,
        name = fields.name ~= nil and tostring(fields.name) or nil,
        key = type(fields.key) == 'string' and fields.key ~= '' and fields.key or nil}
    if kind == 'assign' then
        r.destination, r.ok = Dest(fields.destination), fields.ok == true
        if r.ok and r.destination then
            local a = Nexus.GameAdapter
            local ok, token = Try(a and a.AssignmentActionToken, r.destination)
            r.token = ok and token or nil
        end
        -- The operation's own origin, as this guide issued it: the receipt
        -- belongs to that request only while its context, destination and
        -- Wishlist key are the ones the operation began with.
        local o = origins[fields.guide]
        if o and o.destination == r.destination and o.owner == r.owner and o.epoch == r.epoch
            and o.session == r.session and (o.key == nil or r.key == nil or o.key == r.key) then
            claims[r] = o.request
        end
    elseif kind == 'save' then
        r.saveKind, r.written, r.token = fields.kind, Dest(fields.written), fields.token
    end
    receipts[#receipts + 1] = r
    while #receipts > LIMIT do table.remove(receipts, 1) end
    local s = S
    if s and (kind == 'save' or kind == 'draft') and s.awaitSave then
        G.Recheck()
        if s.awaitSave and r.serial > s.awaitSave then
            if kind == 'draft' then s.draft = r
            elseif SAVED[r.saveKind] then
                s.wishlist = {key = r.key, name = r.name or '', source = 'saved', receipt = r}
                s.draft, s.saveSeen, s.awaitSave, s.request = nil, nil, nil, nil
                if s.target then s.target.confirmedAction = nil end
            else s.saveSeen, s.draft = r, nil end
        end
    end
    Changed(r)
    return r.serial
end
function G.Receipts()
    local out = {}
    for i, r in ipairs(receipts) do
        local copy = {}
        for k, v in pairs(r) do copy[k] = v end
        out[i] = copy
    end
    return out
end

local function Bound(s, r)
    return r.owner == s.context.owner and r.epoch == s.context.epoch and r.session == s.context.session
end

-- verified only from a bound receipt whose token is still the destination's
-- current token and whose Wishlist the fresh read back shows.
function G.AssignStatus()
    local s = G.State(); G.Recheck()
    local w, f = s.wishlist, G.TargetFacts()
    if not (w and f) then return {state = 'none'} end
    local read, req, receipt, foreign = f.read, s.request, nil, nil
    if req then
        for i = #receipts, 1, -1 do
            local r = receipts[i]
            -- Only a result of an operation that began under this very request
            -- (G.BeginAssign) is its own; another operation's later report is
            -- never adopted as this request's result.
            if r.kind == 'assign' and r.serial > req.serial and r.destination == f.destination then
                if claims[r] == req then receipt = r; break end
                if r.ok and not foreign then foreign = r end
            end
        end
    end
    local saved = w.receipt
    if not receipt and saved and saved.written == f.destination and SAVED[saved.saveKind] then
        receipt = {ok = true, token = saved.token, key = saved.key, owner = saved.owner, epoch = saved.epoch,
            session = saved.session, origin = 'save'}
    end
    if receipt then
        local out = {origin = receipt.origin, name = receipt.name, reason = receipt.reason, readName = read.name}
        if not Bound(s, receipt) then out.state = 'outdated'
        elseif receipt.cancelled then out.state = 'cancelled'
        elseif not receipt.ok then out.state = 'refused'
        elseif receipt.key and receipt.key ~= w.key then out.state = 'other'
        elseif not (receipt.token and read.action) then out.state = 'unknown'
        elseif read.action ~= receipt.token then out.state = 'stale'
        elseif read.state == 'assigned' then out.state = read.key == w.key and 'verified' or 'mismatch'
        elseif read.state == 'roles' then out.state = 'partial'
        else out.state = 'unknown' end
        return out
    end
    if read.state == 'assigned' and read.key == w.key then return {state = 'observed', readName = read.name} end
    -- A write another operation reported after this request is not its
    -- result, and what it did to this target is not known here.
    if foreign then return {state = 'unknown', readName = read.name} end
    if req then return {state = req.baseAction ~= read.action and 'changed' or 'pending'} end
    return {state = 'ready'}
end

function G.CanNext()
    local s, id = G.State(), G.StepId()
    if id == 'welcome' then return s.path ~= nil end
    if id == 'wishlist' then G.Recheck(); return s.wishlist ~= nil end
    -- A target the Echo Journal chooser cannot reach now (TargetFacts
    -- canContinue) waits on the player's own action in My Builds; Continue
    -- never leads to an Assign step that could only refuse it.
    if id == 'target' then G.Recheck(); local f = G.TargetFacts(); return f ~= nil and f.canContinue == true end
    if id == 'assign' then local st = G.AssignStatus().state; return st == 'verified' or st == 'observed' end
    if id == 'manual' then return s.manualAck end
    -- Auto continues once the player chose to keep it as it is (KeepAuto)
    -- in this very context; Recheck drops a choice made in another.
    if id == 'auto' then G.Recheck(); return s.autoKept ~= nil end
    return false
end
-- Moves along the current path; changes no choice and no result.
local function Move(d)
    local s, order = G.State(), G.Order()
    local i = G.Position() + d
    if i < 1 or i > #order then return false end
    s.index, s.notice = G.INDEX[order[i]], nil
    return true
end
function G.Next()
    if not G.CanNext() then return false end
    Move(1); Changed(); return true
end
function G.Back()
    Move(-1); G.State().notice = nil
    Changed(); return true
end
-- Skipped is recorded as skipped; it never counts as done. Choosing or
-- trying the step later clears the mark.
function G.Skip()
    local s, id = G.State(), G.StepId()
    if not G.SKIPPABLE[id] then return false end
    s.skipped[id] = true
    Move(1); Changed(); return true
end
-- Welcome's choice of path. It only records the choice; Continue moves on.
function G.SetPath(path)
    if path ~= 'new' and path ~= 'existing' and path ~= 'explore' then return false end
    G.State().path = path
    Changed(); return true
end

-- SIMULATED lesson: fictional cards, no game read or action. Any pick counts
-- as having tried the preview; the player's pick always wins over the mark.
function G.SimPick(i)
    i = tonumber(i)
    if not i or i < 1 or i > 3 then return false end
    local s = G.State()
    s.manualPick, s.manualAck, s.skipped.manual = i, true, nil
    Changed(); return true
end
function G.SimAck()
    local s = G.State()
    if not s.manualPick then return false end
    s.manualAck = true
    Changed(); return true
end

-- Read only. The guide never changes Auto.
function G.AutoState()
    local ok, st = Try(Nexus.RecomputeStats)
    if not ok or type(st) ~= 'table' then return 'unknown' end
    return st.autoEnabled == true and 'on' or 'off'
end
-- The player chose to leave Auto as it is: records the mode read now. It
-- calls no Auto setter.
function G.KeepAuto()
    local s = G.State(); G.Recheck()
    s.autoKept, s.skipped.auto = G.AutoState(), nil
    Changed(); return true
end

function G.Summary()
    local s = G.State(); G.Recheck()
    local function Mark(id, code)
        if code == 'todo' and s.skipped[id] then return 'skipped' end
        return code
    end
    local seen = s.saveSeen and s.saveSeen.saveKind
    local wish = (s.wishlist and 'done') or (s.draft and 'draft')
        or ((seen == 'partial' or seen == 'uncertain') and seen) or 'todo'
    local f = G.TargetFacts()
    local assign = G.AssignStatus().state
    if assign == 'none' or assign == 'ready' then assign = 'todo' end
    local out = {wishlist = Mark('wishlist', wish), target = Mark('target', (f and f.canContinue) and 'done' or 'todo'),
        assign = Mark('assign', assign), manual = s.manualAck and 'lesson' or Mark('manual', 'todo'),
        auto = G.AutoState(), autoKept = s.autoKept, autoSkipped = s.skipped.auto == true}
    -- Skipped wins over a not-yet-reached open state only; never over done.
    if s.skipped.assign and (assign == 'todo' or assign == 'pending') then out.assign = 'skipped' end
    local open = 0
    for _, id in ipairs({'wishlist', 'target'}) do if out[id] ~= 'done' then open = open + 1 end end
    if out.assign ~= 'verified' and out.assign ~= 'observed' then open = open + 1 end
    out.open = open
    out.complete = out.wishlist == 'done' and out.target == 'done' and out.assign == 'verified'
    out.trueNow = out.complete or (out.wishlist == 'done' and out.target == 'done' and out.assign == 'observed')
    return out
end
