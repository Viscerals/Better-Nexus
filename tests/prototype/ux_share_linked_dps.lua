-- M7 (Root conditions linkedOutcome, manualLinkedDps, fixtures): a confirmed
-- Share of your own Saved Build hands the listing's DPS best to Sync with the
-- unchanged DpsCapture.BroadcastBestForBuild(publishedId). Its local admission
-- is kept apart from the summary's: when the summary is refused (here: over
-- the 247-byte line budget) while a linked DPS record is admitted, the
-- completion line no longer says nothing was sent; it scopes the refusal to
-- the summary and says the linked record was queued separately (queued is not
-- sent). A hand-off that raises or answers nothing is "not reported", never
-- proof that nothing was queued. Under Manual and Off the existing
-- ShareFollowUp/mode policy decides; this test traces and prints the actual
-- admission and checks only that the line matches it. No mode permission,
-- wire or auth change.
-- Fixture (SYNTHETIC, genuine-shaped controls, not native scores): a real
-- Saved Build mirror shared through the real Build Library action and
-- confirmation; a synthetic Details! combat on a training-dummy target
-- (as ux_sync_dps_page and batch_class_capture_publication) records a
-- personal best on the same Echoes; the production pipeline links that best
-- to the shared listing. The link is witnessed, not assumed: the hand-off's
-- own call of Sync.BroadcastDpsRecord with record.buildId==publishedId is the
-- SETUP. If the link is not reached, the SETUP fails and the checks that need
-- it are skipped (a blocked control, reported), never faked.
-- Categories (view_regression_support): EXPECT is behaviour added in M7
-- (predicted to fail on accepted M6 0924d06a, whose line says "not queued, so
-- nothing was sent" whatever the linked record did; not executed by the
-- author); GUARD already holds there and must keep holding; SETUP is the
-- fixture. Spies call the real functions and keep their results.
-- Continuation 52 (review38 M7R38-B01/N01): the confirmation each Update was
-- accepted from (its real note, read from the harness popup before Accept)
-- tells the listing apart from the linked record, in every saved mode: an
-- "only ... players who ask" clause names the listing, and the sentence naming
-- a DPS record says that record carries its Echo list (EXPECT, added with this
-- wording repair). Where a linked record was admitted, the record handed to
-- Sync carries Echo entries (GUARD: the payload this copy describes, which the
-- repair does not change). L5 reads the guide's Share step
-- (README-PROTOTYPE.md) for the same disclosure (EXPECT) and for its existing
-- confirmation, local-save, mode and size, Off, queued-not-sent, receipt and
-- recall words (GUARD). Short word checks; the wording may vary.
-- D2/D3 qualification (M5 donor 45036fbc, root-adjudicated oracle): the
-- requester-only reading above (an "only ... players who ask" clause that
-- names the listing) and the guide's former "sent only in answers to players
-- who ask" and "DPS record you hold for this exact build" wording are
-- superseded and kept as history. Being asked for is not being the only
-- recipient: an answer may go on the shared Sync channel, where other
-- listeners may keep a valid copy. Discloses now expects, of each accepted
-- confirmation and of the guide's Share step: no requester-only clause; the
-- summary without Echo list or description; answers that can carry the full
-- listing; a shared-channel answer that can be kept; and, conditional on
-- Automatic, a linked character-best Training Dummy or Lich King DPS record
-- that may be sent with its Echoes, locked Echoes and player info without an
-- additional request, also when the summary is not queued. A DPS clause may
-- say "Echoes" rather than the legacy "Echo list"; none may name a record
-- "you hold", a personal best, a delivery or a promise. L5 also expects the
-- guide to say that this record is newly eligible, that a lower personal
-- best stays on this client, that receiving the record alone can give a
-- viewable, copyable Record Loadout page, and that Manual and Off refuse
-- these automatic sends. These are text oracles only. The real Share,
-- synthetic capture, hand-off, admission, Echo payload, WLD2, Off and
-- not-reported checks of L1-L4 are unchanged.
local V=dofile('tests/prototype/view_regression_support.lua')
local T=dofile('tests/prototype/startup_support.lua')
local printable=V.printable
local C=V.Checker('ux_share_linked_dps')

