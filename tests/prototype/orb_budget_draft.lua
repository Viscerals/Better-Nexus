-- The Orb window's maximum draft (owner answers BN-ORB-DEFAULT-OWNER-ANSWER-001
-- and -002): with no saved maximum the unapproved draft follows the confirmed
-- Orb balance, capped at 1000, until the player types an amount. Max returns
-- the draft to that live tracking (it is not a snapshot). A typed amount
-- (also the same number, a partial or an empty text) stops tracking and stays
-- through refresh and close/reopen. A valid saved maximum is kept as saved.
-- Only the explicit preparation of a new run after a finished one returns the
-- draft to tracking. Start approves the amount shown; an approved maximum
-- never follows the balance.
--
-- Real OrbRuntime, OrbAdapter and Orb window handlers with the synthetic Orb
-- service of orbs_support.lua (SYNTHETIC ids). Expected outcomes are written
-- here from the owner answers, not read back from the implementation.
-- Mutator entry points are counted, refused calls included; saved data is
-- read from the Store row without calling Status() first.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Ser(v,seen)
 seen=seen or {}
 if type(v)=='function' then return 'fn' end
 if type(v)~='table' then return tostring(v) end
 if seen[v] then return '<cycle>' end;seen[v]=true
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local o={};for _,k in ipairs(keys) do o[#o+1]=tostring(k)..'='..Ser(v[k],seen) end
 return '{'..table.concat(o,',')..'}'
end
local function Saved()
 local key=Nexus.Store.CurrentOwnerKey()
 local row=type(NexusDB)=='table' and type(NexusDB.chars)=='table' and NexusDB.chars[key]
 return type(row)=='table' and row.orbRefinement or nil
end
local function SavedMax() local s=Saved();return s and s.maxOrbs end
local WATCH={'Start','Resume','Pause','Stop','Recheck','Prepare','Confirm','PrepareLimitIncrease','ConfirmLimit',
 'UseAssignedWishlist','Exclude','ClearExclusions','SetRecycle','SetSource','SuggestSources','SetLimit'}
local calls,writes={},0
local function Watch(M)
 calls={}
 for _,n in ipairs(WATCH) do
  local real=M[n]
  if real then M[n]=function(...) calls[n]=(calls[n] or 0)+1;return real(...) end end
 end
 -- Writes that change this character's saved Orb data (preferences and
 -- receipt). Other Store writers (for example the assignment read) are not
 -- Orb preference writes.
 local o=Nexus.MainInternals.StoreAuthorityOwner
 local realWrite=o.UpdateStateV1
 o.UpdateStateV1=function(...)
  local before=Ser(Saved())
  local r={realWrite(...)}
  if Ser(Saved())~=before then writes=writes+1 end
  return unpack(r)
 end
 writes=0
end
local function N(name) return calls[name] or 0 end
-- The runtime's lifecycle and approval entry points: none may run from
-- following the balance, Max, typing, opening or refreshing.
local function NoLifecycle()
 for _,n in ipairs({'Start','Resume','Pause','Stop','Recheck','Prepare','Confirm','PrepareLimitIncrease','ConfirmLimit'}) do
  if N(n)>0 then return false,n end
 end
 return true
end
local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 if NexusOrbPanel then NexusOrbPanel:Hide() end
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 return H,H.M,H.A,H.O
end
local function Reload(H)
 H.Fire('PLAYER_LOGOUT')
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 H.M=Nexus.OrbRuntime
 return Nexus.OrbRuntime
end
local function Tick(f) f:GetScript('OnUpdate')(f,.25) end
-- The player types: focus, then text (the client reports it as user input).
local function Type(f,text) f.limit:SetFocus();f.limit:SetText(text) end
local function Leave(f) f.limit:ClearFocus() end
local function Enter(f) f.limit:GetScript('OnEnterPressed')(f.limit) end
local function Escape(f) f.limit:GetScript('OnEscapePressed')(f.limit) end
local function Shown(f) return f.limit:GetText() end
local function Draft(M) return M.LimitDraft() end

