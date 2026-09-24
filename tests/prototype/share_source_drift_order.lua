-- A local Share must not leave the catalog permanently unavailable
-- (ROOT_INVALIDATED / SOURCE_DRIFT) when an authority rebind is requested
-- while the Share's catalog mutation is in flight.
--
-- Cause (reproduced deterministically here): the Share's mutation interns its
-- evidence into an open evidence candidate, and BeginAdmissionFinalization
-- computes the publish plan with that candidate's append. A dependent (the
-- data-compaction owner, when a catalog commit replaced the overlay table)
-- then requests a rebind. The lifecycle rebind coordinator re-initialized the
-- evidence pool before the rebind, which discarded the open candidate; the
-- mutation then published a root whose token lacked the candidate's append
-- while its plan advanced the evidence append revision. The next read found
-- that drift and invalidated the root. The rebind request itself was dropped,
-- because Catalog.Init only resumed the in-flight candidate. Nothing else
-- requested a recovery, so the record was never served.
--
-- Real TOC, form, controller, catalog, evidence pool and lifecycle. The only
-- controls are single-slice pacing (no profile clock, so the phases fall on
-- deterministic frames) and one rebind request through the same public call
-- DataCompaction's ReadmitCatalog makes. Synthetic data only.
local T=dofile('tests/prototype/startup_support.lua')
T.SingleSlicePacing()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,C,E,puts,shares
local function Rows(ordinary,locked,first)
 local rows={}
 for i=1,ordinary+locked do
  rows[i]={spellId=(first or 200000)+i,quality=i%4,stacks=1,locked=(i>ordinary) or nil}
 end
 return rows
end
local function Quiet()
 local dc=Nexus.DataCompaction
 local st=dc and type(dc.Stats)=='function' and dc.Stats() or {}
 return not C.RebindRequired() and not C.RootState().candidate and st.pending~=true
