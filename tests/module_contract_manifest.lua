-- Source-backed inventory for modular-refactor characterization. This file is
-- test data only; it is not loaded by Nexus.toc.

local function Symbols(namespace, names)
    local out = {}
    for _, name in ipairs(names) do out[#out + 1] = namespace .. "." .. name end
    return out
end

local function Append(target, values)
    for _, value in ipairs(values) do target[#target + 1] = value end
    return target
end

local syncSymbols = Symbols("Sync", {
    "GetPeerInfo", "IsKnownPeer", "WorkState", "ResponseStats", "GetShareStatus",
    "GetDeleteStatus", "OnWorldEntry",
    "GetCompatibilityHashes", "GetCanonicalBuildHashes", "GetLegacyBuildHash",
    "HashCacheStats", "EnsureChannel", "ChannelName", "ChannelIndex",
    "IsConnected", "Stats", "IsReceiving", "ReceiveTimeLeft",
    "LastSyncNewCount", "EventLog", "ClearLog", "LogRaw", "RawLog",
    "LogStats", "LogEvent", "NoteTransportNotice", "RequestDataViewRefresh",
    "RequestLoadout", "RequestFullLoadoutSync", "BroadcastBuild",
    "BroadcastMine", "BroadcastBuildSummary", "BroadcastDpsRecord", "BroadcastDps", "BroadcastDelete",
    "HandleIncoming", "RequestSync", "GetLeaderboardSyncStatus",
    "TombstoneCount", "OnUpdate", "HandleStatusRequest", "FlushStatusReply",
    "SendStatusTo", "Init",
})
Append(syncSymbols, Symbols("Responder", {
    "SupportsRequestContext", "RequestContext", "ContextSuffix",
    "ContextRequestId", "NoteContextOutcome",
    "BulkFree", "Backpressured", "CanAdmit", "PrepareSummary",
    "ChunkBuildMessages", "ResolveBuild", "PrepareBuild", "AdmitBuild",
    "BuildCandidateSnapshot", "SnapshotCurrent", "AdvanceCandidateSnapshot",
    "PrepareCandidate", "AdmitCandidate", "SendNextBuild",
    "ValidatePreparedDps", "PrepareResponseEntry", "ResetResponseEntry",
    "NextReadyBucket", "SelectFairUnit", "ProcessLoadoutResponse",
}))

return {
    baseline = "5cbe8ac53b3a06398e4241d6ee1d048aa693c246",
    savedVariables = "## SavedVariables: NexusDB WishlistRealizerDB",
    tocTargetOrder = {
        "core\\CandidateEvidence.lua",
        "core\\Store.lua", "core\\WishlistModel.lua",
        "core\\WishlistController.lua",
        "core\\SyncProtocol.lua", "core\\SyncTransport.lua",
        "core\\SyncCompatibility.lua", "core\\SyncReconciler.lua",
        "core\\SyncInbound.lua", "core\\SyncDiagnostics.lua",
        "core\\SyncSession.lua", "core\\Sync.lua",
        "core\\CommunityProjection.lua", "core\\CommunityController.lua",
        "core\\GameAdapter.lua",
        "ui\\LayoutMetrics.lua",
        "ui\\WishlistRenderer.lua", "ui\\WishlistEditor.lua",
        "ui\\CommunityRenderer.lua",
        "ui\\CommunityBuilds.lua",
        "core\\AutomationRuntime.lua",
        "core\\MainLifecycle.lua",
        "core\\MainCommands.lua", "core\\MainViewModel.lua",
        "core\\MainDiagnostics.lua", "core\\Main.lua",
    },
    modules = {
        {
            id="CandidateEvidence", path="core/CandidateEvidence.lua",
            namespaces={Evidence="pure-evidence"},
            symbols=Symbols("Evidence", {
                "Build", "Validate", "ResolveLocked", "CurrentKind",
                "NormalizeLockedEchoes", "RealDpsPairs", "DpsSummary",
                "DpsPairIdentity", "DpsRowBefore",
            }),
            assignedMembers={}, callbackSites=0, callbackGroups={},
        },
        {
            id="WishlistModel", path="core/WishlistModel.lua",
            namespaces={Factory="internal-model"},
            symbols=Symbols("Factory", {"New"}),
            assignedMembers={}, callbackSites=0, callbackGroups={},
        },
        {
            id="WishlistController", path="core/WishlistController.lua",
            namespaces={Controller="internal-controller"},
            symbols=Symbols("Controller", {"New"}),
            assignedMembers={}, callbackSites=0, callbackGroups={},
        },
        {
            id="Sync", path="core/Sync.lua",
            namespaces={Sync="facade",Responder="internal-responder"},
            symbols=syncSymbols,
            assignedMembers={
                {symbol="Sync.LogEvent",kind="callable-alias",anchor="Sync.LogEvent = LogEvent"},
                {symbol="Sync.BroadcastBuildSummary",kind="callable-alias",anchor="Sync.BroadcastBuildSummary = BroadcastSummary"},
                {symbol="Sync._pendingDeleteScheduled",kind="mutable-state"},
            },
            callbackSites=0, callbackGroups={},
        },
        {
            id="Main", path="core/Main.lua", namespaces={Nexus="facade"},
            symbols=Symbols("Nexus", {
                "RecomputeStats", "RefreshHudView", "HudSnapshotStats",
                "NewAIExportCoroutine", "GetDiagnosticPageText", "RefreshPanel",
                "RequestRecompute", "RetryAutoLock", "AppendAudit",
            }),
            assignedMembers={
                {symbol="Nexus.VERSION",kind="constant"},
                {symbol="Nexus.lastError",kind="mutable-state"},
                {symbol="Nexus.RequestRecompute",kind="callable-alias",anchor="Nexus.RequestRecompute = RequestRecompute"},
                {symbol="Nexus.RetryAutoLock",kind="callable-alias",anchor="Nexus.RetryAutoLock = RetryAutoLock"},
                {symbol="Nexus.AppendAudit",kind="callable-alias",anchor="Nexus.AppendAudit = AppendAudit"},
            },
            callbackSites=9,
            callbackGroups={
                {id="lifecycle-events",count=7,anchor="EH:RegisterEvent(\"ADDON_LOADED\")"},
                {id="event-router",count=1,anchor="EH:SetScript(\"OnEvent\""},
                {id="direct-update-loop",count=1,anchor="EH:SetScript(\"OnUpdate\""},
            },
        },
        {
            id="Store", path="core/Store.lua", namespaces={Store="facade"},
            symbols=Symbols("Store", {
                "Init", "CurrentOwnerKey", "RegisterCurrentCharacter",
                "IsAccountOwnerKey", "IsAccountBuild", "AccountCharacters",
                "SettingsVersion", "Settings", "State",
            }),
            assignedMembers={},
            callbackSites=0, callbackGroups={},
        },
        {
            id="GameAdapter", path="core/GameAdapter.lua", namespaces={A="facade"},
            symbols=Symbols("A", {
                "Catalog", "CheckCatalogSource", "CatalogStatus", "Ready", "Board",
                "Charges", "DumpLockedPerksRaw", "LockedOwned",
                "MaxPermanentEchoes", "Owned", "RunBoundaryReset",
                "RequestGranted", "WishlistKey", "WishlistEvidenceState",
                "GetWishlistCandidates",
                "GetFirstRunWishlist", "SetFirstRunWishlist",
                "SetFirstRunWishlistIdentity", "ClearFirstRunWishlist",
                "GetLoadoutWishlist", "GetLoadoutWishlistState",
                "GetLoadoutWishlistSlot",
                "SetLoadoutWishlistIdentity", "SetFirstLoadoutWishlistIdentity",
                "SetLoadoutWishlist", "UpdateWishlistAssociationAfterSave",
                "ClearLoadoutWishlist", "Wishlist", "WishlistNote",
                "GetLoadoutCandidates", "Slots", "RequestSlots",
                "DiscoverySynced", "LeverHasKnownMember", "UnknownTomesForEchoes",
                "DisabledLevers", "ToggleLever", "InFlight", "Take", "Banish",
                "Reroll", "Freeze", "Activate", "Save", "UploadWishlist",
                "LockPerk", "UnlockPerk", "SetSoloPicker", "AutoAcceptOn",
                "RestoreAutoAccept", "RivalDetected", "Level", "Horizon",
                "ExternalActionSeen", "OwnedSyncInfo", "UnlockedSlots",
                "TomeMutationPaused", "TomeMutationResumeAt",
                "EchoReconcileStats", "AutomationSignature", "ConsumeDirty",
                "RecordLevelBurstPump", "LevelBurstStats",
                "PresentationRevisions",
                "ConsumeUserAction", "Init",
                "OnEvent", "Poll",
            }),
            assignedMembers={
                {symbol="A.DIAGNOSTIC_PASSIVE",kind="constant"},
                {symbol="A._wishlistNote",kind="mutable-state"},
                {symbol="A._pendingWishlistSlot",kind="mutable-state"},
                {symbol="A._pendingWishlistAt",kind="mutable-state"},
                {symbol="A._lastUserAction",kind="mutable-state"},
            },
            callbackSites=7,
            callbackGroups={
                {id="perk-ui-dirty-hooks",count=2,anchor="hooksecurefunc(pe.PerkUI"},
                {id="journal-dirty-hook",count=1,anchor="hooksecurefunc(pe.EchoJournal"},
                {id="service-mutation-hooks",count=4,anchor="hooksecurefunc(svc, \"SelectPerk\""},
            },
        },
        {
            id="CommunityRenderer", path="ui/CommunityRenderer.lua",
            namespaces={Renderer="internal-factory"},
            symbols=Symbols("Renderer", {"New"}),
            assignedMembers={},
            callbackSites=75,
            callbackGroups={
                {id="detail-link-lock-actions",count=16,anchor="p.closeBtn:SetScript"},
                {id="pooled-card-bindings",count=6,anchor="card.addBtn:SetScript"},
                {id="main-frame-lifecycle",count=3,anchor="frame:SetScript(\"OnUpdate\""},
                {id="main-controls-virtual-list",count=35,anchor="dropdownShield:SetScript"},
                {id="post-edit-popups",count=15,anchor="postGoBtn:SetScript"},
            },
        },
        {
            id="CommunityBuilds", path="ui/CommunityBuilds.lua", namespaces={M="facade"},
            symbols=Symbols("M", {
                "IsOwnBuild", "EnsureDpsBuildForEchoes", "PostCurrentWishlist",
                "ShareStatus", "CanRetryShare", "RetryShare",
                "PublishImportedBuild", "EditBuild", "UpdateFromWishlist",
                "DeleteBuild", "_PumpPendingLockIn", "IsLockInPending",
                "LockInSelected", "GetSelectedBuildForPanel",
                "GetSelectedBuildForPanelKey", "VirtualStats",
                "DiagnosticSnapshot",
                "MarkDataDirty", "ScrollTo", "Refresh", "ShowPostBuild",
                "TogglePostPopup", "ToggleEditPopup", "Init", "Select",
                "SetViewMode", "GetViewMode", "Show", "ShowBuild", "Hide",
                "IsShown", "Toggle",
            }),
            assignedMembers={},
            callbackSites=0,
            callbackGroups={},
        },
        {
            id="WishlistRenderer", path="ui/WishlistRenderer.lua",
            namespaces={Renderer="internal-factory"},
            symbols=Symbols("Renderer", {"New"}),
            assignedMembers={},
            callbackSites=71,
            callbackGroups={
                {id="dynamic-row-reset-bindings",count=8,anchor="row:SetScript(\"OnMouseDown\", nil)"},
                {id="main-frame-lifecycle",count=5,anchor="frame:SetScript(\"OnShow\""},
                {id="navigation-wishlist-controls",count=30,anchor="wishlistNameBox:SetScript"},
                {id="list-edit-controls",count=16,anchor="leftArea:SetScript"},
                {id="candidate-association-controls",count=2,anchor="candidateButtons[1]:SetScript"},
                {id="display-popup-controls",count=10,anchor="dragBar:SetScript"},
            },
        },
        {
            id="WishlistEditor", path="ui/WishlistEditor.lua", namespaces={M="facade"},
            symbols=Symbols("M", {
                "_PumpApplyRetry", "IsApplyPending", "ImportEBH1String", "Refresh",
                "ToggleDisplayPopup", "Init", "DebugPendingCount", "DebugDraftState",
                "OpenForCandidate", "OpenForWishlist", "NewWishlist", "Show", "Toggle",
            }),
            assignedMembers={
                {symbol="M._fulfilledDraftTargets",kind="mutable-state"},
            },
            callbackSites=0,
            callbackGroups={},
        },
    },
}
