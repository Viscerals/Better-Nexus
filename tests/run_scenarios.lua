-- Deterministic guaranteed-queue policy scenarios.
dofile("logic/Model.lua")
dofile("logic/Policy.lua")

local Policy = Nexus.Policy
local checks = 0

local function expect(condition, message)
    checks = checks + 1
    assert(condition, message)
end

local rows = {
    [100] = { spellId=100, name="Stack Target", quality=1, maxStack=3 },
    [200] = { spellId=200, name="Ordinary Target", quality=1, maxStack=1 },
    [210] = { spellId=210, name="Quality Target", quality=0, maxStack=1 },
    [211] = { spellId=211, name="Quality Target", quality=2, maxStack=1 },
    [212] = { spellId=212, name="Quality Target", quality=2, maxStack=1 },
    [220] = { spellId=220, name="Held Target", quality=1, maxStack=1 },
    [221] = { spellId=221, name="Equal Side Target", quality=1, maxStack=1 },
    [222] = { spellId=222, name="Another Target", quality=1, maxStack=1 },
    [300] = { spellId=300, name="Guaranteed Target", quality=1, maxStack=1 },
    [400] = { spellId=400, name="Filler A", quality=1, maxStack=1 },
    [401] = { spellId=401, name="Filler B", quality=1, maxStack=1 },
}
local catalog = {
    rows = rows,
    familyOf = {
        [100]="stack", [200]="ordinary", [210]="quality", [211]="quality", [212]="quality",
        [220]="held", [221]="side", [222]="another",
        [300]="guaranteed", [400]="fillerA", [401]="fillerB",
    },
    familyMembers = {
        stack={100}, ordinary={200}, quality={210,211,212}, guaranteed={300},
        held={220}, side={221}, another={222},
        fillerA={400}, fillerB={401},
    },
}
local plan = {
    advisorOnly = false,
    wishedFamilies = {
        stack=true, ordinary=true, quality=true, held=true,
        side=true, another=true, guaranteed=true,
    },
    targets = {
        stack={ targetStacks=3, wishedQuality=1 },
        ordinary={ targetStacks=1, wishedQuality=1 },
        quality={ targetStacks=1, wishedQuality=2,
            qualityTiers={{spellId=211,q=2,n=1}} },
        held={ targetStacks=1, wishedQuality=1 },
        side={ targetStacks=1, wishedQuality=1 },
        another={ targetStacks=1, wishedQuality=1 },
        guaranteed={ targetStacks=1, wishedQuality=1 },
    },
}

local function card(spellId, extra)
    local out = {
        spellId=spellId,
        family=catalog.familyOf[spellId],
        quality=rows[spellId].quality,
    }
    for key, value in pairs(extra or {}) do out[key] = value end
    return out
end

local function decide(cards, guaranteedIndex, options)
    options = options or {}
    return Policy.Decide({
        board={ cards=cards, guaranteedIndex=guaranteedIndex },
        owned={
            synced=options.synced ~= false,
            bySpell=options.bySpell or {},
            byFamily=options.byFamily or {},
        },
        charges=options.charges or {
            freeze=1, banish=1, reroll=1, trustworthy=true,
            banishSpentThisPush=options.banishSpentThisPush,
        },
        plan=plan,
        queue=options.queue,
        catalog=catalog,
        canFreeze=options.canFreeze,
        level=options.level ~= nil and options.level or 20,
        horizon=options.horizon,
        flags=options.flags,
        searchRefused=options.searchRefused,
        allowBanish=options.allowBanish,
    })
end

-- Exact queue promises protect only the same exact target.  A same-quality
-- sibling cannot satisfy the promise merely because it shares the family.
do
    local exact = decide({
        card(211), card(300, { isGuaranteed=true }), card(400),
    }, 2, {queue={entries={
        {spellId=211,family="quality",quality=2,wanted=true},
    }}})
    expect(exact.type == "take" and exact.index == 2
        and exact.annotations[1] == "returns later",
        "exact guaranteed queue promise did not protect its matching target")

    local sibling = decide({
        card(211), card(300, { isGuaranteed=true }), card(400),
    }, 2, {queue={entries={
        {spellId=212,family="quality",quality=2,wanted=true},
    }}})
    expect(sibling.type == "freeze" and sibling.index == 1,
        "same-quality sibling queue promise protected the wrong exact target")
