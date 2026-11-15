-- Issue #171: the whole-addon session pause and Orb mode. Real OrbRuntime,
-- OrbAdapter, its independent frame and the slash commands over synthetic
-- services. Counted: Orb spends (ConfirmSpend), choices (SelectPerk), Orb count
-- requests (RequestCharges) and ownership reads (RequestGrantedPerks).
local PLAN={{spellId=410002,quality=2,stacks=3}}
local H,M,A,O,B
local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;NexusSupportDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil;NexusPanel=nil
 H=dofile('tests/prototype/orbs_support.lua');M,A,O=H.M,H.A,H.O;B=A.Orbs
 H.OrbPlan(PLAN)
end
local function Counts()
 return {spend=H.Count('orb-spend'),take=H.Count('take'),charges=O.requests,owned=H.grantedRequests or 0}
end
local function Same(a,b) for k,v in pairs(a) do if b[k]~=v then return false,k end end return true end

-- O1. Control: on this rig an approved run spends, and selects on its offer.
do
 Fresh();H.Approve(3)
 assert(M.Status().running and H.Count('orb-spend')==1,'control: the approved run requested one Orb')
 H.Offer()
 assert(H.Count('take')==1,'control: the offer is selected')
end

-- O2. Global Pause holds the running run through its own Pause. The offer
-- that arrives, the independent Orb frame, a loading screen and Global Resume
-- send nothing; the run stays paused with the same receipt and maximum. Only
-- its own explicit Resume continues, and only after the global Resume.
do
 Fresh();H.Approve(3)
 local before=M.Status()
 assert(before.running and before.pending and H.Count('orb-spend')==1,'a spend is pending')
 SlashCmdList.NEXUS('pause')
 local s=M.Status()
 assert(s.state=='PAUSED' and not s.running,'the global pause holds the run: '..tostring(s.state))
 assert(s.pending and s.limit==3 and s.spent==before.spent and s.reserved==before.reserved,'receipt, maximum and usage kept')
 local c=Counts()
 H.Offer();H.Advance(5)
 assert(Same(c,Counts()),'no choice, spend or refresh from the offer or the independent frame')
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(15)
 s=M.Status()
 assert(s.state=='PAUSED' and not s.running,'a loading screen does not turn the held run into world recovery: '..tostring(s.state))
 assert(Same(c,Counts()),'nothing sent across the loading screen')
 local ok,why=M.Resume()
 assert(not ok and Same(c,Counts()),'the Orb Resume refuses while Nexus is paused: '..tostring(why))
 assert(not M.Start(3) and Same(c,Counts()),'a new Start refuses while Nexus is paused')
 SlashCmdList.NEXUS('resume');H.Advance(3)
 s=M.Status()
 assert(s.state=='PAUSED' and not s.running and Same(c,Counts()),'Global Resume leaves the Orb run paused')
 assert(M.Resume(),'its own explicit Resume continues')
 H.Advance(1)
 assert(H.Count('take')==1 and H.Count('orb-spend')==1 and M.Status().limit==3,'one choice, same spend and maximum')
end

-- O3. A choice sent before the pause: its exact late result is recorded once
-- while paused, with the same maximum and usage. No next Orb is spent.
do
 Fresh();H.Approve(3);H.Offer()
 assert(H.Count('take')==1 and M.Status().pending,'the choice was sent and waits for its result')
 SlashCmdList.NEXUS('pause')
 H.Result(410002,2);H.Advance(5)
 local s=M.Status()
 assert(not s.pending and s.spent==1 and s.limit==3,'the late result settles the operation once: spent='..tostring(s.spent))
 assert(H.Count('orb-spend')==1 and H.Count('take')==1,'no next spend while paused')
 SlashCmdList.NEXUS('resume');H.Advance(3)
 assert(H.Count('orb-spend')==1 and not M.Status().running,'and none after Global Resume')
end

-- O4. The adapter's own boundaries refuse while paused, before any host call
-- or request mark: a typed preflight REJECTED, never AMBIGUOUS. Unpaused, the
-- same refresh is sent (control).
do
 Fresh()
 SlashCmdList.NEXUS('pause')
 local c=Counts()
 local ok,kind,why,code=B.Spend({},'410001:1',nil)
 assert(ok==nil and kind=='REJECTED' and code=='SESSION_PAUSED','Spend: preflight REJECTED, '..tostring(kind)..'/'..tostring(code))
 ok,kind,why,code=B.Select({},1,'x',410002)
 assert(ok==nil and kind=='REJECTED' and code=='SESSION_PAUSED','Select: preflight REJECTED, '..tostring(kind)..'/'..tostring(code))
 assert(B.Acquire({})==nil,'no new Orb ownership while paused')
 local sent,reason=B.RequestRefresh(false)
 assert(not sent and reason=='session_paused','no Orb count request: '..tostring(reason))
 sent,reason=B.RequestOwnershipRefresh()
 assert(not sent and reason=='session_paused','no ownership request: '..tostring(reason))
 assert(Same(c,Counts()),'nothing reached the host')
 local _,_,_,other=B.Spend({},'410001:1',nil)
 SlashCmdList.NEXUS('resume')
 _,_,_,other=B.Spend({},'410001:1',nil)
 assert(other~='SESSION_PAUSED','unpaused, the same call fails for its own reason')
 assert(B.RequestRefresh(false)==true and O.requests==c.charges+1,'control: the refresh is sent unpaused')
end

-- O5. A pause that lands inside the spend's own final read: the spend is
-- refused before the host call, nothing is reserved or counted as exposure,
-- and the run is held.
do
 Fresh();H.Approve(3);H.Offer();H.Result(410002,2)
 local spends=H.Count('orb-spend')
 local s=M.Status()
 if s.pending then H.Offer();H.Result(410002,2);spends=H.Count('orb-spend');s=M.Status() end
 assert(s.running and not s.pending,'between operations, the run is ready for its next spend')
 local known=ProjectEbonhold.OrbService.IsStateKnown;local armed=true
 ProjectEbonhold.OrbService.IsStateKnown=function(...)
  if armed then armed=false;Nexus.SessionPause.Pause() end
  return known(...)
 end
 H.Advance(1)
 ProjectEbonhold.OrbService.IsStateKnown=known
 s=M.Status()
 assert(Nexus.SessionPause.IsPaused() and not armed,'the pause arrived during the run')
 assert(H.Count('orb-spend')==spends,'no Orb spend after the pause')
 assert(not s.running and not s.pending and (s.reserved or 0)==0,'nothing reserved or pending: '..tostring(s.state))
 assert((s.uncertain or 0)==0,'a refusal before the host call is not exposure')
end

print('PASS session pause holds Orb mode; its own Resume stays explicit')
