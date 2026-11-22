-- Sequential level-one Wishlist selections through the real Journal picker.
-- At level 1, choosing a Wishlist with tome-gated Echoes must bring the
-- server's tome state to exactly that Wishlist's set: every tome it needs
-- enabled AND every tome it no longer needs disabled. This must hold after
-- EACH selection of A -> B -> C -> A -> ... within one running session (no
-- reload, no rebuilt runtime), not only after the first one.
--
-- Real TOC boot, runtime, adapter and Journal controls: the selector, then a
-- picker row click (ui/JournalTab.lua AssociateWishlistOnly, which calls
-- SetFirstRunWishlist or SetLoadoutWishlist with the row's own candidate).
-- A click is not followed by H.Notify: a Nexus association has no server
-- event. The one modelled boundary is the synthetic server. The harness
-- records ToggleTomeEcho; only an accepted call queues a reply, and a
-- delivered reply flips that Echo's disabled flag and notifies after a short
-- latency, or is held to keep the control pending. An accepted request is
-- never counted as a changed state: every tome verdict reads the server
-- mirror (H.disabled), and a step is settled only with no pending toggle and
-- no undelivered reply.
--
--   SEQ     Auto ON and tome automation permission (autoDisable) ON. After
--           each selection: the exact enabled and disabled set, exactly one
--           accepted request per tome that had to change and none otherwise,
--           nothing left pending. First-run and populated Saved Build
--           destinations, entered by an in-session reset from level 80 or by
--           a level-1 login. Also: a Wishlist with the same tome set, a held
--           server reply, reopening without a choice, re-selecting after
--           Unassign, an idle period, and level 2.
--   GUARD   Auto OFF and/or tome permission OFF: every selection changes the
--           assignment, no tome request is sent, the server is unchanged.
--           Control: grant what was withheld; the same route then mutates.
--   NATIVE  Native Wishlist activation is not a Nexus association. With a
--           populated Saved Build the Nexus target stays that Saved Build's
--           association (saved_build_wishlist_transition.lua; GameAdapter
--           keptSavedBuild). First-run native activation is not covered.
--
-- Every case boots fresh and runs to its end; each step is reported on its
-- own, so a good first selection stays visible beside a failed later one.
-- Run from the repository root. Synthetic ids and names only.
local realPrint = print
local results = {}
local function record(group, case, step, label, check, ok, detail)
    results[#results + 1] = {group=group, case=case, step=step, label=label,
        check=check, ok=ok == true}
    realPrint(string.format('%s %s %s #%s %s (%s): %s', ok == true and 'OK  ' or 'MISS',
        group, case, tostring(step), check, label, tostring(detail)))
end

local TICK, REPLY_DELAY = 0.05, 0.3
-- A step is settled once its wanted state holds with nothing pending and no
-- new request for SETTLE_QUIET seconds. SETTLE_MAX bounds a step that never
-- gets there; it exceeds the runtime's 5 s fallback plus four paced sends.
local SETTLE_MAX, SETTLE_QUIET, HOLD_SECONDS, IDLE_SECONDS = 10, 1.5, 2.5, 6
local LETTERS = {'Amber', 'Birch', 'Cedar', 'Dune', 'Ember'}
local GATED, LEVER, TOME, INDEX_OF_ECHO, TOME_OF_LEVER = {}, {}, {}, {}, {}
for i = 1, #LETTERS do
    GATED[i], LEVER[i], TOME[i] = 300100 + i, 777100 + i, 'T' .. i
    INDEX_OF_ECHO[GATED[i]], TOME_OF_LEVER[LEVER[i]] = i, 'T' .. i
end
-- Common ordinary content is held constant: the Wishlists differ only in
-- their tome-gated Echoes. Overlapping tome sets. T5 is in no Wishlist and must stay disabled. D has
-- the tome set of A in another Wishlist: choosing it after A changes no tome.
local WISHLISTS = {
    A = {slot=101, name='Seq Wishlist A', tomes={1, 2}, ordinary=200011},
    B = {slot=102, name='Seq Wishlist B', tomes={2, 3}, ordinary=200011},
    C = {slot=103, name='Seq Wishlist C', tomes={3, 4}, ordinary=200011},
    D = {slot=104, name='Seq Wishlist D', tomes={1, 2}, ordinary=200011},
}
local SAVED_BUILD = 'Saved Build One'

-- The synthetic server. W.hold keeps every reply queued (control pending).
-- ToggleTomeEcho is a toggle, so a delivered reply flips the Echo's flag.
local function Deliver(W)
    if W.hold or #W.queue == 0 then return end
    local H, kept, delivered = W.H, {}, false
    for _, reply in ipairs(W.queue) do
        if H.now >= reply.due - 1e-9 then
            H.disabled[reply.id] = not (H.disabled[reply.id] == true)
            delivered = true
        else
            kept[#kept + 1] = reply
        end
    end
    W.queue = kept
    if delivered then H.Notify() end
end

local function Run(W, seconds)
    local H = W.H
    local stop = H.now + seconds
    while H.now < stop - 1e-8 do
        H.Advance(TICK, TICK)
        Deliver(W)
    end
end

-- Server truth per tome: true when enabled (no member disabled).
local function Server(W)
    local out = {}
    for i = 1, #GATED do out[i] = W.H.disabled[GATED[i]] ~= true end
    return out
end
local function Vector(tomes)
    local out = {}
    for i = 1, #GATED do out[i] = false end
    for _, i in ipairs(tomes) do out[i] = true end
    return out
end
local function Same(a, b)
    for i = 1, #GATED do if a[i] ~= b[i] then return false end end
    return true
end
local function Show(vector)
    local on, off = {}, {}
    for i = 1, #GATED do
        if vector[i] then on[#on + 1] = TOME[i] else off[#off + 1] = TOME[i] end
    end
    return 'on={' .. table.concat(on, ',') .. '} off={' .. table.concat(off, ',') .. '}'
end
local function Pending()
    local state = Nexus.Store.State()
    local map = type(state) == 'table' and state.tomeTogglePending
    return type(map) == 'table' and map or {}
end
local function Quiet(W) return #W.queue == 0 and next(Pending()) == nil end
local function PendingText()
    local out = {}
    for lever, entry in pairs(Pending()) do
        local direction = type(entry) == 'table' and (entry.want == true and 'disable'
            or entry.want == false and 'enable' or 'unknown') or 'legacy'
        out[#out + 1] = (TOME_OF_LEVER[lever] or tostring(lever)) .. '=' .. direction
    end
    table.sort(out)
    return #out > 0 and table.concat(out, ',') or 'none'
end

-- Accepted requests of one step against the minimal change from the server
-- state before it: one request per tome that must change, none otherwise.
local function Sends(W, step, before, want)
    local count, wrong = {}, {}
    for _, request in ipairs(W.requests) do
        if request.step == step then
            local i = INDEX_OF_ECHO[request.id]
            if i then count[i] = (count[i] or 0) + 1
            else wrong[#wrong + 1] = 'unrelated Echo ' .. tostring(request.id) end
        end
    end
    local sent = {}
    for i = 1, #GATED do
        local n, expected = count[i] or 0, before[i] ~= want[i] and 1 or 0
        if n > 0 then sent[#sent + 1] = TOME[i] .. 'x' .. n end
        if n ~= expected then wrong[#wrong + 1] = TOME[i] .. ' sent ' .. n .. ', want ' .. expected end
    end
    return #wrong == 0, #sent > 0 and table.concat(sent, ',') or 'none', table.concat(wrong, '; ')
end

-- Diagnostics only: the assignment's tomes and the runtime's lever view.
local function AssignedText(W)
    local a = W.A.AssignedWishlist() or {}
    local tomes = {}
    for _, entry in ipairs(a.entries or {}) do
        local i = INDEX_OF_ECHO[tonumber(entry.spellId)]
        if i then tomes[#tomes + 1] = TOME[i] end
    end
    table.sort(tomes)
    return tostring(a.state) .. '/' .. tostring(a.name) .. ' tomes={' .. table.concat(tomes, ',') .. '}'
end
local function LeverView(W)
    local ok, view = pcall(W.A.DisabledLevers)
    if not ok or type(view) ~= 'table' then return 'unreadable' end
    local out = {}
    for i = 1, #GATED do
        local value = view[LEVER[i]]
        out[#out + 1] = TOME[i] .. '=' .. (value == 'confirmed' and 'off'
            or value == 'pending' and 'pending-off' or 'on')
    end
    return table.concat(out, ',')
end

local function World(o)
    Nexus, NexusDB, WishlistRealizerDB = nil, nil, nil
    ProjectEbonholdEchoJournal, NexusWishlistOnlyPicker = nil, nil
    NexusLoadoutAssociationPanel, NexusActiveWishlistSelector = nil, nil
    local H = dofile('tests/prototype/harness.lua')
    for i = 1, #GATED do
        local name = 'Gated Echo ' .. LETTERS[i]
        H.AddEcho(GATED[i], name, 1, 1, 0)
        H.db[GATED[i]].requiredSpell = LEVER[i]
        H.names[LEVER[i]] = 'Tome of ' .. name
        H.discovered[GATED[i]] = true
        H.disabled[GATED[i]] = true
    end
    H.perks.discoveredEchoes = H.discovered
    local function Entry(id) return {spellId=id, quality=H.db[id].quality, stacks=1} end
    for _, w in pairs(WISHLISTS) do
        local echoes = {Entry(w.ordinary)}
        for _, i in ipairs(w.tomes) do echoes[#echoes + 1] = Entry(GATED[i]) end
        H.perks.serverBuildSlots[w.slot] = {name=w.name, verified=false, echoes=echoes}
    end
    if o.destination == 'saved_build' then
        H.perks.serverActiveSlot = 1
        H.perks.serverBuildSlots[1] = {name=SAVED_BUILD, verified=true, echoes={Entry(200050)}}
    end
    H.playerLevel = o.entry == 'login1' and 1 or 80
    H.orbKnown = true
    ProjectEbonhold.OrbService = {
        IsStateKnown=function() return H.orbKnown end,
        IsOfferPending=function() return false end,
    }
    local W = {H=H, o=o, group=o.group, case=o.case, requests={}, queue={}, hold=false, step=0}
    local rawToggle = H.service.ToggleTomeEcho
    H.service.ToggleTomeEcho = function(id)
        local accepted = rawToggle(id)
        if accepted then
            W.requests[#W.requests + 1] = {id=id, step=W.step, at=H.now}
            W.queue[#W.queue + 1] = {id=id, due=H.now + REPLY_DELAY}
        end
        return accepted
    end
    H.Boot()
    W.A = Nexus.GameAdapter
    return W
end

local function Plain(text)
    return (tostring(text or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''))
end
-- RefreshAssociations is pcall-guarded, so the panel it draws is required.
local function Journal()
    if not ProjectEbonholdEchoJournal then
        CreateFrame('Frame', 'ProjectEbonholdEchoJournal', UIParent)
    end
    ProjectEbonholdEchoJournal:Show()
    Nexus.JournalTab.RefreshAssociations()
    assert(NexusLoadoutAssociationPanel and NexusLoadoutAssociationPanel:IsShown()
        and NexusActiveWishlistSelector, 'SETUP: the Journal association panel and selector are shown')
end
local function ClosePicker()
    if NexusWishlistOnlyPicker and NexusWishlistOnlyPicker:IsShown() then
        NexusActiveWishlistSelector:Click()
    end
end
local function OpenPicker()
    Journal()
    ClosePicker()
    NexusActiveWishlistSelector:Click()
    local picker = NexusWishlistOnlyPicker
    return (picker and picker:IsShown()) and picker or nil
end
local function Stored(W)
    local state = Nexus.Store.State() or {}
    if W.o.destination == 'saved_build' then
        return type(state.loadoutWishlists) == 'table' and state.loadoutWishlists[1] or nil
    end
    return state.firstRunWishlist
end

-- Since M3 (UX-05) a Journal pick for a numbered Saved Build with Echoes while
-- Auto is selected asks first with the real confirmation. The synthetic player
-- checks it and answers Assign (the dialog's own OnAccept, as the client runs
-- it). Whether it must ask comes from the scenario only: Auto selected and the
-- populated Saved Build One as the Journal's target (also while a Wishlist is
-- natively active: the Journal keeps that Saved Build). A missing or different
-- confirmation, or any dialog where none is expected, fails PICK.
local CONSENT = 'NEXUS_ASSIGN_WISHLIST_AUTO_ON'
local function StoredText(W)
    local stored = Stored(W)
    if type(stored) ~= 'table' then return tostring(stored) end
    return tostring(stored.slot) .. '/' .. tostring(stored.name) .. '/' .. tostring(stored.assignmentId)
end
local function Consent(W, w, picker, prior, asks)
    local p = W.H.popup
    if not asks then
        if p ~= nil then return false, 'unexpected dialog ' .. tostring(p.which) end
        return true, 'no confirmation expected or shown'
    end
    if not (p and p.which == CONSENT) then
        return false, 'expected the Auto-ON assignment confirmation, got ' .. tostring(p and p.which)
    end
    local d = StaticPopupDialogs[CONSENT]
    local where = "Saved Build '" .. SAVED_BUILD .. "'"
    local formatted, asked = pcall(string.format, tostring(d and d.text), p.arg1, p.arg2)
    asked = formatted and Plain(asked) or ''
    local problems = {}
    if not (type(d) == 'table' and d.button1 == 'Assign' and d.button2 == 'Cancel') then
        problems[#problems + 1] = 'buttons are not Assign/Cancel'
    end
    if p.arg1 ~= w.name or p.arg2 ~= where then
        problems[#problems + 1] = 'names ' .. tostring(p.arg1) .. ' / ' .. tostring(p.arg2)
    end
    if asked:find("Assign '" .. w.name .. "' to " .. where .. "?", 1, true) ~= 1
        or not asked:find('Auto is ON', 1, true) or not asked:find('Cancel changes nothing', 1, true) then
        problems[#problems + 1] = 'title or Auto consequence: ' .. asked
    end
    if not picker:IsShown() or StoredText(W) ~= prior then
        problems[#problems + 1] = 'assigned before the answer'
    end
    if #problems > 0 then return false, 'confirmation mismatch: ' .. table.concat(problems, '; ') end
    W.H.popup = nil
    d.OnAccept(p.frame, p.data)
    return true, 'confirmed ' .. w.name .. ' for ' .. where .. ' with Assign'
end

-- One real selection: the selector opens the picker, the named row is clicked
-- (and, where the scenario requires it, the real confirmation is answered).
local function Pick(W, key)
    local w = WISHLISTS[key]
    local picker = OpenPicker()
    if not picker then return false, 'the real selector opened no picker' end
    local row, names = nil, {}
    for _, candidate in ipairs(picker.children) do
        if candidate.nameButton and candidate:IsVisible() then
            local label = Plain(candidate.nameButton.text:GetText()):gsub('^%[Selected%] ', '')
            names[#names + 1] = label
            if label == w.name or label:sub(1, #w.name + 2) == w.name .. '  ' then row = candidate end
        end
    end
    if not row then
        ClosePicker()
        return false, 'no picker row for ' .. w.name .. '; selector "'
            .. Plain(NexusActiveWishlistSelector.text:GetText()) .. '" rows ['
            .. table.concat(names, ' | ') .. ']'
    end
    local auto = Nexus.RecomputeStats().autoEnabled == true
    local asks = auto and W.o.destination == 'saved_build'
    local prior = StoredText(W)
    W.H.popup = nil
    local heard = {}
    print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        heard[#heard + 1] = Plain(table.concat(parts, ' '))
    end
    local ok, err = pcall(row.nameButton.Click, row.nameButton)
    local consented, consent = false, 'not reached'
    if ok then
        local answered, verdict, detail = pcall(Consent, W, w, picker, prior, asks)
        if answered then consented, consent = verdict, detail
        else consented, consent = false, 'the confirmation answer raised: ' .. tostring(verdict) end
    end
    print = realPrint
    if not ok then return false, 'the row click raised: ' .. tostring(err) end
    local closed = not NexusWishlistOnlyPicker:IsShown()
    ClosePicker()
    W.H.popup = nil
    local a, stored = W.A.AssignedWishlist() or {}, Stored(W)
    local storedSlot = type(stored) == 'table' and tonumber(stored.slot) or nil
    local storedName = type(stored) == 'table' and stored.name or nil
    local autoKept = (Nexus.RecomputeStats().autoEnabled == true) == auto
    return consented == true and autoKept and closed and a.state == 'ready' and a.name == w.name
            and storedSlot == w.slot and storedName == w.name,
        string.format('clicked %s (server slot %d): %s; picker closed=%s assigned=%s/%s stored=%s/%s auto kept=%s%s',
            w.name, w.slot, tostring(consent), tostring(closed), tostring(a.state), tostring(a.name),
            tostring(storedSlot), tostring(storedName), tostring(autoKept),
            #heard > 0 and (' heard: ' .. table.concat(heard, ' / ')) or '')
end

-- `want` nil: settle on quiet only (an observed step).
local function Settle(W, want)
    local H = W.H
    local start, reached, seen = H.now, nil, #W.requests
    while H.now - start < SETTLE_MAX - 1e-8 do
        Run(W, TICK)
        if #W.requests ~= seen then seen, reached = #W.requests, nil end
        if reached then
            if H.now - reached >= SETTLE_QUIET - 1e-8 then break end
        elseif Quiet(W) and (want == nil or Same(Server(W), want)) then
            reached = H.now
        end
    end
    return H.now - start
end

-- One user action and its verdict. `action`: a Wishlist key (a real picker
-- click), a function returning ok, detail, or nil. `tomes`: the exact
-- enabled set expected afterwards; nil expects the server state unchanged.
local function Step(W, label, action, tomes, opts)
    opts = opts or {}
    W.step = W.step + 1
    local n = W.step
    local before = Server(W)
    local want = tomes and Vector(tomes) or before
    if opts.hold then W.hold = true end
    if type(action) == 'string' then
        record(W.group, W.case, n, label, 'PICK', Pick(W, action))
    elseif type(action) == 'function' then
        record(W.group, W.case, n, label, 'ACTION', action(W))
    end
    if opts.hold then
        Run(W, HOLD_SECONDS)
        local held, pending, unmatched = Server(W), Pending(), {}
        for i = 1, #GATED do
            local entry = pending[LEVER[i]]
            if before[i] ~= want[i] and not (type(entry) == 'table'
                and entry.want == (not want[i])) then
                unmatched[#unmatched + 1] = TOME[i]
            end
        end
        local each, sent, wrong = Sends(W, n, before, want)
        record(W.group, W.case, n, label, 'HELD-NOT-CHANGED', Same(held, before),
            'server mirror while every reply is held ' .. Show(held) .. '; before ' .. Show(before))
        record(W.group, W.case, n, label, 'HELD-ONE-REQUEST', each,
            'accepted requests while held ' .. sent .. (wrong ~= '' and ('; ' .. wrong) or ''))
        record(W.group, W.case, n, label, 'HELD-PENDING', #unmatched == 0,
            'pending ' .. PendingText() .. (#unmatched > 0
                and ('; no pending entry in the wanted direction for ' .. table.concat(unmatched, ',')) or ''))
        W.hold = false
    end
    local waited = Settle(W, not opts.observeOnly and want or nil)
    local after = Server(W)
    local exact, sent, wrong = Sends(W, n, before, want)
    if opts.observeOnly then
        realPrint('OBSERVE ' .. W.group .. ' ' .. W.case .. ' #' .. n .. ' ' .. label .. ': server '
            .. Show(after) .. ' (before ' .. Show(before) .. '); accepted requests ' .. sent
            .. '; pending ' .. PendingText())
    else
        local stale, missing = {}, {}
        for i = 1, #GATED do
            if after[i] and not want[i] then stale[#stale + 1] = TOME[i] end
            if want[i] and not after[i] then missing[#missing + 1] = TOME[i] end
        end
        record(W.group, W.case, n, label, 'TOMES', Same(after, want), 'server ' .. Show(after)
            .. '; want ' .. Show(want)
            .. (#stale > 0 and ('; still enabled ' .. table.concat(stale, ',')) or '')
            .. (#missing > 0 and ('; not enabled ' .. table.concat(missing, ',')) or ''))
        record(W.group, W.case, n, label, 'REQUESTS', exact,
            'accepted requests ' .. sent .. (wrong ~= '' and ('; ' .. wrong) or ''))
        record(W.group, W.case, n, label, 'CONFIRMED', Quiet(W),
            'pending ' .. PendingText() .. '; undelivered replies ' .. #W.queue)
    end
    realPrint(string.format('TRACE %s %s #%d %s: level=%s auto=%s tomePermission=%s assigned=%s server %s runtime %s requests %s pending %s settled=%.2fs',
        W.group, W.case, n, label, tostring(W.H.playerLevel),
        tostring(Nexus.RecomputeStats().autoEnabled), tostring(Nexus.Store.Settings().autoDisable),
        AssignedText(W), Show(after), LeverView(W), sent, PendingText(), waited))
end

local function Idle(W, label, seconds)
    W.step = W.step + 1
    local n, before = W.step, Server(W)
    Run(W, seconds)
    local none, sent = Sends(W, n, before, before)
    local after = Server(W)
    record(W.group, W.case, n, label, 'IDLE', none and Same(after, before) and Quiet(W),
        string.format('over %ss: accepted requests %s; server %s; pending %s',
            tostring(seconds), sent, Show(after), PendingText()))
end

local function Reopen(W)
    local before = AssignedText(W)
    local opened = OpenPicker() ~= nil
    ClosePicker()
    local after = AssignedText(W)
    return opened and before == after
            and not (NexusWishlistOnlyPicker and NexusWishlistOnlyPicker:IsShown()),
        'picker opened=' .. tostring(opened) .. '; assignment ' .. after .. ' (before ' .. before .. ')'
end

local function Unassign(W)
    local picker = OpenPicker()
    local clear = picker and picker.clearRow
    if not (clear and clear:IsVisible()) then
        ClosePicker()
        return false, 'the picker offers no Unassign row'
    end
    clear:Click()
    ClosePicker()
    return (W.A.AssignedWishlist() or {}).state == 'unassigned', 'after Unassign ' .. AssignedText(W)
end

local function SetPermission(value)
    local result, why = Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1('autoDisable', value)
    assert(result ~= nil and Nexus.Store.Settings().autoDisable == value,
        'SETUP: tome automation permission ' .. tostring(value) .. ' through the settings owner: ' .. tostring(why))
end
local function AutoOn(W)
    SlashCmdList.NEXUS('auto'); Run(W, .4)
    assert(Nexus.RecomputeStats().autoEnabled == true, 'SETUP: /nexus auto turns Auto ON')
end

local function Enter(W)
    local o, H, A = W.o, W.H, W.A
    if o.tomePermission == false then SetPermission(false) end
    if o.auto then AutoOn(W) end
    if o.entry == 'reset' then
        H.playerLevel = 1; H.Fire('PLAYER_LEVEL_UP', 1); H.Notify()
    end
    Run(W, 2)
    assert(H.playerLevel == 1, 'SETUP: level 1')
    assert(A.DiscoverySynced() == true, 'SETUP: discovery mirror synced')
    assert(A.TomeMutationPaused() == false, 'SETUP: no Tome of Echo mutation hold')
    assert(A.OrdinaryBoardAllowed() == true, 'SETUP: ordinary gate open')
    assert(Nexus.RecomputeStats().autoEnabled == (o.auto == true), 'SETUP: Auto is ' .. tostring(o.auto == true))
    assert(Nexus.Store.Settings().autoDisable == (o.tomePermission ~= false),
        'SETUP: tome automation permission is ' .. tostring(o.tomePermission ~= false))
    local catalog = A.Catalog()
    for i = 1, #GATED do
        local lever = catalog and catalog.levers and catalog.levers[LEVER[i]]
        assert(lever and lever.conformant == true and A.LeverHasKnownMember(LEVER[i]) == true,
            'SETUP: ' .. TOME[i] .. ' is a conformant, discovered tome lever')
    end
    assert((A.AssignedWishlist() or {}).state == 'unassigned',
        'SETUP: no Wishlist is assigned before the first selection: ' .. AssignedText(W))
    local server = Server(W)
    record(W.group, W.case, 0, 'before any selection', 'PRE', #W.requests == 0 and Same(server, Vector({})),
        'no tome request without a Wishlist; server ' .. Show(server) .. '; requests ' .. #W.requests)
end

local function NoBuildWrites(W)
    W.step = W.step + 1
    local n = 0
    for _, action in ipairs(W.H.actions) do
        if action[1] == 'upload' or action[1] == 'save' or action[1] == 'activate' then n = n + 1 end
    end
    record(W.group, W.case, W.step, 'whole case', 'NO-BUILD-WRITES', n == 0,
        'selections upload, save or activate no build: ' .. n)
end

local function Sequence(W)
    Enter(W)
    Step(W, 'first selection A', 'A', WISHLISTS.A.tomes)
    Step(W, 'second selection B', 'B', WISHLISTS.B.tomes)
    Step(W, 'third selection C', 'C', WISHLISTS.C.tomes)
    Step(W, 'back to A', 'A', WISHLISTS.A.tomes)
    Step(W, 'D: the tome set of A in another Wishlist', 'D', WISHLISTS.D.tomes)
    Step(W, 'B again', 'B', WISHLISTS.B.tomes)
    Step(W, 'C again, server replies held then released', 'C', WISHLISTS.C.tomes, {hold=true})
    Step(W, 'A again', 'A', WISHLISTS.A.tomes)
    Step(W, 'reopen the picker and choose nothing', Reopen, nil)
    Step(W, 'Unassign', Unassign, nil, {observeOnly=true})
    Step(W, 'select A again after Unassign', 'A', WISHLISTS.A.tomes)
    Idle(W, 'idle after the sequence', IDLE_SECONDS)
    -- Exact level-one eligibility: at level 2 a selection still changes the
    -- assignment, and no tome request follows.
    Step(W, 'advance to level 2', function(W)
        W.H.playerLevel = 2; W.H.Fire('PLAYER_LEVEL_UP', 2)
        return true, 'level ' .. tostring(W.H.playerLevel)
    end, nil)
    Step(W, 'level 2: select B', 'B', nil)
    W.step = W.step + 1
    local requests = #W.requests
    local ok, why = W.A.ToggleLever(LEVER[3], false)
    record(W.group, W.case, W.step, 'adapter at level 2', 'LEVEL2-ADAPTER',
        ok == false and why == 'not level 1' and #W.requests == requests,
        'ToggleLever(' .. TOME[3] .. ', enable) at level 2: ' .. tostring(ok) .. ', ' .. tostring(why))
end

local function Guarded(W)
    Enter(W)
    Step(W, 'first selection A', 'A', nil)
    Step(W, 'second selection B', 'B', nil)
    Step(W, 'third selection C', 'C', nil)
    Step(W, 'back to A', 'A', nil)
    Idle(W, 'idle with the permission withheld', IDLE_SECONDS)
    -- Control: grant only what this case withheld; the same Journal route
    -- then mutates, so the silence above was the permission, not the fixture.
    Step(W, 'grant the withheld permission', function(W)
        if W.o.tomePermission == false then SetPermission(true) end
        if not W.o.auto then AutoOn(W) end
        local auto, tome = Nexus.RecomputeStats().autoEnabled, Nexus.Store.Settings().autoDisable
        return auto == true and tome == true, 'Auto=' .. tostring(auto) .. ' tomePermission=' .. tostring(tome)
    end, nil, {observeOnly=true})
    Step(W, 'control: select B with the permission granted', 'B', WISHLISTS.B.tomes)
end

local function Target(W, label, key)
    local w = WISHLISTS[key]
    local a = W.A.AssignedWishlist() or {}
    Journal()
    local journalLabel = Plain(NexusLoadoutAssociationPanel.label:GetText())
    record(W.group, W.case, W.step, label, 'NATIVE-TARGET',
        a.state == 'ready' and a.name == w.name and journalLabel:find(SAVED_BUILD, 1, true) ~= nil,
        'Nexus target ' .. AssignedText(W) .. ', Journal "' .. journalLabel .. '"; contract: '
            .. w.name .. ', the association of ' .. SAVED_BUILD)
end

local function Native(W)
    Enter(W)
    Step(W, 'Journal selection A', 'A', WISHLISTS.A.tomes)
    Step(W, 'native activation of the Wishlist B mirror', function(W)
        W.H.perks.serverActiveSlot = WISHLISTS.B.slot; W.H.Notify()
        return true, 'native active slot ' .. tostring(W.A.Slots().activeSlot)
    end, nil)
    Target(W, 'native Wishlist active', 'A')
    Step(W, 'Journal selection C while a Wishlist is natively active', 'C', WISHLISTS.C.tomes)
    Step(W, 'native activation back to the Saved Build', function(W)
        W.H.perks.serverActiveSlot = 1; W.H.Notify()
        return true, 'native active slot ' .. tostring(W.A.Slots().activeSlot)
    end, nil)
    Target(W, 'Saved Build natively active again', 'C')
end

local function Case(group, case, o, body)
    o.group, o.case = group, case
    realPrint('CASE ' .. group .. ' ' .. case)
    local ok, err = pcall(function()
        local W = World(o)
        body(W)
        NoBuildWrites(W)
    end)
    print = realPrint
    if not ok then record(group, case, 0, 'case', 'STAGE', false, 'did not complete: ' .. tostring(err)) end
end

for _, destination in ipairs({'first_run', 'saved_build'}) do
    for _, entry in ipairs({'reset', 'login1'}) do
        Case('SEQ', destination .. '/' .. entry,
            {destination=destination, entry=entry, auto=true, tomePermission=true}, Sequence)
    end
end
for _, destination in ipairs({'first_run', 'saved_build'}) do
    for _, g in ipairs({{false, true}, {true, false}, {false, false}}) do
        Case('GUARD', destination .. '/auto-' .. (g[1] and 'on' or 'off') .. '/tome-' .. (g[2] and 'on' or 'off'),
            {destination=destination, entry='reset', auto=g[1], tomePermission=g[2]}, Guarded)
    end
end
Case('NATIVE', 'saved_build/reset',
    {destination='saved_build', entry='reset', auto=true, tomePermission=true}, Native)

-- Per case, each step's verdict in order: a first selection that succeeded
-- stays visible beside a later one that did not.
local order, cases, missed = {}, {}, {}
for _, r in ipairs(results) do
    local key = r.group .. ' ' .. r.case
    local c = cases[key]
    if not c then
        c = {ok=0, miss=0, steps={}, stepOrder={}}
        cases[key] = c; order[#order + 1] = key
    end
    local s = c.steps[r.step]
    if not s then
        s = {misses={}}; c.steps[r.step] = s; c.stepOrder[#c.stepOrder + 1] = r.step
    end
    if r.ok then c.ok = c.ok + 1
    else
        c.miss = c.miss + 1; s.misses[#s.misses + 1] = r.check
        missed[#missed + 1] = key .. ' #' .. tostring(r.step) .. ' ' .. r.check .. ' (' .. r.label .. ')'
    end
end
for _, key in ipairs(order) do
    local c, parts = cases[key], {}
    for _, step in ipairs(c.stepOrder) do
        local s = c.steps[step]
        parts[#parts + 1] = tostring(step) .. '=' .. (#s.misses == 0 and 'ok'
            or ('MISS:' .. table.concat(s.misses, '+')))
    end
    realPrint('SUMMARY ' .. key .. ' ok=' .. c.ok .. ' miss=' .. c.miss .. ' steps ' .. table.concat(parts, ' '))
end
if #missed > 0 then
    error('FAIL native_wishlist_tome_sequence: ' .. #missed .. ' expectation(s) not met:\n'
        .. table.concat(missed, '\n'), 0)
end
realPrint('PASS native_wishlist_tome_sequence: each level-1 Journal selection (A -> B -> C -> A ...) '
    .. 'leaves exactly its tomes enabled and the rest disabled on the synthetic server, one confirmed '
    .. 'request per changed tome; Auto OFF, tome permission OFF and level 2 send none; native Wishlist '
    .. 'activation keeps the Saved Build association; checks=' .. #results)

-- H20: first-run native Wishlist activation (appended; the cases above and
-- their PASS are unchanged). NATIVE above covers only a populated Saved Build.
-- Here the world is a fresh first run: no populated Saved Build, native
-- active slot 0, every tome disabled. A native publication is the raw host
-- change of the active slot plus its notification (as Native does); it is not
-- a Nexus association and not an adapter Activate call.
--
-- Expected target, from source (core/GameAdapter.lua at 919ebe5):
--   WishlistRoles.SelectedSavedBuild (3001-3013): a native active slot above
--     the Saved Build range keeps a Saved Build only when one was kept, and
--     ObserveSavedBuild (2989-2995) keeps one only by reading a populated
--     Saved Build as active. With none, the answer is nil, false for slot 0,
--     101 and 102 alike.
--   A.Wishlist (3669-3700): with no selected or kept Saved Build in range,
--     the target is ResolveFirstRunWishlist (2770-2775), the stored
--     state.firstRunWishlist. ReadAssignedWishlist (3846-3856) takes that same
--     record as the saved assignment when the native slot has no association.
--   ui/JournalTab.lua (1564, 1428-1456): with no selected Saved Build, the
--     picker row calls A.SetFirstRunWishlist, which stamps a new assignment.
-- So native activation of a Wishlist mirror neither assigns that Wishlist nor
-- changes the stored first-run assignment, and only an explicit Journal
-- choice moves the target. Every boundary prints the raw synthetic host and
-- stored facts (H20RAW) before any adapter or observer read (H20VIEW).
-- Each read window is also checked for passivity (H20-READ-PASSIVE): an
-- independent string snapshot of host actions, accepted requests, queued
-- replies, the raw disabled flags, pending directions, the native slot and
-- the durable assignment records, taken before the reads, must equal the
-- one taken after them (H20AFTER). Each completed case must end settled
-- after its final reads (H20-CASE-SETTLED): no undelivered reply, nothing
-- pending, the expected tome set, and no request or host action after the
-- last guarded read. The held boundary in HELD is checked for passivity
-- only; its queue and pending entries stay distinct from delivery.
--
--   FIRST    reset to 1 and login at 1: Journal A, native 101, 102, 0, 102,
--            Journal C with B natively active, native 0, idle.
--   GUARD    Auto OFF and/or tome permission OFF over the same route plus
--            observer reads: no tome request. Control: grant, Journal B.
--   DISC     discovery answer and mirror unknown: assignment and native facts
--            kept, held reason shown, no toggle; a known answer and its
--            notification restored in the same runtime settle the target.
--   HELD     every reply held across native 101/102/0 publications: requests
--            accepted and pending, server mirror unchanged, no duplicate; the
--            queued replies released settle the Journal choice.
--
-- These results are counted on their own below: any H20 miss or setup failure
-- raises after the PASS line above, so the file still exits nonzero.
local h20First = #results + 1
realPrint('H20 prior checks=' .. (h20First - 1))

-- Direction of each accepted request, read from the raw host flag at the
-- call: a toggle of a disabled Echo is an enable request. Wraps the World
-- recorder (which owns W.requests and W.queue); adds no answer of its own.
local function H20Instrument(W)
    local H, inner = W.H, W.H.service.ToggleTomeEcho
    H.service.ToggleTomeEcho = function(id)
        local wasDisabled, count = H.disabled[id] == true, #W.requests
        local accepted = inner(id)
        if accepted and #W.requests == count + 1 then
            W.requests[#W.requests].dir = wasDisabled and 'enable' or 'disable'
        end
        return accepted
    end
    W.h20Nexus, W.h20Adapter = Nexus, W.A
end

local function H20Publish(slot)
    return function(W)
        W.H.perks.serverActiveSlot = slot; W.H.Notify()
        return W.H.perks.serverActiveSlot == slot,
            'raw native active slot ' .. tostring(slot) .. ' published with its notification'
    end
end

local function H20RequestText(W, step)
    local out = {}
    for _, r in ipairs(W.requests) do
        if step == nil or r.step == step then
            local i = INDEX_OF_ECHO[r.id]
            out[#out + 1] = (i and TOME[i] or '?') .. ':' .. tostring(r.id) .. ':' .. tostring(r.dir)
        end
    end
    return #out > 0 and table.concat(out, ',') or 'none'
end

local function H20FirstText(first)
    if type(first) ~= 'table' then return tostring(first) end
    return tostring(first.slot) .. '/' .. tostring(first.name) .. '/' .. tostring(first.assignmentId)
end

-- Independent string snapshot of the consequential facts a read must leave
-- alone. Internal caches and diagnostic counters are deliberately not in it.
local H20_SNAP_PARTS = {'actions', 'requests', 'queue', 'disabled', 'pending', 'native', 'assignment'}
local function H20Snap(W)
    local H, out = W.H, {}
    local actions = {}
    for _, action in ipairs(H.actions) do
        local parts = {}
        for i = 1, #action do
            parts[#parts + 1] = type(action[i]) == 'table' and 'table' or tostring(action[i])
        end
        actions[#actions + 1] = table.concat(parts, ':')
    end
    out.actions = #actions .. '{' .. table.concat(actions, ',') .. '}'
    local requests = {}
    for _, r in ipairs(W.requests) do
        requests[#requests + 1] = tostring(r.id) .. ':' .. tostring(r.dir) .. ':' .. tostring(r.step)
            .. ':' .. string.format('%.2f', r.at)
    end
    out.requests = #requests .. '{' .. table.concat(requests, ',') .. '}'
    local queue = {}
    for _, q in ipairs(W.queue) do queue[#queue + 1] = tostring(q.id) .. '@' .. string.format('%.2f', q.due) end
    out.queue = #queue .. '{' .. table.concat(queue, ',') .. '}'
    local disabled = {}
    for id, flag in pairs(H.disabled) do disabled[#disabled + 1] = tostring(id) .. '=' .. tostring(flag) end
    table.sort(disabled)
    out.disabled = '{' .. table.concat(disabled, ',') .. '}'
    out.pending = PendingText()
    out.native = 'active=' .. tostring(H.perks.serverActiveSlot) .. ' discovery='
        .. tostring(H.perks.discoveredEchoes ~= nil) .. '/' .. tostring(H.discovered ~= nil)
    local state = Nexus.Store.State() or {}
    local first, links = state.firstRunWishlist, {}
    if type(state.loadoutWishlists) == 'table' then
        for slot, link in pairs(state.loadoutWishlists) do
            links[#links + 1] = tostring(slot) .. '=' .. (type(link) == 'table'
                and (tostring(link.name) .. '/' .. tostring(link.assignmentId)) or tostring(link))
        end
    end
    table.sort(links)
    out.assignment = 'first=' .. H20FirstText(first) .. '/' .. tostring(type(first) == 'table' and first.key or nil)
        .. ' links{' .. table.concat(links, ',') .. '} serial=' .. tostring(state.wishlistAssignmentSerial)
    return out
end

-- Compares a snapshot taken before a read window with one taken now.
-- `reads` names the reads of that window.
local function H20Passive(W, label, before, reads)
    local after, changed = H20Snap(W), {}
    for _, part in ipairs(H20_SNAP_PARTS) do
        if after[part] ~= before[part] then
            changed[#changed + 1] = part .. ' ' .. before[part] .. ' -> ' .. after[part]
        end
    end
    W.h20LastRequests, W.h20LastActions = #W.requests, #W.H.actions
    realPrint(string.format('H20AFTER %s %s #%d %s: actions %s requests %s queue %s pending %s disabled %s %s %s',
        W.group, W.case, W.step, label, after.actions, after.requests, after.queue, after.pending,
        after.disabled, after.native, after.assignment))
    record(W.group, W.case, W.step, label, 'H20-READ-PASSIVE', #changed == 0,
        reads .. ' left host actions, requests, queue, mirror, pending, native and assignment facts '
            .. (#changed == 0 and 'unchanged' or ('changed: ' .. table.concat(changed, '; '))))
end

-- One boundary. `key`: the Wishlist expected as the stored first-run
-- assignment and the target (nil: none yet). `identity`: the assignmentId it
-- must still carry (nil: not compared). Returns the stored assignmentId.
local function H20Facts(W, label, active, key, identity)
    local H, n = W.H, W.step
    -- Raw synthetic host and stored state first, and the passivity snapshot.
    local before = H20Snap(W)
    local rawActive = H.perks.serverActiveSlot
    local rawDisabled = {}
    for i = 1, #GATED do rawDisabled[#rawDisabled + 1] = TOME[i] .. '=' .. tostring(H.disabled[GATED[i]] == true) end
    local queued = {}
    for _, q in ipairs(W.queue) do queued[#queued + 1] = tostring(q.id) end
    local state = Nexus.Store.State() or {}
    local first = state.firstRunWishlist
    local links = type(state.loadoutWishlists) == 'table' and state.loadoutWishlists or {}
    local linked = {}
    for slot in pairs(links) do linked[#linked + 1] = tostring(slot) end
    table.sort(linked)
    realPrint(string.format('H20RAW %s %s #%d %s: native active=%s disabled{%s} server %s requests(step) %s requests(all) %s queued{%s} pending %s firstRun=%s loadoutLinks{%s} discovery=%s',
        W.group, W.case, n, label, tostring(rawActive), table.concat(rawDisabled, ','), Show(Server(W)),
        H20RequestText(W, n), H20RequestText(W), table.concat(queued, ','), PendingText(), H20FirstText(first),
        table.concat(linked, ','), tostring(H.perks.discoveredEchoes ~= nil)))
    -- Derived adapter views afterwards.
    local slots = W.A.Slots() or {}
    local selected, kept = W.A.SelectedSavedBuild()
    local a = W.A.AssignedWishlist() or {}
    local assignedText = AssignedText(W)
    realPrint(string.format('H20VIEW %s %s #%d %s: Slots().activeSlot=%s SelectedSavedBuild=%s,%s assigned %s identity=%s note=%s',
        W.group, W.case, n, label, tostring(slots.activeSlot), tostring(selected), tostring(kept),
        assignedText, tostring(a.identity), tostring(a.note)))
    H20Passive(W, label, before, 'Slots, SelectedSavedBuild, AssignedWishlist and AssignedText')
    record(W.group, W.case, n, label, 'H20-NATIVE-SLOT', rawActive == active and tonumber(slots.activeSlot) == active,
        'raw ' .. tostring(rawActive) .. ', adapter ' .. tostring(slots.activeSlot) .. ', want ' .. tostring(active))
    record(W.group, W.case, n, label, 'H20-SELECTED', selected == nil and kept == false,
        'SelectedSavedBuild ' .. tostring(selected) .. ',' .. tostring(kept) .. '; want nil,false (no Saved Build kept)')
    record(W.group, W.case, n, label, 'H20-NO-LOADOUT-LINK', #linked == 0,
        'stored Saved Build associations {' .. table.concat(linked, ',') .. '}; want none')
    if key == nil then
        record(W.group, W.case, n, label, 'H20-FIRST-RUN', first == nil and a.state == 'unassigned',
            'stored ' .. H20FirstText(first) .. ', assigned ' .. tostring(a.state) .. '; want none, unassigned')
        return nil
    end
    local w = WISHLISTS[key]
    local storedOk = type(first) == 'table' and tonumber(first.slot) == w.slot and first.name == w.name
        and first.assignmentId ~= nil and (identity == nil or first.assignmentId == identity)
    record(W.group, W.case, n, label, 'H20-FIRST-RUN', storedOk,
        'stored ' .. H20FirstText(first) .. '; want ' .. w.slot .. '/' .. w.name
            .. (identity and ('/' .. tostring(identity)) or ''))
    local id = type(first) == 'table' and first.assignmentId or nil
    record(W.group, W.case, n, label, 'H20-TARGET', a.state == 'ready' and a.name == w.name
            and id ~= nil and a.identity == id,
        'assigned ' .. assignedText .. ' identity ' .. tostring(a.identity) .. '; want ready/' .. w.name
            .. ' identity ' .. tostring(id))
    return id
end

-- The tome-automation hold the observer states (read-only).
local function H20HeldReason(W, label, wantUnknown)
    local before = H20Snap(W)
    local raw = W.H.perks.discoveredEchoes == nil and W.H.discovered == nil
    local obs = W.A.TomeStateObservation() or {}
    local reasons = table.concat(obs.reasons or {}, '; ')
    local synced = W.A.DiscoverySynced()
    H20Passive(W, label, before, 'TomeStateObservation and DiscoverySynced')
    local held = reasons:find('discovery mirror is unsynced', 1, true) ~= nil
    record(W.group, W.case, W.step, label, 'H20-HELD-REASON',
        (wantUnknown and raw and synced == false and held)
            or (not wantUnknown and not raw and synced == true and not held),
        'raw discovery unknown=' .. tostring(raw) .. ' DiscoverySynced=' .. tostring(synced)
            .. ' reasons [' .. reasons .. ']; server ' .. Show(Server(W)))
end

-- Whole-case guard: the only host mutation calls are the recorded accepted
-- tome toggles, each with a direction. No upload, Save, Activate, lock,
-- unlock, Select (take), banish, freeze or reroll; the OrbService has no
-- ConfirmSpend, so no Orb can be spent here.
local function H20Guard(W, key)
    W.step = W.step + 1
    local other, toggles, undirected = {}, 0, 0
    for _, action in ipairs(W.H.actions) do
        if action[1] == 'toggle' then toggles = toggles + 1
        else other[#other + 1] = tostring(action[1]) end
    end
    for _, r in ipairs(W.requests) do if r.dir == nil then undirected = undirected + 1 end end
    local spend = rawget(ProjectEbonhold.OrbService, 'ConfirmSpend')
    record(W.group, W.case, W.step, 'whole case', 'H20-NO-OTHER-MUTATION',
        #other == 0 and toggles == #W.requests and undirected == 0 and spend == nil
            and Nexus == W.h20Nexus and Nexus.GameAdapter == W.h20Adapter,
        'other host actions {' .. table.concat(other, ',') .. '}; toggles ' .. toggles .. ' = accepted '
            .. #W.requests .. ' (' .. H20RequestText(W) .. '); undirected ' .. undirected
            .. '; Orb spend member ' .. tostring(spend) .. '; same runtime ' .. tostring(Nexus == W.h20Nexus))
    -- Settled after the final reads: nothing undelivered or pending, the
    -- case's final tome set, and nothing sent after the last guarded read.
    local want = Vector(WISHLISTS[key].tomes)
    local server = Server(W)
    record(W.group, W.case, W.step, 'whole case', 'H20-CASE-SETTLED',
        #W.queue == 0 and next(Pending()) == nil and Same(server, want)
            and #W.requests == W.h20LastRequests and #W.H.actions == W.h20LastActions,
        'undelivered replies ' .. #W.queue .. '; pending ' .. PendingText() .. '; server ' .. Show(server)
            .. '; want ' .. Show(want) .. '; requests ' .. #W.requests .. ' (at the last guarded read '
            .. tostring(W.h20LastRequests) .. '); host actions ' .. #W.H.actions .. ' (at the last guarded read '
            .. tostring(W.h20LastActions) .. ')')
end

local function H20FirstRunNative(W)
    H20Instrument(W)
    Enter(W)
    H20Facts(W, 'fresh first-run world', 0, nil)
    Step(W, 'Journal selection A', 'A', WISHLISTS.A.tomes)
    local idA = H20Facts(W, 'Journal selection A', 0, 'A')
    Step(W, 'native active A101', H20Publish(WISHLISTS.A.slot), nil)
    H20Facts(W, 'native active A101', WISHLISTS.A.slot, 'A', idA)
    Step(W, 'native active B102', H20Publish(WISHLISTS.B.slot), nil)
    H20Facts(W, 'native active B102', WISHLISTS.B.slot, 'A', idA)
    Step(W, 'native active 0', H20Publish(0), nil)
    H20Facts(W, 'native active 0', 0, 'A', idA)
    Step(W, 'native active B102 again', H20Publish(WISHLISTS.B.slot), nil)
    H20Facts(W, 'native active B102 again', WISHLISTS.B.slot, 'A', idA)
    Step(W, 'Journal selection C while B is natively active', 'C', WISHLISTS.C.tomes)
    local idC = H20Facts(W, 'Journal selection C while B is natively active', WISHLISTS.B.slot, 'C')
    record(W.group, W.case, W.step, 'Journal selection C', 'H20-NEW-ASSIGNMENT', idC ~= nil and idC ~= idA,
        'assignment ' .. tostring(idA) .. ' -> ' .. tostring(idC))
    Step(W, 'native active 0 after C', H20Publish(0), nil)
    H20Facts(W, 'native active 0 after C', 0, 'C', idC)
    Idle(W, 'idle after the native sequence', IDLE_SECONDS)
    H20Facts(W, 'idle after the native sequence', 0, 'C', idC)
    H20Guard(W, 'C')
end

local function H20Guarded(W)
    H20Instrument(W)
    Enter(W)
    H20Facts(W, 'fresh first-run world', 0, nil)
    Step(W, 'Journal selection A', 'A', nil)
    local idA = H20Facts(W, 'Journal selection A', 0, 'A')
    Step(W, 'native active A101', H20Publish(WISHLISTS.A.slot), nil)
    H20Facts(W, 'native active A101', WISHLISTS.A.slot, 'A', idA)
    Step(W, 'native active B102', H20Publish(WISHLISTS.B.slot), nil)
    H20Facts(W, 'native active B102', WISHLISTS.B.slot, 'A', idA)
    Step(W, 'observer and assignment reads', function(W)
        local before = H20Snap(W)
        Journal()
        local a = W.A.AssignedWishlist() or {}
        local obs = W.A.TomeStateObservation() or {}
        W.A.DisabledLevers(); W.A.SelectedSavedBuild(); Nexus.RecomputeStats()
        H20Passive(W, 'observer and assignment reads', before,
            'Journal refresh, AssignedWishlist, TomeStateObservation, DisabledLevers, SelectedSavedBuild and RecomputeStats')
        return a.state == 'ready', 'assigned ' .. tostring(a.state) .. '/' .. tostring(a.name)
            .. ', observer rows ' .. #(obs.rows or {})
    end, nil)
    Step(W, 'Journal selection C while B is natively active', 'C', nil)
    local idC = H20Facts(W, 'Journal selection C while B is natively active', WISHLISTS.B.slot, 'C')
    Step(W, 'native active 0', H20Publish(0), nil)
    H20Facts(W, 'native active 0', 0, 'C', idC)
    Idle(W, 'idle with the permission withheld', IDLE_SECONDS)
    -- Control, as Guarded: grant only what was withheld; the same route then mutates.
    Step(W, 'grant the withheld permission', function(W)
        if W.o.tomePermission == false then SetPermission(true) end
        if not W.o.auto then AutoOn(W) end
        local auto, tome = Nexus.RecomputeStats().autoEnabled, Nexus.Store.Settings().autoDisable
        return auto == true and tome == true, 'Auto=' .. tostring(auto) .. ' tomePermission=' .. tostring(tome)
    end, nil, {observeOnly=true})
    Step(W, 'control: Journal selection B with the permission granted', 'B', WISHLISTS.B.tomes)
    H20Facts(W, 'control: Journal selection B', 0, 'B')
    H20Guard(W, 'B')
end

local function H20Discovery(W)
    H20Instrument(W)
    Enter(W)
    Step(W, 'Journal selection A', 'A', WISHLISTS.A.tomes)
    local idA = H20Facts(W, 'Journal selection A', 0, 'A')
    Step(W, 'native active B102', H20Publish(WISHLISTS.B.slot), nil)
    H20Facts(W, 'native active B102', WISHLISTS.B.slot, 'A', idA)
    Step(W, 'discovery answer and mirror unknown', function(W)
        W.h20Discovered = W.H.discovered
        W.H.discovered = nil; W.H.perks.discoveredEchoes = nil; W.H.Notify()
        return W.H.service.GetDiscoveredEchoes() == nil, 'synthetic GetDiscoveredEchoes and Perks.discoveredEchoes now nil'
    end, nil)
    H20Facts(W, 'discovery unknown', WISHLISTS.B.slot, 'A', idA)
    H20HeldReason(W, 'discovery unknown', true)
    Step(W, 'Journal selection C while discovery is unknown', 'C', nil)
    local idC = H20Facts(W, 'Journal selection C while discovery is unknown', WISHLISTS.B.slot, 'C')
    H20HeldReason(W, 'Journal selection C while discovery is unknown', true)
    Step(W, 'native active 0 while discovery is unknown', H20Publish(0), nil)
    H20Facts(W, 'native active 0 while discovery is unknown', 0, 'C', idC)
    Idle(W, 'idle while discovery is unknown', IDLE_SECONDS)
    H20HeldReason(W, 'idle while discovery is unknown', true)
    Step(W, 'known discovery answer restored with its notification', function(W)
        W.H.discovered = W.h20Discovered; W.H.perks.discoveredEchoes = W.H.discovered; W.H.Notify()
        return Nexus == W.h20Nexus, 'same runtime ' .. tostring(Nexus == W.h20Nexus)
    end, WISHLISTS.C.tomes)
    H20Facts(W, 'discovery restored', 0, 'C', idC)
    H20HeldReason(W, 'discovery restored', false)
    H20Guard(W, 'C')
end

local function H20Held(W)
    H20Instrument(W)
    Enter(W)
    Step(W, 'Journal selection A', 'A', WISHLISTS.A.tomes)
    local idA = H20Facts(W, 'Journal selection A', 0, 'A')
    Step(W, 'native active A101', H20Publish(WISHLISTS.A.slot), nil)
    H20Facts(W, 'native active A101', WISHLISTS.A.slot, 'A', idA)
    -- One step: Journal C with every reply held across native 102 and 0.
    W.step = W.step + 1
    local n, label = W.step, 'Journal selection C, replies held across native 102 and 0'
    local before, want = Server(W), Vector(WISHLISTS.C.tomes)
    W.hold = true
    record(W.group, W.case, n, label, 'PICK', Pick(W, 'C'))
    Run(W, 1)
    H20Publish(WISHLISTS.B.slot)(W); Run(W, 1)
    H20Publish(0)(W); Run(W, 1)
    local held, pending, count, unmatched, stepped = Server(W), Pending(), {}, {}, 0
    for _, r in ipairs(W.requests) do
        if r.step == n then
            stepped = stepped + 1
            local i = INDEX_OF_ECHO[r.id]
            count[r.id] = (count[r.id] or 0) + 1
            local entry = i and pending[LEVER[i]]
            if not (type(entry) == 'table' and entry.want == (r.dir == 'disable')) then
                unmatched[#unmatched + 1] = (i and TOME[i] or tostring(r.id)) .. ':' .. tostring(r.dir)
            end
        end
    end
    local duplicate = {}
    for id, c in pairs(count) do if c > 1 then duplicate[#duplicate + 1] = tostring(id) .. 'x' .. c end end
    record(W.group, W.case, n, label, 'H20-HELD-NOT-CHANGED', Same(held, before),
        'server mirror while held ' .. Show(held) .. '; before ' .. Show(before))
    record(W.group, W.case, n, label, 'H20-HELD-QUEUED', stepped > 0 and #W.queue == stepped,
        'accepted while held ' .. H20RequestText(W, n) .. '; undelivered replies ' .. #W.queue)
    record(W.group, W.case, n, label, 'H20-HELD-PENDING', stepped > 0 and #unmatched == 0,
        'pending ' .. PendingText() .. (#unmatched > 0 and ('; no matching pending entry for '
            .. table.concat(unmatched, ',')) or ''))
    record(W.group, W.case, n, label, 'H20-HELD-NO-DUPLICATE', #duplicate == 0,
        'same-toggle requests while pending ' .. (#duplicate > 0 and table.concat(duplicate, ',') or 'none'))
    local idC = H20Facts(W, 'held, before release', 0, 'C')
    W.hold = false
    local waited = Settle(W, want)
    local after = Server(W)
    local exact, sent, wrong = Sends(W, n, before, want)
    record(W.group, W.case, n, label, 'TOMES', Same(after, want), 'server ' .. Show(after) .. '; want ' .. Show(want))
    record(W.group, W.case, n, label, 'REQUESTS', exact,
        'accepted requests ' .. sent .. ' (' .. H20RequestText(W, n) .. ')' .. (wrong ~= '' and ('; ' .. wrong) or ''))
    record(W.group, W.case, n, label, 'CONFIRMED', Quiet(W),
        'pending ' .. PendingText() .. '; undelivered replies ' .. #W.queue .. '; settled after ' .. string.format('%.2f', waited) .. 's')
    H20Facts(W, 'released and settled', 0, 'C', idC)
    Step(W, 'native active B102 after release', H20Publish(WISHLISTS.B.slot), nil)
    H20Facts(W, 'native active B102 after release', WISHLISTS.B.slot, 'C', idC)
    H20Guard(W, 'C')
end

local H20_PLAN = {}
local function H20Case(group, case, o, body)
    H20_PLAN[#H20_PLAN + 1] = group .. ' ' .. case
    Case(group, case, o, body)
end
for _, entry in ipairs({'reset', 'login1'}) do
    H20Case('H20-FIRST', 'first_run/' .. entry,
        {destination='first_run', entry=entry, auto=true, tomePermission=true}, H20FirstRunNative)
end
for _, g in ipairs({{false, true}, {true, false}, {false, false}}) do
    H20Case('H20-GUARD', 'first_run/auto-' .. (g[1] and 'on' or 'off') .. '/tome-' .. (g[2] and 'on' or 'off'),
        {destination='first_run', entry='reset', auto=g[1], tomePermission=g[2]}, H20Guarded)
end
H20Case('H20-DISC', 'first_run/reset',
    {destination='first_run', entry='reset', auto=true, tomePermission=true}, H20Discovery)
H20Case('H20-HELD', 'first_run/reset',
    {destination='first_run', entry='reset', auto=true, tomePermission=true}, H20Held)

-- H20 aggregation over only the records added above.
local h20Seen, h20Missed, h20Total = {}, {}, 0
for i = h20First, #results do
    local r = results[i]
    local key = r.group .. ' ' .. r.case
    local c = h20Seen[key] or {ok=0, miss=0, guard=false, writes=false}
    h20Seen[key] = c
    h20Total = h20Total + 1
    if r.check == 'H20-NO-OTHER-MUTATION' then c.guard = true end
    if r.check == 'NO-BUILD-WRITES' then c.writes = true end
    if r.ok then c.ok = c.ok + 1
    else
        c.miss = c.miss + 1
        h20Missed[#h20Missed + 1] = key .. ' #' .. tostring(r.step) .. ' ' .. r.check .. ' (' .. r.label .. ')'
    end
end
for _, key in ipairs(H20_PLAN) do
    local c = h20Seen[key]
    if not (c and c.guard and c.writes) then
        h20Missed[#h20Missed + 1] = key .. ' did not reach its whole-case guards'
    end
    realPrint('H20 SUMMARY ' .. key .. ' ok=' .. (c and c.ok or 0) .. ' miss=' .. (c and c.miss or 0))
end
if #h20Missed > 0 or h20Total == 0 then
    error('FAIL native_wishlist_tome_sequence H20: ' .. #h20Missed .. ' expectation(s) not met of '
        .. h20Total .. ':\n' .. table.concat(h20Missed, '\n'), 0)
end
realPrint('PASS native_wishlist_tome_sequence H20: first-run native Wishlist activation (101, 102, 0) '
    .. 'keeps the stored first-run assignment and target, selects no Saved Build and sends no tome '
    .. 'request; only Journal choices move the target with one confirmed request per changed tome; '
    .. 'Auto OFF / tome permission OFF send none; unknown discovery holds and a restored answer settles; '
    .. 'held replies stay pending without duplicates until released; every boundary read is passive '
    .. 'and every case ends settled; checks=' .. h20Total
    .. ' (prior ' .. (h20First - 1) .. ')')
