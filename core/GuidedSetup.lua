-- Nexus: core/GuidedSetup.lua
-- Session-only state and evidence of the guided setup coach
-- (ui/GuidedSetup.lua, issue #131). Real outcome sites report through
-- G.Note: Wishlist Editor saves and import drafts, and Echo Journal, role
-- picker and editor assignments. A step completes only from a receipt bound
-- to the current owner, assignment epoch, world session, destination and
-- Wishlist key, plus a fresh read back of that destination's opaque
-- assignment-action token and its assigned Wishlist. Reads happen only inside
-- an explicit call (a click, a Show or a receipt); nothing is polled. Nothing
-- here writes saved data, assigns, uploads, sends, spends, requests slots or
-- changes Auto, and nothing persists: a reload starts the guide over.
Nexus = Nexus or {}
local G = {}
Nexus.GuidedSetup = G

G.STEPS = {'welcome', 'wishlist', 'target', 'assign', 'manual', 'auto', 'summary'}
G.INDEX = {}
for i, id in ipairs(G.STEPS) do G.INDEX[id] = i end
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
local function Changed(receipt)
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
function G.Replay() S = Fresh(); Changed(); return S end

-- A changed owner, saved root (epoch) or world session clears every piece of
-- evidence; the step position, path and lesson stay. Never restored later.
function G.Recheck()
    local s, now = G.State(), G.Context()
    local why = (now.owner ~= s.context.owner and 'owner')
        or (now.epoch ~= s.context.epoch and 'epoch')
        or (now.session ~= s.context.session and 'session') or nil
    if why then
        s.wishlist, s.draft, s.saveSeen, s.awaitSave = nil, nil, nil, nil
        s.target, s.request, s.notice, s.context = nil, nil, why, now
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
        elseif #row.echoes == 0 then o.blocked = 'empty' end
        out[#out + 1] = o
    end
    out[#out + 1] = {destination = 'first', name = '', selected = sel == nil}
    -- Where the Echo Journal chooser assigns now (ui/JournalTab.lua).
    local current = sel and out[sel]
    out.journal = current and (current.blocked and 'blocked' or sel) or 'first'
    out.journalName = current and current.name or ''
    return out
end

-- A coach choice of a destination; nothing is loaded, activated or saved.
function G.ChooseTarget(dest)
    local s = G.State(); G.Recheck(); dest = Dest(dest)
    local opts = G.TargetOptions()
    if not opts then return false, 'notLoaded' end
    for _, o in ipairs(opts) do
        if o.destination == dest then
            if o.blocked then return false, o.blocked end
            s.target, s.request = {destination = dest, name = o.name}, nil
            Changed(); return true
        end
    end
    return false, 'missing'
end

function G.TargetFacts()
    local s = G.State(); local t = s.target
    if not t then return nil end
    local read = G.ReadAssignment(t.destination)
    local f = {read = read, destination = t.destination, name = t.name}
    if s.wishlist and (read.state == 'assigned' or read.state == 'roles') then
        f.already = read.key == s.wishlist.key
        f.replaces = not f.already
    end
    -- A replacement is accepted only against the assignment seen when accepted.
    f.confirmed = f.replaces == true and t.confirmedAction ~= nil and t.confirmedAction == read.action
    f.ready = s.wishlist ~= nil and read.state ~= 'unknown' and (not f.replaces or f.confirmed)
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
    if not (s.wishlist and f and f.ready) then return false, 'notReady' end
    local opts = G.TargetOptions()
    if not opts then return false, 'notLoaded' end
    if opts.journal ~= f.destination then return false, 'route', opts.journal, opts.journalName end
    s.request = {serial = Tick(), destination = f.destination, key = s.wishlist.key, baseAction = f.read.action}
    Changed(); return true
end
function G.Disarm() G.State().request = nil end

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
            else s.saveSeen = r end
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
    local read, req, receipt = f.read, s.request, nil
    if req then
        for i = #receipts, 1, -1 do
            local r = receipts[i]
            if r.kind == 'assign' and r.serial > req.serial and r.destination == f.destination then receipt = r; break end
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
    if req then return {state = req.baseAction ~= read.action and 'changed' or 'pending'} end
    return {state = 'ready'}
end

function G.CanNext()
    local s, id = G.State(), G.StepId()
    if id == 'welcome' then return s.path ~= nil end
    if id == 'wishlist' then G.Recheck(); return s.wishlist ~= nil end
    if id == 'target' then G.Recheck(); local f = G.TargetFacts(); return f ~= nil and f.ready end
    if id == 'assign' then local st = G.AssignStatus().state; return st == 'verified' or st == 'observed' end
    if id == 'manual' then return s.manualAck end
    return id == 'auto'
end
function G.Next()
    if not G.CanNext() then return false end
    local s = G.State()
    s.index, s.notice = math.min(#G.STEPS, s.index + 1), nil
    Changed(); return true
end
function G.Back()
    local s = G.State()
    if s.path == 'explore' and s.index == G.INDEX.manual then s.index = 1 else s.index = math.max(1, s.index - 1) end
    s.notice = nil; Changed(); return true
end
-- Skipped is recorded as skipped; it never counts as done.
function G.Skip()
    local s, id = G.State(), G.StepId()
    if id == 'summary' then return false end
    s.skipped[id], s.index, s.notice = true, s.index + 1, nil
    Changed(); return true
end
function G.SetPath(path)
    if path ~= 'new' and path ~= 'existing' and path ~= 'explore' then return false end
    local s = G.State()
    s.path, s.index = path, path == 'explore' and G.INDEX.manual or G.INDEX.wishlist
    Changed(); return true
end

-- SIMULATED lesson: fictional cards, no game read or action.
function G.SimPick(i)
    i = tonumber(i)
    if not i or i < 1 or i > 3 then return false end
    G.State().manualPick = i
    Changed(); return true
end
function G.SimAck()
    local s = G.State()
    if s.manualPick ~= G.SIM_ANSWER then return false end
    s.manualAck = true
    Changed(); return true
end

-- Read only. The guide never changes Auto.
function G.AutoState()
    local ok, st = Try(Nexus.RecomputeStats)
    if not ok or type(st) ~= 'table' then return 'unknown' end
    return st.autoEnabled == true and 'on' or 'off'
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
    local out = {wishlist = Mark('wishlist', wish), target = Mark('target', (f and f.ready) and 'done' or 'todo'),
        assign = Mark('assign', assign), manual = s.manualAck and 'lesson' or Mark('manual', 'todo'),
        auto = G.AutoState()}
    out.complete = out.wishlist == 'done' and out.target == 'done' and out.assign == 'verified'
    out.trueNow = out.complete or (out.wishlist == 'done' and out.target == 'done' and out.assign == 'observed')
    return out
end