-- 1. No saved maximum: the draft follows the confirmed balance (44 -> 60 ->
-- 30), capped at 1000, and nothing is written, started or sent.
local H,M,A,O=Fresh()
H.OrbPlan();O.charges=44
local actions=#H.actions
local f=Nexus.OrbPanel.Show();Watch(M);Tick(f)
check(SavedMax()==nil,'fixture: no saved maximum')
check(M.Status().config.maxOrbs==nil,'an absent saved maximum is not the old fallback 10')
check(Shown(f)=='44' and Draft(M).tracking,'the untouched draft shows the confirmed balance: '..Shown(f))
O.charges=60;Tick(f);check(Shown(f)=='60','it follows an increase')
O.charges=30;Tick(f);check(Shown(f)=='30','and a decrease')
O.charges=1500;Tick(f);check(Shown(f)=='1000','the suggestion is capped at 1000')
check(f.balance:GetText():find('Maximum follows this balance (up to 1000)',1,true)~=nil,'the draft names what it follows')
check(f.max.tooltip:find('until you enter another amount or start the run',1,true) and f.max.tooltip:find('does not spend Orbs',1,true),'Max explains itself')
check(writes==0 and NoLifecycle() and #H.actions==actions,'following the balance writes, starts and sends nothing')

-- 2. A typed amount stops tracking and stays through refresh, a balance
-- change and close/reopen. Typing alone saves nothing; Enter saves it.
O.charges=44;Tick(f)
Type(f,'10');check(not Draft(M).tracking,'typing stops tracking')
Leave(f);O.charges=60;Tick(f);check(Shown(f)=='10','the typed amount stays through refresh and a balance change')
f:Hide();Nexus.OrbPanel.Show();Tick(f);check(Shown(f)=='10' and not Draft(M).tracking,'and through close and reopen')
check(writes==0 and SavedMax()==nil,'typing alone writes nothing')
f.limit:SetFocus();Enter(f)
check(SavedMax()==10 and writes==1 and N('SetLimit')==1,'Enter saves it through the existing explicit path')

-- 3. Max returns the draft to live tracking: it is not a snapshot.
f.max:Click();check(Draft(M).tracking and Shown(f)=='60','Max follows the current balance')
O.charges=45;Tick(f);check(Shown(f)=='45','Max keeps following the balance down')
O.charges=70;Tick(f);check(Shown(f)=='70','and up')
check(SavedMax()==10 and writes==1,'Max writes nothing; the saved maximum is kept')
-- Max while the box still has keyboard focus (a click does not take it):
-- the tracked amount is shown and a Start would approve it, not the typing.
Type(f,'11');f.max:Click()
check(Draft(M).tracking and Shown(f)=='70' and not f.limit:HasFocus(),'Max with the box focused: tracking, the tracked amount shown')
-- Typing the same number is still the player's own amount.
Type(f,'70');Leave(f);check(not Draft(M).tracking,'typing the same number stops tracking')
O.charges=80;Tick(f);check(Shown(f)=='70','the same-number entry stays')

-- 4. An empty or partial entry is an edit. Start never falls back to the
-- saved maximum.
f.max:Click();Type(f,'');Leave(f);Tick(f)
check(Shown(f)=='' and not Draft(M).tracking and Draft(M).value==nil,'an empty entry is an edit with no value')
check(f.balance:GetText():find('Enter a whole-number maximum',1,true)~=nil,'the window asks for a valid amount')
f.start:Click()
check(f.notice:GetText():find('Nothing was started',1,true) and N('Start')==0 and N('Prepare')==0,'Start refuses an empty maximum; the saved 10 is not used: '..f.notice:GetText())
Type(f,'4');Leave(f);O.charges=44;Tick(f);check(Shown(f)=='4' and not Draft(M).tracking,'a partial entry stays as typed')

-- 5. Escape cancels the typing: the draft is what it was before.
f.max:Click();check(Shown(f)=='44','fixture: tracking 44')
Type(f,'9');Escape(f);check(Draft(M).tracking and Shown(f)=='44','Escape after typing on a tracking draft: tracking again')
Type(f,'12');Enter(f);Type(f,'99');Escape(f)
check(not Draft(M).tracking and Shown(f)=='12' and SavedMax()==12,'Escape after a saved amount restores that amount')

-- 6. Focus alone and a programmatic text are not edits.
f.max:Click();f.limit:SetFocus();f.limit:ClearFocus();O.charges=50;Tick(f)
check(Draft(M).tracking and Shown(f)=='50','focus alone is not an edit')
f.limit:SetText('5');check(Draft(M).tracking,'a text set without focus (programmatic) is not an edit')
Tick(f);check(Shown(f)=='50','the next refresh shows the tracked amount again')

-- 7. Balance states. Zero stays zero; unknown and malformed are unavailable
-- (tracking intent kept); a typed amount is kept separately.
O.charges=0;Tick(f)
check(Shown(f)=='0' and not f.max:IsEnabled() and not f.start:IsEnabled(),'a confirmed zero shows 0 (not 1 or 10); Max and Start unavailable')
O.known=false;Tick(f)
check(Shown(f)=='' and f.balance:GetText():find('unavailable until it is confirmed',1,true) and not f.max:IsEnabled(),'an unknown balance: the proposal is unavailable')
check(Draft(M).tracking,'the tracking intent is kept')
local starts=N('Start');f.start:Click();check(N('Start')==starts,'no Start while the balance is unknown')
O.known=true;O.charges=20;Tick(f);check(Shown(f)=='20','a later confirmed balance updates the draft')
O.charges=-1;Tick(f);check(Shown(f)=='','a negative balance is malformed: unavailable')
O.charges=2.5;Tick(f);check(Shown(f)=='','a fractional balance is malformed: unavailable')
O.charges=0;Tick(f);Type(f,'5');Leave(f);O.charges=20;Tick(f)
check(Shown(f)=='5' and not Draft(M).tracking,'a typed amount is kept apart from the balance')
Type(f,'1500');Enter(f);check(SavedMax()==1500,'a typed amount above 1000 is not capped (the cap is only the suggestion)')
check(NoLifecycle() and #H.actions==actions,'sections 1-7 started, approved and sent nothing')

-- 8. A valid saved maximum from an earlier build is kept as saved, whatever
-- its value; Max follows the balance without rewriting it.
do
 local H,M,A,O=Fresh()
 H.OrbPlan();assert(M.SetLimit(3))
 Saved().maxOrbs=10 -- an earlier build's saved value (origin unknown)
 M=Reload(H);O.charges=44
 local f=Nexus.OrbPanel.Show();Watch(M);Tick(f)
 check(Shown(f)=='10' and not Draft(M).tracking,'a valid saved maximum (10) is kept; its origin is not inferred')
 O.charges=60;Tick(f);check(Shown(f)=='10','it does not follow the balance')
 f:Hide();Nexus.OrbPanel.Show();Tick(f)
 check(SavedMax()==10 and writes==0,'opening, refresh and reopen rewrite nothing')
 f.max:Click();check(Draft(M).tracking and Shown(f)=='60','Max: the draft follows the balance')
 check(SavedMax()==10 and writes==0,'without migrating or rewriting the saved value')
 f:Hide();Nexus.OrbPanel.Show();O.charges=65;Tick(f)
 check(Draft(M).tracking and Shown(f)=='65','Max tracking stays through close and reopen')
 check(NoLifecycle(),'no lifecycle entry point ran')
end

-- 9. Start approves the amount shown, never a newer balance read at the
-- click; the approved maximum stays fixed. A tracked amount is not saved.
do
 local H,M,A,O=Fresh()
 H.OrbPlan();O.charges=44
 local f=Nexus.OrbPanel.Show();Watch(M);Tick(f)
 check(Shown(f)=='44','fixture: 44 shown')
 O.charges=60 -- no refresh: the window still shows 44
 f.start:Click()
 check(M.Status().running or M.Status().pending,'Start approved the run: '..tostring(f.notice:GetText()))
 check(M.Status().limit==44,'the run is approved for the 44 shown, not the newer 60: '..tostring(M.Status().limit))
 check(SavedMax()==nil,'the tracked amount is not saved as a typed maximum')
 O.charges=100;Tick(f)
 check(M.Status().limit==44 and Shown(f)=='44','the approved maximum stays fixed when the balance changes')
 check(not f.max:IsEnabled(),'Max is unavailable during the run')
 local ok=M.TrackBalance();check(not ok and M.Status().limit==44,'Max refuses during the run; the approved maximum is unchanged')
 check(not M.EditLimitText('7') and M.Status().limit==44,'typing is refused during the run')
 check(not M.NewRunDraft() and M.Status().limit==44,'an active run is not a new-run boundary')
 check(N('PrepareLimitIncrease')==0 and N('ConfirmLimit')==0,'the budget-increase path is not used')
end

-- 10. The explicit preparation of a new run after a finished run returns the
-- draft to tracking; a changed amount needs a new review.
do
 local H,M,A,O=Fresh()
 H.OrbPlan({{spellId=410002,quality=2,stacks=2}});O.charges=10
 local f=Nexus.OrbPanel.Show();Watch(M);Tick(f)
 Type(f,'1');Leave(f);f.start:Click()
 check(M.Status().limit==1 and SavedMax()==1,'fixture: a typed 1 was started and saved (existing path)')
 check(not M.NewRunDraft(),'a running run is not a new-run boundary')
 H.Offer({{spellId=410001,quality=1},{spellId=410003,quality=0},{spellId=410008,quality=1}})
 H.Result(410001,1)
 check(M.Status().state=='FINISHED','fixture: the run finished at its limit: '..M.Status().state)
 Tick(f);check(Shown(f)=='1' and not Draft(M).tracking,'before a new run the typed amount stays')
 f:Hide();Nexus.OrbPanel.Show();Tick(f);check(Shown(f)=='1','reopening is not a new run')
 local starts=N('Start')
 Type(f,'7') -- still focused when the player clicks Start new run
 f.start:Click()
 check(Draft(M).tracking and Shown(f)==tostring(O.charges),'preparing a new run returns the draft to the balance: '..Shown(f))
 check(f.start:GetText()=='Confirm new run' and f.status:GetText():find('up to '..Shown(f)..' Orb',1,true),'the amount is shown for review')
 O.charges=5;Tick(f)
 check(f.start:GetText()=='Start new run' and f.notice:GetText():find('The maximum changed',1,true),'a changed amount withdraws the confirmation')
 check(N('Start')==starts,'nothing was started')
 f.start:Click();check(f.start:GetText()=='Confirm new run' and Shown(f)=='5','review again')
 f.start:Click();check(M.Status().limit==5 and N('Start')==starts+1,'the new run is approved for the reviewed 5')
end

-- 11. An assignment refresh keeps the draft and its mode.
do
 local H,M,A,O=Fresh()
 H.OrbPlan();O.charges=44
 local f=Nexus.OrbPanel.Show();Watch(M);Tick(f)
 Type(f,'10');Leave(f)
 assert(A.SetFirstLoadoutWishlistIdentity('Orb test',{{spellId=410004,quality=3,stacks=1}}))
 Tick(f);check(Shown(f)=='10' and not Draft(M).tracking,'an assignment refresh keeps the typed amount')
 f.max:Click()
 assert(A.SetFirstLoadoutWishlistIdentity('Orb test',{{spellId=410002,quality=2,stacks=1}}))
 O.charges=50;Tick(f);check(Draft(M).tracking and Shown(f)=='50','and keeps tracking')
end

-- 12. The state changes between render and click: Max checks again and keeps
-- the draft.
do
 local H,M,A,O=Fresh()
 H.OrbPlan();O.charges=44
 local f=Nexus.OrbPanel.Show();Watch(M);Tick(f)
 Type(f,'10');Enter(f);Tick(f);check(f.max:IsEnabled(),'fixture: Max offered')
 O.known=false
 f.max:Click()
 check(not Draft(M).tracking and Shown(f)=='10' and f.notice:GetText():find('Max needs a confirmed Orb balance',1,true),'the balance became unknown: Max refuses and keeps 10')
 O.known=true;Tick(f);check(f.max:IsEnabled(),'fixture: Max offered again')
 H.Approve(2) -- a run starts elsewhere; the window has not refreshed
 f.max:Click()
 check(M.Status().limit==2 and f.notice:GetText():find('fixed during this run',1,true),'the run became active: Max refuses; the approved maximum is unchanged')
end

-- 13. Saved data unavailable: the draft still works in memory, nothing is
-- written, and Start stays refused.
do
 local H,M,A,O=Fresh()
 H.OrbPlan();O.charges=44
 local f=Nexus.OrbPanel.Show();Watch(M);Tick(f)
 local chars=NexusDB.chars;NexusDB.chars=nil
 Type(f,'8');Leave(f);f.max:Click();O.charges=30;Tick(f)
 check(Draft(M).tracking and Shown(f)=='30','the draft works in memory')
 check(not M.Status().canStart,'Start stays refused without durable saved data')
 NexusDB.chars=chars
 check(SavedMax()==nil,'nothing was written')
end

-- 14. Matched runs with and without the window's draft operations: an active
-- approved run and a restored receipt end identical (spends, choices,
-- approved maximum, saved data).
local function Snap(H,M)
 local s=M.Status()
 return Ser({state=s.state,limit=s.limit,spent=s.spent,reserved=s.reserved,pending=s.pending,
  saved=Saved(),actions=H.actions})
end
local function Operate(f,M)
 f.max:Click();Type(f,'3');Leave(f);Escape(f);M.TrackBalance();M.EditLimitText('9');M.CancelLimitEdit()
 for _=1,4 do Tick(f) end
end
local function Active(ui)
 local H,M,A,O=Fresh()
 H.OrbPlan();H.Approve(2);H.Offer()
 if ui then Operate(Nexus.OrbPanel.Show(),M) end
 for _=1,12 do H.Advance(.25) end
 return Snap(H,M)
end
local function Restored(ui)
 local H,M,A,O=Fresh()
 H.OrbPlan();H.Approve(2);H.Offer()
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 M=Reload(H);H.Notify();A.Poll()
 if ui then Operate(Nexus.OrbPanel.Show(),M) end
 for _=1,12 do H.Advance(.25) end
 return Snap(H,M)
end
do
 local control,operated=Active(false),Active(true)
 check(control:find('limit=2',1,true)~=nil,'fixture: the active run is approved for 2: '..control)
 check(operated==control,'an active run is identical with and without draft operations:\n'..operated..'\nvs\n'..control)
 control,operated=Restored(false),Restored(true)
 check(control:find('pending=true',1,true)~=nil,'fixture: the restored receipt is recovered: '..control)
 check(operated==control,'a restored receipt is identical with and without draft operations:\n'..operated..'\nvs\n'..control)
end

-- 15. Layout of the maximum row in the conservative text model (7.0 px per
-- character, 17 px lines) and the default one (5.5 px, 12 px): readable
-- labels, distinct hit targets with padding, inside the window.
do
 local H,M,A,O=Fresh()
 H.OrbPlan();local f=Nexus.OrbPanel.Show()
 local function X(r) local p={r:GetPoint(1)};return type(p[2])=='number' and p[2] or p[4] end
 local function Y(r) local p={r:GetPoint(1)};return type(p[2])=='number' and p[3] or p[5] end
 local CAPS=20
 local row={{f.limitLabel,'label'},{f.limit,'box'},{f.max,'Max'},{f.start,'Start'},{f.stop,'Stop'}}
 for i=2,#row do
  local a,b=row[i-1][1],row[i][1]
  local gap=X(b)-(X(a)+a:GetWidth())
  check(gap>=6,row[i-1][2]..' and '..row[i][2]..' are distinct targets with padding: '..gap)
 end
 check(X(f.start)-(X(f.max)+f.max:GetWidth())>=12,'Max is visibly separate from Start')
 check(X(f.stop)+f.stop:GetWidth()<=f:GetWidth()-4,'the row stays inside the window')
 for _,m in ipairs({{'default',5.5,12},{'conservative',7.0,17}}) do
  check(#'Maximum Orbs this run:'*m[2]<=f.limitLabel:GetWidth(),m[1]..': the label fits')
  check(#'Max'*m[2]+CAPS<=f.max:GetWidth(),m[1]..': the Max label fits')
  for _,label in ipairs({'Start','Start new run','Confirm new run','Pause','Resume'}) do
   check(#label*m[2]+CAPS<=f.start:GetWidth(),m[1]..': the Start button label fits: '..label)
  end
  check(#'99999'*m[2]<=f.limit:GetWidth()-10,m[1]..': five digits fit in the box')
  for _,line in ipairs({
   'Orb balance: unsupported. The client does not expose the Orb balance capability.',
   'Maximum follows this balance (up to 1000) until you enter another amount.',
   'Maximum follows the confirmed balance; unavailable until it is confirmed.',
   'Enter a whole-number maximum from 1 to 10,000, or press Max.'}) do
   check(#line*m[2]<=f.balance:GetWidth(),m[1]..': one balance line stays one line: '..line)
  end
  check(2*m[3]<=f.balance:GetHeight(),m[1]..': the balance and the draft line fit the balance box')
 end
 check(Y(f.max)==Y(f.start) and f.max:GetHeight()==f.start:GetHeight(),'Max sits on the Start row, same height')
end

print('PASS orb_budget_draft checks='..checks)