end

-- An unsynchronized owned snapshot is not safe for irreversible auto-play.
do
    local result = decide({
        card(400, { isGuaranteed=true }), card(401),
    }, 1, {
        synced=false,
        charges={ freeze=0, banish=0, reroll=0, trustworthy=true },
    })
    expect(result.type == "wait",
        "an unsynchronized owned snapshot must pause automatic choices")
end

-- Wanted side + wanted guaranteed: bank the side first, then drain.
do
    local first = decide({
        card(200), card(300, { isGuaranteed=true }), card(400),
    }, 2)
    expect(first.type == "freeze" and first.index == 1,
        "wanted side must freeze before a wanted guaranteed card")
    local second = decide({
        card(200, { isFrozen=true }), card(300, { isGuaranteed=true }), card(400),
    }, 2)
    expect(second.type == "banish" and second.index == 3,
        "a safe filler must be Banished after the wanted side is protected")
    local third = decide({
        card(200, { isFrozen=true }), card(300, { isGuaranteed=true }), card(400),
    }, 2, { charges={ freeze=0, banish=0, reroll=1, trustworthy=true } })
    expect(third.type == "take" and third.index == 2,
        "guaranteed card must drain after early Banishes are exhausted")
end

-- A filler guarantee is rejected as soon as a wanted side Echo is visible.
do
    local result = decide({
        card(200), card(400, { isGuaranteed=true }), card(401),
    }, 2)
    expect(result.type == "take" and result.index == 1,
        "wanted side must replace an off-wishlist guaranteed card")
end

-- A wanted side already promised later by the queue is not one of the missing
-- targets that should replace an off-wishlist guarantee.
do
    local result = decide({
        card(200), card(400, { isGuaranteed=true }), card(401),
    }, 2, {
        queue={ entries={
            { spellId=200, family="ordinary", wanted=true },
        } },
    })
    expect(result.type == "banish" and result.index == 3
        and result.annotations[1] == "returns later",
        "off-wishlist guarantee search must preserve queue-deliverable targets")
end

-- A useful single-stack side card already pending in the guaranteed queue
-- returns later; spending Freeze would occupy a side slot for no gain.
do
    local result = decide({
        card(200), card(300, { isGuaranteed=true }), card(400),
    }, 2, {
        queue={ entries={
            { spellId=300, family="guaranteed", wanted=true },
            { spellId=200, family="ordinary", wanted=true },
        } },
    })
    expect(result.type == "take" and result.index == 2
        and result.annotations[1] == "returns later",
        "a queue-deliverable single-stack wanted side card must not be frozen")
end

-- A high-quality side catch is still scarce when the queue only promises a
-- below-target member of the same multi-quality family.
do
    local result = decide({
        card(211), card(300, { isGuaranteed=true }), card(400),
    }, 2, {
        queue={ entries={
            { spellId=300, family="guaranteed", wanted=true },
            { spellId=210, family="quality", wanted=false },
        } },
    })
    expect(result.type == "freeze" and result.index == 1,
        "a superior-quality catch must remain freeze-worthy")
end

-- A stacking target stays scarce even when its family appears in the queue:
-- injection supplies only the first copy, not every requested stack.
do
    local result = decide({
        card(100), card(300, { isGuaranteed=true }), card(400),
    }, 2, {
        queue={ entries={
            { spellId=300, family="guaranteed", wanted=true },
            { spellId=100, family="stack", wanted=true },
        } },
        byFamily={ stack=1 },
    })
    expect(result.type == "freeze" and result.index == 1,
        "a still-short stacking family must remain freeze-worthy")
end

