-- UX M5 (UX-12 / LP-12): what Sync may send without a click is stated, in
-- one vocabulary, on the Welcome, Help, the Build Library and the Leaderboard;
-- the current saved Sync mode is shown and never changed.
-- Healthy behaviour (EXPECT, fails on the accepted M4 source 23109b90 by
-- design): the Welcome Sync line in every mode and its fit; the Automatic
-- mode line in the Build Library status; the same Sync Now words (mode line
-- and sent / received / stored) in the Build Library and Leaderboard
-- tooltips; the Help disclosure of each mode, of the read-only mode and of the
-- Sync words; no "mesh" jargon in the status.
-- Unchanged (GUARD, holds there too): the Off and Manual status lines;
-- opening, reading and closing these views sends, queues and grants nothing
-- and changes no mode or saved byte (checked with no time passing, so normal
-- background Sync cannot be confused with an effect); the default and saved
-- modes stay as they were after time passes; no game action.
-- 14d amendment (LP-12 is now implemented, so the former no-control and
-- no-setter assumptions are replaced): the only Sync mode control is the one
-- "Sync mode..." button beside Sync Now in the Build Library (none on the
-- Welcome, Leaderboard or Help); viewing does not open it or write a choice;
-- the Store facade exports and the private mutation entries are unchanged.
-- Strengthened (EXPECT on the preimage): the Build Library status region the
-- production layout allocates holds every row of its text in both repository
-- font models; the added Record Loadout tooltip line; Help's qualified share
-- and mode-choice text.
-- M5 continuation 39 (queue item 3): the Record Loadout tooltip line was
-- categorical ("also shares its Record Loadout build page"). Both identical
-- Sync Now tooltips now say a new best and its page may be sent, each only
-- if this client admits it, with the page's Echo list only in later answers,
-- and that sending is not delivery. EXPECT (fails on 2e34bce8 and c34fa248):
-- the qualified line in both, the categorical line in neither, and Help's
-- qualified phrases (possible send, admission by this client, no delivery
-- promise, the Build Library's scroll route). Help's earlier needles are kept
-- inside those phrases. The mode, default, Store, saved-byte and no-effect
-- GUARDs are unchanged.
-- Continuation 52 (review38 M7R38-B01/N01, kept as history): Help's step 3 no
-- longer reads as if a new DPS best left only as its Record Loadout page, with
-- the Echo list only for players who ask. It says that DPS record carries its
-- Echo list (still an EXPECT below), and it scoped the requester-only Echo
-- wording to the page; that scoping is superseded by the D2/D3 correction and
-- is no longer expected.
-- D2/D3 correction: supersedes the requester-only/new-personal-best wording
-- above. EXPECTs require character encounter-best eligibility, unsolicited
-- ordinary/locked Echo disclosure, independent summary refusal and receiver
-- page creation. Actual wire/receiver behavior is GUARD in ux_sync_dps_page.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Real TOC boots: a format-2 profile (Automatic even though its settings store
-- "manual") and accepted format-5 profiles with Manual and Off. The fit of the
-- Welcome line uses the quickstart_layout_fit font models (default 5.5 px / 12
-- px lines; conservative 7.0 px / 17 px lines). Native fit is NOT established.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local printable=V.printable
local C=V.Checker('ux_sync_disclosure')

-- The vocabulary contract: Automatic is named here; Off and Manual are
-- core/SyncModePolicy.lua's own text.
local AUTOMATIC="Sync is Automatic: may send without a click (login requests, answers to other users, eligible character-best DPS with Echoes and player info)."
local SYNC_NOW='Asks other Nexus users for shared builds and DPS records.'
local WORDS='Sent means it left this client, not that anyone stored it. Received means it arrived here; stored means this client kept it.'
local DPS_PAGE="With Automatic, an eligible new character best for Training Dummy or Lich King may send a DPS record with Echoes, any locked Echoes and player info without a request. The Record Loadout summary is separate; even if it is refused, the DPS record may let receivers create that page. Each send needs this client's admission. Sending is not delivery."
-- The former categorical line (2e34bce8, c34fa248): no longer in either tooltip.
local CATEGORICAL_DPS_PAGE='With Automatic, a new personal DPS best also shares its Record Loadout build page: a summary first, the Echo list only to players who ask.'
-- The Store facade as the preimage exports it (the architecture text counts
-- nine; this build's facade carries these ten functions, unchanged by 14d).
local STORE_EXPORTS={'AccountCharacters','CurrentOwnerKey','Init','IsAccountBuild','IsAccountOwnerKey',
 'RegisterCurrentCharacter','Settings','SettingsVersion','State','StateWriteStatus'}
local OWNER_ENTRIES={'ReadStateV1','ResolveStateRowV1','UpdateSettingsV1','UpdateStateV1'}
local WELCOME_TAIL=' Help: Sharing lists what is sent.'
local MODELS={{name='default',char=5.5,line=12},{name='conservative',char=7.0,line=17}}

local function Wrapped(text,width,char)
 text=V.Plain(text)
 local lines=0
 for para in (text..'\n'):gmatch('(.-)\n') do
  lines=lines+1;local used=0
  for word in para:gmatch('%S+') do
   local w=#word*char;local gap=used>0 and char or 0
   if used>0 and used+gap+w>width then lines=lines+1;used=w else used=used+gap+w end
  end
 end
 return lines
end
local function Has(lines,text)
 for _,l in ipairs(lines) do if V.Plain(l)==text then return true end end
 return false
end
local function Joined(lines) local t={};for i,l in ipairs(lines) do t[i]=V.Plain(l) end;return table.concat(t,' | ') end
-- Facts, independently of sentence equality/parity: these predicates reject
-- the donor's every-personal-best and requester-only Echo descriptions.
local function DpsDisclosure(text)
 local s=V.Plain(text):lower():gsub('%s+',' ')
 local function has(v) return s:find(v,1,true)~=nil end
 return (has('character best') or has('character-best') or has("character's best"))
  and has('training dummy') and has('lich king') and has('may')
  and has('echoes') and has('locked echoes')
  and (has('player info') or has('character info') or (has('realm') and has('class') and has('level')))
  and (has('without a request') or has('does not need a request'))
  and has('summary') and has('separate') and has('refus')
  and has('receiv') and has('creat') and has('page')
  and not has('each new personal dps best')
  and not has('echo list only in later answers')
  and not has('echo list only to players who ask')
end
-- D23: a record's build link (Sync VerifiedDpsBuildId -> b=relatedBuildId)
-- is conditional. Every "linked build ID" in the text must be the "when
-- verified" one, so no wording promises that each record carries a link.
local function LinkConditional(text)
 local s=V.Plain(text):gsub('%s+',' ')
 local all=select(2,s:gsub('linked build ID',''))
 local conditional=select(2,s:gsub('when verified, the linked build ID',''))
 return all>0 and all==conditional
end

local H,CB
-- Everything an opened view could start: sends, queue admissions, refusals,
-- a manual grant, the effective mode, the saved mode value and marker, game
-- actions. (Other saved settings, such as Library filters, are not Sync.)
local function Snapshot()
 local stats=Nexus.Sync.Stats() or {}
 local policy=Nexus.SyncModePolicy
 local settings=rawget(NexusDB,'settings')
 return {sent=#H.sent,actions=#H.actions,admitted=stats.admittedPackets or 0,refused=stats.modeRefused or 0,
  grant=type(policy.ActiveManualGrant)=='function' and policy.ActiveManualGrant() or nil,
  mode=policy.Mode(),saved=type(settings)=='table' and rawget(settings,'syncMode') or nil,
  choice=type(settings)=='table' and rawget(settings,'nexusSyncModeChoice') or nil,
  version=rawget(NexusDB,'settingsVersion')}
end
local function Same(a,b)
 return a.sent==b.sent and a.actions==b.actions and a.admitted==b.admitted and a.refused==b.refused
  and a.grant==b.grant and a.mode==b.mode and a.saved==b.saved and a.version==b.version
  and a.choice==b.choice
end
-- The Leaderboard's Sync button (its label follows the Sync state).
local function LeaderboardSync()
 local f=NexusLeaderboardFrame
 for _,c in ipairs(f and f.children or {}) do
  local label=c.kind=='Button' and V.Plain(c:GetText() or '') or ''
  if label=='Sync Now' or label=='Preparing shared data...' then return c end
 end
 return nil
end
local function Text(s)
 return string.format('sent=%d actions=%d admitted=%d refused=%d grant=%s mode=%s saved=%s version=%s',
  s.sent,s.actions,s.admitted,s.refused,printable(s.grant),printable(s.mode),printable(s.saved),printable(s.version))
end
-- Buttons below a window whose label offers a Sync mode choice.
local function ModeButtons(root)
 local found={}
 local function Walk(f)
  for _,c in ipairs(f.children or {}) do
   if c.kind=='Button' then
    local label=V.Plain(c:GetText() or '')
    if label=='Automatic' or label=='Manual' or label=='Off' or label:lower():find('sync mode',1,true) then found[#found+1]=label end
   end
   Walk(c)
  end
 end
 if root then Walk(root) end
 return found
end

local helpChecked=false
local function Run(tag,database,mode,line)
 -- Named windows of an earlier boot are not this boot's.
 NexusQuickStart,NexusCommunityBuildsFrame,NexusLeaderboardFrame=nil,nil,nil
 NexusHelpWindow,NexusOverwriteWarning,NexusPanel=nil,nil,nil
 H=F.Boot(database)
 local policy=Nexus.SyncModePolicy
 C.setup(Nexus.StartupStatus().coreReady==true,tag..': fixture: start-up reached core-ready')
 C.setup(policy.Mode()==mode,tag..': fixture: the effective saved Sync mode is '..mode,policy.Mode())
 local afterBoot=Snapshot()

 -- 1. Open, read and close every surface with no time passing.
 local before=Snapshot()
 local okSetup=Nexus.QuickStart.ShowSetup()
 local qs=NexusQuickStart
 local welcome=qs and qs.sync and V.Plain(qs.sync:GetText() or '') or ''
 CB=Nexus.CommunityBuilds;CB.Show()
 local lib=NexusCommunityBuildsFrame
 local libBtn=lib and lib._syncBtn
 local libTip=libBtn and V.TooltipLines(libBtn:GetScript('OnEnter'),libBtn) or {}
 Nexus.Leaderboard.Show()
 local lbBtn=LeaderboardSync()
 local lbTip=lbBtn and lbBtn:GetScript('OnEnter') and V.TooltipLines(lbBtn:GetScript('OnEnter'),lbBtn) or {}
 Nexus.Help.Show('sharing')
 local help=NexusHelpWindow and V.Plain(NexusHelpWindow.body:GetText() or ''):gsub('%s+',' ') or ''
 local modeButtons,libraryModeButtons={},ModeButtons(lib)
 for _,root in ipairs({qs,NexusLeaderboardFrame,NexusHelpWindow}) do
  for _,label in ipairs(ModeButtons(root)) do modeButtons[#modeButtons+1]=label end
 end
 local dialogOpened=NexusSyncModeDialog~=nil and NexusSyncModeDialog:IsShown()
 if qs then qs:Hide() end
 CB.Hide()
 if NexusLeaderboardFrame then NexusLeaderboardFrame:Hide() end
 if NexusHelpWindow then NexusHelpWindow:Hide() end
 local after=Snapshot()
 print('OBSERVED',tag,'welcome='..welcome)
 print('OBSERVED',tag,'library tooltip='..Joined(libTip))
 print('OBSERVED',tag,'leaderboard tooltip='..Joined(lbTip))
 C.setup(okSetup==true and qs~=nil and libBtn~=nil and lbBtn~=nil and NexusHelpWindow~=nil,
  tag..': fixture: the Welcome, Build Library, Leaderboard and Help windows opened')
 C.guard(Same(before,after),tag..': opening, reading and closing them sends, queues and grants nothing and changes no mode or saved byte',
  Text(before)..' -> '..Text(after))
 C.guard(#modeButtons==0,tag..': the Welcome, Leaderboard and Help offer no Sync mode control',table.concat(modeButtons,', '))
 C.expect(#libraryModeButtons==1 and libraryModeButtons[1]=='Sync mode...',
  tag..': the Build Library offers exactly one Sync mode control, "Sync mode...", beside Sync Now',table.concat(libraryModeButtons,', '))
 C.guard(not dialogOpened and Snapshot().choice==before.choice and before.choice==nil,
  tag..': viewing neither opens the choice nor writes one')

 -- 2. One vocabulary.
 C.expect(welcome==line..WELCOME_TAIL,tag..': the Welcome states the current Sync mode in the shared words',welcome)
 C.expect(Has(libTip,'Sync Now') and Has(libTip,SYNC_NOW) and Has(libTip,line) and Has(libTip,WORDS),
  tag..': the Build Library Sync Now tooltip gives the mode and the sent / received / stored words',Joined(libTip))
 C.expect(#lbTip>0 and Joined(lbTip)==Joined(libTip),tag..': the Leaderboard Sync Now tooltip uses exactly the same words',Joined(lbTip))
 C.expect(Has(libTip,DPS_PAGE),tag..': the tooltip discloses the automatic Record Loadout page as a possible send that this client admits, not a delivery',Joined(libTip))
 C.expect(DpsDisclosure(Joined(libTip)) and DpsDisclosure(Joined(lbTip)),
  tag..': both tooltips disclose eligible character-best records, unsolicited locked Echoes and independent receiver pages')
 C.expect(not Has(libTip,CATEGORICAL_DPS_PAGE) and not Has(lbTip,CATEGORICAL_DPS_PAGE),
  tag..': neither tooltip keeps the categorical "also shares its Record Loadout build page" line',Joined(libTip)..' || '..Joined(lbTip))

 -- 3. The status line, after its render (time passes here; the read is passive).
 CB.Show()
 local status=''
 for _=1,60 do
  H.Advance(.05,.05)
  status=V.Plain(lib and lib._syncStatusText and lib._syncStatusText:GetText() or '')
  if status:find(line,1,true) then break end
 end
 print('OBSERVED',tag,'status='..(status:gsub('\n',' / ')))
 C.setup(status~='',tag..': fixture: the Build Library status has rendered',status)
 if mode=='automatic' then
  C.expect(status:find(line,1,true)~=nil,tag..': the status states Sync is Automatic and what it may send',status)
 else
  C.guard(status:find(line,1,true)~=nil,tag..': the status states the saved '..mode..' mode',status)
 end
 C.expect(status:find('mesh',1,true)==nil,tag..': no "mesh" jargon in the status',status)
 -- Production status region: the box the Community layout allocated (and
 -- the FontString it placed) holds every row of the text, both font models.
 local layout=lib and lib._responsiveLayout
 local box=type(layout)=='table' and type(layout.boxes)=='table' and layout.boxes.status or nil
 C.setup(box~=nil,tag..': fixture: the production Community layout allocated a status region')
 if box then
  local raw=lib._syncStatusText:GetText() or ''
  for _,m in ipairs(MODELS) do
   local rows=G.Rows(raw,box.w,m.char)
   print('OBSERVED',tag,'status fit',m.name,'rows='..rows,'needs='..rows*m.line,'box='..box.w..'x'..box.h)
   C.expect(rows*m.line<=box.h and lib._syncStatusText:GetHeight()==box.h,
    tag..': '..m.name..' font: the allocated status region holds every row of its text',rows*m.line..' > '..box.h)
  end
 end
 CB.Hide()

 -- 4. The Welcome line fits its region in both font models, apart from the
 -- buttons and the hint, inside the window, on the smallest UI height.
 if qs and qs.sync then
  local root=qs
  local W,Ht=qs:GetWidth(),qs:GetHeight()
  local r=G.Rect(qs.sync,root)
  local okRect=r[1]>=11 and r[3]<=W-12 and r[2]>=12 and r[4]<=Ht-11
  local clear,seen=true,0
  local BUTTONS={['Set up current build']=true,['Import / Create Wishlist']=true,['Browse Community builds']=true,
   ['Open Leaderboard']=true,['Help / Getting Started']=true,['Orbs / Lost Memories']=true,['Close']=true}
  -- The exact "Close" caption of the dismiss control is an EXPECT. Only
  -- after it fails may the real legacy "Later" control stand in for it in
  -- this count and overlap check (the seen==9 SETUP is unchanged); the failed
  -- EXPECT stays in the final failure set.
  local exactClose=false
  for _,c in ipairs(qs.children) do
   if c.kind=='Button' and V.Plain(c:GetText() or '')=='Close' then exactClose=true end
  end
  if not C.expect(exactClose,tag..': the Welcome dismiss control reads exactly "Close"') then BUTTONS['Later']=true end
  for _,c in ipairs(qs.children) do
   local button=c.kind=='Button' and BUTTONS[V.Plain(c:GetText() or '')]
   if button or c==qs.hint or c==qs.body then
    seen=seen+1
    if not G.Apart(r,G.Rect(c,root)) then clear=false end
   end
  end
  C.setup(seen==9,tag..': fixture: the seven Welcome buttons, the body and the hint were found',seen)
  C.expect(okRect,tag..': the Welcome Sync line lies inside the window border',G.Text(r)..' in '..W..'x'..Ht)
  C.expect(clear,tag..': and overlaps no button, the body or the hint',G.Text(r))
  for _,m in ipairs(MODELS) do
   local lines=Wrapped(welcome,qs.sync:GetWidth(),m.char)
   print('OBSERVED',tag,'welcome fit',m.name,'lines='..lines,'needs='..lines*m.line,'height='..qs.sync:GetHeight())
   C.expect(lines*m.line<=qs.sync:GetHeight(),tag..': '..m.name..' font: every Welcome Sync line fits',lines*m.line..' > '..qs.sync:GetHeight())
  end
  C.guard(Ht/2+55<=384 and W<=1024,tag..': the Welcome still fits the smallest UI height at its offset',W..'x'..Ht)
 end
 -- The first-time presentation gives the same line.
 local okShow=pcall(Nexus.QuickStart.Show)
 C.setup(okShow and qs and qs:IsShown(),tag..': fixture: the Welcome opens normally')
 C.expect(qs and V.Plain(qs.sync and qs.sync:GetText() or '')==line..WELCOME_TAIL,tag..': the normal Welcome states it too',qs and qs.sync and qs.sync:GetText())
 if qs then qs:Hide() end

 -- 5. Help (the same in every mode).
 if not helpChecked then
  helpChecked=true
  print('OBSERVED','Help sharing page='..help)
  for _,needle in ipairs({'What Sync sends','your saved Sync mode decides','click Sync mode... beside Sync Now',
   'Apply saves only your choice for this account and sends nothing by itself','your own choice replaces that',
   'Your own Share actions need your click',
   'an eligible new character best for Training Dummy or Lich King may send without a click',
   'a separate automatic "Record Loadout" summary without the Echo list',
   'That DPS record carries its Echo list',
   'ordinary and any locked Echoes and player info',
   'receivers may create a viewable, copyable page from the record alone',
   'Nexus removes the old page on this client only',
   'Sync is Automatic: Nexus may send without a click.','asks other Nexus users for shared builds and DPS records',
   'answers their requests with the shared builds and records this client holds',
   'Training Dummy result lasting at least 30 seconds','Lich King result lasting at least 20 seconds',
   "when it becomes this character's best for that encounter",
   'A personal best for another Echo set below that encounter best stays local',
   'character name, realm, class, level, ordinary Echoes, any locked Echoes, encounter, DPS, duration and time',
   'character name, realm, class, level, ordinary Echoes, any locked Echoes, encounter, DPS, duration and time and, when verified, the linked build ID',
   'It can leave without a request, independently of its separate Record Loadout summary',
   'Refusing the summary does not refuse the separate DPS record',
   'Each of these leaves only if this client admits it','What leaves may still reach no one',
   'Sending is not delivery: Nexus cannot confirm that anyone receives or keeps what it sent.',
   'If the Build Library is taller than your screen','its content scrolls: use the bar at its right edge',
   'Sync is Manual: Nexus sends only what you start (Sync Now or Share).','Sync is Off: Nexus sends nothing. Local records are kept.',
   'joins its hidden Sync chat channel and can receive what others send',
   'queued means waiting to send','Sent means it left this client; receipt is not confirmed.','Received means it arrived here.',
   'Stored means this client kept it after its checks.','does not show which other players have it',
   'asks you to confirm first','A shared build cannot be recalled'}) do
   C.expect(help:find(needle,1,true)~=nil,'Help: the Sharing page says "'..needle..'"')
  end
  C.expect(not help:find('shares each new personal DPS best',1,true)
   and not help:find('the Echo list is sent only in later answers',1,true),
   'Help: no every-personal-best trigger or requester-only Echo promise remains')
  C.expect(DpsDisclosure(help),'Help: the detailed sharing page contains all automatic DPS disclosure facts')
  C.expect(LinkConditional(help),'Help: the Sharing page names the linked build ID only when verified')
  -- The Help mode sentences are the shared words, not a second wording.
  C.guard(policy.Text('manual'):find('Nexus sends only what you start (Sync Now or Share).',1,true)~=nil
   and policy.Text('off'):find('Nexus sends nothing. Local records are kept.',1,true)~=nil,
   'Help: its Manual and Off sentences are the SyncModePolicy words')
 end

 -- 6. Nothing changed the mode or the saved settings over time.
 for _=1,100 do H.Advance(.05,.05) end
 local later=Snapshot()
 C.guard(later.mode==afterBoot.mode and later.saved==afterBoot.saved and later.version==afterBoot.version,
  tag..': after time passes the mode, the saved mode value and the marker are as they were',Text(afterBoot)..' -> '..Text(later))
 -- The choice writes only through the existing private Store owner: the
 -- Store facade and the owner's entries are exactly the preimage ones.
 local function Names(t,functionsOnly)
  local out={}
  for k,v in pairs(type(t)=='table' and t or {}) do
   if not functionsOnly or type(v)=='function' then out[#out+1]=tostring(k) end
  end
  table.sort(out)
  return table.concat(out,',')
 end
 local owner=Nexus.MainInternals and Nexus.MainInternals.StoreAuthorityOwner
 C.guard(Names(Nexus.Store,true)==table.concat(STORE_EXPORTS,','),tag..': the Store facade exports are unchanged',Names(Nexus.Store,true))
 C.guard(Names(owner,true)==table.concat(OWNER_ENTRIES,','),tag..': the private Store owner keeps its entries (no new writer)',Names(owner,true))
 C.guard(Snapshot().choice==nil and afterBoot.choice==nil,tag..': no choice was written by any view or by time passing')
 C.guard(#H.actions==0,tag..': no game action',#H.actions)
end

C.scenario('A format-2 profile: Automatic (its stored "manual" is not this build\'s choice)',function()
 Run('A',F.Database({version=2}),'automatic',AUTOMATIC)
 C.guard(NexusDB.settings.syncMode=='manual' and NexusDB.settingsVersion==2,'A: the stored value and the format-2 marker are kept as they were',
  printable(NexusDB.settings.syncMode)..'/'..printable(NexusDB.settingsVersion))
end)
C.scenario('M accepted format 5: Manual',function()
 Run('M',F.Database(),'manual',
  "Sync is Manual: your saved Sync mode is Manual, so Nexus sends only what you start (Sync Now or Share).")
 C.setup(Nexus.SyncModePolicy.Text('manual')=="Sync is Manual: your saved Sync mode is Manual, so Nexus sends only what you start (Sync Now or Share).",
  'M: fixture: the Manual words are SyncModePolicy\'s',Nexus.SyncModePolicy.Text('manual'))
 C.guard(NexusDB.settings.syncMode=='manual' and NexusDB.settingsVersion==5,'M: the saved Manual choice and marker are unchanged')
end)
C.scenario('O accepted format 5: Off',function()
 Run('O',F.Database({mutate=function(db) db.settings.syncMode='off' end}),'off',
  "Sync is Off: your saved Sync mode is Off, so Nexus sends nothing. Local records are kept.")
 C.setup(Nexus.SyncModePolicy.Text('off')=="Sync is Off: your saved Sync mode is Off, so Nexus sends nothing. Local records are kept.",
  'O: fixture: the Off words are SyncModePolicy\'s',Nexus.SyncModePolicy.Text('off'))
 C.guard(NexusDB.settings.syncMode=='off' and NexusDB.settingsVersion==5,'O: the saved Off choice and marker are unchanged')
end)

C.scenario('D23 documented automatic sends',function()
 -- D23 linked build ID: exact anchors of the focused document's detailed
 -- field list and its source gate. The README check is unchanged.
 local LINK_ANCHORS={['docs/9020_SYNC_AND_NO_GUARANTEE.md']={
  'with player name, realm, class, level, ordinary Echoes, any locked Echoes, category, DPS, duration and time and, when verified, the linked build ID.',
  '(`WLD2`, including `e` and optional `lk`; optional `b` is `relatedBuildId` from `VerifiedDpsBuildId`:',
  "the record's `buildId` only when `CatalogGet` finds that build with the record's verified owner and fingerprint and an `ordinary` `Identity.SavedMirrorKind`; otherwise `b` is omitted)",
 }}
 for _,path in ipairs({'README.md','docs/9020_SYNC_AND_NO_GUARANTEE.md'}) do
  local f=io.open(path,'rb')
  C.setup(f~=nil,'D23: disclosure document is readable: '..path)
  local text=f and f:read('*a') or ''
  if f then f:close() end
  C.expect(DpsDisclosure(text),'D23: '..path..' discloses the actual automatic DPS path')
  for _,anchor in ipairs(LINK_ANCHORS[path] or {}) do
   C.expect(text:find(anchor,1,true)~=nil,'D23: '..path..' says "'..anchor..'"')
  end
  if LINK_ANCHORS[path] then
   C.expect(LinkConditional(text),'D23: '..path..' names the linked build ID only when verified')
  end
 end
end)

C.finish('(one Sync vocabulary on the Welcome, Help, Build Library and Leaderboard; the mode is shown, never set; viewing has no effect)')
