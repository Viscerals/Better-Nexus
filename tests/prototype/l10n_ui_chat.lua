-- Full-UI localization, chat family (core/Main.lua, core/MainLifecycle.lua,
-- core/Updates.lua, core/MainViewModel.lua). The real slash commands, start-up
-- notices, update notices and Updates.Status() are driven through the real
-- TOC boot and their chat lines are read where the client shows them
-- (DEFAULT_CHAT_FRAME via H.chat). Sections:
--  1. English: exact bytes of representative lines; every reviewed English
--     chat sentence is a fixed point of UserText.Message, so the English path
--     (which still runs that rewrite) shows exactly the catalog English.
--  2. Pseudo pack: every chat line of this family is marked, the code-owned
--     "Nexus:" prefix and colour codes stay outside the translation, slash
--     command words and data stay literal; the known unadopted lines are
--     listed explicitly (pending/excluded in the fragment).
--  3. Lifecycle and update paths: start-up line, EchoOptimizer warning, the
--     HUD Auto feedback, a catalog-full notice, the update notice, the menu row
--     and /nexus update.
--  4. HUD view-model labels (quality names, unknown spell, unnamed Wishlist).
--  5. Templates: unknown count "?", zero "0", non-ASCII names verbatim, an
--     over-bound slot keeps the exact former English line.
--  6. Long pseudo mode on the densest replies: no error, text still shown.
--  7. Missing pack entries show their exact English.
--  8. Passivity of the read-only commands: saved tables, sends, actions.
-- Synthetic offline evidence only: no native chat, font or layout claim.
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local PREFIX='|cff7fd5ffNexus:|r '
local WISHLIST_NAME='Zażółć Wünschliste'

local H
local function Boot(mode,entries,setup)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;EchoOptimizer=nil
 if mode then S.InstallBootHook(mode~='wrap' and mode or nil,entries) end
 H=dofile('tests/prototype/harness.lua')
 if setup then setup() end
 H.Boot()
 return H
end
local function Assign()
 assert(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity(WISHLIST_NAME,{{spellId=200001,quality=1,stacks=2}}))
 H.Advance(2,.05)
end
local function Run(cmd)
 local first=#H.chat+1
 SlashCmdList.NEXUS(cmd)
 local out={}
 for i=first,#H.chat do out[#out+1]=H.chat[i] end
 return out
end
local function Has(lines,want) for _,l in ipairs(lines) do if l==want then return true end end return false end
local function Joined(lines) return table.concat(lines,'\n') end