-- One carried wanted card already protects the side opportunity. Do not
-- fill the other side slot with a second Freeze.
do
    local result = decide({
        card(200, { isCarried=true }), card(100),
        card(300, { isGuaranteed=true }),
    }, 3, { byFamily={ stack=1 } })
    expect(result.type == "take" and result.index == 3,
        "an existing carried wanted card must suppress a second Freeze")
end

-- Unavailable or untrustworthy Freeze uses explicit loss prevention.
do
    local result = decide({
        card(200), card(300, { isGuaranteed=true }), card(401),
    }, 2, { charges={ freeze=0, banish=9, reroll=9, trustworthy=true } })
    expect(result.type == "take" and result.index == 1
        and string.find(result.reason, "Freeze", 1, true),
        "missing Freeze must take the wanted side with a clear reason")
end

-- Side priority: stacking, then quality-qualified one-shot, then delta/index.
do
    local result = decide({
        card(200), card(211), card(100), card(300, { isGuaranteed=true }),
    }, 4, { byFamily={ stack=1 } })
    expect(result.type == "freeze" and result.index == 3,
        "a stacking family below target must win side-card priority")

    result = decide({
        card(200), card(211), card(300, { isGuaranteed=true }),
    }, 3)
    expect(result.type == "freeze" and result.index == 2,
        "a quality-qualified one-shot must beat an ordinary wanted side card")

    result = decide({
        card(200), card(200), card(300, { isGuaranteed=true }),
    }, 3)
    expect(result.type == "freeze" and result.index == 1,
        "equal wanted side cards must use the lowest stable index")
end

-- During leveling, safe Banishes are front-loaded even while the guaranteed
-- queue is active. Guaranteed identity remains semantic, not positional.
do
    local result = decide({
        card(400, { isGuaranteed=true }), card(401), card(400),
    }, 1, { charges={ freeze=2, banish=3, reroll=4, trustworthy=true } })
    expect(result.type == "banish" and result.index == 2,
        "leveling must front-load a safe side Banish before queue drain")

    result = decide({
        card(400, { isGuaranteed=true }), card(401), card(400),
    }, 1, { charges={ freeze=2, banish=0, reroll=4, trustworthy=true } })
    expect(result.type == "reroll",
        "after Banishes, an off-wishlist guarantee must search with Reroll")

    result = decide({
        card(400, { isGuaranteed=true }), card(401), card(400),
    }, 1, { charges={ freeze=2, banish=0, reroll=0, trustworthy=true } })
    expect(result.type == "take" and result.index == 2,
        "exhausted search must discard the off-wishlist guarantee via a side")
end

-- Once the queue is gone, consume frozen wanted cards first.
do
    local result = decide({
        card(200), card(211, { isFrozen=true }), card(100),
    }, nil)
    expect(result.type == "take" and result.index == 2,
        "a frozen wanted card must be taken before unfrozen wanted cards")
end

-- Search phase: Banish once, then Reroll after re-evaluation.
do
    local cards = { card(400), card(401) }
    local first = decide(cards, nil)
    expect(first.type == "banish" and first.index == 1,
        "a junk board must safely Banish the deterministic worst filler")
    local second = decide(cards, nil, {
        banishSpentThisPush=true,
        charges={
            freeze=0, banish=1, reroll=1, trustworthy=true,
            banishSpentThisPush=true,
        },
    })
    expect(second.type == "reroll",
        "the same fresh run-data push must Reroll after its one safe Banish")
end

-- Front-loading is limited to the leveling run. At level 80 with no confirmed
-- final horizon, an off-wishlist guarantee is still rejected.
do
    local result = decide({
        card(400, { isGuaranteed=true }), card(401),
    }, 1, {
        level=80,
        charges={ freeze=0, banish=4, reroll=4, trustworthy=true },
    })
    expect(result.type == "banish" and result.index == 2,
        "level 80 must still search away an off-wishlist guarantee")
end

