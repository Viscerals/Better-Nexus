-- UX M5 (UX-12 / LP-12): the Sync words a player is shown match what that
-- runtime actually sends without a click. Two real runtimes per mode
-- (sync_pair_support; packets are only those captured from real
-- SendChatMessage/SendAddonMessage calls). Automatic says it may send login
-- requests and answers to other users: the automatic login request and an
-- answer to the other peer are observed. Manual says it sends only what you
-- start and Off says it sends nothing: neither request nor answer is
-- observed. Viewing the words (Build Library, both Sync Now tooltips, the
-- Welcome) is checked with no time passing and starts nothing; normal
-- background Sync is observed only while time passes afterwards.
-- Healthy behaviour (EXPECT, fails on the accepted M4 source 23109b90 by
-- design): the Automatic peer is shown "Sync is Automatic: ..." and the same
-- words in both Sync Now tooltips and on the Welcome.
-- Unchanged (GUARD, holds there too): the Off and Manual lines; the observed
-- sends of each mode (sync_saved_mode_* cover them in depth); viewing starts
-- nothing; the saved mode value and marker. The new-DPS-best send is traced in
-- source (core/DpsCapture.lua new-best branch) and is not re-run here.
local P=dofile('tests/prototype/sync_pair_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('ux_sync_disclosure_sends')

local AUTOMATIC="Sync is Automatic: Nexus may send without a click (login requests, answers to other users, your new DPS bests with your character name)."

-- Every line one peer's tooltip receives while `button`'s OnEnter runs.
local function Tip(peer,button)
 local lines,tip={},peer.e.GameTooltip
 local saved={AddLine=rawget(tip,'AddLine'),SetText=rawget(tip,'SetText')}
 rawset(tip,'AddLine',function(_,s) lines[#lines+1]=V.Plain(tostring(s or '')) end)
 rawset(tip,'SetText',function(_,s) lines[#lines+1]=V.Plain(tostring(s or '')) end)
 local script=button and button:GetScript('OnEnter')
 local ok,err=true,nil
 if script then ok,err=pcall(script,button) end
 rawset(tip,'AddLine',saved.AddLine);rawset(tip,'SetText',saved.SetText)
 return lines,ok,err
end
local function Has(lines,text) for _,l in ipairs(lines) do if l==text then return true end end return false end
local function FromA(A,since,code)
 local n=0
 for i=since+1,#P.trace do local t=P.trace[i];if t.from==A.name and (not code or t.code==code) then n=n+1 end end
 return n
end
local function Snapshot(A)
 local stats=A.e.Nexus.Sync.Stats() or {}
 return {sent=#A.H.sent,admitted=stats.admittedPackets or 0,mode=A.e.Nexus.SyncModePolicy.Mode(),
  saved=A.e.NexusDB.settings.syncMode,version=A.e.NexusDB.settingsVersion}
end
local function Same(a,b)
 return a.sent==b.sent and a.admitted==b.admitted and a.mode==b.mode and a.saved==b.saved and a.version==b.version
end
local function Text(s)
 return string.format('sent=%d admitted=%d mode=%s saved=%s version=%s',s.sent,s.admitted,printable(s.mode),printable(s.saved),printable(s.version))
end

local function Run(tag,mode,line)
 local A,B=P.Boot({'DisclosePeer','OtherPeer'},{5,5},function(i,db)
  if i==1 then db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode=mode end
 end)
 local e=A.e
 C.setup(e.Nexus.SyncModePolicy.Mode()==mode,tag..': fixture: the disclosing peer\'s effective mode is '..mode,e.Nexus.SyncModePolicy.Mode())
 if A.H.AcknowledgeOverwriteWarnings then A.H.AcknowledgeOverwriteWarnings() end

 -- 1. What this peer is shown, read with no time passing.
 local before=Snapshot(A)
 e.Nexus.CommunityBuilds.Show()
 local lib=e.NexusCommunityBuildsFrame
 local libTip=Tip(A,lib and lib._syncBtn)
 e.Nexus.Leaderboard.Show()
 local lbBtn
 for _,c in ipairs(e.NexusLeaderboardFrame and e.NexusLeaderboardFrame.children or {}) do
  local label=c.kind=='Button' and V.Plain(c:GetText() or '') or ''
  if label=='Sync Now' or label=='Preparing shared data...' then lbBtn=c end
 end
 local lbTip=Tip(A,lbBtn)
 local okWelcome=e.Nexus.QuickStart.ShowSetup()
 local welcome=e.NexusQuickStart and e.NexusQuickStart.sync and V.Plain(e.NexusQuickStart.sync:GetText() or '') or ''
 if e.NexusQuickStart then e.NexusQuickStart:Hide() end
 if e.NexusLeaderboardFrame then e.NexusLeaderboardFrame:Hide() end
 e.Nexus.CommunityBuilds.Hide()
 local after=Snapshot(A)
 print('OBSERVED',tag,'library tooltip='..table.concat(libTip,' | '))
 print('OBSERVED',tag,'welcome='..welcome)
 C.setup(lib~=nil and lbBtn~=nil and okWelcome==true,tag..': fixture: the Build Library, Leaderboard and Welcome opened')
 C.guard(Same(before,after),tag..': viewing the Sync words starts nothing and changes no mode',Text(before)..' -> '..Text(after))
 local shown=Has(libTip,line) and Has(lbTip,line) and welcome:find(line,1,true)==1
 if mode=='automatic' then
  C.expect(shown,tag..': both Sync Now tooltips and the Welcome say "'..line..'"',table.concat(libTip,' | '))
 else
  C.expect(shown,tag..': both Sync Now tooltips and the Welcome give the saved '..mode..' line',table.concat(libTip,' | '))
 end

 -- 2. What this peer sends without a click (time passes: background Sync).
 local mark,sent=#P.trace,#A.H.sent
 P.Advance(40)
 local requests=FromA(A,mark,'WLRQ')
 local idle=#A.H.sent-sent
 sent=#A.H.sent
 B.e.Nexus.Sync.RequestSync()
 if mode=='automatic' then
  pcall(P.Until,function() return #A.H.sent>sent end,4000)
 else
  P.Advance(20)
 end
 local answers=#A.H.sent-sent
 print('OBSERVED',tag,'login requests from this peer='..requests,'idle sends='..idle,'sends after the other peer asked='..answers)
 if mode=='automatic' then
  C.guard(requests>0,tag..': it does send the automatic login request it discloses',requests)
  C.guard(answers>0,tag..': and it does answer the other peer, as it discloses',answers)
 else
  C.guard(requests==0 and idle==0,tag..': without a click it sends no login request and nothing else',requests..'/'..idle)
  C.guard(answers==0,tag..': and it does not answer the other peer',answers)
 end
 -- The words match the behaviour just observed.
 local claimsLogin=line:find('login requests',1,true)~=nil
 local claimsAnswers=line:find('answers to other users',1,true)~=nil
 local claimsNothing=line:find('sends nothing',1,true)~=nil or line:find('sends only what you start',1,true)~=nil
 local truthful=(claimsLogin==(requests>0)) and (claimsAnswers==(answers>0)) and (claimsNothing==(requests==0 and answers==0))
 if mode=='automatic' then
  C.expect(shown and truthful,tag..': the shown words match what this runtime sent without a click',line)
 else
  C.guard(truthful,tag..': the '..mode..' words match what this runtime sent without a click',line)
 end
 C.guard(e.NexusDB.settings.syncMode==mode and e.NexusDB.settingsVersion==5,tag..': the saved mode value and marker are unchanged')
 C.guard(#A.H.actions==0,tag..': no game action',#A.H.actions)
end

C.scenario('A Automatic',function() Run('A','automatic',AUTOMATIC) end)
C.scenario('M Manual',function()
 Run('M','manual',"Sync is Manual: your saved Sync mode is Manual, so Nexus sends only what you start (Sync Now or Share).")
end)
C.scenario('O Off',function()
 Run('O','off',"Sync is Off: your saved Sync mode is Off, so Nexus sends nothing. Local records are kept.")
end)

C.finish('(each mode\'s shown Sync words match its observed sends without a click; viewing starts nothing)')
