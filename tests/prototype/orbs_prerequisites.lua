local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();assert(M.SuggestSources())
O.known=false;check(not M.Prepare(),'unknown balance blocks');O.known=true
O.charges=0;check(not M.Prepare(),'zero balance blocks');O.charges=10
ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',true)
check(not M.Prepare(),'host automatic picker blocks')
ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',false)
H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
check(not M.Prepare(),'ordinary outstanding board blocks')
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=410002
check(not M.Prepare(),'host pending action blocks');H.perks.pendingSelectSpellId=nil
O.offer=true;check(not M.Prepare(),'unrelated Orb offer blocks');O.offer=false
local confirm=ProjectEbonhold.OrbService.ConfirmSpend;ProjectEbonhold.OrbService.ConfirmSpend=nil
local state=M.Status();check(state.error and state.error:find('ConfirmSpend',1,true),'missing game capability explained')
check(not M.Prepare() and H.Count('orb-spend')==0,'unsupported capability never probed by spending')
ProjectEbonhold.OrbService.ConfirmSpend=confirm
local p=assert(M.Prepare());O.charges=9
check(not M.Confirm(p.token) and H.Count('orb-spend')==0,'changed resources invalidate confirmation')
O.charges=10;H.Approve(2,false)
check(not A.UploadWishlist('Forbidden',{{spellId=410002,quality=2,stacks=1}},101),'target upload cannot race active Orb ownership')
check(not M.SetRecycle(true) and not M.SetSource('410001:1',0),'approved pool/recycle immutable during run')
check(not M.SetLimit(500),'ordinary setter cannot reset active budget')
local spent=H.Count('orb-spend');H.now=H.now+10.1;M.Pump()
check(O.requests==1 and M.Status().pending,'one read-only automatic refresh after offer timeout')
H.now=H.now+10.1;M.Pump()
check(M.Status().state=='PAUSED' and O.requests==1,'second timeout pauses rather than endless refresh')
H.now=H.now+60;M.Pump();check(O.requests==1 and H.Count('orb-spend')==spent,'paused timeout cannot repeat mutation or automatic refresh')
O.charges=20;M.Pump();check(H.Count('orb-spend')==spent,'unexpected resources never restart run')
check(M.Stop(),'Stop is available during uncertainty')
print('PASS Orb capabilities, sources, host competition, resources and timeout controls='..checks)