-- A just-frozen wanted side must finish resolving before the unwanted
-- guarantee can be discarded.
do
    local result = decide({
        card(400, { isGuaranteed=true }),
        card(200, { justFrozen=true }),
        card(401),
    }, 1)
    expect(result.type == "wait"
        and string.find(result.reason, "Freeze", 1, true),
        "off-wishlist guarantee search must wait for a just-frozen wanted side")
end

-- A below-quality wished family is not wanted, but the family is protected
-- from Banish because Banish may remove every quality variant.
do
    local result = decide({ card(210), card(400) }, nil)
    expect(result.type == "banish" and result.index == 2,
        "below-quality wished family must be protected from Banish")
end

-- A held wanted Echo protects the side opportunity, so leveling may spend a
-- safe early Banish before normal guaranteed draining.
do
    local result = decide({
        card(220, { isFrozen=true }), card(400),
        card(300, { isGuaranteed=true }),
    }, 3, {
        horizon=2,
        charges={ freeze=0, banish=4, reroll=4, trustworthy=true },
    })
    expect(result.type == "banish" and result.index == 2,
        "a banked wanted side must permit a safe early Banish")

    result = decide({
        card(220, { isFrozen=true }), card(400),
        card(300, { isGuaranteed=true }),
    }, 3, {
        horizon=2,
        charges={ freeze=0, banish=0, reroll=4, trustworthy=true },
    })
    expect(result.type == "take" and result.index == 3,
        "after early Banishes, horizon above one must drain the guarantee")
end

-- Level 80 can still have multiple selections. Freeze remains valid only
-- when Main has confirmed a numeric horizon above one.
do
    local result = decide({
        card(220), card(400), card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=2,
        canFreeze=true,
        charges={ freeze=1, banish=0, reroll=0, trustworthy=true },
    })
    expect(result.type == "freeze" and result.index == 1,
        "level 80 with horizon above one must still allow Freeze")

    result = decide({
        card(220), card(400), card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        canFreeze=false,
        charges={ freeze=1, banish=0, reroll=0, trustworthy=true },
    })
    expect(result.type == "take" and result.index == 1,
        "final selection must take an unfrozen wanted side Echo as loss prevention")
end

-- A lower-level horizon of one only ends the current pending-roll batch. It
-- must keep normal queue behavior because later leveling boards still exist.
do
    local result = decide({
        card(220), card(400), card(300, { isGuaranteed=true }),
    }, 3, {
        level=18,
        horizon=1,
        canFreeze=true,
        charges={ freeze=1, banish=4, reroll=4, trustworthy=true },
    })
    expect(result.type == "freeze" and result.index == 1
        and not result.endgame,
        "lower-level horizon one must not trigger final-selection search")
end

-- On the final selection, search the safe free slot before consuming the
-- held wanted Echo. Protected and guaranteed cards are never Banish targets.
do
    local result = decide({
        card(220, { isFrozen=true }), card(400),
        card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        charges={ freeze=0, banish=2, reroll=3, trustworthy=true },
    })
    expect(result.type == "banish" and result.index == 2 and result.endgame,
        "final selection must safely Banish the off-wishlist side card first")
end

-- A wanted guaranteed card is also a protected final fallback. Even without a
-- frozen card, spend a safe Banish on an off-wishlist side before draining it.
do
    local result = decide({
        card(400), card(401), card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        charges={ freeze=0, banish=2, reroll=3, trustworthy=true },
    })
    expect(result.type == "banish" and result.index == 1 and result.endgame,
        "final selection must safely Banish before a protected guarantee")
end

-- Once that Banish is spent, an unconfirmed Reroll hold must not gamble away
-- the wanted guaranteed fallback. A confirmed hold may continue the search.
do
    local result = decide({
        card(400), card(401), card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        flags={},
        charges={
            freeze=0, banish=1, reroll=3, trustworthy=true,
            banishSpentThisPush=true,
        },
    })
    expect(result.type == "take" and result.index == 3,
        "unknown Reroll hold must drain the protected guaranteed card")

    result = decide({
        card(400), card(401), card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        flags={ REROLL_HOLDS_GUARANTEED=true },
        charges={
            freeze=0, banish=1, reroll=3, trustworthy=true,
            banishSpentThisPush=true,
        },
    })
    expect(result.type == "reroll" and result.endgame,
        "confirmed Reroll hold must search beyond the protected guarantee")
