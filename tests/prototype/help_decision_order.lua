-- Help and the player guide describe the actual ordinary decision order
-- (BN-FULL-REVIEW-PRIVATE-BUILD-003). Each documented rule is checked against
-- the real EchoWeaver decision used by Nexus (EchoWeaver.NEXUS_POLICY), and
-- the text is checked for the rule, its position and the removed absolute
-- claims. Also: the Saved Build save/load warning and the Orb-service
-- distinction (an existing service with unknown state also pauses ordinary
-- rolling). Reading Help changes nothing.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function has(text,s) return type(text)=='string' and text:find(s,1,true)~=nil end
local function before(text,a,b,label)
 local i,j=text:find(a,1,true),text:find(b,1,true)
 check(i and j and i<j,label..' ("'..a..'" before "'..b..'")')
end
local actions,sent=#H.actions,#H.sent
local function Page(id) Nexus.Help.Show(id);return NexusHelpWindow.body:GetText() end
local start,rolling,orbs=Page('start'),Page('rolling'),Page('orbs')
local file=assert(io.open('README-PROTOTYPE.md','rb'));local guide=file:read('*a'):gsub('%s+',' '):gsub('%*%*','');file:close()

-- 1. The real decisions behind each documented rule.
local W=Nexus.EchoWeaver
check(W.NEXUS_POLICY.rerollIgnoresSatisfiedTargets==true,'Nexus policy: only a still-needed offer stops a Reroll')
local NEEDED,MET,OTHER1,OTHER2=200001,200002,200003,200004
local function Decide(o)
 local requested={[NEEDED]=o.neededCopies or 3,[MET]=1}
 local outstanding={[NEEDED]=o.missing or 0,[MET]=0}
 local total=(o.missing or 0)
 local choices={}
 for i,id in ipairs(o.board) do choices[i]={echoID=id,quality=2,index=i,selectable=true,frozen=o.frozen and o.frozen[i] or nil} end
 return W.Decide({objective={requestedCounts=requested,outstandingCounts=outstanding,outstandingTotal=total},
  remainingPicks=o.left,
  board={choices=choices,twoFrozenRerollProhibited=o.twoFrozen,capabilities={canSelect=true,canBanish=true,canFreeze=o.freeze~=false,canReroll=o.reroll~=false}},
  resources={banishesRemaining=o.banishes or 3,freezesRemaining=1,rerollsRemaining=o.rerolls or 3},
  commonBoardRerollEnabled=o.reroll~=false,policy=W.NEXUS_POLICY})
end
local d=Decide({missing=0,left=30,board={OTHER1,OTHER2,MET}})
check(d.action=='SELECT' and d.echoID==OTHER1,'targets complete: takes an available offer outside the Wishlist: '..tostring(d.action))
d=Decide({missing=3,left=4,board={OTHER1,MET,OTHER2}})
check(d.action=='REROLL','no still-needed offer: Reroll before Banish even with few picks left: '..tostring(d.action))
d=Decide({missing=3,left=4,board={OTHER1,MET,OTHER2},reroll=false})
check(d.action=='BANISH','Reroll off and few picks left: Banish an offer that is not needed: '..tostring(d.action))
d=Decide({missing=3,left=4,board={OTHER1,MET,OTHER2},reroll=false,banishes=0})
check(d.action=='SELECT' and d.echoID~=NEEDED,'no Reroll and no Banish left: takes an available offer: '..tostring(d.action))
d=Decide({missing=1,left=200,board={OTHER1,MET,OTHER2},reroll=false})
check(d.action=='SELECT','Reroll off and many picks left: takes an available offer, no Banish: '..tostring(d.action))
d=Decide({missing=1,left=200,board={OTHER1,NEEDED,OTHER2}})
check(d.action=='SELECT' and d.echoID==NEEDED,'a needed offer is taken: '..tostring(d.action))
d=Decide({missing=3,left=4,board={OTHER1,NEEDED,OTHER2}})
check(d.action=='FREEZE' and d.echoID==NEEDED,'very few picks, two or more missing, Banish available: Freeze the needed offer: '..tostring(d.action))
d=Decide({missing=3,left=4,board={OTHER1,NEEDED,OTHER2},freeze=false})
check(d.action=='SELECT' and d.echoID==NEEDED,'Freeze off: the needed offer is taken: '..tostring(d.action))
d=Decide({missing=1,left=4,board={OTHER1,NEEDED,OTHER2}})
check(d.action=='SELECT','one copy missing: no Freeze: '..tostring(d.action))
d=Decide({missing=3,left=150,board={OTHER1,MET,OTHER2},rerolls=3})
check(d.action=='REROLL','many picks left: Reroll is not kept back: '..tostring(d.action))
-- Review cases (fixed pressure limits, the frozen-needed branch, two frozen).
d=Decide({missing=1,left=18,board={OTHER1,MET,OTHER2},reroll=false})
check(d.action=='BANISH','18 picks is "few" even with one copy missing: Banish: '..tostring(d.action))
d=Decide({missing=1,left=19,board={OTHER1,MET,OTHER2},reroll=false})
check(d.action=='SELECT','19 picks and one missing copy is not "few": take an available offer: '..tostring(d.action))
d=Decide({missing=3,left=4,board={NEEDED,OTHER1,OTHER2},frozen={true}})
check(d.action=='BANISH','only a frozen needed offer, very few picks, Banish left: Banish an offer not needed: '..tostring(d.action))
d=Decide({missing=1,left=200,board={NEEDED,OTHER1,OTHER2},frozen={true}})
check(d.action=='SELECT' and d.echoID==NEEDED,'only a frozen needed offer, many picks: take the frozen offer: '..tostring(d.action))
d=Decide({missing=3,left=4,board={NEEDED,OTHER1,NEEDED},frozen={true}})
check(d.action=='SELECT' and d.index==3,'after a Freeze, another needed offer is taken: '..tostring(d.action))
d=Decide({missing=3,left=30,board={OTHER1,MET,OTHER2},twoFrozen=true})
check(d.action~='REROLL','two frozen offers: no Reroll: '..tostring(d.action))

