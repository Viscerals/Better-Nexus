-- Player-facing terminology only. Stable policy/reason codes and protocol data
-- remain unchanged; diagnostics may retain original codes for support.
Nexus=Nexus or {}
local T={};Nexus.UserText=T
local reasons={
    ["unsynced"]="Waiting for current Echo data from the server - automatic choices paused",
    ["waiting for owned-echo sync"]="Waiting for current Echo data from the server - automatic choices paused",
    ["waiting for owned-state sync"]="Waiting for current Echo data from the server - automatic choices paused",
    ["no wishlist set - advisor only"]="No Wishlist assigned - recommendations only",
    ["no wishlist"]="Assign a Wishlist to use its targets",
    ["waiting for three-card board"]="Waiting for the next three Echo choices",
    ["pending-pick count"]="Waiting for the remaining-choice count",
    ["Orb state active or unknown"]="Ordinary rolling paused while the Orb choice is active or cannot be confirmed",
    ["orb state not yet known"]="Ordinary rolling paused: the server's Orb state is not confirmed yet",
    ["orb state unknown"]="Ordinary rolling paused: the game's Orb state could not be read",
    ["orb state unavailable"]="Ordinary rolling paused: the game's Orb service does not expose its pending-offer state",
    ["orb state capability missing"]="Ordinary rolling paused: the game's Orb service does not report whether its state is known, so Nexus cannot confirm that no Orb choice is open",
    ["Orb offer active -- manual action required"]="An Orb offer is active; use Orb mode or resolve it in the game",
    ["Take wanted Echo (Pilot)"]="Take a needed Echo",
    ["Take available Echo (Pilot)"]="Take an available Echo",
    ["Freeze wanted Echo before search (Pilot)"]="Freeze a needed Echo before searching for another target",
    ["Banish to find Wishlist targets (Pilot)"]="Banish to find Wishlist targets",
    ["Reroll: no requested Echo on board (Pilot)"]="Reroll: no requested Echo on board",
    ["Reroll: no needed Echo on board (Pilot)"]="Reroll: no Echo on this board is still needed",
    ["Take available filler (Pilot)"]="Take an available Echo outside the Wishlist",
    ["Take filler; search unavailable (Pilot)"]="Take an Echo outside the Wishlist; no permitted Banish or Reroll action",
    ["Wishlist complete; take filler (Pilot)"]="Wishlist complete; take an Echo outside the Wishlist",
    ["Take wanted Echo"]="Take a needed Echo",
    ["invalid wishlist"]="This Wishlist cannot be used yet. Open it in the editor to check its targets",
    ["invalid loadout"]="This Saved Build is unavailable or not valid for this action. Check My Builds",
    ["ROOT_MUTATION_PENDING"]="Saving is still in progress; wait for its final result",
    ["CURSOR_REQUIRED"]="This list is still being prepared",
    ["ROOT_PENDING"]="The build library is still being prepared",
    ["STORE_PENDING"]="Reading your saved data",
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
local function availabilityName(id)
    local a=Nexus.GameAdapter
    local catalog=a and a.Catalog and a.Catalog()
    local lever=catalog and catalog.levers and catalog.levers[tonumber(id)]
    local name=lever and lever.tomeName
    return name and (tostring(name).." (control #"..id..")") or ("Echo-availability control #"..id)
end
function T.Message(value)
    local s=tostring(value or "")
    if reasons[s] then return reasons[s] end
    local prefix,body=s:match("^(L%d+ %-%- )(.*)$")
    if prefix then return prefix..T.Message(body) end
    body=s:match("^waiting: (.*)$")
    if body then return T.Message(body) end
    local id=s:match("^disabling off%-wishlist tome lever (%d+)$")
    if id then return "Disabling off-Wishlist "..availabilityName(id) end
    id=s:match("^re%-enabling wishlist tome lever (%d+)$")
    if id then return "Enabling Wishlist "..availabilityName(id) end
    local detail
    id,detail=s:match("^lever (%d+): (.*)$")
    if id then return availabilityName(id)..": "..detail:gsub("non%-conformant data","unsupported availability data") end
    if s:find("locked roles remain unknown",1,true) or s:find("awaiting authoritative lock evidence",1,true)
        or s:find("waiting for authoritative locked%-Echo evidence") then
        return "Choose this Wishlist's locked Echo targets in the editor. Your planned build does not have to match the equipped build. Details: "..s
    end
    if s:find("waiting for synchronized permanent locked%-Echo evidence") then
        return "Waiting for the server's current locked Echo list. Details: "..s
    end
    if s:find("waiting for the server mirror",1,true) then
        return "The saved Wishlist is not available from the server yet. Details: "..s
    end
    if s:find("payload changed",1,true) or s:find("preview is stale",1,true) then
        return "This draft changed. Reopen it and review the current targets before saving. Details: "..s
    end
    local lost,gain,fewer=s:match("exact wishlist progress regressed (%d+) %(gained (%d+), shed (%d+) exact stacks%)")
    if lost then return "Not saved: this run matches "..lost.." fewer Wishlist copies ("..gain.." gained, "..fewer.." fewer than the saved build)." end
    if s:find("cleanup-only save added new excess/wrong-quality pollution",1,true) then
        return "Not saved: this run adds excess or wrong-quality copies compared with the saved build."
    end
    if s:find("no net gain",1,true) then return "Not saved: no additional matching Wishlist copies were confirmed." end
    if s:find("coverage lost:",1,true) then return "Not saved: some previously matched Wishlist targets would be lost. See diagnostics for the exact targets." end
    if s:match("^[A-Z][A-Z0-9_]+$") then return "This action is not available yet. Check the status or diagnostics. Details: "..s end
    s=s:gsub("Take wanted Echo %(Pilot%)","Take a needed Echo")
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
function T.Annotation(value)
    return ({wanted="Needed",["returns later"]="Not taken now; a later offer is not guaranteed",
        banked="Held offer",filler="Not on Wishlist",["low quality"]="Different quality from target",
        ["target met"]="Target already met",["wrong quality"]="Different quality from target"})[value] or T.Message(value)
end
function T.Details(code) return "Details: "..tostring(code or "unknown") end
