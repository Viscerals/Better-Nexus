-- M7 (Root conditions retryOff and retryContext; work item 4): Retry Share of
-- a stopped Share states why it is offered and what the current saved mode
-- does, and each click says what actually happened. CanRetryShare and the mode
-- rules are unchanged, including the reachable Off refusal: showing the view
-- enables nothing and starts nothing. A click carries the context the Retry
-- was drawn in; RetryShare refuses a changed context ("player or catalog
-- changed") and queues nothing. retryOnFull, current-mode admission, the
-- explicit click, the 247-byte budget and the provenance guards are the
-- existing ones.
-- Fixture boundaries, kept apart:
--  * INJECTED: the first Share's queue admission is refused once at the real
--    transport (EnqueueControl, queueClass "share") with a synthetic reason, as
--    sync_saved_mode_share_retry injects a full queue. That makes the Share
--    terminal and retryable; it is fixture behaviour, not a production refusal.
--  * PRODUCTION: the Off refusal of a Retry is the saved-mode policy's own.
--  * SYNTHETIC: the stale-context control replaces the Retry button's drawn
--    context with one whose owner differs from the current one, as when the
--    player changed after the view was drawn.
-- If the injected refusal does not leave a retryable Share, the SETUP fails
-- and the scenarios that need it are skipped (a blocked control, reported).
-- Categories (view_regression_support): EXPECT is behaviour added in M7
-- (predicted to fail on accepted M6 0924d06a; not executed by the author); a
-- missing drawn context there is a failed EXPECT, not a raised scenario. GUARD
-- already holds there and must keep holding; SETUP is the fixture.
-- Oracles: the real Build Library detail panel and Retry button handler, the
-- real controller and Sync, printed lines, Sync.BroadcastBuildSummary calls
-- (pass-through spy keeping the real result) and the summaries on the wire.
-- Real TOC boot, format-5 saved data (Manual). Artificial names only.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('ux_retry_share_feedback')

local TITLE='Retry R1'
local injecting=false
F.fileHooks={['core\\SyncTransport.lua']=function()
 local factory=Nexus.SyncInternals.Transport
 local New=factory.New
 factory.New=function(...)
  local T=New(...)
  local enqueue=T.EnqueueControl
  T.EnqueueControl=function(payload,metadata)
   if injecting and type(metadata)=='table' and metadata.queueClass=='share' then
    injecting=false;return false,'synthetic transport refusal'
   end
   return enqueue(payload,metadata)
  end
  return T
 end
end}
local db=F.Database({mutate=function(d)d.settings.syncMode='manual';d.communityBuilds={};d.chars={} end})
local H=F.Boot(db,function(h)
 h.perks.serverBuildSlots={[102]={name='NEXUS-TEST-RETRY-FEEDBACK',verified=false,echoes={{spellId=200001,quality=1,stacks=3}}}}
end)
F.fileHooks=nil
local CB,S,P=Nexus.CommunityBuilds,Nexus.Sync,Nexus.SyncModePolicy

local summaries={}
local realSummary=S.BroadcastBuildSummary
S.BroadcastBuildSummary=function(record,options,...)
 local r={pcall(realSummary,record,options,...)}
 summaries[#summaries+1]={id=type(record)=='table' and record.id or nil,retryOnFull=type(options)=='table' and options.retryOnFull==true,
  ok=r[1],queued=r[2],why=r[3]}
 if not r[1] then error(r[2],0) end
 return unpack(r,2)
end
local realPrint,said=print,{}
print=function(...)
 local t={}
 for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end
 said[#said+1]=table.concat(t,' ')
 return realPrint(...)
end
local function SaidSince(mark,needle)
 for i=mark+1,#said do if V.Plain(said[i]):find(needle,1,true) then return V.Plain(said[i]) end end
end
local function Until(limit,fn) for _=1,limit do if fn() then return true end;H.Advance(.05,.05) end;return fn() end
local function Has(text,needle) return tostring(text or ''):find(needle,1,true)~=nil end
local function WLBI(since)
 local n=0
 for i=since+1,#H.sent do if V.Plain(H.sent[i].text):gsub('||','|'):gsub('^P%d+:',''):find('^WLBI|') then n=n+1 end end
 return n
end
local function Mode(mode)
 local ok=P.ApplyChoice(mode,(P.Choice() or {}).token)
 return ok==true and P.Mode()==mode
end
local function Panel() local f=NexusCommunityBuildsFrame;return f and f._detailPanel end
local function Show(id)
 CB.ShowBuild(id);CB.Refresh()
 Until(400,function() local p=Panel();return p and p:IsShown() and p._nexusShownId==id end)
 local p=Panel()
 return p and p:IsShown() and p._nexusShownId==id and p or nil
end

C.setup(P.Mode()=='manual','fixture: accepted format 5 with Manual',P.Mode())
Until(400,function() return Nexus.BuildCatalog.ManualPreparationStatus().ready end)
-- The Share form's own explicit Share, refused once at the transport.
CB.ShowPostBuild()
local post=NexusPostPopup
C.setup(post~=nil,'fixture: the Share form is open')
local id
if post then
 post._postTitleBox:_NexusSetRawText(TITLE)
 post._postDescBox:_NexusSetRawText('Synthetic retry feedback share')
 injecting=true
 post._postGoBtn:Click()
 local status=CB.ShareStatus()
 id=status and status.id
end
C.setup(id~=nil,'fixture: the Share saved a listing locally',printable(id))
Until(600,function() local s=id and S.GetShareStatus(id);return type(s)=='table' and s.terminal==true end)
local share=id and S.GetShareStatus(id)
print('OBSERVED','first Share status','outcome='..printable(share and share.outcome),'reason='..printable(share and share.reason),
 'terminal='..printable(share and share.terminal),'injected='..tostring(not injecting))
C.setup(share and share.terminal==true and share.outcome=='rejected','fixture: the INJECTED refusal left a stopped Share',printable(share and share.outcome))
if post and post:IsShown() then post:Hide() end
CB.Show()

C.scenario('T1 the detail note says why Retry is offered and what the current mode does',function()
 if not id then return end
 local p=Show(id)
 C.setup(p~=nil,'T1: fixture: the listing is shown')
 if not p then return end
 C.setup(p.retryShareBtn:IsShown(),'T1: fixture: Retry Share is offered for the stopped Share (CanRetryShare)')
 if not p.retryShareBtn:IsShown() then return end
 C.guard(p.retryShareBtn:IsEnabled() and p.editBtn:IsShown(),'T1: Retry is enabled and Edit Build stays available')
 local note=V.Plain(p.editState:GetText() or '')
 print('OBSERVED','T1 note='..note)
 C.expect(Has(note,'Last Share was not sent (rejected') and Has(note,'synthetic transport refusal'),'T1: the note names the stopped outcome and its reason',note)
 C.expect(Has(note,'Sync is Manual now: Retry Share queues it again only when you click.'),'T1: and the current mode with what a click does',note)
 local tip=V.Plain(table.concat(V.TooltipLines(p.retryShareBtn:GetScript('OnEnter'),p.retryShareBtn),' '))
 C.guard(Has(tip,'only after you click'),'T1: the tooltip keeps "only after you click"',tip)
 C.expect(Has(tip,'with Sync Off, a Retry is refused and nothing is sent'),'T1: the tooltip says the saved mode still decides',tip)
end)

C.scenario('T2 under Off the refusal and the mode are stated; nothing is sent or enabled',function()
 if not id then return end
 C.setup(Mode('off'),'T2: fixture: the explicit choice Off is applied',P.Mode())
 local p=Show(id)
 if not (p and p.retryShareBtn:IsShown()) then C.setup(false,'T2: fixture: Retry Share is still offered under Off');return end
 C.guard(p.retryShareBtn:IsEnabled(),'T2: Retry stays offered under Off (CanRetryShare unchanged)')
 local note=V.Plain(p.editState:GetText() or '')
 C.expect(Has(note,'Sync is Off now: a Retry is refused and nothing is sent'),'T2: the note states the Off refusal before any click',note)
 C.guard(P.Mode()=='off','T2: showing the view changed no mode')
 local mark,calls,sent=#said,#summaries,#H.sent
 p.retryShareBtn:Click()
 local line=SaidSince(mark,'Share retry of')
 print('OBSERVED','T2 line='..printable(line)..' summaryCalls='..(#summaries-calls))
 local refusal=summaries[#summaries]
 C.guard(#summaries==calls+1 and refusal.id==id and refusal.retryOnFull==true,'T2: the click is one existing retry hand-off (retryOnFull)',#summaries-calls)
 C.guard(refusal and refusal.queued~=true,'T2: Off refuses it at admission (existing policy)',printable(refusal and refusal.why))
 C.expect(line~=nil and Has(line,"Share retry of '"..TITLE.."' not sent:") and Has(line,P.Text('off')),'T2: the line states the saved mode\'s own refusal',line)
 Until(40,function() return false end)
 C.guard(WLBI(sent)==0,'T2: no summary left the client',WLBI(sent))
 C.guard(P.Mode()=='off','T2: the click enabled no Sync mode')
 p=Show(id)
 C.guard(p and p.retryShareBtn:IsShown() and p.retryShareBtn:IsEnabled(),'T2: Retry is offered again after the refusal')
end)

C.scenario('T3 a click whose drawn context no longer matches queues nothing',function()
 if not id then return end
 C.setup(Mode('manual'),'T3: fixture: the explicit choice Manual is applied',P.Mode())
 local p=Show(id)
 if not (p and p.retryShareBtn:IsShown()) then C.setup(false,'T3: fixture: Retry Share is offered');return end
 local drawn=p.retryShareBtn._nexusRetryContext
 C.expect(type(drawn)=='table' and drawn.owner~=nil,'T3: the Retry button carries the context it was drawn in',type(drawn))
 if type(drawn)~='table' then return end
 -- SYNTHETIC: the player changed after the view was drawn.
 p.retryShareBtn._nexusRetryContext={database=drawn.database,catalog=drawn.catalog,
  owner='Synthetic-OtherRealm',binding=drawn.binding}
 local mark,calls,sent=#said,#summaries,#H.sent
 p.retryShareBtn:Click()
 local line=SaidSince(mark,'Share retry of')
 print('OBSERVED','T3 line='..printable(line))
 C.expect(line~=nil and Has(line,'player or catalog changed') and Has(line,'Nothing was queued by this click'),'T3: the click says the context changed and nothing was queued',line)
 C.expect(#summaries==calls,'T3: no retry was handed to Sync',#summaries-calls)
 Until(40,function() return false end)
 C.expect(WLBI(sent)==0,'T3: no summary left the client',WLBI(sent))
 p=Show(id)
 C.guard(p and p.retryShareBtn:IsShown(),'T3: the stopped Share is still offered for a Retry')
 C.expect(type(p.retryShareBtn._nexusRetryContext)=='table' and p.retryShareBtn._nexusRetryContext.owner~='Synthetic-OtherRealm',
  'T3: a redraw captures the current context again')
 -- fresh31 (RetryShare binding question): the catalog's preparation binding
 -- is a number while ManualPreparationStatus exists (BuildCatalog binding
 -- generation starts at 0 and is only copied), so a drawn context with the
 -- same catalog never carries a nil binding; a nil binding comes only with a
 -- missing catalog, which the catalog comparison refuses. A different binding
 -- with everything else equal is refused on its own.
 drawn=p.retryShareBtn._nexusRetryContext or {}
 local prep=Nexus.BuildCatalog.ManualPreparationStatus()
 C.expect(type(drawn.binding)=='number' and drawn.binding==prep.binding,'T3: the drawn binding is the catalog\'s current number',
  printable(drawn.binding)..' vs '..printable(prep and prep.binding))
 if type(drawn.binding)~='number' then return end
 -- SYNTHETIC: the catalog binding moved on after the view was drawn.
 p.retryShareBtn._nexusRetryContext={database=drawn.database,catalog=drawn.catalog,owner=drawn.owner,binding=drawn.binding+1}
 mark,calls,sent=#said,#summaries,#H.sent
 p.retryShareBtn:Click()
 line=SaidSince(mark,'Share retry of')
 print('OBSERVED','T3 binding line='..printable(line))
 C.expect(line~=nil and Has(line,'player or catalog changed') and #summaries==calls,'T3: a changed binding alone is refused before any hand-off',line)
 Until(40,function() return false end)
 C.expect(WLBI(sent)==0,'T3: and nothing left the client',WLBI(sent))
end)

C.scenario('T4 a click in the current context: the line matches the actual admission',function()
 if not id then return end
 C.setup(Mode('automatic'),'T4: fixture: the explicit choice Automatic is applied',P.Mode())
 local p=Show(id)
 if not (p and p.retryShareBtn:IsShown()) then C.setup(false,'T4: fixture: Retry Share is offered');return end
 local mark,calls=#said,#summaries
 p.retryShareBtn:Click()
 local line=SaidSince(mark,'Share retry of')
 local call=summaries[#summaries]
 print('OBSERVED','T4 line='..printable(line),'queued='..printable(call and call.queued),'why='..printable(call and call.why))
 C.guard(#summaries==calls+1 and call.id==id and call.retryOnFull==true,'T4: one existing retry hand-off with retryOnFull',#summaries-calls)
 local status=S.GetShareStatus(id) or {}
 if call and call.queued==true and status.retryPending==true then
  C.expect(Has(line,'is waiting for one bounded Sync queue slot. Nothing is sent until it is admitted.'),'T4: a waiting retry says so',line)
 elseif call and call.queued==true then
  C.expect(Has(line,"Share retry of '"..TITLE.."' queued its summary. Queued is not sent"),'T4: an admitted retry says queued, not sent',line)
  C.guard(not Has(line,'received') or Has(line,'not confirmed'),'T4: no receipt is claimed',line)
 elseif call and P.IsModeReason(call.why) then
  C.expect(Has(line,'not sent: '..tostring(call.why)),'T4: a mode refusal is stated as it is',line)
 else
  C.expect(Has(line,'failed:') and Has(line,'Nothing was queued by this click'),'T4: another refusal says nothing was queued',line)
 end
end)

print=realPrint
C.guard(#H.actions==0,'no game action: nothing was activated, saved to the server or spent',#H.actions)
C.finish('(Retry states its reason, mode and actual outcome; a changed context queues nothing; policy unchanged)')