-- 2. The text states those rules, in that order, without the old absolutes.
for label,text in pairs({Help=rolling,guide=guide}) do
 check(has(text,'All targets complete: Nexus takes an available offer. It can be outside the Wishlist.'),label..': fallback when targets are complete')
 check(has(text,'No offer is still needed: Reroll comes first, when Reroll is allowed, you have one and fewer than two offers are frozen.'),label..': Reroll first when nothing needed')
 check(has(text,'Picks are very few when 6 or fewer remain, or no more than the missing copies.'),label..': "very few" uses the real limits')
 check(has(text,'Picks are few when 18 or fewer remain, or the missing copies are at least a third of them.'),label..': "few" uses the real limits')
 check(has(text,'After a Freeze, Nexus takes another needed offer if one is shown. While picks stay very few and a Banish is left, it banishes an offer that is not needed. Otherwise it takes the frozen offer.'),label..': the frozen-needed branch')
 check(has(text,'Freeze is used only in some cases'),label..': Freeze is conditional')
 check(has(text,'which can be outside the Wishlist'),label..': fallback outside the Wishlist')
 check(has(text,'Nexus does not keep rerolls back for later in a run.'),label..': no reserved rerolls')
 check(has(text,'only allows or forbids that action; it does not choose another strategy'),label..': reroll/freeze commands are permissions')
 check(has(text,'not a guarantee of any future offer or of a complete build'),label..': no guarantee')
 before(text,'Reroll comes first','Nexus banishes',label..': Reroll stated before Banish')
 check(not has(text,'Take chooses a needed offer'),label..': no absolute "Take chooses a needed offer"')
 check(not has(text,'[G] means'),label..': the panel prefix is named as shown')
end
check(has(rolling,'[Guaranteed offer] means the server marks this offer guaranteed.'),'Help names the shown prefix')
check(has(rolling,'Frozen offer is a card kept by Freeze.'),'Help names the Frozen offer label')

-- 3. Saved Build save/load: replacement warning before the plan-only note.
for label,text in pairs({Help=start,guide=guide}) do
 check(has(text,'Saving writes your current Echoes into the slot you selected'),label..': what saving does')
 check(has(text:upper(),'REPLACES WHAT THAT SLOT HELD'),label..': saving replaces the slot')
 check(has(text,'Nexus cannot undo a save'),label..': no undo')
 check(has(text,'Nexus never loads a Saved Build for you'),label..': Nexus does not load')
 check(has(text,'Assigning a Wishlist by itself changes no Saved Build.'),label..': assignment by itself changes nothing')
 before(text,'Saving writes your current Echoes','saves only a plan',label..': warning before the plan-only note')
end
check(has(start,'What Nexus is for:'),'Help: plain purpose for a newcomer')
before(start,'With Auto ON, Nexus may replace that active Saved Build','Saving and loading Saved Builds','the automatic-save warning stays first')

-- 4. Orb service: absent versus unknown state.
for label,text in pairs({Help=orbs,guide=guide}) do
 check(has(text,'If the game has no Orb service, only Orb mode is unavailable and ordinary rolling still works.'),label..': absent service')
 check(has(text,'If the Orb service exists but Nexus cannot read its state, ordinary rolling waits too.'),label..': unknown state pauses ordinary rolling')
 check(not has(text,'disable only Orb mode'),label..': old sentence removed')
end
NexusHelpWindow:Hide()
check(#H.actions==actions and #H.sent==sent,'reading Help sends and performs nothing')
print('PASS help_decision_order checks='..checks)