end

-- A filler guarantee needs no hold proof: after the safe Banish, Reroll may
-- continue looking for any still-missing wanted target.
do
    local result = decide({
        card(401), card(400, { isGuaranteed=true }),
    }, 2, {
        level=80,
        horizon=1,
        flags={},
        charges={
            freeze=0, banish=1, reroll=3, trustworthy=true,
            banishSpentThisPush=true,
        },
    })
    expect(result.type == "reroll" and result.endgame,
        "a filler guaranteed card must not block final Reroll search")

    result = decide({
        card(401), card(400, { isGuaranteed=true }),
    }, 2, {
        level=80,
        horizon=1,
        charges={ freeze=0, banish=0, reroll=0, trustworthy=true },
    })
    expect(result.type == "take" and result.index == 1 and result.endgame,
        "exhausted final search must discard an off-wishlist guarantee")
end

-- One-Banish-per-push remains binding. Once that safe action is spent,
-- final search advances to Reroll without claiming the guaranteed is held.
do
    local result = decide({
        card(220, { isFrozen=true }), card(400),
        card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        flags={},
        charges={
            freeze=0, banish=1, reroll=2, trustworthy=true,
            banishSpentThisPush=true,
        },
    })
    expect(result.type == "reroll" and result.endgame,
        "spent final-selection Banish must advance to Reroll")
    expect(not string.find(result.reason, "guaranteed wanted Echo is held", 1, true),
        "Reroll reason must not claim the guaranteed is held without the flag")

    -- Remove the frozen fallback here so the confirmed guarantee hold is the
    -- specific protection that makes Reroll safe (and therefore the reason
    -- Nexus should report).
    result = decide({
        card(400), card(401), card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        flags={ REROLL_HOLDS_GUARANTEED=true },
        charges={
            freeze=0, banish=1, reroll=2, trustworthy=true,
            banishSpentThisPush=true,
        },
    })
    expect(result.type == "reroll"
        and string.find(result.reason, "guaranteed wanted Echo is held", 1, true),
        "confirmed Reroll hold may be stated in the final-search reason")
end

-- Exhausted search always cashes the frozen target instead of falling back
-- to the guaranteed card.
do
    local result = decide({
        card(220, { isFrozen=true }), card(400),
        card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        charges={ freeze=0, banish=0, reroll=0, trustworthy=true },
    })
    expect(result.type == "take" and result.index == 1 and result.endgame,
        "no final-search charges must take the frozen Echo, not guaranteed")
end

-- Final comparison uses ordinary wishlist demand only. Equal targets keep the
-- protected frozen card; a real stacking deficit may replace it.
do
    local result = decide({
        card(220, { isFrozen=true }), card(221),
        card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        charges={ freeze=0, banish=0, reroll=0, trustworthy=true },
    })
    expect(result.type == "take" and result.index == 1 and result.endgame,
        "equal remaining targets must keep the protected frozen Echo")

    result = decide({
        card(220, { isFrozen=true }), card(100),
        card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        charges={ freeze=0, banish=0, reroll=0, trustworthy=true },
    })
    expect(result.type == "take" and result.index == 2 and result.endgame,
        "normal stacking demand must drive final selection without name rules")
end

-- The final branch is independent of guaranteed-card identity. It continues
-- after Reroll removes the guaranteed card as long as the frozen Echo remains.
do
    local result = decide({
        card(220, { isFrozen=true }), card(400),
    }, nil, {
        level=80,
        horizon=1,
        charges={ freeze=0, banish=0, reroll=2, trustworthy=true },
    })
    expect(result.type == "reroll" and result.endgame,
        "final search must continue when Reroll removes the guaranteed card")