end
local function Boot(slots,db)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPostPopup=nil
 H=dofile('tests/prototype/harness.lua');H.playerLevel=80
 NexusDB=db or T.Profile(0,0)
 H.perks.serverActiveSlot=0
 H.perks.serverBuildSlots=slots
 T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
 C,E=Nexus.BuildCatalog,Nexus.LoadoutEvidence
 T.Until(H,function()return C.ManualPreparationStatus().ready end)
 -- Start-up work (first compaction and its rebind requests) settles first.
 T.Until(H,Quiet,20000)
 for _=1,200 do H.Advance(.05,.05) end
 check(Quiet(),'fixture: start-up work settled before the Share')
 puts,shares={},{}
 local put=C.Put
 C.Put=function(record,...)puts[#puts+1]=H.Clone(record);return put(record,...)end
 local broadcast=Nexus.Sync.BroadcastBuildSummary
 Nexus.Sync.BroadcastBuildSummary=function(record,...)shares[#shares+1]=H.Clone(record);return broadcast(record,...)end
end
local function MenuButton(text)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f:IsVisible() then
   for _,r in ipairs({f:GetRegions()})do
    if r.GetText and type(r:GetText())=='string' and r:GetText():find(text,1,true) then return f end
   end
  end
 end
end
local function Share(title)
 Nexus.CommunityBuilds.ShowPostBuild()
 local p=assert(NexusPostPopup)
 p._postWishlistBtn:Click();assert(MenuButton(title),'the source menu lists '..title):Click()
 p._postTitleBox:_NexusSetRawText(title);p._postDescBox:_NexusSetRawText('Synthetic drift regression')
 p._postGoBtn:Click()
 return assert(Nexus.CommunityBuilds.ShareStatus(),title..': the Share was accepted').id
end
local function Copies(rows,locked)
 local n=0;for _,e in ipairs(rows or {})do if (e.locked==true)==locked then n=n+(e.stacks or 1) end end;return n
end
local AFTER_PLAN={index=true,bundle=true,['witness-capture']=true,['witness-verify']=true}
-- One Share. When `atPhase` is set, a rebind is requested at the first frame
-- where the Share's mutation is in that phase with its evidence candidate
-- holding an append. Returns the frame outcome.
local function Run(title,atPhase,external)
 local drift0=C.DebugStats().driftInvalidations
 local id=Share(title)
 local requested,requestedPhase
 local out={id=id}
 for frame=1,4000 do
  local phase=tostring(C.ManualPreparationStatus().phase)
  local window=atPhase=='after-plan' and E.CandidateOpen() and #E.CandidateRevisionPlanV1()>0
   and AFTER_PLAN[phase]
  if atPhase and not requested and C.RootState().candidate and (window or phase==atPhase) then
   if external then external() end
   C.RequestAuthorityRebindV1('SOURCE_REBIND_REQUIRED')
   requested,requestedPhase=frame,phase
  end
  H.Advance(.05,.05)
  local st=C.RootState()
  if st.state=='ROOT_ADMITTED' and not st.candidate and not C.RebindRequired()
   and (C.Get(id)~=nil or (Nexus.CommunityBuilds.ShareStatus(id) or {}).localPending==false) then
   out.frame=frame;break
  end
 end
 local st=C.RootState()
 out.requested,out.requestedPhase=requested,requestedPhase
 out.state,out.reason,out.rebind=st.state,st.reason,C.RebindRequired()
 out.drift=C.DebugStats().driftInvalidations-drift0
 out.status=Nexus.CommunityBuilds.ShareStatus(id) or {}
 out.record=C.Get(id)
 return out
end

-- 1. Adjacent control: the same Share with no rebind request is served.
Boot({[102]={name='DRIFT-CONTROL',verified=false,echoes=Rows(78,6)}})
local r=Run('DRIFT-CONTROL')
check(r.frame and r.record and r.drift==0,'control: the Share is served without drift at frame '..tostring(r.frame))

-- 2. The causal schedule: the rebind is requested after the publish plan was
-- computed and before the mutation publishes.
local slot2={[102]={name='DRIFT-WINDOW',verified=false,echoes=Rows(78,6)}}
Boot(slot2)
r=Run('DRIFT-WINDOW','after-plan')
check(r.requested~=nil,'fixture: the rebind was requested inside the window (phase '..tostring(r.requestedPhase)..')')
check(r.drift==0,'no drift invalidation after the local Share: '..r.drift..' ('..tostring(r.state)..' '..tostring(r.reason)..')')
check(r.state=='ROOT_ADMITTED' and r.rebind==nil,'the catalog is admitted and the rebind request was served: '..tostring(r.state)..' rebind '..tostring(r.rebind))
check(r.record~=nil,'the shared record is served without another Share, reload or reset')
check(r.status.localSaved==true and r.status.localPending==false,'the Share status says saved locally, and it is')
check(Copies(r.record.echoes,false)==78 and Copies(r.record.lockedEchoes,true)==6,
 'exact role copies: '..Copies(r.record.echoes,false)..' ordinary / '..Copies(r.record.lockedEchoes,true)..' locked')
check(#puts==1 and #shares==1 and shares[1].id==r.id,'one local write and one transport hand-off: '..#puts..' / '..#shares)
check(Copies(shares[1].echoes,false)==78 and Copies(shares[1].lockedEchoes,true)==6,'transport receives the same roles')
check(C.ManualPreparationStatus().ready,'the catalog is ready for the next operation')
-- A second legitimate Share in the same session works.
H.perks.serverBuildSlots[103]={name='DRIFT-SECOND',verified=false,echoes=Rows(41,6,200100)}
puts,shares=puts,shares
local second=Run('DRIFT-SECOND')
check(second.record~=nil and second.drift==0 and #puts==2 and #shares==2,'a second Share is stored and handed off once')
-- Both records survive a reload.
local saved=NexusDB
local firstId,secondId=r.id,second.id
Boot(slot2,saved)
check(C.Get(firstId)~=nil and C.Get(secondId)~=nil,'both records survive a reload')

-- 3. Boundary schedules: a rebind requested in each phase of the Share's
-- mutation that falls on a frame boundary under single-slice pacing ends with
-- the record served and no drift invalidation. (The collect, sort, finalize
-- and bundle phases complete inside one frame here.)
for _,phase in ipairs({'put-prepare','rows','index','witness-capture','witness-verify'})do
 local title='DRIFT-'..phase:upper():gsub('%W','')
 Boot({[102]={name=title,verified=false,echoes=Rows(78,6)}})
 local b=Run(title,phase)
 check(b.record~=nil and b.drift==0 and b.state=='ROOT_ADMITTED' and b.rebind==nil,
  'rebind requested in phase '..phase..': served, no drift ('..tostring(b.state)..', drift '..b.drift..')')
 check(b.requested~=nil and b.requestedPhase==phase,'fixture: the rebind was requested in phase '..phase)
end

-- 4. Genuine drift is still refused safely, and the requested rebind recovers
-- the catalog from the current durable source. An outside writer replaces the
-- retention-marker table inside the durable bundle while the Share's mutation
-- is in flight (the kind of replacement DataCompaction reports).
Boot({[102]={name='DRIFT-EXTERNAL',verified=false,echoes=Rows(78,6)}})
local function Replace()
 local bundle=rawget(NexusDB,'authorityBundle')
 local current=bundle and rawget(bundle,'communityRetentionEvictions') or {}
 local copy={};for k,v in pairs(current)do copy[k]=v end
 rawset(bundle,'communityRetentionEvictions',copy)
end
local drift0=C.DebugStats().driftInvalidations
r=Run('DRIFT-EXTERNAL','after-plan',Replace)
check(r.requested~=nil,'fixture: the outside replacement happened inside the window')
check(C.DebugStats().driftInvalidations-drift0>=1,'the drift guard still fires on a genuine outside change')
check(r.record==nil and r.status.localSaved~=true,'the refused mutation is not committed and not reported as saved: '..tostring(r.status.localStage))
check(#shares==0,'nothing is handed to transport for the refused Share')
check(r.state=='ROOT_ADMITTED' and r.rebind==nil,'the requested rebind re-admitted the catalog: '..tostring(r.state)..' '..tostring(r.reason))
check(C.ManualPreparationStatus().ready,'the catalog is usable again without a reload')
print('PASS share_source_drift_order: no drift after a local Share under a rebind in any mutation phase; roles, one write and one hand-off; second Share; reload; genuine drift refused and recovered checks='..checks)
