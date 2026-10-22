-- Review controls for PR #119: visit-latched non-idempotent toggles, fair
-- keep/disable progress, typed progress, and bound Auto-prompt consent.
-- Real TOC/runtime/adapter; synthetic host only. No native client claim.
local S = dofile('tests/prototype/approved_tome_coverage_support.lua')
local K = S.Checker('tome_review_controls')
local function Auto() return Nexus.RecomputeStats().autoEnabled == true end
local function DialogText()
    local info = StaticPopupDialogs and StaticPopupDialogs.NEXUS_LEVEL1_AUTO_TOMES
    return info and tostring(info.text or '') or ''
end
local function EchoFor(A, lever)
    local lv = A.Catalog() and A.Catalog().levers and A.Catalog().levers[lever]
    return lv and lv.members and lv.members[1]
end
local function WrapCalls(H, refuseId)
    local calls, inner = {}, H.service.ToggleTomeEcho
    H.service.ToggleTomeEcho = function(id)
        calls[#calls + 1] = {id = id, at = H.now}
        if refuseId and id == refuseId then return false end
        return inner(id)
    end
    return calls
end
local function Count(calls, id)
    local n = 0
    for i = 1, #calls do if calls[i].id == id then n = n + 1 end end
    return n
end
local function FinishOnboarding(H)
    local f = rawget(_G, 'NexusOverwriteWarning')
    if not (f and f:IsShown()) then SlashCmdList.NEXUS('auto'); f = rawget(_G, 'NexusOverwriteWarning') end
    H.Advance(5.01, .05)
    if f and f:IsShown() and f.yes:IsEnabled() then f.yes:Click() end
    local quick = rawget(_G, 'NexusQuickStart')
    if quick and quick:IsShown() then quick:Hide(); H.Advance(.2, .05) end
    return Nexus.OverwriteWarning.EnsureOnboarding() ~= 'pending' and not Auto()
end

K.Run({
    {id = 'keep_fair', fn = function(c)
        local A1, B1 = S.Lever(1, 'Keep Alpha', true, true), S.Lever(2, 'Keep Beta', true, true)
        local H, A = S.Fixture({levers = {A1, B1}})
        c(S.Assign(H, A, 'Keep pair', {A1, B1}), 'keep_fair reached: both Wishlist tomes assigned')
        c(S.AutoOn(H), 'keep_fair reached: Auto ON')
        local plan = Nexus.Strategy.Compile(A.Catalog(), A.Wishlist(), Nexus.Store.Settings())
        local firstLever, secondLever = plan.leverPlan.keep[1], plan.leverPlan.keep[2]
        local firstEcho, secondEcho = EchoFor(A, firstLever), EchoFor(A, secondLever)
        c(firstEcho and secondEcho and firstEcho ~= secondEcho, 'keep_fair reached: two keep candidates')
        local calls = WrapCalls(H, firstEcho)
        S.ResetToLevel1(H)
        H.Advance(.3, .05)
        c(#calls >= 1 and calls[1].id == firstEcho, 'keep_fair reached: first keep candidate is attempted')
        H.Advance(.7, .05)
        c(Count(calls, firstEcho) >= 1 and Count(calls, secondEcho) == 1,
            'keep_fair a persistently refused keep A does not starve keep B')
        c(H.disabled[secondEcho] == false, 'keep_fair keep B is accepted and confirmed')
    end},
    {id = 'disable_fair', fn = function(c)
        local R = S.Lever(1, 'Disable Anchor', true, false)
        local X1, X2 = S.Lever(2, 'Disable Spare One', true, false), S.Lever(3, 'Disable Spare Two', true, false)
        local H, A = S.Fixture({levers = {R, X1, X2}})
        c(S.Assign(H, A, 'Disable pair', {R}), 'disable_fair reached: Wishlist assigned')
        c(S.AutoOn(H), 'disable_fair reached: Auto ON')
        local plan = Nexus.Strategy.Compile(A.Catalog(), A.Wishlist(), Nexus.Store.Settings())
        local firstLever, secondLever = plan.leverPlan.disable[1], plan.leverPlan.disable[2]
        local firstEcho, secondEcho = EchoFor(A, firstLever), EchoFor(A, secondLever)
        c(firstEcho and secondEcho and firstEcho ~= secondEcho, 'disable_fair reached: two disable candidates')
        local calls = WrapCalls(H, firstEcho)
        S.ResetToLevel1(H)
        H.Advance(.3, .05)
        c(#calls >= 1 and calls[1].id == firstEcho, 'disable_fair reached: first disable candidate is attempted')
        H.Advance(.7, .05)
        c(Count(calls, firstEcho) >= 1 and Count(calls, secondEcho) == 1,
            'disable_fair a persistently refused disable A does not starve disable B')
        c(H.disabled[secondEcho] == true, 'disable_fair disable B is accepted and confirmed')
    end},
    {id = 'unread_keep', fn = function(c)
        local R, X = S.Lever(1, 'Unread Keep', true, false), S.Lever(2, 'Unread Spare', true, false)
        local H, A = S.Fixture({levers = {R, X}})
        c(S.Assign(H, A, 'Unread plan', {R}), 'unread_keep reached: Wishlist assigned')
        local raw = H.service.IsTomeEchoDisabled
        H.service.IsTomeEchoDisabled = function(id)
            if id == R.echo then return nil end
            return raw(id)
        end
        c(A.LeverMirrorKind(R.lever) == 'unknown' and A.DisabledLevers()[R.lever] == nil,
            'unread_keep reached: unreadable keep is omitted from DisabledLevers')
        c(S.AutoOn(H), 'unread_keep reached: Auto ON')
        S.ResetToLevel1(H)
        H.Advance(1.2, .05)
        local text = DialogText()
        c(text:find('will not send another automatic change', 1, true) ~= nil,
            'unread_keep unknown keep is not reported as configured')
        c(not text:find('Please wait', 1, true) and not text:find('You may now level up', 1, true),
            'unread_keep unknown keep neither waits nor claims success')
        c(#H.trace == 1 and H.trace[1].id == X.echo, 'unread_keep still disables the readable spare')
    end},
    {id = 'unconfirmed_disable', fn = function(c)
        local R, X = S.Lever(1, 'Held Anchor', true, false), S.Lever(2, 'Held Spare', true, false)
        local H, A = S.Fixture({levers = {R, X}, holdMirror = true})
        c(S.Assign(H, A, 'Held disable', {R}), 'unconfirmed_disable reached: Wishlist assigned')
        c(S.AutoOn(H), 'unconfirmed_disable reached: Auto ON')
        S.ResetToLevel1(H)
        S.Within(H, 2, function() return #H.trace >= 1 end)
        c(#H.trace == 1 and H.trace[1].id == X.echo and H.disabled[X.echo] == false,
            'unconfirmed_disable reached: disable is accepted with a held mirror')
        H.Advance(31, .05)
        c(#H.trace == 1, 'unconfirmed_disable expiry does not send a second disable')
        local text = DialogText()
        c(text:find('will not send another automatic change', 1, true) ~= nil,
            'unconfirmed_disable remaining work is unconfirmed, not in-progress')
        c(not text:find('Please wait', 1, true) and not text:find('You may now level up', 1, true),
            'unconfirmed_disable neither waits nor claims success')
        H.holdMirror = false; H.disabled[X.echo] = true; H.Notify(); H.Advance(1, .05)
        c(#H.trace == 1 and H.disabled[X.echo] == true,
            'unconfirmed_disable late confirmation does not authorize another request')
    end},
    {id = 'late_enable', fn = function(c)
        local R, X = S.Lever(1, 'Late Enable', true, true), S.Lever(2, 'Late Spare', true, false)
        local H, A = S.Fixture({levers = {R, X}, holdMirror = true})
        c(S.Assign(H, A, 'Late enable', {R}), 'late_enable reached: Wishlist assigned')
        c(S.AutoOn(H), 'late_enable reached: Auto ON')
        S.ResetToLevel1(H)
        S.Within(H, 2, function() return #H.trace >= 1 end)
        c(#H.trace == 1 and H.trace[1].id == R.echo and H.disabled[R.echo] == true,
            'late_enable reached: enable is pending without its mirror')
        H.Advance(31, .05)
        c(S.Toggles(H, R.echo) == 1, 'late_enable expiry does not resubmit the enable')
        H.holdMirror = false; H.disabled[R.echo] = false; H.Notify(); H.Advance(1, .05)
        c(S.Toggles(H, R.echo) == 1 and H.disabled[R.echo] == false,
            'late_enable late confirmation settles without a second toggle')
    end},
    {id = 'prompt_retire', fn = function(c)
        local R = S.Lever(1, 'Prompt Echo', true, true)
        local H, A = S.Fixture({levers = {R}})
        c(S.Assign(H, A, 'Prompt plan', {R}), 'prompt_retire reached: Wishlist assigned')
        S.ResetToLevel1(H); H.Advance(1, .05)
        c(not Auto() and H.popup and H.popup.which == 'NEXUS_LEVEL1_AUTO_TOMES',
            'prompt_retire reached: Auto-OFF mismatch shows the Enable Auto prompt')
        H.disabled[R.echo] = false; H.Notify(); H.Advance(1, .05)
        c(H.popup == nil, 'prompt_retire resolving the mismatch retires the Auto-OFF prompt')
        c(not Auto() and #H.trace == 0, 'prompt_retire retiring the prompt does not enable Auto or send')
    end},
    {id = 'prompt_revalidate', fn = function(c)
        local R = S.Lever(1, 'Bound Echo', true, true)
        local H, A = S.Fixture({levers = {R}})
        c(S.Assign(H, A, 'Bound plan', {R}), 'prompt_revalidate reached: Wishlist assigned')
        S.ResetToLevel1(H); H.Advance(1, .05)
        c(H.popup and H.popup.which == 'NEXUS_LEVEL1_AUTO_TOMES', 'prompt_revalidate reached: prompt is open')
        Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1('autoDisable', false)
        local accepted = H.AcceptPopup()
        c(accepted ~= true and not Auto(),
            'prompt_revalidate Yes is refused after tome permission is cleared')
    end},
    {id = 'prompt_overwrite', fn = function(c)
        local R = S.Lever(1, 'Overwrite Echo', true, true)
        local H, A = S.Fixture({levers = {R}, keepPrompts = true})
        local f = rawget(_G, 'NexusOverwriteWarning')
        if not (f and f:IsShown()) then SlashCmdList.NEXUS('auto'); f = rawget(_G, 'NexusOverwriteWarning') end
        H.Advance(5.01, .05)
        if f and f:IsShown() and f.yes:IsEnabled() then f.yes:Click() end
        local quick = rawget(_G, 'NexusQuickStart')
        if quick and quick:IsShown() then quick:Hide(); H.Advance(.2, .05) end
        c(Nexus.OverwriteWarning.EnsureOnboarding() ~= 'pending' and not Auto(),
            'prompt_overwrite reached: onboarding answered, Auto still OFF')
        c(S.Assign(H, A, 'Overwrite plan', {R}), 'prompt_overwrite reached: Wishlist assigned')
        S.ResetToLevel1(H); H.Advance(1, .05)
        c(H.popup and H.popup.which == 'NEXUS_LEVEL1_AUTO_TOMES',
            'prompt_overwrite reached: the bound Auto prompt is open')
        H.AcceptPopup()
        f = rawget(_G, 'NexusOverwriteWarning')
        c(f and f:IsShown() and not Auto() and #H.trace == 0,
            'prompt_overwrite reached: prompt Yes opens the overwrite warning')
        H.disabled[R.echo] = false; H.Notify(); H.Advance(1, .05)
        if f and f:IsShown() and f.yes:IsEnabled() then f.yes:Click() end
        c(not Auto() and #H.trace == 0,
            'prompt_overwrite a deferred Yes is refused after the bound mismatch resolves')
    end},
    {id = 'unconfirmed_revisit', fn = function(c)
        local R, X = S.Lever(1, 'Unconfirmed Keep', true, true), S.Lever(2, 'Other Keep', true, false)
        local H, A = S.Fixture({levers = {R, X}, holdMirror = true})
        c(S.Assign(H, A, 'Original keep', {R}), 'unconfirmed_revisit reached: original Wishlist assigned')
        c(S.AutoOn(H), 'unconfirmed_revisit reached: Auto ON')
        S.ResetToLevel1(H)
        S.Within(H, 2, function() return S.Toggles(H, R.echo) == 1 end)
        c(S.Toggles(H, R.echo) == 1 and H.disabled[R.echo] == true,
            'unconfirmed_revisit reached: one enable accepted without a matching mirror')
        H.Advance(31, .05)
        c(S.Toggles(H, R.echo) == 1, 'unconfirmed_revisit unchanged plan excludes the expired enable')
        c(S.Assign(H, A, 'Other keep', {X}), 'unconfirmed_revisit reached: changed to the other Wishlist')
        H.Advance(1, .05)
        c(S.Assign(H, A, 'Original keep again', {R}), 'unconfirmed_revisit reached: returned to the required tome')
        H.Advance(1, .05)
        c(S.Toggles(H, R.echo) == 1 and H.disabled[R.echo] == true,
            'unconfirmed_revisit Wishlist switches do not resubmit an unconfirmed enable')
        local acceptedBeforeConfirmation = S.Toggles(H, R.echo)
        H.holdMirror = false; H.disabled[R.echo] = false; H.Notify(); H.Advance(1, .05)
        c(S.Toggles(H, R.echo) == acceptedBeforeConfirmation and H.disabled[R.echo] == false,
            'unconfirmed_revisit late confirmation settles the original enable without another send')
        c(S.Assign(H, A, 'Other keep after confirmation', {X}),
            'unconfirmed_revisit reached: a confirmed reversal is now requested')
        H.Advance(1, .05)
        c(S.Toggles(H, R.echo) == acceptedBeforeConfirmation + 1 and H.disabled[R.echo] == true,
            'unconfirmed_revisit confirmed enable permits a later disable')
        c(S.Assign(H, A, 'Original after confirmed disable', {R}),
            'unconfirmed_revisit reached: required tome restored after a confirmed disable')
        H.Advance(1, .05)
        c(S.Toggles(H, R.echo) == acceptedBeforeConfirmation + 2 and H.disabled[R.echo] == false,
            'unconfirmed_revisit confirmed disable permits a later enable')
    end},
    {id = 'prompt_wishlist_changed', fn = function(c)
        for _, replacementDisabled in ipairs({false, true}) do
            local R = S.Lever(1, 'Original Prompt', true, true)
            local X = S.Lever(2, 'Replacement Prompt', true, replacementDisabled)
            local H, A = S.Fixture({levers = {R, X}, keepPrompts = true})
            c(FinishOnboarding(H), 'prompt_wishlist_changed reached: onboarding answered with Auto OFF')
            c(S.Assign(H, A, 'Original mismatch', {R}), 'prompt_wishlist_changed reached: original Wishlist assigned')
            S.ResetToLevel1(H); H.Advance(1, .05)
            c(H.popup and H.popup.which == 'NEXUS_LEVEL1_AUTO_TOMES',
                'prompt_wishlist_changed reached: original Tome prompt is open')
            H.AcceptPopup()
            local f = rawget(_G, 'NexusOverwriteWarning')
            c(f and f:IsShown() and not Auto() and #H.trace == 0,
                'prompt_wishlist_changed reached: the original overwrite Yes is deferred')
            c(S.Assign(H, A, 'Replacement Wishlist', {X}), 'prompt_wishlist_changed reached: Wishlist identity changed')
            H.Advance(1, .05)
            c(f and f:IsShown() and f.yes:IsEnabled(), 'prompt_wishlist_changed reached: old Yes remains available')
            if f and f:IsShown() and f.yes:IsEnabled() then f.yes:Click() end
            c(not Auto() and #H.trace == 0,
                'prompt_wishlist_changed old Yes cannot authorize either a configured or mismatched replacement')
            -- Keep the fresh-consent control independent of the stale-Yes result.
            if Auto() then SlashCmdList.NEXUS('auto') end
            SlashCmdList.NEXUS('auto')
            f = rawget(_G, 'NexusOverwriteWarning')
            c(f and f:IsShown() and not Auto(), 'prompt_wishlist_changed reached: fresh explicit Auto opens its warning')
            if f and f:IsShown() and f.yes:IsEnabled() then f.yes:Click() end
            c(Auto(), 'prompt_wishlist_changed fresh explicit Auto consent still enables Auto')
        end
    end},
    {id = 'prompt_overwrite_current', fn = function(c)
        local R = S.Lever(1, 'Current Prompt', true, true)
        local H, A = S.Fixture({levers = {R}, keepPrompts = true})
        c(FinishOnboarding(H), 'prompt_overwrite_current reached: onboarding answered with Auto OFF')
        c(S.Assign(H, A, 'Current mismatch', {R}), 'prompt_overwrite_current reached: current Wishlist assigned')
        S.ResetToLevel1(H); H.Advance(1, .05)
        c(H.popup and H.popup.which == 'NEXUS_LEVEL1_AUTO_TOMES', 'prompt_overwrite_current reached: Tome prompt open')
        H.AcceptPopup()
        local f = rawget(_G, 'NexusOverwriteWarning')
        c(f and f:IsShown() and not Auto(), 'prompt_overwrite_current reached: overwrite warning awaits Yes')
        if f and f:IsShown() and f.yes:IsEnabled() then f.yes:Click() end
        c(Auto(), 'prompt_overwrite_current unchanged bound context still permits Yes')
        H.Advance(1, .05)
        c(S.Toggles(H, R.echo) == 1 and H.disabled[R.echo] == false,
            'prompt_overwrite_current approved current Wishlist configures its required tome once')
    end},
    {id = 'unconfirmed_new_visit', fn = function(c)
        local R = S.Lever(1, 'Unconfirmed Across Runs', true, true)
        local H, A = S.Fixture({levers = {R}, holdMirror = true})
        c(S.Assign(H, A, 'Unconfirmed run', {R}), 'unconfirmed_new_visit reached: Wishlist assigned')
        c(S.AutoOn(H), 'unconfirmed_new_visit reached: Auto ON')
        S.ResetToLevel1(H)
        S.Within(H, 2, function() return S.Toggles(H, R.echo) == 1 end)
        H.Advance(31, .05)
        c(S.Toggles(H, R.echo) == 1 and H.disabled[R.echo] == true,
            'unconfirmed_new_visit reached: expired accepted enable still lacks confirmation')
        S.NewVisit(H); H.Advance(1, .05)
        c(S.Toggles(H, R.echo) == 1, 'unconfirmed_new_visit run boundary does not repeat the unresolved enable')
        local text = DialogText()
        c(text:find('will not send another automatic change', 1, true) ~= nil
            and not text:find('Please wait', 1, true) and not text:find('You may now level up', 1, true),
            'unconfirmed_new_visit excluded work remains unconfirmed rather than continuing after a run boundary')
        SlashCmdList.NEXUS('auto'); H.Notify(); H.Advance(1, .05)
        c(not Auto() and H.popup == nil and S.Toggles(H, R.echo) == 1,
            'unconfirmed_new_visit excluded work does not offer Auto-OFF consent for a Tome change it cannot send')
        H.holdMirror = false; H.disabled[R.echo] = false; H.Notify(); H.Advance(1, .05)
        c(not Auto() and H.popup == nil and S.Toggles(H, R.echo) == 1,
            'unconfirmed_new_visit late confirmation does not enable Auto or send another request')
    end},
    {id = 'prompt_overwrite_interleaved', fn = function(c)
        local R = S.Lever(1, 'Interleaved Prompt', true, true)
        local H, A = S.Fixture({levers = {R}, keepPrompts = true})
        c(FinishOnboarding(H), 'prompt_overwrite_interleaved reached: onboarding answered with Auto OFF')
        c(S.Assign(H, A, 'Unchanged consent', {R}), 'prompt_overwrite_interleaved reached: Wishlist assigned')
        S.ResetToLevel1(H); H.Advance(1, .05)
        c(H.popup and H.popup.which == 'NEXUS_LEVEL1_AUTO_TOMES', 'prompt_overwrite_interleaved reached: Tome prompt open')
        H.AcceptPopup()
        local f = rawget(_G, 'NexusOverwriteWarning')
        c(f and f:IsShown() and not Auto(), 'prompt_overwrite_interleaved reached: bound overwrite warning awaits Yes')
        H.Notify(); H.Advance(1, .05)
        SlashCmdList.NEXUS('auto')
        c(f and f:IsShown() and not Auto() and #H.trace == 0,
            'prompt_overwrite_interleaved reached: another Auto request leaves the same warning open')
        if f and f:IsShown() and f.yes:IsEnabled() then f.yes:Click() end
        c(Auto(), 'prompt_overwrite_interleaved a refused intervening Auto request does not revoke unchanged valid consent')
        H.Advance(1, .05)
        c(S.Toggles(H, R.echo) == 1 and H.disabled[R.echo] == false,
            'prompt_overwrite_interleaved the original valid Yes configures the current required Tome once')
    end},
    {id = 'prompt_exception_cleanup', fn = function(c)
        for _, inject in ipairs({false, true}) do
            local R = S.Lever(1, 'Exception Review Echo', true, true)
            local H, A = S.Fixture({levers = {R}})
            c(S.Assign(H, A, 'Exception review plan', {R}),
                'prompt_exception_cleanup reached: Wishlist assigned')
            S.ResetToLevel1(H); H.Advance(1, .05)
            c(H.popup and H.popup.which == 'NEXUS_LEVEL1_AUTO_TOMES' and not Auto(),
                'prompt_exception_cleanup reached: bound Auto-OFF prompt open')
            if inject then
                local original = Nexus.OverwriteWarning.RequestAuto
                Nexus.OverwriteWarning.RequestAuto = function()
                    error('Synthetic RequestAuto fault')
                end
                local ok, err = pcall(H.AcceptPopup)
                Nexus.OverwriteWarning.RequestAuto = original
                c(not ok and tostring(err):find('Synthetic RequestAuto fault', 1, true),
                    'prompt_exception_cleanup reached: the original request exception remains visible')
            end
            Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1('autoDisable', false)
            H.Notify()
            SlashCmdList.NEXUS('auto')
            c(Auto(), inject
                and 'prompt_exception_cleanup a failed prompt request does not bind a fresh generic Auto request'
                or 'prompt_exception_cleanup generic Auto remains available without Tome permission')
            c(#H.trace == 0, 'prompt_exception_cleanup no Tome request was submitted')
        end
    end},
}, rawget(_G, 'arg'))