-- A long Saved Build name: with the harness player name its listing summary
-- is over the 247-byte line budget, so the summary is refused locally.
local SLOT_NAME='Synthetic linked listing with a deliberately long title'
local H,A,D,S,P,CB
local dpsCalls,bestCalls,said
local function Boot()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 NexusCommunityBuildsFrame,NexusHelpWindow,NexusSyncModeDialog=nil,nil,nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=10
 NexusDB=T.Profile(0,0)
 for i=1,3 do H.AddEcho(300000+i,'Synthetic linked Echo '..i,2,4,300000+i) end
 T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function() return Nexus.StartupStatus().state=='ready' end)
 A,D,S,P,CB=Nexus.GameAdapter,Nexus.DpsCapture,Nexus.Sync,Nexus.SyncModePolicy,Nexus.CommunityBuilds
 dpsCalls,bestCalls,said={},{},{}
 local realRecord=S.BroadcastDpsRecord
 S.BroadcastDpsRecord=function(record,...)
  -- The Echo entries of the record as it was handed over.
  local echoes=0
  if type(record)=='table' and type(record.echoes)=='table' then for _ in pairs(record.echoes) do echoes=echoes+1 end end
  local r={pcall(realRecord,record,...)}
  dpsCalls[#dpsCalls+1]={buildId=type(record)=='table' and record.buildId or nil,ok=r[1],result=r[2],why=r[3],echoes=echoes}
  if not r[1] then error(r[2],0) end
  return unpack(r,2)
 end
 local realBest=D.BroadcastBestForBuild
 D.BroadcastBestForBuild=function(id,...)
  bestCalls[#bestCalls+1]={id=id,count=select('#',...)+1}
  return realBest(id,...)
 end
 local realPrint=print
 print=function(...)
  local t={}
  for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end
  said[#said+1]=table.concat(t,' ')
  return realPrint(...)
 end
 return realPrint
end
local function Until(limit,fn) for _=1,limit do if fn() then return true end;H.Advance(.05,.05) end;return fn() end
local function UseEchoes()
 H.granted={['Synthetic linked Echo 1']={{spellId=300001,quality=2}}}
 H.locked={}
 H.perks.serverBuildSlots={[1]={name=SLOT_NAME,verified=true,echoes={{spellId=300001,quality=2,stacks=1,locked=false}}}}
 H.perks.serverActiveSlot=1
 H.Notify();A.Poll()
end
local combat={total=0}
function combat:GetActor() return {total=self.total,Tempo=function() return 30 end} end
function combat:GetCombatTime() return 30 end
local function Capture(total)
 local realName=UnitName
 UnitName=function(unit) if unit=='target' then return 'Training Dummy' end;return realName(unit) end
 UnitExists=function(unit) return unit=='target' end
 Details={GetCurrentCombat=function() return combat end};DETAILS_ATTRIBUTE_DAMAGE=1
 combat.total=total
 D.OnCombatStart()
 for _=1,7 do H.Advance(5,.05);D.OnUpdate(5) end
 local ok,err=pcall(D.OnCombatEnd)
 UnitName=realName
 return ok,err
end
local function Mode(mode)
 local ok,result=P.ApplyChoice(mode,(P.Choice() or {}).token)
 return ok==true and P.Mode()==mode,result
end
local function Mirror()
 for _,b in pairs(CB.Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild==true and tonumber(b.serverSlot)==1 then return b end
 end
end
local function ImportIdle()
 local stats=CB.VirtualStats()
 local import=type(stats)=='table' and type(stats.savedImport)=='table' and stats.savedImport or {}
 return import.pending~=true
end
local function Panel() local f=NexusCommunityBuildsFrame;return f and f._detailPanel end
local function SaidSince(mark,needle)
 for i=mark+1,#said do if V.Plain(said[i]):find(needle,1,true) then return V.Plain(said[i]) end end
end
-- One confirmed Share of the mirror through its own action and confirmation.
local function Share(tag,id)
 CB.ShowBuild(id)
 Until(2000,function() local p=Panel();return p and p:IsShown() and p._nexusShownId==id and ImportIdle() end)
 local p=Panel()
 local share=p and p.shareBtn
 C.setup(share~=nil and share:IsShown() and share:IsEnabled(),tag..': fixture: the mirror offers its Share action')
 if not (share and share:IsShown() and share:IsEnabled()) then return nil end
 H.popup=nil;share:Click()
 C.setup(H.popup~=nil and type(H.popup.data)=='table' and H.popup.data.id==id,tag..': fixture: its confirmation is open')
 if not H.popup then return nil end
 -- The confirmation's own text, as the player reads it before accepting.
 local note=V.Plain(tostring(H.popup.arg2 or ''))
 local mark=#said
 H.AcceptPopup()
 Until(400,function() return SaidSince(mark,'locally as your shared listing')~=nil or SaidSince(mark,'Not shared:')~=nil end)
 return SaidSince(mark,'locally as your shared listing'),mark,note
end
local function Has(text,needle) return tostring(text or ''):find(needle,1,true)~=nil end
-- Review38 B01/N01, kept as history: every "only ... who ask" clause about the
-- Echo list was to name the listing, and every sentence naming a DPS record was
-- to say it carries its Echo list. D2/D3 (header) supersedes the first part and
-- keeps the second with "Echoes" or "Echo list". Read one clause at a time, in
-- lower case (split at . ; ! ? before a space or the end), by semantic words.
-- Returns whether every D2/D3 fact holds, the detail, the clauses and the
-- Automatic DPS clause.
local function Word(text,word) return tostring(text or ''):find('%f[%a]'..word..'%f[%A]')~=nil end
local function Parts(text)
 local s=(V.Plain(text or ''):gsub('%s+',' '))
 local out,start={},1
 for i=1,#s do
  if s:sub(i,i):find('[%.;!?]') and (i==#s or s:sub(i+1,i+1)==' ') then
   local part=s:sub(start,i):match('^%s*(.-)%s*$'):lower()
   if part~='' then out[#out+1]=part end
   start=i+1
  end
 end
 local rest=s:sub(start):match('^%s*(.-)%s*$'):lower()
 if rest~='' then out[#out+1]=rest end
 return out
end
local function Discloses(text)
 local parts,missing=Parts(text),{}
 local only,dps,dpsNoEcho,dpsLoose,auto=0,0,0,0,nil
 for _,l in ipairs(parts) do
  -- A requester-only claim, about the listing, its Echo list or anything else.
  if Word(l,'only') and not Has(l,'not only')
   and (Has(l,'ask') or Has(l,'request') or Has(l,'answer') or Has(l,'fetch')) then only=only+1 end
  if Has(l,'dps record') then
   dps=dps+1
   if not Has(l,'echo') then dpsNoEcho=dpsNoEcho+1 end
   if Has(l,'you hold') or Has(l,'personal') or Has(l,'deliver')
    or Word(l,'will') or Word(l,'always') or Word(l,'every') then dpsLoose=dpsLoose+1 end
  end
  if auto==nil and Has(l,'in automatic') and Has(l,'dps') then auto=l end
 end
 local function Any(label,fn)
  for _,l in ipairs(parts) do if fn(l) then return end end
  missing[#missing+1]=label
 end
 Any('the summary has no Echo list or description',function(l)
  return Has(l,'summary') and (l:find('no echo list,? or [%a ]-description')~=nil
   or l:find('neither [%a ]-echo list,? nor [%a ]-description')~=nil
   or l:find('neither [%a ]-description,? nor [%a ]-echo list')~=nil)
 end)
 Any('answers can carry the full listing',function(l)
  return Has(l,'answer') and (Has(l,'can be sent') or Has(l,'may be sent'))
   and (Has(l,'full listing') or Has(l,'with its description'))
 end)
 Any('an answer on the shared Sync channel can be kept',function(l)
  return Has(l,'sync channel') and (Has(l,'kept') or Has(l,'keep'))
 end)
 local facts={
  {'in Automatic, if, may',function(l) return Has(l,'in automatic') and Word(l,'if') and Word(l,'may') end},
  {'linked',function(l) return Has(l,'linked') end},
  {"the character's best",function(l) return Has(l,"character's best") or Has(l,'character-best') end},
  {'Training Dummy and Lich King',function(l) return Has(l,'training dummy') and Has(l,'lich king') end},
  {'Echoes and locked Echoes',function(l) return Has(l,'echoes') and Has(l,'locked echoes') end},
  {'player info',function(l) return Has(l,'player info') end},
  {'without an additional request',function(l) return Has(l,'without an additional request')
   or Has(l,'without anyone asking') or Has(l,'unasked') end},
  {'also when the summary is not queued',function(l) return Has(l,'summary')
   and (Has(l,'not queued') or Has(l,'not admitted') or Has(l,'refused')) end},
 }
 for _,fact in ipairs(facts) do
  if not (auto and fact[2](auto)) then missing[#missing+1]='Automatic DPS: '..fact[1] end
 end
 if only>0 then missing[#missing+1]='no requester-only clause ('..only..' found)' end
 if dps==0 then missing[#missing+1]='a clause naming a DPS record' end
 if dpsNoEcho>0 then missing[#missing+1]='Echoes in each DPS record clause ('..dpsNoEcho..' without)' end
 if dpsLoose>0 then missing[#missing+1]='no held, personal, delivered or promised DPS record ('..dpsLoose..' found)' end
 return #missing==0,'requesterOnly='..only..' dpsClauses='..dps..' withoutEcho='..dpsNoEcho..' loose='..dpsLoose
  ..' missing: '..(#missing>0 and table.concat(missing,'; ') or 'none'),parts,auto
end

-- Shares once, captures a synthetic best on the same Echoes, optionally
-- changes the mode, then Updates the Share and traces its hand-off.
local function Trace(tag,before,after)
 local realPrint=Boot()
 local result={tag=tag}
 local ok=pcall(function()
  C.setup(Mode(before),tag..': fixture: the saved mode is '..before,P.Mode())
  UseEchoes()
  CB.Show()
  C.setup(Until(4000,function() return Mirror()~=nil and ImportIdle() end),tag..': fixture: the Saved Build is imported as a mirror')
  local m=(Mirror() or {}).id
  C.setup(m~=nil and CB.IsOwnBuild(m)==true,tag..': fixture: the mirror is the character\'s own',printable(m))
  if not m then return end
  local first=Share(tag..' first',m)
  local mirror=CB.Builds() and Mirror()
  local listing=mirror and mirror.publishedBuildId
  C.setup(first~=nil and listing~=nil,tag..': fixture: the first Share saved the listing',printable(first))
  if not listing then return end
  local captured,why=Capture(60000)
  C.setup(captured,tag..': fixture: the SYNTHETIC training-dummy combat was captured',printable(why))
  Until(200,function() return D.GetPersonalBest(listing,'dummy')~=nil end)
  if after then C.setup(Mode(after),tag..': fixture: the saved mode is now '..after,P.Mode()) end
  local dpsMark,bestMark,sentMark=#dpsCalls,#bestCalls,#H.sent
  local line,_,note=Share(tag..' update',m)
  result.line=line
  result.listing=listing
  result.note=note
  if note then
   print('OBSERVED',tag,'confirmation='..note)
   local disclosed,detail=Discloses(note)
   C.expect(disclosed,tag..': the confirmation accepted under '..P.Mode()..' makes no requester-only claim, says what the summary, answers and shared Sync channel carry, and that Automatic may send a linked character-best DPS record with its Echoes, unasked',
    detail..' | '..note)
  end
  local linked,admitted={},false
  for i=dpsMark+1,#dpsCalls do
   local c=dpsCalls[i]
   if c.buildId==listing then
    linked[#linked+1]=c
    if c.ok and c.result~=false then
     admitted=true
     result.minEchoes=math.min(result.minEchoes or c.echoes,c.echoes)
    end
   end
  end
  result.linked,result.admitted=#linked,admitted
  local status=S.GetShareStatus(listing)
  result.reason=type(status)=='table' and status.reason or nil
  local exact,other=0,0
  for i=bestMark+1,#bestCalls do if bestCalls[i].id==listing and bestCalls[i].count==1 then exact=exact+1 else other=other+1 end end
  result.exact,result.other=exact,other
  print('OBSERVED',tag,'mode='..P.Mode(),'linkedCalls='..#linked,'admitted='..tostring(admitted),
   'results='..table.concat((function() local t={};for _,c in ipairs(linked) do t[#t+1]=printable(c.result)..'/'..printable(c.why) end;return t end)(),','),
   'summaryReason='..printable(result.reason),'line='..printable(line))
  C.setup(#linked>=1,tag..': the hand-off reached the best linked to the listing (row.buildId==publishedId, witnessed at Sync.BroadcastDpsRecord)',#linked)
  C.guard(exact==1 and other==0,tag..': the DPS-best hand-off is one call with the listing ID only',exact..'/'..other)
  Until(60,function() return false end)
  local wld2=0
  for i=sentMark+1,#H.sent do if tostring(H.sent[i].text):gsub('^P%d+:',''):find('^WLD2|') then wld2=wld2+1 end end
  result.wld2=wld2
  if not admitted then
   C.guard(wld2==0,tag..': a linked record that was not admitted does not leave the client',wld2)
  end
  result.ran=true
 end)
 print=realPrint
 C.setup(ok,tag..': fixture: the trace ran')
 return result
end

C.scenario('L1 Automatic: a refused summary is scoped to the summary; a linked record queued is said',function()
 -- Captured under Manual (no automatic best broadcast), shared under
 -- Automatic: the hand-off is the linked record's first admission.
 local r=Trace('L1','manual','automatic')
 if not (r.ran and r.linked>=1) then return end
 C.setup(r.reason=='summary too large','L1: fixture: the listing summary is over the line budget',printable(r.reason))
 C.expect(Has(r.line,'its summary was not queued, so nothing was sent for it') and Has(r.line,'summary too large'),
  'L1: the refusal is scoped to the summary',r.line)
 C.guard(Has(r.line,'not queued') and Has(r.line,'nothing was sent') and not Has(r.line,'queued its summary'),
  'L1: the pinned words stay (not queued, nothing was sent, no queued-summary claim)',r.line)
 if r.admitted then
  C.expect(Has(r.line,'A DPS record linked to this build was queued separately; queued is not sent.'),
   'L1: the linked record admitted for sending is said, as queued (not sent)',r.line)
  C.guard((r.minEchoes or 0)>=1,'L1: that admitted record carries its Echo list (the payload the confirmation discloses)',printable(r.minEchoes))
 else
  C.expect(not Has(r.line,'queued separately'),'L1: no linked record admitted: none is claimed',r.line)
 end
end)

C.scenario('L2 Manual: the existing policy decides the linked record; the line matches it',function()
 local r=Trace('L2','manual',nil)
 if not (r.ran and r.linked>=1) then return end
 print('OBSERVED','L2 Manual linked-DPS admission (ShareFollowUp policy unchanged): admitted='..tostring(r.admitted))
 if r.admitted then
  C.expect(Has(r.line,'queued separately'),'L2: a linked record admitted under Manual is said',r.line)
 else
  C.expect(not Has(r.line,'queued separately') and not Has(r.line,'not reported'),'L2: a refused linked record is not claimed queued',r.line)
 end
 C.guard(P.Mode()=='manual','L2: the saved mode is unchanged')
end)

C.scenario('L3 Off: nothing is queued; the line claims nothing linked',function()
 local r=Trace('L3','off',nil)
 if not (r.ran and r.linked>=1) then return end
 C.guard(not r.admitted and r.wld2==0,'L3: under Off no linked record is admitted or sent',tostring(r.admitted)..'/'..tostring(r.wld2))
 C.expect(r.line~=nil and not Has(r.line,'queued separately') and not Has(r.line,'queued its summary'),'L3: the line claims no queued record',r.line)
 C.guard(Has(r.note,'Sync mode is Off'),'L3: the confirmation under Off still says the listing is saved here and not sent',printable(r.note))
end)

C.scenario('L4 a hand-off that raises or answers nothing is not reported, not proof of nothing',function()
 local realPrint=Boot()
 local ok,err=pcall(function()
  UseEchoes();CB.Show()
  C.setup(Until(4000,function() return Mirror()~=nil and ImportIdle() end),'L4: fixture: the Saved Build is imported as a mirror')
  local m=(Mirror() or {}).id
  if not m then return end
  C.setup(Share('L4 first',m)~=nil,'L4: fixture: the first Share saved the listing')
  local real=D.BroadcastBestForBuild
  D.BroadcastBestForBuild=function() error('synthetic hand-off failure') end
  local raised=Share('L4 raises',m)
  D.BroadcastBestForBuild=function() return nil end
  local silent=Share('L4 no answer',m)
  D.BroadcastBestForBuild=real
  print('OBSERVED','L4 raised line='..printable(raised),'silent line='..printable(silent))
  C.expect(Has(raised,'Whether a linked DPS record was queued was not reported.'),'L4: a raising hand-off is not reported',raised)
  C.expect(Has(silent,'Whether a linked DPS record was queued was not reported.'),'L4: a hand-off with no answer is not reported',silent)
  C.guard(raised~=nil and silent~=nil,'L4: the listing is still saved locally each time')
 end)
 print=realPrint
 C.setup(ok,'L4: fixture: the injected hand-offs ran',printable(err))
end)

C.scenario('L5 the guide\'s Share step tells the listing reply apart from the linked DPS record',function()
 local END='Sharing is separate from saving a Wishlist or a Saved Build.'
 local file=io.open('README-PROTOTYPE.md','rb')
 local guide=file and file:read('*a') or ''
 if file then file:close() end
 guide=guide:gsub('%*%*',''):gsub('%s+',' ')
 local from=guide:find('Share Build... on your own Saved Build',1,true)
 local to=from and guide:find(END,from,true)
 C.setup(from~=nil and to~=nil,'L5: fixture: the guide\'s Share step was found')
 if not (from and to) then return end
 local step=guide:sub(from,to+#END-1)
 print('OBSERVED','L5 guide Share step='..step)
 local disclosed,detail,parts,auto=Discloses(step)
 C.expect(disclosed,'L5: the guide makes no requester-only claim, says what the summary, answers and shared Sync channel carry, and that Automatic may send a linked character-best DPS record with its Echoes, unasked',
  detail..' | '..step)
 -- Guide-only D2/D3 facts (the confirmation states its own subset), read by
 -- clause with semantic words; the wording may vary.
 local function Find(fn) for _,l in ipairs(parts) do if fn(l) then return l end end;return nil end
 C.expect(auto~=nil and (auto:find('%f[%a]eligib')~=nil or auto:find('%f[%a]qualif')~=nil),
  'L5: the guide says the Automatic DPS record is a newly eligible one',printable(auto))
 C.expect(Find(function(l) return Has(l,'lower') and Has(l,'best') and Has(l,'stay') and Has(l,'on this client') end)~=nil,
  'L5: the guide says a lower personal best for the same Echoes stays on this client',step)
 C.expect(Find(function(l) return Has(l,'dps record') and Has(l,'alone') and Has(l,'record loadout')
  and Has(l,'view') and Has(l,'copy') and (Word(l,'can') or Word(l,'may')) end)~=nil,
  'L5: the guide says receiving that DPS record alone can give a viewable, copyable Record Loadout page',step)
 C.expect(Find(function(l) return Word(l,'manual') and Word(l,'off') and Has(l,'dps')
  and (Has(l,'refuse') or Has(l,'not') or Has(l,'never')) and not Has(l,'in automatic') end)~=nil,
  'L5: the guide says Manual and Off refuse these automatic DPS sends',step)
 C.guard(Has(step,'confirm') and Has(step,'on this client') and Has(step,'Sync mode') and Has(step,'size')
  and Has(step,'Off nothing is queued') and Has(step,'Queued is not sent') and Has(step,'receipt by other players is not confirmed')
  and Has(step,'cannot be recalled'),
  'L5: the guide keeps its confirmation, local-save, mode and size, Off, queued-not-sent, receipt and recall words',step)
end)

C.finish('(linked DPS admission kept apart from the summary; synthetic capture; policy unchanged)')