------------------------------------------------------------------------------
-- 1. English
------------------------------------------------------------------------------
Boot(nil)
local L=Nexus.Localization
check(L.ActiveLanguage()=='enUS','English session')
local d=L.Diagnostics()
check(d.base.undeclared==0 and d.base.missingDeclared==0 and d.base.rejected==0,'composed English catalog admitted whole')
local version,label=Nexus.VERSION,Nexus.RuntimeBuildLabel()
check(H.chat[1]==PREFIX..'v'..version..' build='..label..' -- type /nexus for commands.','start-up line, exact English: '..tostring(H.chat[1]))
Assign()
local status=Run('status')
check(Has(status,PREFIX..'v'..version..' build='..label..' -- level 40, auto OFF'),'status version line exact')
check(Has(status,PREFIX..'ACTIVE: no build activated right now.'),'status ACTIVE line exact')
check(Has(status,PREFIX..'READABLE: 0 confirmed Saved Build(s), 0 desired Wishlist plan(s)'),'status READABLE line exact (count slots)')
check(Has(status,PREFIX..'No confirmed Saved Build yet; complete and save your first run.'),'status Saved Build line exact')
-- v3: every runtime/adapter chat line of Main's runtime phrase source,
-- rebuilt as its producer builds it (a count 7, a text 'Frostwake'), with
-- and without a producer's coloured tag; and the Auto hold line.
local function RuntimeLines()
 local book=Nexus.MainRuntimeBook()
 local out={}
 for raw in pairs(book.exact) do out[#out+1]=raw;out[#out+1]='|cffff9040Nexus:|r '..raw end
 for _,entry in ipairs(book.formats) do
  local args={}
  for n,slot in ipairs(entry.slots) do args[n]=slot=='count' and 7 or 'Frostwake' end
  local line=string.format(entry.format,unpack(args))
  out[#out+1]=line;out[#out+1]='|cff4dff80Nexus:|r '..line
 end
 out[#out+1]='Auto is ON but paused: user acting'
 return out,book
end
-- v3: the raw status lines show the English UserText's rewrite showed before.
for _,raw in ipairs({'OWNED this run: 3 echoes (synced).','OWNED this run: 0 echoes (not synced yet).','TARGET: none -- advisor only',
 "TARGET: |cff7fff7f'Plan'|r (your active loadout) -- 12 echoes",'TARGET: none -- advisor only  (Waiting for loadout data...)'}) do
 check(Nexus.UserText.Message(raw)==Nexus.UserText.EnglishMessage(raw),'v3: English status line unchanged: '..Nexus.UserText.Message(raw))
end
check(Nexus.UserText.Message('OWNED this run: 3 echoes (synced).')=='Rolled Echoes this run: 3 echoes (server confirmed).','v3: the owned line keeps its exact English')
do
 local lines,book=RuntimeLines()
 local n=0
 for _ in pairs(book.exact) do n=n+1 end
 check(n==10 and #book.formats==11,'v3: the runtime chat book is admitted whole: '..n..' exact, '..#book.formats..' formats')
 for _,line in ipairs(lines) do
  check(Nexus.UserText.Message(line)==Nexus.UserText.EnglishMessage(line),'v3: English runtime chat line unchanged: '..line)
 end
end
check(Has(status,PREFIX..'rolling strategy: adaptive') and Has(status,PREFIX..'rolling strategy last decision: none'),'rolling lines exact')
local recording
for _,l in ipairs(status) do if l:find('roll recording: ',1,true) then recording=l end end
check(recording and recording:match('^'..PREFIX:gsub('%p','%%%0')..'roll recording: on %(local only%), %d+ saved records %(limit %d+%), %d+ failed, %d+ dropped$'),'roll recording line exact shape: '..tostring(recording))
check(Has(status,PREFIX.."WISHLIST: |cff7fff7f'"..WISHLIST_NAME.."'|r (your wishlist) -- 1 echoes"),'pending TARGET line keeps its English rewrite')
local english={}
english.wishlist=Run('wishlist')
check(english.wishlist[1]==PREFIX.."reading |cff7fff7f'"..WISHLIST_NAME.."'|r (from your wishlist) -- 1 echoes, 1 families",'wishlist reading line exact: '..tostring(english.wishlist[1]))
english.progress=Run('progress')
check(english.progress[1]==PREFIX..'this run: |cff7fff7f0/2|r echoes (0%) -- 1 still short','progress line exact: '..tostring(english.progress[1]))
english.reference=Run('reference')
check(#english.reference==4
 and english.reference[1]==PREFIX..'Nexus reference: /nexus help | guide | reference | editor | panel | status | loading | orbs | policy | trace'
 and english.reference[2]==PREFIX..'Rolling permissions: /nexus reroll on|off, /nexus freeze on|off. Automation is a separate switch.'
 and english.reference[3]==PREFIX..'Rolling strategy: /nexus policy adaptive|released. Local roll record: /nexus trace.'
 and english.reference[4]==PREFIX..'Session pause: /nexus pause, /nexus resume, /nexus paused. Pauses Auto, Orb actions, sharing and DPS recording until Resume or reload.',
 'reference lines exact')
check(Joined(Run('reroll bogus'))==PREFIX..'Use /nexus reroll on|off, /nexus freeze on|off, or /nexus currentlocks on|off','usage line exact')
check(Joined(Run('pause'))==PREFIX..'Nexus paused for this session. Auto, Orb actions, sharing and DPS recording are held. An action already sent may still finish. Type /nexus resume to continue.','pause line exact')
check(Joined(Run('resume'))==PREFIX..'Nexus resumed. Auto can continue if it was already on. Orb runs stay paused.','resume line exact')
check(Joined(Run('reroll on'))==PREFIX..'reroll permission: on. The master Automation switch remains separate.','rolling permission exact')
check(Joined(Run('anchor 123'))==PREFIX..'Adaptive Power preference set to 123','anchor exact')
check(Joined(Run('legacy bogus'))==PREFIX..'Use /nexus legacy to review older saved data, then /nexus legacy keep <code>.','legacy usage exact')
local update=Run('update')
check(#update==2 and update[1]==PREFIX..'Installed: '..Nexus.Updates.Status().installed..' (development source).'
 ..'\nNo verified update information. Nexus cannot check for updates by itself.'
 ..'\nVersions stated by other players\' clients are not release information.'
 ..'\nThat is not proof that this build is the latest: to check, open the Releases page.'
 ..'\nUpdate notices: on, stable releases and public test builds.'
 and update[2]==PREFIX..'Releases page: https://github.com/Viscerals/Better-Nexus/releases','update detail exact: '..Joined(update))
check(Nexus.Updates.Status().detailSource=='base' and Nexus.Updates.Status().menu=='Version and updates: no verified update info','English status: base source, exact menu row')
-- Every reviewed English chat sentence of this family is a fixed point of
-- UserText.Message: the English path keeps running that rewrite, so the
-- English shown is exactly the catalog English (placeholders filled with
-- neutral sample values).
local catalog=S.English()
local familyKeys=0
for key,text in pairs(catalog) do
 if key:match('^command%.') or key:match('^main%.') or key:match('^update%.') or key:match('^chat%.') then
  familyKeys=familyKeys+1
  local sample=text:gsub('{[a-z_]+}','7')
  for line in (sample..'\n'):gmatch('(.-)\n') do
   check(Nexus.UserText.Message(line)==line,'English is shown unchanged by the legacy rewrite: '..key)
  end
 end
end
-- 160 reviewed (v2) keys plus the 8 of the v3 supplemental cohort
-- (remainder_misc: the /nexus status WISHLIST: and Rolled Echoes lines) and
-- 1 of the v5 supplemental cohort (main.value.unknown_tome, Source86 P73).
check(familyKeys==160+8+1,'the 169 chat-family keys (160 v2 + 8 v3 + 1 v5 supplemental) are in the English catalog: '..familyKeys)

------------------------------------------------------------------------------
-- 2. Pseudo pack: real commands
------------------------------------------------------------------------------
Boot('wrap')
L=Nexus.Localization
check(L.ActiveLanguage()=='frFR' and S.IsPseudo(L.Text('command.chat.automation_on')),'pseudo pack active from session start')
d=L.Diagnostics()
check(d.base.undeclared==0 and d.base.missingDeclared==0,'no undeclared or missing key')
check(H.chat[1]==PREFIX..S.OPEN..'v'..version..' build='..label..' -- type /nexus for commands.'..S.CLOSE,'start-up line marked, data verbatim: '..tostring(H.chat[1]))
Assign()
-- Lines of this family's commands that are not adopted, each listed in the
-- fragment (pending: UserText rewrite couplings and other owners' text;
-- excluded: support payload, protocol, diagnostics, data lists).
local KNOWN={
 {'^catalog capacity: ','excluded support_payload (SupportReport.CatalogCapacityLines)'},
-- (v3: the WISHLIST:, Rolled Echoes and GameAdapter note lines pass the
-- seam through the /nexus status and Orb phrase sources.)
 {'^/nexus reroll on|off | /nexus freeze','excluded protocol'},
 {'^Wire: ','excluded log_payload (SyncWire stats)'},
 {'^  ','data list of Echo names'},
}
local function Known(body)
 for _,k in ipairs(KNOWN) do if body:find(k[1]) then return k[2] end end
end
local seenKnown={}
local function Scan(lines,cmd)
 for _,line in ipairs(lines) do
  check(line:sub(1,#PREFIX)==PREFIX,'/nexus '..cmd..': code-owned prefix stays first: '..line)
  local body=line:sub(#PREFIX+1)
  local known=Known(body)
  if known then
   seenKnown[known]=true
  else
   check(S.IsPseudo(body),'/nexus '..cmd..': chat line passed the seam: '..body)
   local word=S.LooksUntranslated(body)
   check(word==nil,'/nexus '..cmd..': no unmarked English word ('..tostring(word)..'): '..body)
  end
 end
end
local COMMANDS={'status','wishlist','progress','missing','dps','sync','reference','not-a-command','help','guide',
 'paused','policy','policy bogus','policy adaptive','trace','trace bogus','trace on','reroll bogus','reroll on',
 'freeze off','currentlocks on','currentlocks off','anchor 123','anchor off','prototype','nameplate','update',
 'legacy','legacy bogus','restore','auto','auto','pause','pause','paused','resume','resume','logclear','trace clear'}
local pseudo={}
do
 local lines=RuntimeLines()
 for _,line in ipairs(lines) do
  local shown=Nexus.UserText.Message(line)
  local tag=line:match('^(|c%x+Nexus:|r )') or ''
  check(shown:sub(1,#tag)==tag and S.IsPseudo(shown:sub(#tag+1)) and S.LooksUntranslated(shown:sub(#tag+1),function(w) return w=='Frostwake' end)==nil,
   'v3: runtime chat line said through the seam, its tag kept: '..shown)
 end
 check(Nexus.UserText.Message('Auto is ON but paused: Ordinary rolling paused while the Orb choice is active or cannot be confirmed')
  ==S.OPEN..'Auto is ON but paused: '..S.OPEN..'Ordinary rolling paused while the Orb choice is active or cannot be confirmed'..S.CLOSE..S.CLOSE,
  'v3: a recognized Auto hold reason is said through its key inside the line')
end
for _,cmd in ipairs(COMMANDS) do
 local lines=Run(cmd)
 pseudo[cmd]=lines
 check(#lines>0,'/nexus '..cmd..' answered in chat')
 Scan(lines,cmd)
end
do
 local target,owned
 for _,line in ipairs(pseudo['status']) do
  local body=line:sub(#PREFIX+1)
  if body:find(S.OPEN..'WISHLIST: ',1,true)==1 then target=body end
  if body:find(S.OPEN..'Rolled Echoes this run: ',1,true)==1 then owned=body end
 end
 check(target~=nil and owned~=nil,'v3: the /nexus status WISHLIST: and Rolled Echoes lines are said through their keys: '
  ..tostring(target)..' / '..tostring(owned))
 local raw='TARGET: none -- advisor only  (Choose or create a wishlist to begin your first run.)'
 check(Nexus.UserText.Message(raw)==S.OPEN..'WISHLIST: none -- advisor only  ('..S.OPEN
  ..'Choose or create a wishlist to begin your first run.'..S.CLOSE..')'..S.CLOSE,'v3: the advisor-only line says its note through its key')
end
-- Colour codes stay in code around the translated text.
local dps=Joined(pseudo.dps)
check(dps:find(PREFIX..'|cffff9040'..S.OPEN..'Details! damage meter is not installed.'..S.CLOSE..'|r',1,true),'orange DPS line keeps its colour outside the translation')
-- Command words and argument syntax stay literal (slots or literal text).
check(pseudo.reference[1]==PREFIX..S.OPEN..'Nexus reference: /nexus help | guide | reference | editor | panel | status | loading | orbs | policy | trace'..S.CLOSE,'command list slot verbatim')
check(Joined(pseudo['reroll bogus'])==PREFIX..S.OPEN..'Use /nexus reroll on|off, /nexus freeze on|off, or /nexus currentlocks on|off'..S.CLOSE,'usage slots verbatim')
check(Joined(pseudo['reroll on'])==PREFIX..S.OPEN..'reroll permission: on. The master Automation switch remains separate.'..S.CLOSE,'option and value are literal command words')
check(Joined(pseudo['policy adaptive']):find(S.OPEN..'Rolling strategy selected: adaptive.',1,true),'setting value literal')
check(pseudo.pause[1]:find('/nexus resume',1,true) and pseudo.help[1]:find('/nexus reference',1,true),'slash commands inside sentences stay literal')
check(pseudo.wishlist[1]==PREFIX..S.OPEN.."reading |cff7fff7f'"..WISHLIST_NAME.."'|r (from "..S.OPEN..'your wishlist'..S.CLOSE..') -- 1 echoes, 1 families'..S.CLOSE,'non-ASCII name and its colour verbatim in a slot; nested source phrase translated: '..pseudo.wishlist[1])
check(Has(pseudo.status,PREFIX..S.OPEN..'READABLE: 0 confirmed Saved Build(s), 0 desired Wishlist plan(s)'..S.CLOSE),'zero counts render as 0')
check(Has(pseudo.status,PREFIX..S.OPEN..'rolling strategy last decision: '..S.OPEN..'none'..S.CLOSE..S.CLOSE),'the none word is translated and nested')
-- The translated text never runs through the English-only rewrite: the
-- pseudo text of a sentence that rewrite would change shows unchanged.
check(Nexus.UserText.Message('TARGET: x')=='WISHLIST: x','SETUP the rewrite is active in this session')
-- The update detail: every line translated; the URL is data.
local upd=pseudo.update
check(#upd==2 and upd[2]==PREFIX..S.OPEN..'Releases page: https://github.com/Viscerals/Better-Nexus/releases'..S.CLOSE,'Releases line: URL verbatim')
for line in (upd[1]:sub(#PREFIX+1)..'\n'):gmatch('(.-)\n') do
 check(S.IsPseudo(line) and S.LooksUntranslated(line)==nil,'every update detail line translated: '..line)
end
check(Nexus.Updates.Status().detailSource=='candidate','Status says a translation is in its detail')
-- R5 retro: the whole translated /nexus update reply, built independently of
-- Updates.Status().detail from the pack entries in their order (installed,
-- no verified info, peer versions, not proof, notices), joined by LF after
-- the one chat prefix; the Releases line keeps the URL verbatim. A dropped
-- clause or separator fails here even when every remaining line is marked.
do
 local P=S.activeEntries
 local function E(key,args) return (P[key]:gsub('{(%l[%w_]*)}',function(n) return args and args[n] end)) end
 local installed=Nexus.Updates.Status().installed
 local want=PREFIX..E('update.body.installed',{build=installed,channel=E('update.value.channel_development')})
  ..'\n'..E('update.body.no_verified_info')..'\n'..E('update.body.peer_versions_not_release')
  ..'\n'..E('update.body.not_proof_latest')..'\n'..E('update.body.notices_on_all')
 check(upd[1]==want,'R5 retro: the whole translated update detail, in order: '..upd[1])
 check(upd[2]==PREFIX..E('command.chat.update_releases_page',{url='https://github.com/Viscerals/Better-Nexus/releases'}),
  'R5 retro: the translated Releases line with the verbatim URL')
end
local menuRow
for _,item in ipairs(Nexus.Panel.MoreMenuItems()) do
 if item.text==Nexus.Updates.Status().menu then menuRow=item end
end
check(menuRow and S.IsPseudo(menuRow.text) and S.LooksUntranslated(menuRow.text)==nil,'the real More menu shows the translated update row: '..tostring(menuRow and menuRow.text))
check(Nexus.Updates.Status().channelLabel==S.OPEN..'development source'..S.CLOSE,'channel label translated')

------------------------------------------------------------------------------
-- 3. Lifecycle and update notices under the pseudo pack
------------------------------------------------------------------------------
-- The TOC loaded as startup_support does it, so a test can wrap a module
-- between load and ADDON_LOADED. `before` runs in that gap.
local T=dofile('tests/prototype/startup_support.lua')
local function LoadBoot(mode,entries,before)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;EchoOptimizer=nil
 if mode then S.InstallBootHook(mode~='wrap' and mode or nil,entries) end
 H=dofile('tests/prototype/harness.lua')
 NexusDB=T.Profile(3,0)
 T.Load()
 if before then before() end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
 H.AcknowledgeOverwriteWarnings()
end
-- EchoOptimizer warning, and the HUD Auto button's callback as the real
-- lifecycle hands it to Panel.Init.
local panelOptions
LoadBoot('wrap',nil,function()
 EchoOptimizer={}
 local init=Nexus.Panel.Init
 Nexus.Panel.Init=function(options,...) panelOptions=options;return init(options,...) end
end)
local warning
for _,l in ipairs(H.chat) do if l:find('EchoOptimizer detected',1,true) then warning=l end end
check(warning==PREFIX..'|cffff6060'..S.OPEN.."EchoOptimizer detected -- it conflicts with Nexus's board hook. Disable EchoOptimizer; Nexus replaces its functionality."..S.CLOSE..'|r','red EchoOptimizer warning: colour outside, text marked: '..tostring(warning))
EchoOptimizer=nil
local toggle=panelOptions and panelOptions.ToggleAuto
check(type(toggle)=='function','SETUP the HUD Auto callback')
local before=#H.chat
local on=toggle()
local line=H.chat[before+1]
check(line==PREFIX..S.OPEN..(on and 'auto ON' or 'auto OFF')..S.CLOSE,'HUD Auto feedback marked: '..tostring(line))
local off=toggle()
check(H.chat[before+2]==PREFIX..S.OPEN..(off and 'auto ON' or 'auto OFF')..S.CLOSE,'second HUD Auto feedback marked')
-- A catalog-full notice: the real lifecycle reads the catalog's refusal
-- record (stubbed reads) and says it once.
local catalogModule=Nexus.BuildCatalog
local realRefusals,realSummary=catalogModule.SaturationRefusals,catalogModule.SaturationSummary
catalogModule.SaturationRefusals=function() return 1 end
catalogModule.SaturationSummary=function() return {refusedBuilds=1} end
before=#H.chat
H.Advance(2,.05)
catalogModule.SaturationRefusals,catalogModule.SaturationSummary=realRefusals,realSummary
local notice
for i=before+1,#H.chat do if H.chat[i]:find('Community catalog full',1,true) then notice=H.chat[i] end end
check(notice==PREFIX..S.OPEN..'Community catalog full: new shared builds are refused.'..S.CLOSE..' '..S.OPEN
 ..'Your existing Community builds and Leaderboard stay available. See /nexus status.'..S.CLOSE,'catalog-full notice: two marked sentences: '..tostring(notice))

-- The update notice (bundled newer public test build), set up as
-- update_notices.lua does it.
local function UpdateBoot(mode)
 LoadBoot(mode,nil,function()
  Nexus.Release.buildLabel='test.9027-3f1cd20';Nexus.Release.channel='public-test'
  Nexus.Release.availableVersion='1.20.0-beta.1+test.9029'
 end)
end
UpdateBoot('wrap')
local updateNotice
for _,l in ipairs(H.chat) do if l:find('1.20.0-beta.1 test.9029',1,true) then updateNotice=l end end
check(updateNotice==PREFIX..S.OPEN..'New Nexus test build available: 1.20.0-beta.1 test.9029. You have 1.20.0-beta.1 test.9027. Installation is manual: /nexus update shows the Releases page.'..S.CLOSE,
 'update notice translated with versions verbatim, not rewritten: '..tostring(updateNotice))
local st=Nexus.Updates.Status()
check(st.state=='available' and st.menu==S.OPEN..'Update available: 1.20.0-beta.1 test.9029'..S.CLOSE,'available menu row marked')
check(st.detail:find(S.OPEN..'Installed: 1.20.0-beta.1 test.9027 ('..S.OPEN..'public test build'..S.CLOSE..', test.9027-3f1cd20).'..S.CLOSE,1,true),'installed line with label: '..st.detail)
for l in (st.detail..'\n'):gmatch('(.-)\n') do check(S.LooksUntranslated(l)==nil,'available detail translated: '..l) end
-- English for the same notice, exact (the former bytes).
UpdateBoot(nil)
check(Has(H.chat,PREFIX..'New Nexus test build available: 1.20.0-beta.1 test.9029. You have 1.20.0-beta.1 test.9027. Installation is manual: /nexus update shows the Releases page.'),'English update notice exact')
st=Nexus.Updates.Status()
check(st.menu=='Update available: 1.20.0-beta.1 test.9029' and st.detailSource=='base'
 and st.detail:find('Installed: 1.20.0-beta.1 test.9027 (public test build, test.9027-3f1cd20). New Nexus test build available: 1.20.0-beta.1 test.9029.',1,true),'English available status exact')

------------------------------------------------------------------------------
-- 4. HUD view-model labels
------------------------------------------------------------------------------
Boot('wrap')
local VM=Nexus.MainInternals.ViewModel.New({ratchet=Nexus.Ratchet,model=Nexus.Model,wishlistModel=Nexus.WishlistModel.New()})
local vmCatalog={rows={[900002]={name='Tier Epic',quality=3},[900003]={name='Tier Legendary',quality=4}},familyName={famA='Family A'}}
local plan={wishedFamilies={famA=true},targets={famA={targetStacks=2,qualityTiers={{spellId=900002,q=3,n=1},{spellId=900003,q=4,n=1}}}}}
local _,_,missing=VM.WishlistProgress(plan,{bySpell={},byFamily={}},vmCatalog,{},nil,nil,nil)
local joined=table.concat(missing,' | ')
check(joined:find(S.OPEN..'Epic'..S.CLOSE..':×1',1,true) and joined:find(S.OPEN..'Legendary'..S.CLOSE..':×1',1,true),'quality tier labels translated, code marks kept: '..joined)
local progress=VM.BuildProgress({plan=plan,owned={bySpell={[777001]=2},byFamily={}},catalog=vmCatalog,wishlist={name='',entries={}}})
check(progress.wishlistName==S.OPEN..'(unnamed)'..S.CLOSE,'unnamed Wishlist label translated')
check(#progress.shed==1 and progress.shed[1]==S.OPEN..'spell 777001'..S.CLOSE..' ×2','unknown spell label translated, ID verbatim: '..tostring(progress.shed[1]))

------------------------------------------------------------------------------
-- 5. Templates through the seam with this family's keys; an over-bound slot
------------------------------------------------------------------------------
L=Nexus.Localization
local readable=L.Format('command.chat.status_readable',{saved=L.Count(nil),plans=L.Count(0)})
check(readable==S.OPEN..'READABLE: ? confirmed Saved Build(s), 0 desired Wishlist plan(s)'..S.CLOSE,'unknown count is ?, zero is 0: '..readable)
local long=string.rep('Ł',200)
check(L.Format('command.chat.dps_last_session',{note=long})==S.OPEN..'Last session: '..long..S.CLOSE,'long non-ASCII text slot verbatim')
-- A value above a key's result limit is never cut: the seam refuses it.
local refused,source=L.Format('command.chat.rolling_strategy',{strategy=long})
check(source=='unavailable' and not refused:find(long,1,true),'over-limit output is refused, not cut')
-- A DPS note above the text-slot bound keeps the exact former English line.
local note=string.rep('n',1500)
Nexus.lastDpsNote=note
local lines=Run('dps')
check(Has(lines,PREFIX..'Last session: '..note),'over-bound note: the exact former English line, not the unavailable status')
Nexus.lastDpsNote=nil

------------------------------------------------------------------------------
-- 6. Long pseudo mode on the densest replies
------------------------------------------------------------------------------
Boot('long')
Assign()
for _,cmd in ipairs({'status','reference','wishlist','update','legacy bogus','policy','trace'}) do
 local out=Run(cmd)
 check(#out>0,'long mode: /nexus '..cmd..' still answers')
 for _,l in ipairs(out) do
  local body=l:sub(#PREFIX+1)
  check(l:sub(1,#PREFIX)==PREFIX and body~='','long mode: prefix and text shown')
  if not Known(body) then check(S.IsPseudo(body),'long mode: marked: '..body) end
 end
end

------------------------------------------------------------------------------
-- 7. Missing pack entries fall back to their exact English
------------------------------------------------------------------------------
local entries=S.PseudoEntries()
for _,key in ipairs({'main.chat.loaded','command.chat.reference_session_pause','command.chat.status_readable',
 'update.menu.no_verified_info','command.chat.session_only_note'}) do
 check(entries[key]~=nil,'SETUP pseudo entry exists: '..key);entries[key]=nil
end
Boot('wrap',entries)
check(H.chat[1]==PREFIX..'v'..version..' build='..label..' -- type /nexus for commands.','missing entry: start-up line exact English')
local ref=Run('reference')
check(ref[4]==PREFIX..'Session pause: /nexus pause, /nexus resume, /nexus paused. Pauses Auto, Orb actions, sharing and DPS recording until Resume or reload.','missing entry: exact English line')
check(S.IsPseudo(ref[1]),'its neighbours stay translated')
check(Has(Run('status'),PREFIX..'READABLE: 0 confirmed Saved Build(s), 0 desired Wishlist plan(s)'),'missing template entry: exact English')
st=Nexus.Updates.Status()
check(st.menu=='Version and updates: no verified update info' and st.detailSource=='candidate','missing menu entry: exact English; detail still translated')

------------------------------------------------------------------------------
-- 8. Passivity of the read-only commands (pseudo session)
------------------------------------------------------------------------------
local function Serialize(value,seen)
 local kind=type(value)
 if kind~='table' then return kind..':'..tostring(value) end
 seen=seen or {}
 if seen[value] then return '<cycle>' end
 seen[value]=true
 local keys={}
 for k in pairs(value) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return type(a)..tostring(a)<type(b)..tostring(b) end)
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=Serialize(k,seen)..'='..Serialize(value[k],seen) end
 seen[value]=nil
 return '{'..table.concat(out,',')..'}'
end
Boot('wrap')
Assign()
H.Advance(2,.05)
local function Snapshot()
 return {db=Serialize(NexusDB),legacy=Serialize(WishlistRealizerDB),sent=#H.sent,actions=#H.actions,
  popup=Serialize(H.popup),auto=Nexus.RecomputeStats().autoEnabled}
end
local s0=Snapshot()
for _,cmd in ipairs({'status','wishlist','progress','missing','paused','policy','legacy'}) do Run(cmd) end
local s1=Snapshot()
for k,v in pairs(s0) do check(s1[k]==v,'read-only chat commands change nothing: '..k) end

------------------------------------------------------------------------------
-- 9. Source16 (Main identity-note lease): the adapter's identity-found note,
-- from the real adapter after a real association, at /nexus status (inside
-- the advisor-only line, whole, as that line showed it) and at /nexus
-- wishlist (UserText: without its lead). Expected texts are written out here.
------------------------------------------------------------------------------
local O,C=S.OPEN,S.CLOSE
local ID_SUFFIX=' Open the Wishlist Editor to choose and confirm its locked targets.'
local REASON='active loadout is not verified; locked-Echo evidence is pending'
local NOTE='Wishlist identity found; '..REASON..'.'..ID_SUFFIX
local function IdentityWorld(entries)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;EchoOptimizer=nil
 if entries~=false then S.InstallBootHook(nil,entries) end
 H=dofile('tests/prototype/harness.lua')
 local locks={200690,200756,200882,201250,201262,201270};local q={2,3,2,3,3,3};local total={}
 for i=1,79 do local id=210000+i;H.AddEcho(id,'Ordinary '..i,2,5);total[#total+1]={spellId=id,quality=2,stacks=1,locked=false} end
 for i,id in ipairs(locks) do H.AddEcho(id,'Locked '..i,q[i],5);total[#total+1]={spellId=id,quality=q[i],stacks=1,locked=false};H.locked[#H.locked+1]={spellId=id,stacks=1} end
 H.perks.serverBuildSlots={[1]={name='Synthetic active',verified=true,echoes=H.Clone(total)},[101]={name='Synthetic plan',verified=false,echoes=H.Clone(total)}}
 H.perks.serverActiveSlot=1
 H.Boot()
 local A=Nexus.GameAdapter
 local c;for _,row in ipairs(A.GetWishlistCandidates()) do if row.slot==101 then c=row end end
 assert(c and A.SetLoadoutWishlist(1,101,c),'SETUP S16 Main identity: a real association')
 H.perks.serverBuildSlots[101]=nil
 H.perks.serverBuildSlots[1].verified=false
 return A
end
-- The note lines of /nexus status and /nexus wishlist, read passively.
local function NoteRoutes(A)
 local before={db=Serialize(NexusDB),legacy=Serialize(WishlistRealizerDB),sent=#H.sent,actions=#H.actions}
 local status,wish
 for _,l in ipairs(Run('status')) do if l:find('advisor only',1,true) or l:find('Details: TARGET',1,true) then status=l end end
 local lines=Run('wishlist');wish=lines[#lines]
 local note=A.WishlistNote()
 local after={db=Serialize(NexusDB),legacy=Serialize(WishlistRealizerDB),sent=#H.sent,actions=#H.actions}
 local passive=true;for k,v in pairs(before) do if after[k]~=v then passive=false end end
 return status,wish,note,passive
end
do
 local A=IdentityWorld(nil)
 local status,wish,note,passive=NoteRoutes(A)
 check(note==NOTE,'S16 Main identity: the adapter keeps its raw note: '..tostring(note))
 check(status==PREFIX..O..'WISHLIST: none -- advisor only  ('..O..'Wishlist identity found; '..O..REASON..C..'.'..ID_SUFFIX..C..')'..C,
  'S16 Main identity: /nexus status says the whole note inside the advisor-only line, the reason through its key: '..tostring(status))
 check(wish==PREFIX..O..O..REASON..C..'.'..ID_SUFFIX..C,'S16 Main identity: /nexus wishlist says the note without its lead: '..tostring(wish))
 check(passive,'S16 Main identity: /nexus status and /nexus wishlist read passively')
 -- Close controls: the keyed wait sentence keeps precedence over the whole
 -- line; an unknown or other assignment note keeps its existing route.
 H.perks.serverBuildSlots[1].verified=true;H.locked=nil
 local syncStatus,_,syncNote=NoteRoutes(A)
 check(syncStatus==PREFIX..O.."Waiting for the server's current locked Echo list. Details: TARGET: none -- advisor only  ("..syncNote..')'..C,
  'S16 Main identity: close control, the keyed wait sentence keeps the whole status line as details: '..tostring(syncStatus))
 local unknown='Wishlist identity found; an external; reason {x} 100%.'
 check(Nexus.UserText.Message('TARGET: none -- advisor only  ('..unknown..')')==O..'WISHLIST: none -- advisor only  ('..unknown..')'..C,
  'S16 Main identity: a note the adapter did not produce stays exactly as given inside the line')
 check(Nexus.UserText.Message('TARGET: none -- advisor only  (Waiting for loadout data...)')==O..'WISHLIST: none -- advisor only  ('..O..'Waiting for loadout data...'..C..')'..C,
  'S16 Main identity: close control, an exact assignment note keeps its own key')
end
do
 local entries=S.PseudoEntries();entries['orb.assignment.identity_found_open_editor']=nil
 local A=IdentityWorld(entries)
 local status,wish=NoteRoutes(A)
 check(status==PREFIX..O..'WISHLIST: none -- advisor only  ('..NOTE..')'..C,'S16 Main identity missing: a missing note candidate keeps the complete English note inside the line: '..tostring(status))
 check(wish==PREFIX..O..O..REASON..C..'.'..ID_SUFFIX..C,'S16 Main identity missing: /nexus wishlist keeps its own form')
 entries=S.PseudoEntries();entries['command.chat.status_target_none_note']='{note} {nope}'
 A=IdentityWorld(entries)
 status=NoteRoutes(A)
 check(status==PREFIX..'WISHLIST: none -- advisor only  ('..NOTE..')','S16 Main identity invalid: an invalid line candidate shows the whole exact English line: '..tostring(status))
end
do
 local A=IdentityWorld(false)
 local status,wish,note,passive=NoteRoutes(A)
 check(status==PREFIX..'WISHLIST: none -- advisor only  ('..NOTE..')','S16 Main identity English: /nexus status is the exact English line: '..tostring(status))
 check(wish==PREFIX..REASON..'.'..ID_SUFFIX,'S16 Main identity English: /nexus wishlist is the exact English: '..tostring(wish))
 check(note==NOTE and passive,'S16 Main identity English: raw note unchanged and passive')
end

print('l10n_ui_chat: '..checks..' checks')
