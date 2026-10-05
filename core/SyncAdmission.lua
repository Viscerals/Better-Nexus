-- Nexus: core/SyncAdmission.lua
-- Deferred inbound admission owner for Sync: the validated inbound items the
-- catalog refused without a ticket because another transaction owned
-- admission, retained bounded and session-only, and submitted as one batch
-- when ordinary admission is available again.
--
-- Moved verbatim from core/Sync.lua (the Responder.Admission functions) so
-- that the Sync chunk, at the Lua 5.1 limit of 200 local variables, carries
-- one owner less. Sync creates the state table (order/byKey/count/inFlight
-- and the bounds) and keeps the read-only Sync.AdmissionSnapshot view; this
-- factory installs the behaviour onto that table. Every dependency is given
-- by Sync at load, as the other SyncInternals factories receive theirs;
-- the two that Sync binds later (the session owner and the catalog mutation
-- identity) are read through accessors at call time.

Nexus = Nexus or {}
if type(Nexus.SyncInternals) ~= "table" then Nexus.SyncInternals = {} end

local Admission = {}
Nexus.SyncInternals.Admission = Admission

-- An item whose own submission raises is retried once and then refused.
local ADMISSION_ERROR_ATTEMPTS = 2

-- options:
--   responder        Sync's Responder table; Responder.Admission is the state
--                    table this factory installs onto, and
--                    Responder.NoteContextOutcome records context outcomes
--   sync             the Sync module (IsConnected)
--   stats            Sync's live counters table (never replaced)
--   now              clock
--   catalog          catalog accessor (Nexus.BuildCatalog or nil)
--   currentOwnerKey  local verified owner key or nil
--   mutationIdentity accessor for Sync's catalog mutation identity
--   transport        the transport owner (ThrottleRemaining, OutboundProgress)
--   reconciler       the reconciler owner (Counts)
--   session          accessor for the session owner (bound after this call)
--   bindCatalogCompletion(ticket, callback) -> bound
--   logEvent(kind, format, ...), peerObserve(event, fields)
--   pendingTtl, pendingMaxAge, responseElectionDelay  Sync's constants
function Admission.New(options)
    options = options or {}
    local Responder = assert(options.responder, "SyncAdmission requires responder")
    assert(type(Responder.Admission) == "table", "SyncAdmission requires the Responder.Admission state table")
    local Sync = assert(options.sync, "SyncAdmission requires sync")
    local stats = assert(options.stats, "SyncAdmission requires stats")
    local Now = assert(options.now, "SyncAdmission requires now")
    local Catalog = assert(options.catalog, "SyncAdmission requires catalog")
    local CurrentOwnerKey = assert(options.currentOwnerKey, "SyncAdmission requires currentOwnerKey")
    local MutationIdentity = assert(options.mutationIdentity, "SyncAdmission requires mutationIdentity")
    local Transport = assert(options.transport, "SyncAdmission requires transport")
    local Reconciler = assert(options.reconciler, "SyncAdmission requires reconciler")
    local CurrentSession = assert(options.session, "SyncAdmission requires session")
    local BindCatalogCompletion = assert(options.bindCatalogCompletion, "SyncAdmission requires bindCatalogCompletion")
    local LogEvent = assert(options.logEvent, "SyncAdmission requires logEvent")
    local PeerObserve = assert(options.peerObserve, "SyncAdmission requires peerObserve")
    local PENDING_TTL = assert(tonumber(options.pendingTtl), "SyncAdmission requires pendingTtl")
    local PENDING_MAX_AGE = assert(tonumber(options.pendingMaxAge), "SyncAdmission requires pendingMaxAge")
    local RESPONSE_ELECTION_DELAY = assert(tonumber(options.responseElectionDelay),
        "SyncAdmission requires responseElectionDelay")

    -- Catalog.Put answers `false` plus a root-pending reason, and no ticket, when
    -- another transaction owns admission. Nothing was accepted, so that is not a
    -- pending operation. It is also not a verdict on the item. The validated item
    -- is retained here, bounded and session-only, and is submitted once when
    -- ordinary admission is available again. The complete inbound handler runs
    -- again at that point, so owner, revision, pending-replacement and tombstone
    -- state are rechecked against the then-current catalog. Only the ticket that
    -- submission returns may report success; expiry, overflow, reset and a
    -- changed catalog scope settle as the same storage refusal the item would
    -- have received before.
    --
    -- Each item has one fixed deadline, PENDING_MAX_AGE from its own arrival.
    -- Other catalog work never extends it. An item whose turn does not come in
    -- that time fails as a storage refusal, even while the catalog keeps working.
    function Responder.Admission.Busy(stored, why)
        return stored == false and (why == "ROOT_MUTATION_PENDING"
            or why == "ROOT_ADMISSION_PENDING")
    end

    function Responder.Admission.Remove(entry)
        if Responder.Admission.byKey[entry.key] ~= entry then return false end
        Responder.Admission.byKey[entry.key] = nil
        for index, candidate in ipairs(Responder.Admission.order) do
            if candidate == entry then
                table.remove(Responder.Admission.order, index)
                break
            end
        end
        Responder.Admission.count = #Responder.Admission.order
        return true
    end

    function Responder.Admission.Fail(entry, counter, detail)
        if not Responder.Admission.Remove(entry) then return false end
        if counter then
            stats.storageRejected = (stats.storageRejected or 0) + 1
            stats[counter] = (stats[counter] or 0) + 1
        end
        Responder.NoteContextOutcome(entry.context, "rejected", "storage")
        PeerObserve("receiver_commit", {id=entry.id,peer=entry.sender,
            outcome="store_failed",reason=detail})
        LogEvent("RX", "REJECT deferred %s '%s': %s", tostring(entry.kind),
            tostring(entry.id), tostring(detail))
        entry.settle(false, false, "storage")
        return true
    end

    -- The scope an item was validated in: this Sync session, this catalog owner,
    -- its bound database and binding generation, and the local player. An item is
    -- never submitted into any other scope.
    function Responder.Admission.Scope()
        local catalog = Catalog()
        local preparation = catalog
            and type(catalog.ManualPreparationStatus) == "function"
            and catalog.ManualPreparationStatus() or nil
        return {
            identity=MutationIdentity(),catalog=catalog,
            database=catalog and type(catalog.BoundDatabase) == "function"
                and catalog.BoundDatabase() or nil,
            savedVariables=NexusDB,
            binding=preparation and preparation.binding or nil,
            owner=CurrentOwnerKey(),
        }
    end

    function Responder.Admission.SameScope(entry)
        local scope, current = entry.scope, Responder.Admission.Scope()
        for _, key in ipairs({"identity", "catalog", "database", "savedVariables",
            "binding", "owner"}) do
            if scope[key] ~= current[key] then return false end
        end
        return current.catalog ~= nil and current.database ~= nil
    end

    -- Returns "deferred", "duplicate", "rejected" or "overflow". One entry per
    -- kind and ID: an older or equal revision never displaces the retained one,
    -- and a different owner claim cannot take over its place in the queue.
    function Responder.Admission.Defer(fields)
        local key = tostring(fields.kind) .. ":" .. type(fields.id) .. ":"
            .. tostring(fields.id)
        -- Settle cancelled and expired items first. An item retained in an earlier
        -- scope is not a prior claim in this one: it must not make a fresh valid
        -- receipt a duplicate, refuse its owner, or count against the bounds.
        Responder.Admission.Expire()
        local prior = Responder.Admission.byKey[key]
        if prior then
            if prior.owner ~= fields.owner then
                Responder.NoteContextOutcome(fields.context, "rejected", "ownership")
                return "rejected"
            end
            local promotes = fields.stamp == prior.stamp
                and fields.direct == true and prior.direct ~= true
                and fields.digest == prior.digest
            -- The owner's answer that states the locked set supersedes a held
            -- answer for the same content without it (never the reverse).
            local enriches = fields.stamp == prior.stamp
                and fields.direct == true and fields.digest == prior.digest
                and fields.rolesKnown == true and prior.rolesKnown ~= true
            if fields.stamp < prior.stamp then
                Responder.NoteContextOutcome(fields.context, "duplicate", "stale")
                return "duplicate"
            end
            if fields.stamp == prior.stamp and not promotes and not enriches then
                local same = fields.digest == prior.digest
                Responder.NoteContextOutcome(fields.context,
                    same and "duplicate" or "rejected",
                    same and "duplicate" or "integrity")
                return same and "duplicate" or "rejected"
            end
            Responder.Admission.Remove(prior)
            stats.admissionSuperseded = (stats.admissionSuperseded or 0) + 1
            Responder.NoteContextOutcome(prior.context, "duplicate", "stale")
            prior.settle(true, false)
        end
        local fromSender = 0
        for _, candidate in ipairs(Responder.Admission.order) do
            if candidate.sender == fields.sender then fromSender = fromSender + 1 end
        end
        for _, member in ipairs(Responder.Admission.inFlight) do
            if member.sender == fields.sender then fromSender = fromSender + 1 end
        end
        local held = Responder.Admission.count + Responder.Admission.inFlightCount
        if held >= Responder.Admission.maxTotal
            or fromSender >= Responder.Admission.maxPerSender then
            stats.admissionOverflow = (stats.admissionOverflow or 0) + 1
            return "overflow"
        end
        local current = Now()
        local entry = {
            key=key,kind=fields.kind,id=fields.id,stamp=fields.stamp,
            owner=fields.owner,direct=fields.direct == true,digest=fields.digest,
            rolesKnown=fields.rolesKnown == true,sender=fields.sender,context=fields.context,run=fields.run,
            settle=fields.settle,enqueuedAt=current,
            expiresAt=current + PENDING_MAX_AGE,
            scope=Responder.Admission.Scope(),
        }
        Responder.Admission.byKey[key] = entry
        Responder.Admission.order[#Responder.Admission.order + 1] = entry
        Responder.Admission.count = #Responder.Admission.order
        stats.admissionDeferred = (stats.admissionDeferred or 0) + 1
        PeerObserve("receiver_commit", {id=fields.id,peer=fields.sender,
            outcome="deferred",reason="catalog admission pending"})
        LogEvent("RX", "DEFER %s '%s': catalog admission pending",
            tostring(fields.kind), tostring(fields.id))
        return "deferred"
    end

    function Responder.Admission.Expire()
        if Responder.Admission.count == 0 then return end
        local current, index = Now(), 1
        while Responder.Admission.order[index] do
            local entry = Responder.Admission.order[index]
            if not Responder.Admission.SameScope(entry) then
                -- A changed player, database or binding cancels the item. It is
                -- never carried into the new scope.
                Responder.Admission.Fail(entry, "admissionCancelled",
                    "catalog scope changed")
            elseif current >= entry.expiresAt then
                Responder.Admission.Fail(entry, "admissionExpired",
                    "catalog admission wait expired")
            else
                index = index + 1
            end
        end
    end

    -- A submission makes the catalog busy, and the lifecycle then withholds every
    -- full Sync turn until that transaction ends. Transport only sends in a full
    -- turn, so a queue that submits in every ready turn leaves outbound traffic,
    -- including the user's explicit Sync Now request, with no turn at all.
    -- Outbound and deferred inbound work therefore alternate, and the outbound
    -- unit is a whole transfer, never a single chunk: a catalog transaction
    -- between two chunks outlasts the chunks' own deadline.
    --  * Sync's paced owners (response election, recovery, send pacing) only
    --    accumulate time in full turns. After the catalog becomes ready they get
    --    one continuous RESPONSE_ELECTION_DELAY window before any submission, or
    --    they would never produce the outbound work that is then owed.
    --  * A started multi-chunk transfer is never interrupted.
    --  * While a response or loadout is pending, admission yields: its election
    --    and bucket delays accumulate only in full turns, and a unit sent for
    --    other work is not its turn. While only valid outbound traffic waits,
    --    one whole unit must be transmitted between two submissions. Outbound
    --    goes first.
    --  * Apart from a started transfer, admission never yields to owed work for
    --    more than PENDING_TTL of continuous ready time, so sustained outbound
    --    work cannot hold deferred inbound work until its deadline.
    -- The catalog stays ready in the meantime, so ordinary send pacing decides
    -- when a transmission happens. Admission yields only to a transmission
    -- that can actually happen: when the channel is absent, a throttle pause is
    -- active, or the wire itself reports a persistent blocker (suspended, combat,
    -- no throttle library), no send is possible and the catalog is not left
    -- idle. Nothing is dropped, reordered or extended: each item keeps its fixed
    -- deadline.
    function Responder.Admission.OutboundOwed()
        if not Sync.IsConnected() or Transport.ThrottleRemaining() > 0 then
            return false
        end
        -- The same owner Transport asks before every dispatch.
        local wire = Nexus.SyncWire
        if not wire or type(wire.Blocked) ~= "function" or wire.Blocked() then
            return false
        end
        local progress = Transport.OutboundProgress()
        if progress.midTransfer then return true end
        local current = Now()
        local readySince = Responder.Admission.readySince or current
        local pending = (tonumber(Reconciler.Counts().total) or 0) > 0
        local owed = progress.waiting > 0 or pending
        -- The yield cap runs from the first turn in which retained items
        -- yielded to owed work within this continuous ready period. Idle ready
        -- time before the work existed does not spend it; a later arrival or a
        -- later request does not restart it. Newly owed work is served first,
        -- as at the first submission: a unit sent for earlier work is not its
        -- turn.
        if not owed then
            Responder.Admission.yieldSince = nil
            Responder.Admission.unitsAtSubmission = nil
        else
            Responder.Admission.yieldSince = math.max(
                Responder.Admission.yieldSince or current, readySince)
        end
        if current - readySince < RESPONSE_ELECTION_DELAY then return true end
        if not owed then return false end
        if current - Responder.Admission.yieldSince >= PENDING_TTL then
            return false
        end
        -- A pending response or loadout has not had its turn because some other
        -- unit was sent: its election and bucket delays accumulate only in full
        -- turns. It is served first, inside the cap above.
        if pending then return true end
        return progress.unitsSent == (Responder.Admission.unitsAtSubmission or -1)
            or Responder.Admission.unitsAtSubmission == nil
    end

    -- A validated inbound item that finds the catalog ready normally takes it at
    -- once. While the user's explicit manual request is still unsent, that write
    -- costs the request its turn: every commit invalidates the hash walk the
    -- request waits for, the lifecycle withholds every full Sync turn until the
    -- catalog and the hash are both ready, and at a large catalog the request
    -- expires unsent behind a chain of direct writes. The lifecycle already gives
    -- a pending Share the next admission turn; this gives the same to a manual
    -- request. The item is not refused, dropped or delayed beyond its own
    -- deadline: it enters this same bounded, scoped owner, keeps its validation,
    -- fixed deadline, scope capture and FIFO place, and is submitted by the pump
    -- after the request's transmission. The hold is bounded by the request's own
    -- fixed lifetime, and it never waits for a transmission the wire cannot make.
    -- A full owner refuses a held item exactly as it refuses one that found the
    -- catalog busy: a counted storage refusal, never a silent drop.
    function Responder.Admission.RequestHold()
        local Session = CurrentSession()
        if not (Session and type(Session.ManualRequestUnsent) == "function"
            and Session.ManualRequestUnsent()) then return false end
        if not Sync.IsConnected() or Transport.ThrottleRemaining() > 0 then
            return false
        end
        local wire = Nexus.SyncWire
        if not wire or type(wire.Blocked) ~= "function" or wire.Blocked() then
            return false
        end
        return true
    end

    -- The same turn is owed to a peer's transaction. A received reconciliation
    -- or loadout request is answered only in a full Sync turn, and it expires
    -- after PENDING_TTL without one; a queued loadout recovery request is sent
    -- only in a full turn. On a busy channel every ready moment of the catalog
    -- was taken by the next valid inbound record, so a responder never reached
    -- a turn and the exact full record was never serialized. While such work is
    -- owed and the wire can send, a valid inbound item is retained in this same
    -- bounded owner instead. Nothing is refused that would not be refused for a
    -- busy catalog, and no lifetime changes. Owed work is a pending response or
    -- loadout, a started transfer, valid queued outbound packets, or a queued
    -- recovery request that has not reached the wire.
    -- Retention is only the entry and has no clock of its own: the pump below
    -- decides when the item is submitted, with its whole-unit alternation and
    -- its PENDING_TTL yield cap. A transaction already in flight when the
    -- request arrives is never cut short; if it outlasts PENDING_TTL the request
    -- still expires.
    function Responder.Admission.Owed()
        local progress = Transport.OutboundProgress()
        if progress.midTransfer or progress.waiting > 0
            or (tonumber(Reconciler.Counts().total) or 0) > 0 then return true end
        -- A queued recovery request reaches the wire only in a full turn.
        local Session = CurrentSession()
        local session = Session and type(Session.WorkSnapshot) == "function"
            and Session.WorkSnapshot() or nil
        return session ~= nil and (tonumber(session.recovery) or 0) > 0
    end

    function Responder.Admission.OwedHold()
        if not Sync.IsConnected() or Transport.ThrottleRemaining() > 0 then
            return false
        end
        local wire = Nexus.SyncWire
        if not wire or type(wire.Blocked) ~= "function" or wire.Blocked() then
            return false
        end
        return Responder.Admission.Owed()
    end

    -- FIFO place. An item that finds the catalog ready while older items are
    -- still retained queues behind them; a direct write would overtake them at
    -- every ready moment and leave them to expire behind newer traffic. A busy
    -- catalog is asked as before and gives its ordinary refusal.
    function Responder.Admission.Behind()
        if Responder.Admission.count == 0 then return false end
        local catalog = Catalog()
        local preparation = catalog
            and type(catalog.ManualPreparationStatus) == "function"
            and catalog.ManualPreparationStatus() or nil
        return preparation ~= nil and preparation.ready == true
    end
    -- Full Sync turns are continuous while the catalog is ready. A gap means the
    -- lifecycle withheld them, so the continuous ready window starts again.
    function Responder.Admission.NoteTurn()
        local current = Now()
        if not Responder.Admission.turnAt or current - Responder.Admission.turnAt > 1 then
            Responder.Admission.readySince = current
        end
        Responder.Admission.turnAt = current
    end

    -- Runs only behind the lifecycle's full catalog readiness gate, after the
    -- transport turn. The passive status read means a still-busy catalog receives
    -- no further Put call.
    function Responder.Admission.Pump()
        if Responder.Admission.count == 0 then
            Responder.Admission.yieldSince = nil
            Responder.Admission.unitsAtSubmission = nil
            return
        end
        Responder.Admission.Expire()
        if Responder.Admission.OutboundOwed() then
            stats.admissionYielded = (stats.admissionYielded or 0) + 1
            return
        end
        local catalog = Catalog()
        local function Ready()
            local preparation = catalog
                and type(catalog.ManualPreparationStatus) == "function"
                and catalog.ManualPreparationStatus() or nil
            return preparation == nil or preparation.ready == true
        end
        if not Ready() then return end
        if Responder.Admission.inFlightCount > 0 then return end
        -- Frozen membership: the items waiting at this moment. An item that
        -- arrives while this batch runs waits for a later batch; it never
        -- enlarges or restarts the candidate.
        local frozen = {}
        for index, entry in ipairs(Responder.Admission.order) do frozen[index] = entry end
        local collected = {}
        Responder.Admission.collector = collected
        local ok = pcall(function()
            for _, entry in ipairs(frozen) do
                -- An item whose own submission took the catalog (a path that
                -- does not join the batch) ends the collection at once.
                if not Ready() then break end
                if Responder.Admission.byKey[entry.key] == entry then
                    -- Rechecked at the point of submission, after Expire above,
                    -- because a rebind can complete between turns.
                    if not Responder.Admission.SameScope(entry) then
                        Responder.Admission.Fail(entry, "admissionCancelled",
                            "catalog scope changed")
                    else
                        -- One item's error is its own terminal outcome. Without
                        -- this, a repeating error would be retained, restored
                        -- and retried for ever, and the valid items behind it
                        -- would expire waiting for a pass that never completes.
                        local ranOk, outcome = pcall(entry.run, entry)
                        if not ranOk then
                            -- One item's error is its own problem. It is reported,
                            -- retried once, and then refused with a counted
                            -- outcome, so it can never become a poison item that
                            -- starves the valid work behind it. Items collected
                            -- before it in this pass are still submitted.
                            LogEvent("RX", "ERROR admission item '%s': %s",
                                tostring(entry.id), tostring(outcome))
                            if Nexus.Errors and Nexus.Errors.Record then
                                pcall(Nexus.Errors.Record, "Sync.Admission",
                                    tostring(outcome))
                            end
                            entry.errorCount = (entry.errorCount or 0) + 1
                            if entry.errorCount >= ADMISSION_ERROR_ATTEMPTS then
                                Responder.Admission.Fail(entry, "admissionError",
                                    "admission failed")
                            end
                            break
                        else
                            if outcome == "busy" then break end
                            Responder.Admission.Remove(entry)
                        end
                    end
                end
            end
        end)
        Responder.Admission.collector = nil
        if #collected == 0 then return end
        if not ok or not Ready() then
            -- Nothing was submitted: the collected members go back to the queue
            -- with their original deadlines and places, never settled here.
            Responder.Admission.Restore(collected)
            return
        end
        Responder.Admission.SubmitBatch(collected)
    end

    -- Put collected members back at the front of the queue, in their original
    -- order and with their own unchanged deadlines. A member whose key was taken
    -- by a newer retained item in the meantime keeps that newer item and settles
    -- as the ordinary busy refusal.
    function Responder.Admission.Restore(collected)
        for index = #collected, 1, -1 do
            local member = collected[index]
            local entry = member.entry
            if type(entry) == "table" and Responder.Admission.byKey[entry.key] == nil then
                Responder.Admission.byKey[entry.key] = entry
                table.insert(Responder.Admission.order, 1, entry)
                Responder.Admission.count = #Responder.Admission.order
                stats.admissionRestored = (stats.admissionRestored or 0) + 1
                -- It was collected, not resolved: its run counted a resolution
                -- that did not happen, so the counter keeps its meaning.
                stats.admissionResolved = math.max(0, (stats.admissionResolved or 0) - 1)
            else
                member.complete(false, "ROOT_MUTATION_PENDING")
            end
        end
    end

    -- One catalog mutation for the whole frozen batch. Each member keeps its own
    -- ticket, storage answer and refusal reason, and is settled exactly once.
    function Responder.Admission.SubmitBatch(collected)
        local catalog = Catalog()
        local requests = {}
        for index, member in ipairs(collected) do
            requests[index] = {record=member.record, options=member.options}
        end
        local stored, storedAs, tickets
        if catalog and type(catalog.PutBatch) == "function" then
            stored, storedAs, tickets = catalog.PutBatch(requests)
        else
            stored, storedAs = false, "batch admission unavailable"
        end
        if not (stored == nil and storedAs == "ROOT_MUTATION_PENDING"
            and type(tickets) == "table") then
            -- The catalog could not start this batch at all. Its members keep
            -- their own deadlines and wait for a later turn; nothing is settled
            -- as a storage failure here.
            Responder.Admission.Restore(collected)
            return
        end
        stats.admissionBatches = (stats.admissionBatches or 0) + 1
        stats.admissionBatchMembers = (stats.admissionBatchMembers or 0) + #collected
        if #collected > (stats.admissionBatchLargest or 0) then
            stats.admissionBatchLargest = #collected
        end
        for index, member in ipairs(collected) do
            local ticket = tickets[index]
            local row = {key=member.key, sender=member.sender, settled=false}
            Responder.Admission.inFlight[#Responder.Admission.inFlight + 1] = row
            Responder.Admission.inFlightCount = #Responder.Admission.inFlight
            local bound = ticket ~= nil and BindCatalogCompletion(ticket,
                function(ok, why)
                    Responder.Admission.FinishInFlight(row)
                    member.complete(ok, why)
                end)
            if not bound then
                Responder.Admission.FinishInFlight(row)
                member.complete(false, "INVALID_MUTATION_TICKET")
            end
        end
        -- One accepted submission per turn; the next batch waits for a whole
        -- transmitted unit while outbound work is owed.
        Responder.Admission.unitsAtSubmission = Transport.OutboundProgress().unitsSent
    end

    function Responder.Admission.FinishInFlight(row)
        if row.settled then return end
        row.settled = true
        for index, candidate in ipairs(Responder.Admission.inFlight) do
            if candidate == row then
                table.remove(Responder.Admission.inFlight, index)
                break
            end
        end
        Responder.Admission.inFlightCount = #Responder.Admission.inFlight
    end

    function Responder.Admission.Reset()
        while Responder.Admission.order[1] do
            Responder.Admission.Fail(Responder.Admission.order[1], nil, "explicit reset")
        end
        Responder.Admission.order, Responder.Admission.byKey, Responder.Admission.count = {}, {}, 0
        Responder.Admission.inFlight, Responder.Admission.inFlightCount = {}, 0
        Responder.Admission.unitsAtSubmission = nil
        Responder.Admission.readySince, Responder.Admission.turnAt = nil, nil
        Responder.Admission.yieldSince = nil
    end

    return Responder.Admission
end