end

-- Missing horizon is conservative: no final exception is inferred from level.
do
    local result = decide({
        card(220, { isFrozen=true }), card(400),
        card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        charges={ freeze=0, banish=4, reroll=4, trustworthy=true },
    })
    expect(result.type == "take" and result.index == 3,
        "nil horizon must not trigger the final-selection exception")

    result = decide({
        card(220, { isFrozen=true }), card(400),
        card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon="1",
        charges={ freeze=0, banish=4, reroll=4, trustworthy=true },
    })
    expect(result.type == "take" and result.index == 3,
        "non-numeric horizon must not trigger the final-selection exception")
end

-- With no guarantee and selections still remaining, Phase B keeps its
-- existing consume-bank-first behavior.
do
    local result = decide({
        card(220, { isFrozen=true }), card(400),
    }, nil, {
        horizon=2,
        charges={ freeze=0, banish=4, reroll=4, trustworthy=true },
    })
    expect(result.type == "take" and result.index == 1,
        "non-final Phase B must take the frozen Echo before searching")
end

-- A wished low-quality family, frozen card, and guaranteed card are all
-- protected from Banish. With no safe target or Reroll, cash the frozen Echo.
do
    local result = decide({
        card(220, { isFrozen=true }), card(210),
        card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        charges={ freeze=0, banish=3, reroll=0, trustworthy=true },
    })
    expect(result.type == "take" and result.index == 1,
        "final Banish must never target frozen, guaranteed, or wished cards")
end

-- Synchronous search refusals are supplied by Main on the next pure-policy
-- call: skip the refused action, then settle on the frozen target.
do
    local result = decide({
        card(220, { isFrozen=true }), card(400),
        card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        searchRefused={ banish=true },
        charges={ freeze=0, banish=2, reroll=1, trustworthy=true },
    })
    expect(result.type == "reroll",
        "a refused final Banish must advance to Reroll")

    result = decide({
        card(220, { isFrozen=true }), card(400),
        card(300, { isGuaranteed=true }),
    }, 3, {
        level=80,
        horizon=1,
        searchRefused={ banish=true, reroll=true },
        charges={ freeze=0, banish=2, reroll=1, trustworthy=true },
    })
    expect(result.type == "take" and result.index == 1,
        "refused final search actions must take the frozen Echo")
end

-- Disabling automatic Banish must advance to another executable action rather
-- than repeatedly proposing a Banish that Main intentionally will not send.
do
    local result = decide({
        card(400), card(401),
    }, nil, {
        allowBanish=false,
        charges={ freeze=0, banish=2, reroll=0, trustworthy=true },
    })
    expect(result.type == "take",
        "disabled automatic Banish must fall through to a selectable action")
    expect(result.forced == true,
        "mandatory least-harmful selections must preserve forced-take metadata")
end

-- Final Phase B has no protected guarantee/frozen fallback, but its search
-- actions still need endgame refusal recovery.
do
    local result = decide({
        card(400), card(401),
    }, nil, {
        level=80,
        horizon=1,
        charges={ freeze=0, banish=2, reroll=1, trustworthy=true },
    })
    expect(result.type == "banish" and result.endgame,
        "unprotected final Banish must be marked for refusal recovery")

    result = decide({
        card(400), card(401),
    }, nil, {
        level=80,
        horizon=1,
        searchRefused={ banish=true },
        charges={ freeze=0, banish=2, reroll=1, trustworthy=true },
    })
    expect(result.type == "reroll" and result.endgame,
        "refused final Banish must advance to an endgame Reroll")

    result = decide({
        card(400), card(401),
    }, nil, {
        level=80,
        horizon=1,
        searchRefused={ banish=true, reroll=true },
        charges={ freeze=0, banish=2, reroll=1, trustworthy=true },
    })
    expect(result.type == "take" and result.endgame,
        "exhausted unprotected final search must make a mandatory selection")
end

print("guaranteed-queue policy scenarios OK (checks=" .. checks .. ")")
