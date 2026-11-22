-- Player-facing terminology only. Stable policy/reason codes and protocol data
-- remain unchanged; diagnostics may retain original codes for support.
-- Issue #123/#142: five reasons resolve their English text through the
-- Nexus.Localization seam (localizedReasons below).
-- Full visible-UI localization (issues #143-#148, family "usertext"): every
-- other visible output of this file except T.Guide (reason texts, refusals,
-- waits, the "Not saved:" comparisons, annotations, the "Details:" suffix,
-- destination words, count units, record scope, setup and status lines and
-- terms) is shown through the same seam by a stable semantic key (reason.*,
-- term.*, count.*, usertext.*), looked up at call time. The English beside
-- each key here is its exact English base: it is shown only when the seam is
-- absent or cannot give the key, so no English byte changes. T.Message's
-- INPUTS are raw producer strings matched by English patterns: the inputs,
-- the patterns and the values captured from them are never translated; a
-- captured value reaches the output only as a template slot, verbatim. The
-- output is presented once (ui/Panel.lua Present) and is never passed through
-- T.Message again. The in-text rewrite chain at the end of T.Message rewrites
-- fragments of producer-composed English and stays English until those
-- producers are converted together with it (docs/localization-dynamic-cohorts.md).
-- T.Guide (guided setup copy, read by ui/GuidedSetup.lua) is not covered here.
Nexus=Nexus or {}
local T={};Nexus.UserText=T

-- While T.EnglishMessage runs: an empty pack, so the seam answers with its
-- English base whatever the active language is; nil otherwise (active pack).
local englishPack
local ENGLISH_ONLY={}
-- The seam at call time (a test may swap Nexus.Localization), never cached.
local function Seam()
    local localization=Nexus.Localization
    if type(localization)=="table" and type(localization.Text)=="function" then return localization end
    return nil
end
-- A static meaning: the seam's text for key, else its exact English.
local function Say(key,english)
    local localization=Seam()
    if localization then
        local text,source=localization.Text(key,englishPack)
        if type(text)=="string" and source~="unavailable" then return text end
    end
    return english
end
-- A template meaning. args: field name -> a string (a "text" slot, inserted
-- verbatim and never parsed again) or a whole number (a "count" slot, through
-- Localization.Count). english is the exact English output, shown when the
-- seam is absent or refuses (for example a slot value above its byte limit).
local function SayF(key,args,english)
    local localization=Seam()
    if localization and type(localization.Format)=="function" and type(localization.Count)=="function" then
        local slots={}
        for name,value in pairs(args) do
            slots[name]=type(value)=="number" and localization.Count(value) or value
        end
        local text,source=localization.Format(key,slots,englishPack)
        if type(text)=="string" and source~="unavailable" then return text end
    end
    return english
end
-- A {key, english} entry through Say; any other value (a code-owned glyph
-- such as "?") as it is.
local function Pick(entry)
    if type(entry)=="table" then return Say(entry[1],entry[2]) end
    return entry
end

local reasons={
    ["unsynced"]="Waiting for current Echo data from the server - automatic choices paused",
    ["waiting for owned-echo sync"]="Waiting for current Echo data from the server - automatic choices paused",
    ["waiting for owned-state sync"]="Waiting for current Echo data from the server - automatic choices paused",
    ["no wishlist set - advisor only"]="No Wishlist assigned - recommendations only",
    ["no wishlist"]="Assign a Wishlist to use its targets",
    ["pending-pick count"]="Waiting for the remaining-choice count",
    ["Orb state active or unknown"]="Ordinary rolling paused while the Orb choice is active or cannot be confirmed",
    ["orb state not yet known"]="Ordinary rolling paused: the server's Orb state is not confirmed yet",
    ["orb state unknown"]="Ordinary rolling paused: the game's Orb state could not be read",
    ["orb state unavailable"]="Ordinary rolling paused: the game's Orb service does not expose its pending-offer state",
    ["orb state capability missing"]="Ordinary rolling paused: the game's Orb service does not report whether its state is known, so Nexus cannot confirm that no Orb choice is open",
    ["Orb offer active -- manual action required"]="An Orb offer is active; use Orb mode or resolve it in the game",
    ["Take wanted Echo (EchoWeaver)"]="Take a needed Echo",
    ["Take available Echo (EchoWeaver)"]="Take an available Echo",
    ["Freeze wanted Echo before search (EchoWeaver)"]="Freeze a needed Echo before searching for another target",
    ["Banish to find Wishlist targets (EchoWeaver)"]="Banish to find Wishlist targets",
    ["Reroll: no requested Echo on board (EchoWeaver)"]="Reroll: no requested Echo on board",
    ["Reroll: no needed Echo on board (EchoWeaver)"]="Reroll: no Echo on this board is still needed",
    ["Take available filler (EchoWeaver)"]="Take an available Echo outside the Wishlist",
    ["Take filler; search unavailable (EchoWeaver)"]="Take an Echo outside the Wishlist; no permitted Banish or Reroll action",
    ["Wishlist complete; take filler (EchoWeaver)"]="Wishlist complete; take an Echo outside the Wishlist",
    ["Freeze one wanted Echo to keep a second wanted offer (EchoWeaver, experimental)"]="Freeze one of the needed offers",
    ["Banish an unwanted Echo before Reroll (EchoWeaver, experimental)"]="Banish an unneeded Echo before Reroll",
    ["Take the held wanted Echo instead of searching (EchoWeaver, experimental)"]="Take the held needed Echo instead of searching",
    ["Take wanted Echo"]="Take a needed Echo",
    ["invalid wishlist"]="This Wishlist cannot be used yet. Open it in the editor to check its targets",
    ["invalid loadout"]="This Saved Build is unavailable or not valid for this action. Check My Builds",
    ["ROOT_PENDING"]="The build library is still being prepared",
    ["SOURCE_KEY_WIDTH_EXCEEDED"]="A saved record has an unsupported long key. Keep your backup and report this code",
    ["preparing"]="Preparing shared-build data",
    ["cleaning"]="Removing expired requests",
    ["throttled"]="Waiting for the permitted network send rate",
    ["armed (guaranteed queue live)"]="The server marked a current offer guaranteed; no future offer is assumed",
    ["Activate did not guarantee -- treating as unarmed"]="No guaranteed offer was shown after activation; no future guarantee is assumed",
    ["bracket fishing: reroll filler guarantee"]="Reroll the unneeded guaranteed offer under the enabled policy",
    ["tight horizon"]="Few selections remain",
    ["drain guaranteed queue"]="Use the offer shown on this board; no future offer is assumed",
    ["Tome levers"]="Echo availability controls",
    ["flag demotions cleared (they re-arm on fresh evidence)"]="Temporary safety-assumption disablements cleared; new evidence can disable them again",
}
-- The stable semantic key of each reason above (raw producer reason -> key).
-- Raw reasons with the same meaning share one key; the raw reason stays the
-- lookup and is never rewritten. A key is never made from the reason's text.
local reasonKeys={
    ["unsynced"]="reason.wait_echo_data",
    ["waiting for owned-echo sync"]="reason.wait_echo_data",
    ["waiting for owned-state sync"]="reason.wait_echo_data",
    ["no wishlist set - advisor only"]="reason.no_wishlist_advisor",
    ["no wishlist"]="reason.assign_wishlist_targets",
    ["pending-pick count"]="reason.wait_remaining_choice_count",
    ["Orb state active or unknown"]="reason.orb_active_or_unconfirmed",
    ["orb state not yet known"]="reason.orb_state_not_confirmed",
    ["orb state unknown"]="reason.orb_state_unreadable",
    ["orb state unavailable"]="reason.orb_state_unexposed",
    ["orb state capability missing"]="reason.orb_knownness_unreported",
    ["Orb offer active -- manual action required"]="reason.orb_offer_active",
    ["Take wanted Echo (EchoWeaver)"]="reason.take_needed",
    ["Take available Echo (EchoWeaver)"]="reason.take_available",
    ["Freeze wanted Echo before search (EchoWeaver)"]="reason.freeze_needed_before_search",
    ["Banish to find Wishlist targets (EchoWeaver)"]="reason.banish_find_targets",
    ["Reroll: no requested Echo on board (EchoWeaver)"]="reason.reroll_no_requested",
    ["Reroll: no needed Echo on board (EchoWeaver)"]="reason.reroll_none_needed",
    ["Take available filler (EchoWeaver)"]="reason.take_outside_wishlist",
    ["Take filler; search unavailable (EchoWeaver)"]="reason.take_outside_no_search",
    ["Wishlist complete; take filler (EchoWeaver)"]="reason.complete_take_outside",
    ["Freeze one wanted Echo to keep a second wanted offer (EchoWeaver, experimental)"]="reason.freeze_one_needed",
    ["Banish an unwanted Echo before Reroll (EchoWeaver, experimental)"]="reason.banish_unneeded_before_reroll",
    ["Take the held wanted Echo instead of searching (EchoWeaver, experimental)"]="reason.take_held_needed",
    ["Take wanted Echo"]="reason.take_needed",
    ["invalid wishlist"]="reason.wishlist_unusable",
    ["invalid loadout"]="reason.saved_build_invalid",
    ["ROOT_PENDING"]="reason.library_preparing",
    ["SOURCE_KEY_WIDTH_EXCEEDED"]="reason.record_key_unsupported",
    ["preparing"]="reason.shared_data_preparing",
    ["cleaning"]="reason.removing_expired_requests",
    ["throttled"]="reason.wait_send_rate",
    ["armed (guaranteed queue live)"]="reason.guaranteed_offer_marked",
    ["Activate did not guarantee -- treating as unarmed"]="reason.no_guarantee_after_activate",
    ["bracket fishing: reroll filler guarantee"]="reason.reroll_unneeded_guaranteed",
    ["tight horizon"]="reason.few_selections_remain",
    ["drain guaranteed queue"]="reason.use_shown_offer",
    ["Tome levers"]="term.echo_availability_controls",
    ["flag demotions cleared (they re-arm on fresh evidence)"]="reason.safety_disablements_cleared",
}
-- Reasons whose English text comes from Nexus.Localization (issue #123). The
-- raw reason stays the lookup key and is never rewritten; the value is the
-- stable semantic key of its reviewed text (data/LocalizationEnglish.lua).
local localizedReasons={
    ["ROOT_MUTATION_PENDING"]="reason.save_in_progress",
    ["CURSOR_REQUIRED"]="reason.list_preparing",
    ["STORE_PENDING"]="reason.saved_data_reading",
    -- Issue #142: the two planner wait reasons. The older "pending-pick count"
    -- mapping above is a different reason and stays as it is.
    ["waiting for three-card board"]="reason.wait_three_choices",
    ["waiting for pending-pick count"]="reason.wait_pending_pick_count",
}
-- Without the seam, the two wait reasons keep the exact English they showed
-- before they moved to it (issue #142).
local legacyWaitText={
    ["waiting for three-card board"]="Waiting for the next three Echo choices",
    ["waiting for pending-pick count"]="waiting for pending-pick count",
}
-- A tome's control name. The tome name is game catalog data and the id is the
-- raw number from the producer's text: both are inserted verbatim.
local function availabilityName(id)
    local a=Nexus.GameAdapter
    local catalog=a and a.Catalog and a.Catalog()
    local lever=catalog and catalog.levers and catalog.levers[tonumber(id)]
    local name=lever and lever.tomeName
    if name then
        local shown=tostring(name)
        return SayF("usertext.label.tome_control",{name=shown,id=id},shown.." (control #"..id..")")
    end
    return SayF("usertext.label.availability_control",{id=id},"Echo-availability control #"..id)
end
-- One of those reasons through the seam. When the seam has no reviewed text
-- for the key it returns its documented safe status and the raw code is kept
-- as the support detail; without the seam the reason reads like any other
-- unrecognized code (the generic line in T.Message below).
local function LocalizedReason(key,code)
    local localization=Nexus.Localization
    if type(localization)=="table" and type(localization.Text)=="function" then
        local text,source=localization.Text(key,englishPack)
        if type(text)=="string" and text~="" then
            if source=="unavailable" then return text.." "..T.Details(code) end
            -- Only an actual validated base/candidate result carries this
            -- presentation provenance. Arbitrary raw strings never do.
            return text, (source=="base" or source=="candidate")
                and type(localization.IsText)=="function" and localization.IsText(text)==true
        end
    end
    if legacyWaitText[code] then return legacyWaitText[code] end -- issue #142, seam absent
    return "This action is not available yet. Check the status or diagnostics. Details: "..code
end
-- A reason of the reasons table through the seam, with the same provenance
-- rule as LocalizedReason: only a validated base/candidate result carries it.
-- These reasons keep their English in this file, so a seam that cannot give
-- the key shows that exact English (without provenance) instead of the safe
-- status; the raw reason is never shown in place of its text.
local function SeamReason(key,english)
    local localization=Seam()
    if localization then
        local text,source=localization.Text(key,englishPack)
        if type(text)=="string" and text~="" and source~="unavailable" then
            return text, (source=="base" or source=="candidate")
                and type(localization.IsText)=="function" and localization.IsText(text)==true
        end
    end
    return english
end
-- A whole count captured as digits from a producer's text, or nil when the
-- number would not show its exact digits again (the English is then shown).
local function CapturedCount(digits)
    local value=tonumber(digits)
    if value and tostring(value)==digits then return value end
    return nil
end
-- Display phrasebooks of other owners (e.g. the Orb window's book for the
-- Orb reasons a blocked action carries): fn(raw) returns the shown text and
-- whether it recognized raw. Asked only after every rule below that names a
-- text, so no text those rules show changes; a text no source recognizes
-- keeps its existing presentation.
local phraseSources={}
function T.AddPhraseSource(fn)
    if type(fn)~="function" then return end
    for _,known in ipairs(phraseSources) do if known==fn then return end end
    phraseSources[#phraseSources+1]=fn
end
-- The English text of a reason above, recognized as that reason: a runtime
-- that keeps the English presentation (T.EnglishMessage) for its record has
-- it said once, in the active language, at the display.
local reasonKeysByEnglish={}
for raw,english in pairs(reasons) do reasonKeysByEnglish[english]=reasonKeys[raw] end
local function FromPhraseSources(s)
    -- The English presentation is the one before these sources existed.
    if englishPack then return nil end
    local key=reasonKeysByEnglish[s]
    if key then return SeamReason(key,s) end
    for _,source in ipairs(phraseSources) do
        local ok,shown,known=pcall(source,s)
        if ok and known==true and type(shown)=="string" then
            local localization=Seam()
            return shown, localization~=nil and type(localization.IsText)=="function"
                and localization.IsText(shown)==true
        end
    end
    return nil
end
-- The adapter's composed identity-found note (core/GameAdapter.lua
-- A.WishlistNoteFacts: its reason, and whether the editor instruction
-- follows), said from those facts. `whole` is the Orb window's form, which
-- keeps the "Wishlist identity found;" lead; otherwise the form this file's
-- rewrite always showed (without it). A known reason is said through its
-- key when the active language has it; any other reason stays as given.
-- nil for a text the adapter did not produce, or when the form's key has
-- no valid candidate (the display then keeps its exact English).
local IDENTITY_REASONS={
    ["wishlist identity or structure is invalid"]="editor.reason.wishlist_identity_or_structure_is_invalid",
    ["Choose locked targets in the Wishlist Editor; the saved role choice is unavailable"]="library.reason.evidence_choose_in_editor",
    ["associated loadout is not active; locked roles remain unknown"]="library.reason.evidence_loadout_inactive",
    ["no verified active loadout for locked-Echo evidence"]="library.reason.evidence_no_verified_active",
    ["active loadout is not verified; locked-Echo evidence is pending"]="library.reason.evidence_active_unverified",
    ["wishlist does not exactly match the verified active loadout; locked roles remain unknown"]="library.reason.evidence_not_exact_match",
    ["active loadout contains malformed Echo evidence"]="library.reason.evidence_malformed",
    ["active loadout contains conflicting Echo quality evidence"]="library.reason.evidence_conflicting_quality",
    ["active loadout exceeds the supported Echo count"]="library.reason.evidence_too_many",
    ["waiting for synchronized permanent locked-Echo evidence"]="library.reason.evidence_waiting_sync",
    ["permanent locked-Echo counts do not fit the exact active loadout"]="library.reason.evidence_counts_mismatch",
    ["locked evidence cannot establish at most 79 ordinary and 6 locked copies"]="library.reason.evidence_envelope",
    ["waiting for authoritative locked-Echo evidence"]="library.reason.evidence_waiting_authoritative",
}
function T.IdentityNote(value,whole)
    local adapter,localization=Nexus.GameAdapter,Nexus.Localization
    local facts=type(value)=="string" and type(adapter)=="table" and type(adapter.WishlistNoteFacts)=="function"
        and adapter.WishlistNoteFacts(value) or nil
    if not facts or type(localization)~="table" or type(localization.Format)~="function" then return nil end
    -- englishPack: while T.EnglishMessage runs, no candidate is used, so the
    -- route below shows the exact English from the facts.
    local reason,reasonKey=facts.reason,IDENTITY_REASONS[facts.reason]
    if reasonKey then
        local text,source=localization.Text(reasonKey,englishPack)
        if source=="candidate" then reason=text end
    end
    local key
    if whole then
        key=facts.pending and "orb.assignment.identity_found_open_editor" or "orb.assignment.identity_found"
    else
        key=facts.pending and "orb.assignment.identity_found_reason_open_editor" or "orb.assignment.identity_found_reason"
    end
    local shown,source=localization.Format(key,{reason=reason},englishPack)
    if source=="candidate" then return shown end
    return nil
end

-- The adapter's identity-found note, recognized only by its trusted facts for
-- exactly the adapter's current note bytes, before T.Message's legacy
-- substring rules and rewrites can change an opaque reason inside it. The
-- note itself: said through its key, else its exact English without the
-- lead (built from the facts). The note inside another owner's line (the
-- /nexus status advisor line): that owner's phrase source says the line.
-- The reasons below keep their own keyed wait/choose sentence instead.
local IDENTITY_KEYED_ROUTE={
    ["associated loadout is not active; locked roles remain unknown"]=true,
    ["wishlist does not exactly match the verified active loadout; locked roles remain unknown"]=true,
    ["waiting for authoritative locked-Echo evidence"]=true,
    ["waiting for synchronized permanent locked-Echo evidence"]=true,
}
local function IdentityRoute(s)
    local adapter=Nexus.GameAdapter
    if type(adapter)~="table" or type(adapter.WishlistNote)~="function"
        or type(adapter.WishlistNoteFacts)~="function" then return nil end
    local note=adapter.WishlistNote()
    local facts=type(note)=="string" and adapter.WishlistNoteFacts(note) or nil
    if not facts or IDENTITY_KEYED_ROUTE[facts.reason] or not s:find(note,1,true) then return nil end
    if s==note then
        local shown=T.IdentityNote(s,false)
        if shown then return shown,true end
        return facts.reason.."."..(facts.pending
            and " Open the Wishlist Editor to choose and confirm its locked targets." or ""),false
    end
    return FromPhraseSources(s)
end

-- A text another owner's display recognizes (an English reason wording or
-- a phrase source), in the active language; any other text unchanged. Unlike
-- T.Message it never rewrites an unknown text.
function T.Recognized(value)
    if type(value)~="string" then return value end
    local shown=FromPhraseSources(value)
    return shown or value
end
function T.Message(value)
    local s=tostring(value or "")
    if reasons[s] then return SeamReason(reasonKeys[s],reasons[s]) end
    if localizedReasons[s] then return LocalizedReason(localizedReasons[s],s) end
    local prefix,body=s:match("^(L%d+ %-%- )(.*)$")
    if prefix then
        local text,localized=T.Message(body)
        local combined=prefix..text
        local localization=Nexus.Localization
        return combined, localized==true and type(localization)=="table"
            and type(localization.IsText)=="function" and localization.IsText(combined)==true
    end
    body=s:match("^waiting: (.*)$")
    if body then return T.Message(body) end
    local id=s:match("^disabling off%-wishlist tome lever (%d+)$")
    if id then
        local control=availabilityName(id)
        return SayF("usertext.status.disabling_control",{control=control},"Disabling off-Wishlist "..control)
    end
    id=s:match("^re%-enabling wishlist tome lever (%d+)$")
    if id then
        local control=availabilityName(id)
        return SayF("usertext.status.enabling_control",{control=control},"Enabling Wishlist "..control)
    end
    local detail
    id,detail=s:match("^lever (%d+): (.*)$")
    if id then
        -- The detail is the producer's raw text (one legacy fragment rewrite).
        local control=availabilityName(id)
        local shown=detail:gsub("non%-conformant data","unsupported availability data")
        return SayF("usertext.status.control_detail",{control=control,detail=shown},control..": "..shown)
    end
    local identity,identityLocalized=IdentityRoute(s)
    if identity then return identity,identityLocalized end
    if s:find("locked roles remain unknown",1,true) or s:find("awaiting authoritative lock evidence",1,true)
        or s:find("waiting for authoritative locked%-Echo evidence") then
        return SayF("reason.choose_locked_targets",{details=s},"Choose this Wishlist's locked Echo targets in the editor. Your planned build does not have to match the equipped build. Details: "..s)
    end
    if s:find("waiting for synchronized permanent locked%-Echo evidence") then
        return SayF("reason.wait_locked_echo_list",{details=s},"Waiting for the server's current locked Echo list. Details: "..s)
    end
    if s:find("waiting for the server mirror",1,true) then
        return SayF("reason.wait_server_wishlist",{details=s},"The saved Wishlist is not available from the server yet. Details: "..s)
    end
    if s:find("payload changed",1,true) or s:find("preview is stale",1,true) then
        return SayF("reason.draft_changed",{details=s},"This draft changed. Reopen it and review the current targets before saving. Details: "..s)
    end
    local lost,gain,fewer=s:match("exact wishlist progress regressed (%d+) %(gained (%d+), shed (%d+) exact stacks%)")
    if lost then
        local english="Not saved: this run matches "..lost.." fewer Wishlist copies ("..gain.." gained, "..fewer.." fewer than the saved build)."
        local lostCount,gainCount,fewerCount=CapturedCount(lost),CapturedCount(gain),CapturedCount(fewer)
        if not (lostCount and gainCount and fewerCount) then return english end
        return SayF("reason.not_saved_fewer_copies",{lost=lostCount,gained=gainCount,fewer=fewerCount},english)
    end
    if s:find("cleanup-only save added new excess/wrong-quality pollution",1,true) then
        return Say("reason.not_saved_adds_excess","Not saved: this run adds excess or wrong-quality copies compared with the saved build.")
    end
    if s:find("no net gain",1,true) then return Say("reason.not_saved_no_gain","Not saved: no additional matching Wishlist copies were confirmed.") end
    if s:find("coverage lost:",1,true) then return Say("reason.not_saved_coverage_lost","Not saved: some previously matched Wishlist targets would be lost. See diagnostics for the exact targets.") end
    local identity=T.IdentityNote(s,false)
    if identity then return identity,true end
    local phrased,phrasedText=FromPhraseSources(s)
    if phrased then return phrased,phrasedText end
    if s:match("^[A-Z][A-Z0-9_]+$") then
        return SayF("reason.unknown_code",{code=s},"This action is not available yet. Check the status or diagnostics. Details: "..s)
    end
    s=s:gsub("Take wanted Echo %(EchoWeaver%)","Take a needed Echo")
        :gsub("Wishlist identity found; ","")
        :gsub("TARGET:","WISHLIST:")
        :gsub("OWNED this run:","Rolled Echoes this run:")
        :gsub(" %(synced%)"," (server confirmed)")
        :gsub(" %(not synced yet%)"," (waiting for current Echo data from the server)")
        :gsub("UNARMED","No guaranteed offer observed")
        :gsub("ARMED","Guaranteed current offer observed; no future offer is assumed")
         :gsub("tight horizon","few selections remain")
        :gsub("bracket fishing","searching with the enabled Banish/Reroll actions")
        :gsub("tome lever ","Echo-availability control #")
        :gsub("search unavailable","no permitted Banish or Reroll action")
        :gsub("before search","before searching for another target")
        :gsub("waiting for owned%-echo sync","waiting for current Echo data from the server")
    return s
end
-- T.Message's English presentation, whatever the active language: for a
-- runtime that keeps it in a record (a support report line), so the record's
-- bytes never depend on the language and the display says it once.
function T.EnglishMessage(value)
    local outer=englishPack
    englishPack=ENGLISH_ONLY
    local ok,text=pcall(T.Message,value)
    englishPack=outer
    if not ok then error(text,0) end
    return text
end
-- A card annotation code -> its {key, English}; EchoWeaver's own words for the
-- same states share the key of that state.
local ANNOTATIONS={
    wanted={"usertext.label.card_needed","Needed"},
    ["returns later"]={"usertext.label.card_not_taken_now","Not taken now; a later offer is not guaranteed"},
    banked={"usertext.label.card_held_offer","Held offer"},
    filler={"usertext.label.card_not_on_wishlist","Not on Wishlist"},
    ["low quality"]={"usertext.label.card_different_quality","Different quality from target"},
    ["target met"]={"usertext.label.card_target_met","Target already met"},
    ["wrong quality"]={"usertext.label.card_different_quality","Different quality from target"},
    -- EchoWeaver's own words for the same states.
    ["target satisfied"]={"usertext.label.card_target_met","Target already met"},
    frozen={"usertext.label.card_frozen_offer","Frozen offer"},
}
function T.Annotation(value)
    local entry=value~=nil and ANNOTATIONS[value] or nil
    if entry then return Say(entry[1],entry[2]) end
    return T.Message(value)
end
-- The support detail. The raw code is inserted verbatim and never translated.
function T.Details(code)
    if not code then return Say("usertext.label.details_no_code","Details: unknown") end
    local shown=tostring(code)
    return SayF("usertext.label.details",{code=shown},"Details: "..shown)
end

------------------------------------------------------------------------
-- M4 (UX-04/13/14/15): shared player-facing presentation of destinations,
-- counts, record scope and terms. Every function below is a pure function of
-- the facts its caller already holds: it reads no state, calls no service,
-- writes nothing and schedules nothing. An unknown is said as unknown or
-- unavailable, never as 0, and a planned or partial state is never called
-- complete. Names pass through the existing display sanitizer (UTF-8 safe).
-- Each worded value comes from the seam by key (see the header); names,
-- slot numbers and codes are template slots, never translated.
------------------------------------------------------------------------

-- A whole, finite, non-negative number, else nil (unknown).
local function Whole(value)
    value = tonumber(value)
    if value and value == value and value >= 0 and value < math.huge then
        return math.floor(value)
    end
    return nil
end

-- Cut at a character boundary (UTF-8 lead bytes), never inside a letter.
-- pairedPipes: the text is display-safe (Identity.DisplaySafeText), so each
-- literal pipe is the escaped pair "||". A cut that would keep only the first
-- pipe of a pair keeps neither, so no lone pipe reaches the "..." (I-01). The
-- kept text is then one character shorter, never longer, than maxChars.
local function Utf8Cut(text, maxChars, pairedPipes)
    maxChars = tonumber(maxChars)
    if not maxChars or maxChars < 1 then return text end
    local count, index, length = 0, 1, #text
    while index <= length do
        local byte = text:byte(index)
        local width = (byte < 0xC0 and 1) or (byte < 0xE0 and 2) or (byte < 0xF0 and 3) or 4
        count = count + 1
        if count > maxChars then
            local keep = index - 1
            if pairedPipes then
                -- Pipes are single bytes: an odd run of them ending the kept
                -- text ends in the first pipe of a split pair; dropping that
                -- pipe leaves whole pairs only.
                local pipes, at = 0, keep
                while at >= 1 and text:byte(at) == 0x7C do pipes, at = pipes + 1, at - 1 end
                if pipes % 2 == 1 then keep = keep - 1 end
            end
            return text:sub(1, keep) .. "..."
        end
        index = index + width
    end
    return text
end

-- A name as it may be shown (the existing display sanitizer), optionally
-- shortened at a character boundary that does not split an escaped pipe
-- pair; nil when there is nothing to show. The caller's value is not changed.
function T.SafeName(value, maxChars)
    if value == nil then return nil end
    local text = tostring(value)
    local identity = Nexus.Identity
    if identity and type(identity.DisplaySafeText) == "function" then
        local ok, shown = pcall(identity.DisplaySafeText, text, 1024, false)
        text = ok and shown or nil
    end
    if type(text) ~= "string" or text == "" then return nil end
    return Utf8Cut(text, maxChars, true)
end

-- "Saved Build 'Fire PvE' (slot 2)", "Saved Build 2" or nil.
function T.SavedBuildLabel(slot, name, maxChars)
    slot = Whole(slot)
    local shown = T.SafeName(name, maxChars)
    if slot and slot >= 1 then
        if shown then
            return SayF("term.saved_build_named_slot", {name = shown, slot = tostring(slot)},
                "Saved Build '" .. shown .. "' (slot " .. slot .. ")")
        end
        return SayF("term.saved_build_slot", {slot = tostring(slot)}, "Saved Build " .. slot)
    end
    return shown and SayF("term.saved_build_named", {name = shown}, "Saved Build '" .. shown .. "'") or nil
end

-- Shared wording of the destination descriptor documented below, used by
-- both DestinationLines and DestinationFields so that they cannot disagree.
-- Pure: these only word the facts they are given. Each state has its
-- in-sentence words (lower case, after "Destination: " or "Captured; ") and
-- the same words as a whole cell value (raised first letter): two keys,
-- because a translation may word the two places differently.
--   {lowerKey, lower English, cellKey, cell English}
local SAVED_BUILD_STATE_WORDS = {
    unavailable = {"usertext.value.build_unavailable", "not available right now",
        "usertext.value.build_unavailable_cell", "Not available right now"},
    empty = {"usertext.value.build_empty", "empty: it holds no Echoes, so assigning to it is refused",
        "usertext.value.build_empty_cell", "Empty: it holds no Echoes, so assigning to it is refused"},
    active = {"usertext.value.build_active", "active in the game",
        "usertext.value.build_active_cell", "Active in the game"},
    inactive = {"usertext.value.build_inactive", "not active in the game",
        "usertext.value.build_inactive_cell", "Not active in the game"},
    unconfirmed = {"usertext.value.build_unconfirmed", "not confirmed as the active Saved Build",
        "usertext.value.build_unconfirmed_cell", "Not confirmed as the active Saved Build"},
}
-- A Saved Build whose active state is not stated (DestinationFields only).
local BUILD_STATE_NOT_KNOWN = {"usertext.value.build_state_not_known", "active state not known",
    "usertext.value.build_state_not_known_cell", "Active state not known"}
-- The other destinations: their Saved Build cell ({key, English}, a cell
-- value) and destination words (as above).
local DESTINATION_WORDS = {
    firstRun = {build = {"usertext.value.build_cell_none_in_use", "None in use"},
        state = {"usertext.value.dest_first_run", "first-run target (no Saved Build in use)",
            "usertext.value.dest_first_run_cell", "First-run target (no Saved Build in use)"}},
    restoring = {build = {"usertext.value.build_cell_not_known_yet", "Not known yet"},
        state = {"usertext.value.dest_restoring", "not known yet (the saved assignment is being restored)",
            "usertext.value.dest_restoring_cell", "Not known yet (the saved assignment is being restored)"}},
    unknown = {build = {"usertext.value.build_cell_not_loaded_yet", "Not loaded yet"},
        state = {"usertext.value.dest_not_loaded", "Saved Build data is not loaded yet",
            "usertext.value.dest_not_loaded_cell", "Saved Build data is not loaded yet"}},
    unconfirmed = {build = {"usertext.value.build_cell_not_confirmed", "Not confirmed right now"},
        state = {"usertext.value.dest_unconfirmed", "not confirmed right now",
            "usertext.value.dest_unconfirmed_cell", "Not confirmed right now"}},
    none = {build = {"usertext.value.build_cell_none_captured", "None captured"},
        state = {"usertext.value.dest_none", "none captured",
            "usertext.value.dest_none_cell", "None captured"}},
}
-- In-sentence (cell false) or whole-cell (cell true) words of such an entry.
local function StateWords(entry, cell)
    if cell then return Say(entry[3], entry[4]) end
    return Say(entry[1], entry[2])
end
local WISHLIST_STATES = {assigned = true, unassigned = true, unavailable = true, restoring = true}

-- Compact alternatives (DestinationFields only). Display metadata: the value
-- and tooltip stay the authoritative disclosure and grant no assignment.
-- compact is a complete shorter value (a bare name stays whole); the state
-- and Wishlist cells' minimum is their shortest atomic alternative, for a
-- cell too narrow for compact. Both are chosen from the descriptor codes,
-- never cut from or parsed out of the worded value, and a state label is
-- shown whole. A Wishlist meaning word precedes its name, so a shortened name
-- never reads as assigned; only an assigned Wishlist shows its name alone.
-- A Wishlist minimum is that assigned name, else its meaning marker alone.
-- Compressed markers (each disclosed in full by the tooltip):
--   "?"        not known or not confirmed (never unassigned, first-run or active)
--   "#2 Name"  Saved Build slot 2, then its name
--   "On"/"Off" the Saved Build is / is not active in the game
--   "N/A"      unavailable right now
--   "Empty"    the Saved Build holds no Echoes, so any assignment is refused
--   "1st"      first-run target (no Saved Build in use)
--   "Wait"     the saved assignment is being restored
--   "None"     nothing captured
--   "P"        Preview (d.preview): a Community Build preview is shown
-- One-glyph marks, for a captured or Preview state (state) and for a
-- Wishlist minimum without a shown name (Wishlist); "?" keeps the meaning
-- above:
--   "+"  state: active in the game      Wishlist: assigned
--   "-"  state: not active in the game  Wishlist: none assigned
--   "x"  state and Wishlist: unavailable right now
--   "~"  state and Wishlist: the saved assignment is being restored
--   "0"  state: empty, the Saved Build holds no Echoes
--   "1"  state: first-run target (no Saved Build in use)
--   "!"  Wishlist: refused, the Saved Build is explicitly empty (no Echoes)
--   "_"  state: nothing captured ("none"), in a Preview minimum only
-- A captured state minimum is "C:" then its state record's mark, 3 glyphs
-- ("C:+", "C:0", "C:?", ...): the capture and each state stay visible, and
-- being captured is not evidence of the current assignment. A Preview
-- state minimum is its own atomic alternative, at most 3 glyphs: "P",
-- then "C" when captured, then that mark ("P+", "P1", "PC0", "PC?", ...),
-- so Preview, the capture and each state stay visible. A "none"
-- destination is never captured; its only mark is "_", in that Preview
-- minimum ("P_"). No mark is a pipe or a control character; each is
-- chosen from the descriptor codes, never cut from or parsed out of the
-- worded value.
-- Worded markers are {key, English} (Pick); the one-glyph marks and "?" are
-- code-owned glyphs, the same in every language. The "C:", "P" and "PC"
-- prefixes are keyed templates around the mark.
local SAVED_BUILD_STATE_COMPACT = {
    unavailable = {compact = {"usertext.value.compact_build_unavailable", "Unavailable"},
        minimum = {"usertext.value.minimum_build_unavailable", "N/A"}, mark = "x"},
    empty = {compact = {"usertext.value.compact_build_empty", "Empty"},
        minimum = {"usertext.value.minimum_build_empty", "Empty"}, mark = "0"},
    active = {compact = {"usertext.value.compact_build_active", "Active"},
        minimum = {"usertext.value.minimum_build_active", "On"}, mark = "+"},
    inactive = {compact = {"usertext.value.compact_build_inactive", "Inactive"},
        minimum = {"usertext.value.minimum_build_inactive", "Off"}, mark = "-"},
    unconfirmed = {compact = {"usertext.value.compact_build_unconfirmed", "Unconfirmed"}, minimum = "?", mark = "?"},
    notStated = {compact = {"usertext.value.compact_build_not_known", "Not known"}, minimum = "?", mark = "?"},
}
local DESTINATION_COMPACT = {
    firstRun = {build = {"usertext.value.compact_dest_build_none", "None"},
        compact = {"usertext.value.compact_dest_first_run", "First run"},
        minimum = {"usertext.value.minimum_dest_first_run", "1st"}, mark = "1"},
    restoring = {build = "?", compact = {"usertext.value.compact_dest_restoring", "Restoring"},
        minimum = {"usertext.value.minimum_dest_restoring", "Wait"}, mark = "~"},
    unknown = {build = "?", compact = {"usertext.value.compact_dest_not_loaded", "Not loaded"}, minimum = "?", mark = "?"},
    unconfirmed = {build = "?", compact = {"usertext.value.compact_dest_unconfirmed", "Unconfirmed"}, minimum = "?", mark = "?"},
    none = {build = "?", compact = {"usertext.value.compact_dest_none", "None"},
        minimum = {"usertext.value.minimum_dest_none", "None"}},
}
-- The one-glyph minimum mark of a stated Wishlist assignment state; an
-- assigned Wishlist with a name shows that name instead (see
-- DestinationFields). Refused is "!" and not known is "?" (see above).
local WISHLIST_MINIMUM = {
    assigned = "+", unassigned = "-", unavailable = "x", restoring = "~",
}
-- A stated Wishlist assignment state in compact words.
local function WishlistCompact(wishlist, state)
    if state == "assigned" then
        return wishlist or Say("usertext.value.compact_wishlist_assigned", "Assigned")
    elseif state == "unassigned" then
        return Say("usertext.value.compact_wishlist_none", "None")
    elseif state == "unavailable" then
        return wishlist and SayF("usertext.value.compact_wishlist_unavailable_named", {name = wishlist}, "N/A: " .. wishlist)
            or Say("usertext.value.compact_wishlist_unavailable", "N/A")
    elseif state == "restoring" then
        return Say("usertext.value.compact_wishlist_restoring", "Restoring")
    end
    return wishlist and SayF("usertext.value.compact_wishlist_unknown_named", {name = wishlist}, "?: " .. wishlist) or "?"
end

-- The descriptor's facts as codes and display-safe names. The Saved Build
-- state keeps one order: unavailable, empty, active, not active,
-- unconfirmed, else not stated.
local function DestinationParts(d)
    local p = {character = T.SafeName(d.character)}
    if d.kind == "savedBuild" then
        p.kind = "savedBuild"
        p.label = T.SavedBuildLabel(d.slot, d.name)
        if d.unavailable then
            p.state = "unavailable"
        elseif d.empty then
            p.state = "empty"
        elseif d.active == true then
            p.state = "active"
        elseif d.active == false then
            p.state = "inactive"
        elseif d.unconfirmed then
            p.state = "unconfirmed"
        end
    elseif d.kind == "firstRun" or d.kind == "unconfirmed" then
        p.kind = d.kind
    elseif d.kind == "unknown" then
        p.kind = d.reason == "restoring" and "restoring" or "unknown"
    else
        p.kind = "none"
    end
    p.wishlist = T.SafeName(d.wishlist)
    return p
end

-- The Wishlist words for one assignment state, or the name alone when no
-- known state is given (nil when there is neither). cell: the words stand
-- alone as a cell value (raised first letter) rather than after "Wishlist: ".
local function WishlistWords(wishlist, state, cell)
    if state == "assigned" then
        if wishlist then return SayF("usertext.value.wishlist_assigned_named", {name = wishlist}, wishlist .. " (assigned)") end
        return cell and Say("usertext.value.wishlist_assigned_cell", "Assigned")
            or Say("usertext.value.wishlist_assigned", "assigned")
    elseif state == "unassigned" then
        return cell and Say("usertext.value.wishlist_none_assigned_cell", "None assigned")
            or Say("usertext.value.wishlist_none_assigned", "none assigned")
    elseif state == "unavailable" then
        if wishlist then
            return SayF("usertext.value.wishlist_unavailable_named", {name = wishlist}, wishlist .. " - unavailable right now")
        end
        return cell and Say("usertext.value.wishlist_unavailable_cell", "Unavailable right now")
            or Say("usertext.value.wishlist_unavailable", "unavailable right now")
    elseif state == "restoring" then
        return cell and Say("usertext.value.wishlist_restoring_cell", "Restoring the saved assignment")
            or Say("usertext.value.wishlist_restoring", "restoring the saved assignment")
    end
    return wishlist
end

-- The captured destination of a view, confirmation or result, as lines.
-- d.kind: "savedBuild", "firstRun", "unknown" (Saved Build data not loaded;
-- d.reason "restoring": the saved assignment is being restored),
-- "unconfirmed" (neither first-run nor a Saved Build can be confirmed) or
-- anything else (nothing captured). d.slot / d.name: the Saved Build.
-- d.active: true or false only when the caller knows it. d.unconfirmed: a
-- Saved Build's plan whose Saved Build is not confirmed as the active one
-- (no verified active row). d.empty: a numbered Saved Build that holds no
-- Echoes. d.unavailable: it cannot be read now.
-- d.character: an owner/character label the caller holds. d.wishlist and
-- d.wishlistState ("assigned", "unassigned", "unavailable", "restoring" or
-- nil when unknown). The destination is always the one the caller captured;
-- this function never looks up a currently active slot.
-- d.captured is read only by DestinationFields (below), never here.
function T.DestinationLines(d)
    d = type(d) == "table" and d or {}
    local lines = {}
    local p = DestinationParts(d)
    if p.character then
        lines[#lines + 1] = SayF("usertext.label.character_line", {name = p.character}, "Character: " .. p.character)
    end
    local destination
    if p.kind == "savedBuild" then
        local entry = SAVED_BUILD_STATE_WORDS[p.state]
        local build = p.label or Say("usertext.value.selected_build", "the selected Saved Build")
        if entry then
            local state = StateWords(entry, false)
            destination = SayF("usertext.value.build_with_state", {build = build, state = state}, build .. " - " .. state)
        else
            destination = build
        end
    else
        destination = StateWords(DESTINATION_WORDS[p.kind].state, false)
    end
    lines[#lines + 1] = SayF("usertext.label.destination_line", {destination = destination}, "Destination: " .. destination)
    local wishlist = WishlistWords(p.wishlist, d.wishlistState)
    if wishlist then
        lines[#lines + 1] = SayF("usertext.label.wishlist_line", {wishlist = wishlist}, "Wishlist: " .. wishlist)
    end
    return lines
end

-- The same descriptor as four cells for a one-line strip, always in this
-- order: character, savedBuild, wishlist, state. Each record is
-- {key, label, value}; the second result is the complete tooltip, one
-- labeled line per cell (and a note when captured). Every cell has a value:
-- an unknown is "not known", never unassigned, first-run or active, and a
-- Wishlist name alone is never called assigned. An empty Saved Build has no
-- valid assignment, whatever Wishlist state is passed.
-- d.captured == true (explicit only; never inferred, for example from a
-- missing active slot): the caller shows a destination it captured earlier,
-- with d.wishlist the captured Wishlist name when it has one. That states
-- only that it was captured, not that it is assigned now: unless
-- d.wishlistState states the assignment, the state says it is not checked.
-- Plain words (owner-approved usability item 6, 2026-10-30): "assigned now"
-- is the current link a caller states (d.wishlistState "assigned");
-- "captured" is the destination held when an edit or view opened. The
-- captured words and hover say it is not checked as assigned now, and
-- neither is ever called "in use".
-- Value contract: each value is the complete display-safe text (whole
-- SafeName output, in which a literal pipe is already the escaped pair
-- "||"). A later fitting step shows it as it is, or shortens it only at a
-- UTF-8 character boundary that does not split an escaped pipe pair; it
-- never sanitizes or escapes it again, and the tooltip keeps the whole text.
-- Each record also has compact, a complete shorter value, and the state and
-- Wishlist records have minimum, their shortest atomic alternative (see the
-- compact markers above).
function T.DestinationFields(d)
    d = type(d) == "table" and d or {}
    local p = DestinationParts(d)
    local captured = d.captured == true and p.kind ~= "none"
    local build, stateWords, buildCompact, stateShort
    if p.kind == "savedBuild" then
        local name, slot = T.SafeName(d.name), Whole(d.slot)
        if slot and slot < 1 then slot = nil end
        if name and slot then
            build = SayF("usertext.value.build_name_slot", {name = name, slot = tostring(slot)},
                name .. " (slot " .. slot .. ")")
            buildCompact = SayF("usertext.value.compact_build_name_slot", {name = name, slot = tostring(slot)},
                "#" .. slot .. " " .. name)
        elseif slot then
            build = SayF("usertext.value.build_slot", {slot = tostring(slot)}, "Slot " .. slot)
            buildCompact = SayF("usertext.value.compact_build_slot", {slot = tostring(slot)}, "#" .. slot)
        else
            build = name or Say("usertext.value.selected_build_cell", "The selected Saved Build")
            buildCompact = name or Say("usertext.value.compact_build_selected", "Selected")
        end
        stateWords = SAVED_BUILD_STATE_WORDS[p.state] or BUILD_STATE_NOT_KNOWN
        stateShort = SAVED_BUILD_STATE_COMPACT[p.state] or SAVED_BUILD_STATE_COMPACT.notStated
    else
        build = Pick(DESTINATION_WORDS[p.kind].build)
        stateWords = DESTINATION_WORDS[p.kind].state
        buildCompact = Pick(DESTINATION_COMPACT[p.kind].build)
        stateShort = DESTINATION_COMPACT[p.kind]
    end
    local noAssignment = p.kind == "savedBuild" and d.empty and true or false
    local stated = WISHLIST_STATES[d.wishlistState] == true
    -- minimum: the refusal, stated or unknown marker alone (unknown is "?",
    -- never unassigned); only a stated assigned Wishlist keeps its
    -- display-safe name, which is never cut or sanitized again here.
    local wishlist, wishlistCompact, wishlistMinimum
    if noAssignment then
        wishlist = p.wishlist and SayF("usertext.value.wishlist_refused_named", {name = p.wishlist},
                p.wishlist .. " - no valid assignment (the Saved Build holds no Echoes)")
            or Say("usertext.value.wishlist_refused", "No valid assignment (the Saved Build holds no Echoes)")
        wishlistCompact = p.wishlist and SayF("usertext.value.compact_wishlist_refused_named", {name = p.wishlist},
                "Refused: " .. p.wishlist)
            or Say("usertext.value.compact_wishlist_refused", "Refused")
        wishlistMinimum = "!"
    elseif stated then
        wishlist = WishlistWords(p.wishlist, d.wishlistState, true)
        wishlistCompact = WishlistCompact(p.wishlist, d.wishlistState)
        wishlistMinimum = d.wishlistState == "assigned" and p.wishlist
            or WISHLIST_MINIMUM[d.wishlistState]
    elseif p.wishlist then
        -- Captured is the Wishlist held when the edit or view opened, never a
        -- current link; it says so instead of calling it assigned or in use.
        wishlist = captured and SayF("usertext.value.wishlist_captured_named", {name = p.wishlist},
                p.wishlist .. " (captured; not checked as assigned now)")
            or SayF("usertext.value.wishlist_unknown_named", {name = p.wishlist}, p.wishlist .. " (assignment not known)")
        wishlistCompact = SayF("usertext.value.compact_wishlist_unknown_named", {name = p.wishlist}, "?: " .. p.wishlist)
        wishlistMinimum = "?"
    else
        wishlist = Say("usertext.value.wishlist_not_known", "Not known")
        wishlistCompact = "?"
        wishlistMinimum = "?"
    end
    local state, stateCompact, stateMinimum
    if captured then
        local words = StateWords(stateWords, false)
        if noAssignment or stated then
            state = SayF("usertext.value.state_captured", {state = words}, "Captured; " .. words)
        else
            state = SayF("usertext.value.state_captured_unchecked", {state = words},
                "Captured; " .. words .. "; not checked as assigned now")
        end
        -- "C:" keeps the capture visible; the state record's one-glyph mark
        -- keeps each state distinct, 3 glyphs in all (see the markers above).
        -- A captured first-run plan keeps its whole "first-run target" label
        -- (T.Terms.firstRun) in compact; its minimum stays "C:1".
        if p.kind == "firstRun" then
            stateCompact = Say("usertext.value.compact_state_captured_first_run", "Captured: first-run target")
        else
            local compact = Pick(stateShort.compact)
            stateCompact = SayF("usertext.value.compact_state_captured", {state = compact}, "Captured: " .. compact)
        end
        stateMinimum = SayF("usertext.value.minimum_state_captured", {mark = stateShort.mark}, "C:" .. stateShort.mark)
    else
        state = StateWords(stateWords, true)
        stateCompact, stateMinimum = Pick(stateShort.compact), Pick(stateShort.minimum)
    end
    -- d.preview == true (explicit only): the view shows a Community Build
    -- preview, not this destination's plan. Presentation only: the full and
    -- compact state keep the underlying state whole after a Preview
    -- designation, so the preview stays visible at every width and is
    -- never called assigned; the other facts are worded as given. The
    -- minimum is its own atomic alternative (see the markers above), chosen
    -- from the codes alone: "P", then "C" when captured, then the state
    -- record's mark, or "_" for a "none" destination (never captured).
    local preview = d.preview == true
    if preview then
        state = SayF("usertext.value.state_preview", {state = state}, "Preview; " .. state)
        stateCompact = SayF("usertext.value.compact_state_preview", {state = stateCompact}, "Preview: " .. stateCompact)
        local mark = p.kind == "none" and "_" or stateShort.mark
        stateMinimum = captured
            and SayF("usertext.value.minimum_state_preview_captured", {mark = mark}, "PC" .. mark)
            or SayF("usertext.value.minimum_state_preview", {mark = mark}, "P" .. mark)
    end
    -- d.wishlistMode (optional, a string already worded for display): what
    -- this destination uses instead of a Wishlist (Auto-pick by rarity with
    -- its state). The caller gives it only for a destination positively
    -- known to have nothing assigned. It takes the Wishlist cell at its full
    -- and compact widths; the assignment fact it replaces stays on the hover.
    local modeFact
    if type(d.wishlistMode) == "string" and d.wishlistMode ~= "" then
        modeFact = wishlist
        wishlist, wishlistCompact = d.wishlistMode, d.wishlistMode
    end
    local fields = {
        {key = "character", label = Say("usertext.label.field_character", "Character"),
            value = p.character or Say("usertext.value.character_not_known", "Not known"),
            compact = p.character or "?"},
        {key = "savedBuild", label = Say("usertext.label.field_saved_build", "Saved Build"), value = build,
            compact = buildCompact},
        {key = "wishlist", label = Say("usertext.label.field_wishlist", "Wishlist"), value = wishlist,
            compact = wishlistCompact, minimum = wishlistMinimum},
        {key = "state", label = Say("usertext.label.field_state", "State"), value = state,
            compact = stateCompact, minimum = stateMinimum},
    }
    local tooltip = {}
    for index = 1, #fields do
        local label, value = fields[index].label, fields[index].value
        tooltip[index] = SayF("usertext.tooltip.field_line", {label = label, value = value}, label .. ": " .. value)
    end
    if modeFact then
        tooltip[#tooltip + 1] = SayF("usertext.tooltip.field_line", {label = fields[3].label, value = modeFact},
            fields[3].label .. ": " .. modeFact)
    end
    if captured then
        -- The assignment words follow the facts given with it (review
        -- SPEC-GH-1): an empty Saved Build's refusal and a stated
        -- d.wishlistState are kept as given; only an unstated one is called
        -- not checked. Nothing is looked up here. Two sentences, joined by
        -- this code with one space.
        local assignment
        if noAssignment then
            assignment = Say("usertext.tooltip.captured_refused",
                "Assigning to it is refused: the Saved Build holds no Echoes.")
        elseif stated then
            assignment = Say("usertext.tooltip.captured_stated",
                "Its Wishlist line gives the assignment as stated for it; assigned now means the current link, which the Nexus panel shows.")
        else
            assignment = Say("usertext.tooltip.captured_unchecked",
                "It is not checked as assigned now: assigned now means the current link, which the Nexus panel shows.")
        end
        tooltip[#tooltip + 1] = Say("usertext.tooltip.captured_lead",
            "Captured: shown as captured earlier, the destination held when this edit or view opened.")
            .. " " .. assignment
    end
    if preview then
        tooltip[#tooltip + 1] = Say("usertext.tooltip.preview",
            "Preview: a Community Build preview is shown; it is not this destination's assignment.")
    end
    return fields, tooltip
end

-- M7: the setup checklist, worded from current facts only (Panel.SetupFacts).
-- Steps: start-up, the destination Nexus would act on and its Wishlist. Each
-- row is {key, label, status, text}; status is "done", "todo", "waiting" or
-- "unknown". Loading, restoring, unavailable and not-known are never "done",
-- and whether the Welcome was seen or closed is not a fact here. complete is
-- true only when all three steps are done now. key and status are the codes
-- callers act on; label and text are display words only.
local CHECK_MARK_WORDS = {done = {"usertext.label.mark_done", "[done]"}, todo = {"usertext.label.mark_todo", "[to do]"},
    waiting = {"usertext.label.mark_waiting", "[waiting]"}, unknown = {"usertext.label.mark_not_known", "[not known]"},
    info = {"usertext.label.mark_info", "[info]"}}
-- Read at display time: T.CHECK_MARKS[status] is that status's mark.
T.CHECK_MARKS = setmetatable({}, {__index = function(_, status)
    local entry = CHECK_MARK_WORDS[status]
    return entry and Say(entry[1], entry[2]) or nil
end})
function T.SetupChecklist(f)
    f = type(f) == "table" and f or {}
    local rows = {}
    local function row(key, label, status, text)
        rows[#rows + 1] = {key = key, label = label, status = status, text = text}
    end
    local startup = Say("usertext.label.setup_startup", "Start-up")
    local destinationLabel = Say("usertext.label.setup_destination", "Destination")
    local wishlistLabel = Say("usertext.label.setup_wishlist", "Wishlist")
    if f.startup == "ready" then
        row("startup", startup, "done", Say("usertext.status.setup_startup_ready", "Local saved data is restored."))
    elseif f.startup == "loading" then
        row("startup", startup, "waiting", Say("usertext.status.setup_startup_loading",
            "Local saved data is still being restored (see the loading panel)."))
    else
        row("startup", startup, "unknown", Say("usertext.status.setup_startup_unknown", "Start-up status cannot be read."))
    end
    local d = type(f.destination) == "table" and f.destination or nil
    if f.startup ~= "ready" then
        local text = Say("usertext.status.setup_after_startup", "Not known until start-up finishes.")
        row("destination", destinationLabel, "unknown", text)
        row("wishlist", wishlistLabel, "unknown", text)
        return {rows = rows, complete = false}
    end
    if not d then
        local text = Say("usertext.status.setup_no_run_shown", "The Nexus panel has not shown a run yet.")
        row("destination", destinationLabel, "unknown", text)
        row("wishlist", wishlistLabel, "unknown", text)
        return {rows = rows, complete = false}
    end
    local label = T.SavedBuildLabel(d.slot, d.name)
    local destinationDone = false
    if d.kind == "savedBuild" and d.empty then
        local tail = " holds no Echoes, so a Wishlist cannot be assigned to it. Load a Saved Build that holds Echoes in the game's build window."
        row("destination", destinationLabel, "todo", label
            and SayF("usertext.status.setup_dest_empty_named", {build = label}, label .. tail)
            or Say("usertext.status.setup_dest_empty", "The selected Saved Build" .. tail))
    elseif d.kind == "savedBuild" and d.unavailable then
        row("destination", destinationLabel, "unknown", label
            and SayF("usertext.status.setup_dest_unavailable_named", {build = label}, label .. " is not available right now.")
            or Say("usertext.status.setup_dest_unavailable", "The Saved Build is not available right now."))
    elseif d.kind == "savedBuild" and d.active == true then
        destinationDone = true
        row("destination", destinationLabel, "done", label
            and SayF("usertext.status.setup_dest_active_named", {build = label}, label .. " is active in the game.")
            or Say("usertext.status.setup_dest_active", "A Saved Build is active in the game."))
    elseif d.kind == "savedBuild" then
        row("destination", destinationLabel, "unknown", Say("usertext.status.setup_dest_unconfirmed",
            "A Saved Build's plan is in use, but which Saved Build is active is not confirmed."))
    elseif d.kind == "firstRun" then
        destinationDone = true
        row("destination", destinationLabel, "done", Say("usertext.status.setup_dest_first_run",
            "The first-run target (no Saved Build in use)."))
    elseif d.kind == "unknown" then
        row("destination", destinationLabel, "waiting", d.reason == "restoring"
            and Say("usertext.status.setup_dest_restoring", "Not known yet: the saved assignment is being restored.")
            or Say("usertext.status.setup_dest_not_loaded", "Not known yet: Saved Build data is not loaded."))
    else
        row("destination", destinationLabel, "unknown", Say("usertext.status.setup_dest_not_confirmed", "Not confirmed right now."))
    end
    local wishlist = T.SafeName(d.wishlist)
    local state = d.wishlistState
    local wishlistDone = false
    if d.empty then
        row("wishlist", wishlistLabel, "todo", Say("usertext.status.setup_wishlist_needs_build",
            "Needs a Saved Build that holds Echoes first."))
    elseif state == "assigned" then
        wishlistDone = true
        row("wishlist", wishlistLabel, "done", wishlist
            and SayF("usertext.status.setup_wishlist_assigned_named", {name = wishlist}, "'" .. wishlist .. "' is assigned.")
            or Say("usertext.status.setup_wishlist_assigned", "A Wishlist is assigned."))
    elseif state == "unassigned" then
        row("wishlist", wishlistLabel, "todo", Say("usertext.status.setup_wishlist_none",
            "None assigned. Assign Wishlist... opens the chooser; nothing is assigned until you choose. No Wishlist yet? Create one in the Wishlist Editor."))
    elseif state == "restoring" then
        row("wishlist", wishlistLabel, "waiting", Say("usertext.status.setup_wishlist_restoring",
            "The saved assignment is being restored."))
    elseif state == "unavailable" then
        row("wishlist", wishlistLabel, "unknown", wishlist
            and SayF("usertext.status.setup_wishlist_unavailable_named", {name = wishlist},
                "'" .. wishlist .. "' is unavailable right now.")
            or Say("usertext.status.setup_wishlist_unavailable", "The assignment is unavailable right now."))
    else
        row("wishlist", wishlistLabel, "unknown", Say("usertext.status.setup_wishlist_not_known", "Not known right now."))
    end
    return {rows = rows, complete = f.startup == "ready" and destinationDone and wishlistDone}
end

-- M7: Auto, Sync and Orb status as information lines (not setup steps). OFF
-- and no Orb run are complete answers; an unread fact says it is not known.
local SYNC_MODE_LINES = {
    automatic = {"usertext.status.sync_automatic", "Sync: Automatic. Nexus may send shared builds and DPS records without a click; what is sent may reach no one."},
    manual = {"usertext.status.sync_manual", "Sync: Manual. Nexus sends only what you start (Sync Now or Share)."},
    off = {"usertext.status.sync_off", "Sync: Off. Nexus sends nothing; local records are kept."},
}
-- The Orb line. orb: false (an observed owner with no approved run), nil
-- (unknown; observed false: the owner was not read this session, so an
-- unresolved earlier action is not ruled out) or the plain facts of
-- Panel.SetupFacts. The reason is the text the Orb owner last recorded for its
-- run, said as that and never as a fresh check; the operation is the run's
-- recorded name, never a Resume target. Open Orbs reviews the current state.
-- The recorded reason, operation and an unlisted state code are inserted
-- verbatim; the sentences around them are keyed and joined with one space.
local ORB_STATE_WORDS = {PAUSED = {"usertext.status.orb_state_paused", "run paused"},
    STOPPED = {"usertext.status.orb_state_stopped", "run stopped"},
    LIMIT = {"usertext.status.orb_state_limit", "run stopped at its approved maximum"},
    FINISHED = {"usertext.status.orb_state_finished", "run finished"},
    COMPLETE = {"usertext.status.orb_state_complete", "run ended: its selected targets were met"},
    ROLLED_COMPLETE = {"usertext.status.orb_state_rolled_complete", "run ended: its rolled targets were met"},
    OUT_OF_ORBS = {"usertext.status.orb_state_out_of_orbs", "run ended: no Orbs were left"},
    NO_SOURCES = {"usertext.status.orb_state_no_sources", "run ended: no safe source copies were left"}}
local ORB_REASON_CHARS, ORB_NAME_CHARS = 280, 60
local function OrbLine(orb, observed)
    if orb == false then
        return Say("usertext.status.orb_none_approved", "Orbs (optional): no Orb run approved this session.")
    end
    if type(orb) ~= "table" then
        if observed == false then
            return Say("usertext.status.orb_not_read",
                "Orbs (optional): not known. Orb status has not been read this session, so an unresolved earlier Orb action is not ruled out. Open Orbs to check.")
        end
        return Say("usertext.status.orb_status_not_known", "Orbs (optional): status not known right now.")
    end
    local state = type(orb.state) == "string" and orb.state:match("^[%u_]+$") or nil
    -- unresolved is decided from the facts, never by comparing worded text.
    local head, unresolved
    if orb.running == true then head = Say("usertext.status.orb_state_running", "run running")
    elseif orb.restored == true or state == "RECOVERY" then
        unresolved = true
        head = Say("usertext.status.orb_state_unresolved", "an earlier Orb action is unresolved")
    elseif state and ORB_STATE_WORDS[state] then head = Pick(ORB_STATE_WORDS[state])
    elseif state then head = SayF("usertext.status.orb_state_code", {code = state}, "run in state " .. state)
    else head = Say("usertext.status.orb_state_not_known", "run state not known") end
    local line
    if orb.pending == true and not unresolved then
        line = SayF("usertext.status.orb_line_pending", {state = head}, "Orbs (optional): " .. head .. "; a result is pending.")
    else
        line = SayF("usertext.status.orb_line", {state = head}, "Orbs (optional): " .. head .. ".")
    end
    local operation = orb.pending == true and type(orb.operation) == "string"
        and T.SafeName(orb.operation, ORB_NAME_CHARS) or nil
    if operation then
        line = line .. " " .. SayF("usertext.status.orb_operation", {name = operation},
            "Original operation (as recorded): '" .. operation .. "'.")
    end
    local reason = type(orb.reason) == "string" and T.SafeName(Utf8Cut(orb.reason, ORB_REASON_CHARS)) or nil
    if reason then
        if not reason:find("[%.!?]$") then reason = reason .. "." end
        line = line .. " " .. SayF("usertext.status.orb_last_reason", {reason = reason}, "Last reason Nexus recorded: " .. reason)
    end
    return line .. " " .. Say("usertext.status.orb_review", "Open Orbs to review it now and see the actions available there.")
end
function T.StatusLines(f)
    f = type(f) == "table" and f or {}
    local lines = {}
    if f.auto == true then
        local held = T.SafeName(f.autoNote or f.paused, 200)
        lines[#lines + 1] = held and SayF("usertext.status.auto_on_held", {reason = held}, "Auto: ON - not acting now: " .. held)
            or Say("usertext.status.auto_on", "Auto: ON")
    elseif f.auto == false then
        lines[#lines + 1] = Say("usertext.status.auto_off",
            "Auto: OFF. Recommendations only; turning Auto ON is your choice (read its warning first).")
    else
        lines[#lines + 1] = Say("usertext.status.auto_not_known", "Auto: not known right now.")
    end
    local sync = f.syncMode ~= nil and SYNC_MODE_LINES[f.syncMode] or nil
    if sync then
        local line = Pick(sync)
        lines[#lines + 1] = f.syncExplicit == false
            and SayF("usertext.status.sync_not_saved_choice", {line = line}, line .. " (Not a choice you saved.)")
            or line
    else
        lines[#lines + 1] = Say("usertext.status.sync_not_known", "Sync: mode not known right now.")
    end
    lines[#lines + 1] = OrbLine(f.orb, f.orbObserved)
    return lines
end

-- One count vocabulary. These are different units and are never merged:
-- planned copies (the plan), rolled copies this run, the Wishlist's copies
-- found in a Saved Build, locked targets, and Echo families represented (a
-- family counts once whatever its copies). Each unit has its own keys: the
-- bare unit, its "have / want" line and its unavailable line (a whole
-- sentence per unit, so a translation can agree the unit with its numbers).
-- An unknown kind keeps the plain "copies" wording.
local COUNT_KINDS = {
    planned = {unit = "count.planned_copies", english = "rolled copies planned", progress = "count.planned_progress",
        unavailable = "count.planned_unavailable", unavailableEnglish = "Rolled copies planned: unavailable"},
    run = {unit = "count.run_copies", english = "rolled copies this run", progress = "count.run_progress",
        unavailable = "count.run_unavailable", unavailableEnglish = "Rolled copies this run: unavailable"},
    savedBuild = {unit = "count.saved_build_copies", english = "Wishlist copies in this Saved Build",
        progress = "count.saved_build_progress", unavailable = "count.saved_build_unavailable",
        unavailableEnglish = "Wishlist copies in this Saved Build: unavailable"},
    locked = {unit = "count.locked_targets", english = "locked targets", progress = "count.locked_progress",
        unavailable = "count.locked_unavailable", unavailableEnglish = "Locked targets: unavailable"},
    families = {unit = "count.echo_families", english = "Echo families represented", progress = "count.families_progress",
        unavailable = "count.families_unavailable", unavailableEnglish = "Echo families represented: unavailable"},
}
local COUNT_COPIES = {english = "copies", progress = "count.copies_progress",
    unavailable = "count.copies_unavailable", unavailableEnglish = "Copies: unavailable"}
-- Read at display time: T.COUNT_UNITS[kind] is that unit's words.
T.COUNT_UNITS = setmetatable({}, {__index = function(_, kind)
    local entry = kind ~= nil and COUNT_KINDS[kind] or nil
    return entry and Say(entry.unit, entry.english) or nil
end})

-- "12 / 79 rolled copies this run", or "Rolled copies this run: unavailable"
-- when either side is unknown (never 0 / 0 or a guessed total).
function T.CountText(kind, have, want)
    local entry = kind ~= nil and COUNT_KINDS[kind] or COUNT_COPIES
    local h, w = Whole(have), Whole(want)
    if h == nil or w == nil or w <= 0 then
        return Say(entry.unavailable, entry.unavailableEnglish)
    end
    return SayF(entry.progress, {have = h, want = w}, h .. " / " .. w .. " " .. entry.english)
end

-- The run's own progress line. Locked targets still to lock are said; the
-- word "complete" is never used here (ProgressComplete decides that).
-- `compact` gives the short form for a narrow line (still qualified).
function T.RunProgressText(have, want, lockedOutstanding, compact)
    local h, w, outstanding = Whole(have), Whole(want), Whole(lockedOutstanding)
    if h == nil or w == nil or w <= 0 then
        if compact then return Say("count.rolled_unavailable_compact", "Rolled: unavailable") end
        return Say("count.run_unavailable", "Rolled copies this run: unavailable")
    end
    if outstanding and outstanding > 0 then
        local args = {have = h, want = w, outstanding = outstanding}
        if compact then
            return SayF("count.run_to_lock_compact", args, h .. " / " .. w .. " rolled, " .. outstanding .. " to lock")
        end
        return SayF("count.run_to_lock", args, h .. " / " .. w .. " rolled, " .. outstanding .. " still to lock")
    end
    if compact then return SayF("count.run_progress_compact", {have = h, want = w}, h .. " / " .. w .. " rolled") end
    return SayF("count.run_progress", {have = h, want = w}, h .. " / " .. w .. " rolled copies this run")
end

-- Complete only when the rolled copies are met AND no locked target is
-- outstanding; an unknown on either side is not complete.
function T.ProgressComplete(have, want, lockedOutstanding)
    local h, w, outstanding = Whole(have), Whole(want), Whole(lockedOutstanding)
    return h ~= nil and w ~= nil and w > 0 and h >= w and outstanding ~= nil and outstanding == 0
end

-- Record scope (DPS records and leaderboards): what this client holds, not a
-- complete or server-wide ranking. T.BEST_KNOWN, T.RECORD_SCOPE,
-- T.LEADERBOARD_SCOPE and T.GLOSSARY are read at display time (the metatable
-- of T below), so they show the active language.
local BEST_KNOWN = {"term.best_known", "Best known"}
local RECORD_SCOPE = {"usertext.note.record_scope", "Best known: the best shared record this client holds for these exact Echoes. "
    .. "It is not a complete or server-wide ranking."}
local LEADERBOARD_SCOPE = {"usertext.label.leaderboard_scope", "Best known exact loadout per character"}

function T.CategoryName(category)
    if category == "lk" then return Say("usertext.label.category_lich_king", "Lich King") end
    if category == "dummy" then return Say("usertext.label.category_training_dummy", "Training Dummy") end
    if category == "combined" then return Say("usertext.label.category_both", "Both records") end
    return nil
end

-- The facts a record genuinely carries: its category, a positive fight
-- duration, a positive level and a recorded date. A missing or zero value is
-- left out, never shown as 0 or as a dash that reads like a value.
function T.RecordDetailParts(row)
    row = type(row) == "table" and row or {}
    local parts = {}
    local category = T.CategoryName(row.category)
    if category then parts[#parts + 1] = category end
    local duration = Whole(row.duration)
    if duration and duration > 0 then
        local shown = string.format("%d:%02d", math.floor(duration / 60), duration % 60)
        parts[#parts + 1] = SayF("usertext.value.fight_duration", {duration = shown}, shown .. " fight")
    end
    local level = Whole(row.level)
    if level and level > 0 then
        parts[#parts + 1] = SayF("usertext.value.record_level", {level = tostring(level)}, "Level " .. level)
    end
    local stamp = Whole(row.ts)
    local formatDate = (type(date) == "function" and date) or (type(os) == "table" and os.date) or nil
    if stamp and stamp > 0 and formatDate then
        local ok, text = pcall(formatDate, "!%Y-%m-%d", stamp)
        if ok and type(text) == "string" and text ~= "" then
            parts[#parts + 1] = SayF("usertext.value.recorded_date", {date = text}, "Recorded " .. text .. " (UTC)")
        end
    end
    return parts
end

-- The record's own owner flag: verified, not established, or nothing when
-- the record does not say (unknown is not presented as either).
function T.OwnerLine(row)
    if type(row) ~= "table" then return nil end
    if row.ownerVerified == true then return Say("usertext.label.owner_verified", "Owner verified") end
    if row.ownerVerified == false then
        return Say("usertext.label.owner_not_established", "Owner identity not established")
    end
    return nil
end

-- One user meaning per label (UX-15). Internal identifiers, protocol fields
-- and saved-data names keep their own spelling and are not listed here.
-- Read at display time: T.Terms[name] is that term's words.
local TERMS = {
    -- Issue #165: the panel's menu button shows "Options" (ui/Panel.lua
    -- OptionsLabel, localized as panel.button.options); its hover carries the
    -- status. The old key name is kept for existing readers; it now holds the
    -- visible name, never the retired "Menu and status" or a bare ellipsis.
    options = {"term.options", "Options"},
    menuAndStatus = {"term.options", "Options"},
    bestKnown = BEST_KNOWN,
    showRecords = {"term.show_records", "Show DPS records"},
    -- The game's own page that lists your Saved Builds.
    myBuildsPage = {"term.my_builds", "My Builds"},
    -- The Build Library scope that lists your Saved Builds and shared listings
    -- (internal scope key "mine").
    mineScope = {"term.mine_scope", "Mine"},
    firstRun = {"term.first_run_target", "first-run target"},
}
T.Terms = setmetatable({}, {__index = function(_, name)
    local entry = name ~= nil and TERMS[name] or nil
    return entry and Say(entry[1], entry[2]) or nil
end})
local GLOSSARY = {"usertext.body.glossary", "Counts: planned copies (the plan), rolled copies this run, the Wishlist's copies in a Saved Build "
    .. "and locked targets are different counts, and Echo families represented counts a family once. "
    .. "Unavailable is not 0, and a plan is not a finished build. Best known: the best shared DPS record this "
    .. "client holds for the exact same Echoes; it is not a complete or server-wide ranking. My Builds is the "
    .. "game's page of your Saved Builds; in Build Library, the Mine scope lists your Saved Builds and "
    .. "shared listings. Options: the Options button on the Nexus panel header opens its menu of direct "
    .. "choices; point at it for the current status."}
local DISPLAY_FIELDS = {BEST_KNOWN = BEST_KNOWN, RECORD_SCOPE = RECORD_SCOPE,
    LEADERBOARD_SCOPE = LEADERBOARD_SCOPE, GLOSSARY = GLOSSARY}
setmetatable(T, {__index = function(_, name)
    local entry = name ~= nil and DISPLAY_FIELDS[name] or nil
    return entry and Say(entry[1], entry[2]) or nil
end})

------------------------------------------------------------------------
-- Guided setup coach copy (ui/GuidedSetup.lua, issue #131), from the Claude
-- Design guided-setup copy deck. English only: the localization packs do not
-- cover these strings, and no language coverage is claimed for them. Glyphs
-- are printable ASCII, always beside a word. Plain data; nothing here reads
-- or acts.
------------------------------------------------------------------------
T.Guide = {
    title = 'Nexus setup',
    charLine = '%s - Saved Builds read from Nexus',
    charUnknown = 'Character not read yet',
    kicker = 'Step %d of %d',
    kickerOptional = ' - OPTIONAL',
    labels = {welcome = 'Welcome', wishlist = 'Choose a Wishlist', target = 'Pick the Saved Build',
        assign = 'Assign & confirm', manual = 'Read a recommendation', auto = 'Auto (optional)', summary = 'Finish'},
    -- One word-plus-glyph status language (never colour alone).
    status = {
        ['not'] = {glyph = 'o', word = 'Not started'}, waiting = {glyph = '*', word = 'Needs you'},
        checking = {glyph = '...', word = 'Checking...'}, verified = {glyph = '+', word = 'Done - confirmed'},
        skipped = {glyph = '-', word = 'Skipped'}, unavailable = {glyph = '!', word = 'Unavailable'},
        stale = {glyph = '?', word = 'Unknown - re-check'}, rejected = {glyph = 'x', word = 'Declined'}},
    words = {chosen = 'Chosen', tried = 'Tried', linked = 'Already linked', draft = 'Draft - not saved',
        cancelled = 'Cancelled', review = 'Review & close', summary = 'Summary',
        leftOn = 'Left ON', leftOff = 'Left OFF', leftUnknown = 'Left alone - mode unknown', modeUnknown = 'Mode unknown'},
    -- The guide's place is kept for this character (core/GuidedSetup.lua,
    -- PlaceKept "saved"); while saved data cannot be written it is kept for
    -- this session only, and the Session words say so.
    checklistTitle = 'CHECKLIST',
    -- Setup Alternative: the header's Reference opens the optional Reference
    -- view in place of the step (help is that view's flag); All steps opens
    -- the step list; Continue later closes exactly as X does.
    buttons = {help = 'Reference', close = 'X', closeTip = 'Close (Esc) - your place is kept',
        closeTipSession = 'Close (Esc) - your place is kept until you reload or log out: saved data cannot be written right now',
        back = 'Back', later = 'Continue later',
        skip = 'Skip for now', next = 'Continue', finish = 'Close guide',
        checklistShow = 'All steps v', checklistHide = 'All steps ^', helpClose = 'X', fullHelp = 'Open full Reference',
        fullReference = 'Open full Reference', allTopics = '< All topics',
        refBack = '< Back to step %d - %s', dismissDraft = 'Pick a saved Wishlist',
        open = 'Open the Wishlist chooser', openAgain = 'Open the Wishlist chooser again', check = 'Check again',
        replace = 'Replace and continue', cancel = 'Choose another', retry = 'Try again',
        goWishlist = 'Choose a Wishlist', goTarget = 'Pick a Saved Build', goStep = 'Go to step',
        keep = 'Keep Auto %s', leave = 'Leave Auto alone', review = 'Review on the Nexus panel...', reread = 'Try reading it again',
        autoMore = '> What does Auto do?', autoLess = 'v What Auto does',
        read = 'Read', hide = 'Hide', replay = 'Run the guide again',
        checkCode = 'Check code', openDraft = 'Open it as a draft', openBuilds = 'Open My Builds',
        returnPlan = 'Return to Plan draft', planChanged = 'Keep or discard Plan draft',
        -- The bounded window's body controls (ui/GuidedSetup.lua ScreenCap).
        scrollUp = 'Scroll up (or use the mouse wheel)', scrollDown = 'Scroll down (or use the mouse wheel)'},
    -- Owner-approved usability item 5 (2026-10-30): shorter plain words. Each
    -- screen says a thing once: the navigation safety words are Welcome's
    -- WHAT YOU WILL SEE line (expect.welcome), not a second line beside it.
    safety = 'Moving between steps never assigns, spends Orbs, sends data, or changes Auto.',
    -- Setup Alternative: one short reason per step, the action under DO
    -- THIS, then the outcome slot. Only a result the guide read is WHAT HAPPENED;
    -- before that the slot says what to expect, never that it happened.
    whyLabel = 'WHY THIS MATTERS', doLabel = 'DO THIS',
    why = {welcome = 'Nexus points at Echoes from a Wishlist you choose. Nothing changes in game until you confirm a step.',
        wishlist = 'A Wishlist is the Echoes you want. Recommendations and Orb runs work from it.',
        target = 'A Saved Build is the build slot the game loads. Choose which Saved Build should use your Wishlist.',
        assign = 'Once they are linked, recommendations follow your Wishlist for the build you play.',
        manual = 'This is what Nexus points at while you roll.',
        auto = 'Auto can act for you. It is optional.',
        summary = 'See what is done and what is still open.'},
    -- A result the guide read or the player made is WHAT HAPPENED (plain
    -- words for the design's OBSERVED); before it, WHAT YOU WILL SEE.
    outcome = {expectLabel = 'WHAT YOU WILL SEE', observedLabel = 'WHAT HAPPENED', summaryLabel = 'SUMMARY',
        expect = {welcome = 'Seven short steps. Moving between steps never assigns, spends Orbs, sends data, or changes Auto.',
            wishlist = 'One Wishlist lights up and the footer shows the same name.',
            target = 'One Saved Build lights up. Nexus does not edit it.',
            assign = 'After you confirm, Nexus reads the result back. Only a confirmed result counts as done.',
            manual = 'A sample recommendation appears below. Try one pick.',
            auto = 'Auto stays as it is unless you change it yourself.',
            summary = 'Only steps Nexus confirmed are marked done. Skipped, unknown and declined steps stay open.'},
        extra = {skipped = 'Nothing was changed; this step stays open.',
            rejected = 'Nothing was changed; this step stays open.',
            unavailable = 'Nothing is marked done.', stale = 'The earlier result no longer counts.',
            waiting = 'Nothing is marked done yet.'}},
    -- The optional Reference view (Setup Alternative): a topic list, then one
    -- short article per topic in the same view; never shown under a step.
    -- Open full Reference is the separate, explicit way to the dense manual
    -- page (U.OpenHelp), which opens in place of the guide.
    reference = {title = 'Reference', tag = 'Reference - optional',
        lead = 'More detail for after setup. One topic at a time.',
        escStep = 'Esc: back to step %d', escTopics = 'Esc: back to topics',
        full = 'Open full Reference opens the complete manual page (/nexus reference) in place of this guide; close it to come back to this step.',
        topics = {
            {page = 'start', title = 'Getting started', paras = {
                'Nexus points at Echoes from a Wishlist you choose. This guide links one Wishlist to one Saved Build, and each step says what it changes before it does.',
                '/nexus guide reopens this guide at your step. /nexus reference opens the full manual.'}},
            {page = 'wishlists', title = 'Wishlists and locked targets', paras = {
                'A Wishlist is the Echoes you want. Edit and save it in Plan (the Wishlist Editor); an unsaved Plan draft stays yours until you save or discard it there.',
                'A Saved Build follows one Wishlist at a time. You assign it in the Echo Journal chooser, and Nexus reads the result back before a step counts as done.'}},
            {page = 'rolling', title = 'Auto, rolling and saving', paras = {
                'Without Auto, Nexus only recommends: you choose every offer yourself.',
                'Auto is a separate switch on the Nexus panel, with its own warning. This guide never turns it on or off.'}},
            {page = 'orbs', title = 'Orbs / Lost Memories', paras = {
                'Orb runs are optional and separate from setup. Opening the Orbs window, reading it or using Max spends nothing.',
                'A run spends Orbs only after you press Start, within the maximum you approve. Closing the window does not stop a run: use Pause or Stop.'}},
            {page = 'sharing', title = 'Shared builds and DPS', paras = {
                'Sharing a build is always its own confirmed action. Sent is not delivered, and a shared build cannot be recalled.',
                'What Sync sends depends on your saved Sync mode; with Sync Off, Nexus sends nothing. This guide never sends anything.'}},
            {page = 'troubleshooting', title = 'Problems and bug reports', paras = {
                'Something wrong? Type /nexus report before any reload, then Copy summary. Do not reload, reset or clear data to recreate it.',
                'A prepared report file stays on this computer. Send it privately, never in public.'}}}},
    welcome = {title = 'Welcome to Nexus', titleReplay = 'Welcome back',
        body = 'This guide links one Wishlist to one Saved Build, then shows you a sample recommendation.',
        bodyReplay = 'Running the guide again resets nothing. It checks again what is set now, and you can change anything.',
        paths = {
            {id = 'new', title = 'New to Nexus', desc = 'Start a Wishlist and give it a build slot. About 3 minutes.'},
            {id = 'existing', title = 'I already have a Saved Build', desc = 'Point one of your Saved Builds at a Wishlist. You will see what gets replaced first.'},
            {id = 'explore', title = 'Just look around', desc = 'See how recommendations and Auto work. Nothing is set up or changed.'}}},
    wishlist = {title = 'Choose a Wishlist',
        conceptWish = 'Wishlist - what you want', conceptWishBody = 'The Echoes you are aiming for.',
        conceptBuild = 'Saved Build - what you play', conceptBuildBody = 'A build slot the game loads. Each one follows one Wishlist.',
        yours = 'Yours on the server', needsRoles = 'Yours - needs locked targets; the chooser asks for them',
        importTitle = 'Paste a Wishlist code', importDesc = 'From a friend or a guide. Check it here first; checking imports and saves nothing.',
        -- The in-step check (WishlistEditor.CheckImportCode) reads the code
        -- only; Open it as a draft hands that same code to the editor's import.
        importLabel = 'Paste the whole code',
        importOk = '+ Code read: %s - %d Echo entries (%d rolled copies, %d locked targets).',
        importOkBody = 'Nothing is imported or saved yet. Open it as a draft: the Wishlist Editor asks for a name, checks the Echoes again and shows the draft. It counts only after you save it there.',
        importRoles = 'It has more than 79 rolled copies, so the editor asks you to choose locked targets before the draft opens.',
        importSuspended = 'An unsaved Plan draft is open in another workspace. Return to Plan and finish it before opening this code.',
        importUnnamed = 'an unnamed code',
        importBad = "x That code didn't work.",
        importBadBody = "It looks cut off or isn't a Nexus Wishlist code. Copy the whole code again from where you got it. Nothing was imported.",
        importLong = "It filled this field's %d-letter limit, so it may be cut off. Copy the whole code again from where you got it. Nothing was imported.",
        importEmpty = '! Not checked: paste a code first.',
        importUnavailable = '! Not checked: the code reader is not available yet. Nothing was read or imported.',
        createTitle = 'Start an empty Wishlist', createDesc = 'Opens the Wishlist Editor. Add Echoes there, then save.',
        -- While an unsaved Plan draft is set aside (Setup Alternative): the
        -- row reads unavailable before it is clicked; a click shows one note.
        createBlocked = 'Start an empty Wishlist (unavailable: unsaved Plan draft)',
        createBlockedDesc = 'An empty Wishlist would replace your unsaved Plan draft. Return to it or pick a saved Wishlist.',
        -- The footer's one name, the same Wishlist the single chosen card shows.
        selected = 'Selected: %s', selectedNone = 'Selected: nothing yet',
        -- Start an empty Wishlist while an unsaved Plan draft is set aside in
        -- another workspace (WishlistEditor.SuspendedPlanDraft); the editor
        -- never replaces that draft, and Return to Plan draft reopens it.
        -- Under another character or Saved Build it cannot be reopened as it
        -- is: Keep or discard Plan draft asks the editor's own question, whose
        -- Discard draft opens Plan for the current context without it.
        planHead = '! An unsaved Plan draft is waiting in Plan.',
        planBody = 'You left it in Plan to open another workspace. An empty Wishlist would replace it, so none was opened. Nothing was saved or changed.',
        planSame = 'Return to Plan draft to finish and save it there, or close it if you do not need it. Then start an empty Wishlist here.',
        planContext = 'It was set aside under another character or Saved Build, so it cannot be reopened here. Keep or discard Plan draft asks you first: Keep draft leaves it set aside as it is; Discard draft deletes that unsaved draft and opens Plan for the current character and Saved Build, without it.',
        -- A kept Wishlist that more than one listed Wishlist matches after a
        -- reload (core/GuidedSetup.lua Readopt): none is picked for the player.
        reselect = '! Choose your Wishlist again: more than one of your Wishlists holds the same Echoes as the one you chose, so none was picked for you.',
        chosen = 'Chosen: %s.', saved = 'Saved in the Wishlist Editor: %s.',
        draft = 'A draft is open in the Wishlist Editor. It counts only after you save it there.',
        partial = 'The plan was uploaded, but the save did not finish. See the result in the Wishlist Editor.',
        uncertain = 'The game reported an error while sending it; it may or may not exist now. Check the Wishlist list before saving again.',
        notSaved = 'The Wishlist Editor did not save it. Your edits are kept there.',
        more = 'More Wishlists are listed in the Wishlist Editor.',
        none = 'No Wishlist is listed yet. Paste a code or start an empty one.',
        notLoaded = 'Your Wishlists could not be read yet. Try again in a moment.'},
    target = {title = 'Which Saved Build should follow it?',
        read = 'Read from Nexus just now. Picking one changes nothing yet.',
        unavailable = "! Couldn't read your Saved Builds.", unavailableBody = 'Nexus did not answer. It may still be loading after login. Nothing has changed.',
        slot = 'Slot %d - %s', slotUnnamed = 'Slot %d', first = 'First-run target',
        firstDesc = 'Used until a Saved Build with Echoes is active.',
        active = 'Active now', follows = 'Follows %s', followsNone = 'Follows no Wishlist yet',
        followsUnknown = 'What it follows could not be read', empty = 'Empty - holds no Echoes, so it cannot follow a Wishlist yet',
        -- An empty slot is offered (the original guided design); it can
        -- follow a Wishlist only after the player saves Echoes into it in the
        -- game's own build window, which asks before it saves.
        emptyOffer = 'Empty - holds no Echoes yet. Save your current Echoes into it in My Builds first',
        missing = 'Not available right now',
        ifAssign = 'If you assign %s here',
        cAlready = '%s already follows %s.', cAlready2 = 'Nothing will change. The next step just confirms it with Nexus.',
        cReplace = '%s follows %s now. Assigning switches it to %s.', cKept = '%s stays in your Wishlists. Nothing is deleted.',
        cEchoes = 'Echoes in this slot are not touched.',
        cActive = 'The Echo Journal targets this slot now, so the next recommendation Nexus makes uses the new Wishlist.',
        cAutoOn = 'Auto is ON: a later finished run that fits the new Wishlist better may replace this Saved Build.',
        cNew = 'Nothing is linked here yet, so no link is replaced.',
        cUnknown = 'What this slot follows could not be read, so the consequence is unknown. Try again later.',
        -- Routes the Echo Journal chooser cannot take now (core/GuidedSetup.lua
        -- TargetOptions route). Each names the player's own game step; the
        -- guide saves, loads, activates and assigns nothing.
        cEmpty = '%s is empty: it holds no Echoes, so it cannot follow a Wishlist yet.',
        cEmptySave = 'To use it, open My Builds, select this slot and save your current Echoes into it there. The game asks you to confirm before it saves; Nexus never saves a Saved Build for you.',
        cSelect = 'The Echo Journal chooser assigns only to the Saved Build that is active in the game, and %s is not active now.',
        cSelectHow = 'To use it, open My Builds and choose it there yourself. Choosing a different Saved Build there changes your active loadout; Nexus never does that for you.',
        cFirst = 'The Echo Journal chooser does not assign to the first-run target while a Saved Build is selected in the game. Choose the Saved Build it assigns to, or another.',
        cReturn = 'Then reopen this guide (Setup / Welcome, or /nexus guide). It reads your Saved Builds again; nothing is assumed.',
        accepted = 'Replacement accepted for this choice only. Nothing changes until you choose in the Echo Journal.',
        shortAlready = 'Already linked. This only checks it; nothing is written.',
        shortReplace = 'Replaces the %s link on this slot. Nothing is deleted.', shortNew = 'Links this slot. Nothing is replaced.'},
    assign = {title = 'Assign, then let Nexus confirm',
        missing = 'Choose a Wishlist and a Saved Build first. Nothing to assign yet.',
        openNote = 'Opens the Echo Journal Wishlist chooser. Nothing changes until you choose %s there.',
        waiting = '* Waiting for you to choose %s in the Wishlist chooser. Nothing is assigned yet.',
        verified = '+ Nexus confirmed it', readback = 'Read back from Nexus',
        evCharacter = 'Character', evBuild = 'Saved Build', evWishlist = 'Wishlist', evRequest = 'Request',
        evRead = 'Read back', evRequestValue = '#%d - this session', evSave = 'Your save in the Wishlist Editor',
        evReadValue = 'Just now - after your choice',
        observed = '+ Already linked.', observedBody = '%s already follows %s. Nexus read it back just now; this guide did not change it.',
        rejected = 'x Nexus declined.', rejectedBody = 'The assignment was refused (%s). Nothing was assigned.',
        cancelled = 'x Cancelled.', cancelledBody = 'The choice in the Wishlist chooser was cancelled. Nothing was assigned.',
        unavailable = '! No answer from Nexus.', unavailableBody = 'The slot may or may not have changed - the guide will not guess. Check again, or skip and look in the Echo Journal later.',
        stale = '? The earlier check no longer counts.',
        staleBody = {stale = 'The assignment of %s changed after your choice. Check again so the result belongs to what is set now.',
            changed = 'The assignment of %s changed through another route, not through this guide. Check again.',
            other = 'Another Wishlist (%s) was assigned instead. Open the chooser and choose your Wishlist.',
            mismatch = '%s follows another Wishlist (%s). Open the chooser and choose your Wishlist.',
            outdated = 'This result belongs to another character or session. Assign again to confirm it here.',
            partial = '%s follows your Wishlist, but its locked targets are still unconfirmed.'}},
    sim = {title = 'Reading a recommendation',
        body = 'When the game offers Echoes, Nexus marks the one your Wishlist wants. You still choose. Try it below.',
        banner = 'SIMULATED PREVIEW - NOTHING IS CHOSEN IN GAME',
        cards = {{name = 'Sample Ember', desc = 'Rare - on the sample Wishlist, 2 copies missing'},
            {name = 'Sample Frost', desc = 'Common - not on the sample Wishlist'},
            {name = 'Sample Ash', desc = 'Uncommon - not on the sample Wishlist'}},
        mark = '>> Wishlist pick',
        why = 'Sample Ember is marked because it is on the sample Wishlist and you do not have it yet.',
        picked = 'Preview only: you picked %s. Nothing was chosen in game.',
        match = ' That matches the recommendation.', differ = ' Nexus marked Sample Ember, but your pick always wins.',
        autoOn = ' Auto is ON for this character, so in game Nexus may act without asking. More on the next step.'},
    auto = {title = 'Auto is up to you',
        modeOn = 'Auto is ON right now', modeOff = 'Auto is OFF right now', modeUnknown = 'Auto mode unknown',
        subRead = 'Read from Nexus just now.', subUnknown = 'Nexus did not report it. The guide will leave it alone.',
        lead = 'Most players start with Auto OFF and just follow the recommendations.',
        moreOn = 'With Auto ON, Nexus may choose offers and may replace your active Saved Build with a better finished run, without asking. It never loads a build or starts Orbs.',
        moreOff = 'With Auto OFF, Nexus only recommends. Slots change only when you change them.',
        reviewNote = 'Turning Auto ON or OFF is done with the Auto button on the Nexus panel, after its own warning.',
        keptOn = 'Left ON. Nothing changed.', keptOff = 'Left OFF. Nothing changed.',
        keptUnknown = 'Left alone. Its mode is still unknown, and this guide did not touch it.'},
    finish = {titleDone = "You're set up", titleOpen = 'Not finished: %d step%s still open', titleExplore = "You've had a look around",
        subDone = 'Nexus confirmed the assignment. Nothing else was changed by this guide.',
        subTrue = 'Nexus read back that the assignment was already in place. This guide changed nothing.',
        subOpen = "You can close now. Your place is kept, but setup won't be marked complete. Skipped steps stay skipped.",
        subOpenSession = "You can close now. Your place is kept until you reload or log out, but setup won't be marked complete. Skipped steps stay skipped.",
        subExplore = 'Nothing was set up or changed. Run the guide again to set up for real.',
        explore = 'Not part of a look-around',
        rows = {wishlist = 'Choose a Wishlist', target = 'Pick the Saved Build', assign = 'Assign & confirm',
            manual = 'Read a recommendation', auto = 'Auto (optional)'},
        -- Each row is this guide's own progress; "in this guide" keeps a row
        -- from reading as the game's assignment, which currentNote states
        -- apart (read just now, never a completed step).
        wishDone = '%s', wishSkipped = 'Skipped. No Wishlist chosen.', wishNot = 'Not chosen in this guide',
        wishDraft = 'A draft is open, not saved', wishPartial = 'The save did not finish', wishUncertain = 'The save may or may not have happened',
        targetSkipped = 'Skipped', targetNot = 'Not chosen in this guide',
        assignDone = '%s follows %s. Confirmed by read back.', assignTrue = '%s already follows %s. Read back; not changed by this guide.',
        assignSkipped = 'Skipped. Nothing was assigned.', assignWaiting = 'Chooser opened, nothing chosen yet.',
        assignRejected = 'Nexus declined the assignment.', assignUnknown = "Not confirmed. Nexus didn't answer.",
        assignStale = 'It was confirmed, but something changed since. Needs a fresh check.', assignNot = 'Not assigned by this guide',
        currentNote = 'In the game now (read just now, not set or confirmed by this guide): %s follows %s.',
        currentUnknown = 'What the game follows now could not be read just now.',
        manualDone = 'Tried the preview', manualSkipped = 'Skipped', manualNot = 'Not tried',
        autoUnknown = "Mode not reported. This guide didn't touch it.", autoMode = '%s, unchanged by this guide',
        autoNotReviewed = '%s - not reviewed',
        sent = 'This guide sent nothing and used no Orbs.',
        more = 'Want more?', moreSub = "Separate and optional - setup doesn't need them.",
        lessons = {
            {id = 'orbs', title = 'Orbs & Lost Memories', open = 'Open Orbs / Lost Memories',
                lines = {"Orb runs can refine a build after you've played it. They're optional and separate from setup.",
                    'Reading this spends nothing. Every Orb run asks you first.'}},
            {id = 'sharing', title = 'Sharing & Sync', open = 'Open Reference: Sharing',
                lines = {'Sync can send shared builds and DPS records; Reference - Sharing lists exactly what goes out and when.',
                    'This guide never sends anything.'}}}},
    -- The design's aside: full Help is the reference pages /nexus reference
    -- opens (/nexus help and /nexus tutorial open this coach).
    help = {title = 'About: %s', full = 'Full guide: the Nexus reference pages (/nexus reference). They open in place of this guide; close them to come back to this step.',
        lines = {
            welcome = {"Nexus watches the Echoes you're offered and points at the ones on your Wishlist.",
                'Each change in this guide has its own button and tells you what it does first.'},
            wishlist = {'One Saved Build follows one Wishlist at a time. A Wishlist can serve several builds.',
                'Codes come from friends or guides. Nexus checks them before using them.'},
            target = {'Slots are read fresh from Nexus each time you open this step.',
                'Replacing a link never deletes the old Wishlist.'},
            assign = {'"Done" appears only after Nexus reports the same character, slot and Wishlist for this request.',
                "If Nexus doesn't answer, the guide says so instead of guessing."},
            manual = {'The preview uses made-up Echoes. Nothing is chosen in game.'},
            auto = {'Auto stays as it was unless you change it with the Auto button on the Nexus panel.',
                'You can turn it off any time with that same button.'},
            summary = {'Closing never marks skipped or unconfirmed steps as done.', 'Orbs and Sharing are separate and optional.'}}},
    gate = {welcome = 'Pick how you want to start.', wishlist = 'Choose a Wishlist to continue.',
        wishlistDraft = 'Save the draft in the Wishlist Editor, pick another Wishlist, or skip.',
        wishlistImport = 'Paste a code and check it, choose another Wishlist, or skip.',
        wishlistChecked = 'Open the checked code as a draft and save it there, choose another Wishlist, or skip.',
        target = 'Pick a Saved Build to continue.', targetUnavailable = "Saved Builds couldn't be read. Try again or skip.",
        targetReplace = 'Accept the replacement or choose another.',
        targetSelect = 'Make it your active Saved Build in My Builds, or choose another.',
        targetSave = 'Save your current Echoes into it in My Builds, or choose another.',
        targetFirst = 'Choose the Saved Build the Echo Journal assigns to, or skip.',
        assign = 'Continues once Nexus confirms.', assignWaiting = 'Choose your Wishlist in the Wishlist chooser.',
        assignRejected = 'Nexus declined. Try again or skip.', assignUnknown = 'Not confirmed. Check again or skip.',
        assignStale = 'Needs a fresh check.', manual = 'Try one pick in the preview, or skip.',
        auto = 'Keep Auto as it is, or review it.', autoUnknown = 'Leave Auto alone or retry reading it.'},
    chat = {paused = '[Nexus] Setup guide closed at "%s". Closing changed nothing.',
        -- Both routes open the coach itself (the design's "Reopen: Nexus
        -- menu > Setup / Welcome"). A resumed guide reads every result again.
        reopen = '[Nexus] Reopen it from the Options menu: Setup / Welcome, or type /nexus help. It resumes at this step and checks every result again.',
        reopenSession = '[Nexus] Reopen it from the Options menu: Setup / Welcome, or type /nexus help. Saved data cannot be written right now, so your place is kept only until you reload or log out.',
        complete = '[Nexus] Setup confirmed: %s follows %s.',
        auto = '[Nexus] Auto is %s (this guide did not change it).',
        explore = '[Nexus] Look-around finished. Nothing was set up or changed.',
        incomplete = '[Nexus] Setup guide closed with %d step%s open. Not marked complete.'},
    notice = {owner = 'The character changed, so earlier guide results were cleared.',
        epoch = 'Saved data changed, so earlier guide results were cleared.',
        session = 'A new world session started, so earlier guide results were cleared and must be checked again.',
        -- The kept place is remembered; every result is read again (never
        -- carried over as done).
        restored = 'Picked up where you left off. Each earlier result is checked again now.',
        reselect = 'Resumed where you left off. More than one of your Wishlists holds the same Echoes as the one you chose, so the guide cannot tell which it was. Choose your Wishlist again; nothing was chosen for you.'},
    notes = {startup = 'Start-up is still running (see the loading panel). Nothing was opened.',
        unavailable = 'The game Character Progression button was not found. Nothing was opened or assigned.',
        noEditor = 'The Wishlist Editor is not available. Nothing was opened.',
        importChanged = 'That code no longer reads as a Wishlist code. Check it again. Nothing was opened.',
        importSuspended = 'An unsaved Plan draft is open in another workspace. Return to Plan before opening this code. Nothing was imported.',
        planRefused = 'Plan did not reopen the draft; a Save there may still be pending. Nothing was changed. Try again in a moment.',
        planDiscarded = 'You discarded the Plan draft. Plan did not open over this guide; open it from the Nexus panel when you need it. Nothing else was changed.',
        gone ='That Wishlist is no longer listed. Choose again.',
        notLoaded = 'Saved Build data is not loaded yet. Try again in a moment.',
        empty = 'That Saved Build holds no Echoes, so it cannot follow a Wishlist yet.',
        missing = 'That Saved Build is not available right now.',
        notReady = 'Choose a Wishlist and a ready Saved Build first.', blocked = 'an empty Saved Build',
        buildsUnavailable = 'My Builds did not open: the game Character Progression button was not found. Nothing was opened, saved or changed.',
        -- The game's button was used, but Nexus did not see My Builds after it
        -- (ui/JournalTab.lua OpenBuilds onSettled), so the coach stays.
        buildsUnconfirmed = 'Nexus could not confirm that My Builds opened, so this guide stays open. If My Builds is not on screen, open it in Character Progression yourself. Nothing was saved or changed.',
        route = 'The Echo Journal assigns to %s, not to your target %s. Select your target in the game build window, or go Back and choose the Saved Build the Journal targets. Nothing was opened or assigned.'},
}
