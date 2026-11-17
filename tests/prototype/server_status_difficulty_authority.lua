-- #126 difficulty authority (SETUP/EXPECT/GUARD; EXPECT fails at 9bfb2bb9 by design).
-- The difficulty Nexus mirrors is the Project Ebonhold hardmode service's own
-- confirmed state, read passively. PROVIDED nonsecret contract (static facts
-- from an existing user-authorized export; never loaded or executed here):
-- ProjectEbonhold.HardmodeService.IsDifficultyKnown() and
-- GetCurrentDifficulty() are zero-argument passive functions; 1 is Normal and
-- 2..6 are Hardcore I..V; the cache starts at 1 with known false; a nonempty
-- current-data reply (the producer itself coerces a malformed one to 1) or a
-- successful set reply updates the cache and sets known true; a failed set
-- changes nothing; world entry requests data and does not clear known, so
-- known means last confirmed, not confirmed in this zone. The compact HUD tier
-- label starts as a literal Normal and is repainted separately; the Hardcore
-- window slider is a local draft.
-- EXPECT (fails at 9bfb2bb9 by design): a confirmed value is shown whatever the
-- compact label or the selected draft says (known 6 with compact Normal is
-- HC5); an unconfirmed placeholder, a missing, raising or unloaded service and
-- every value outside a finite integer 1..6 are unknown (the generic
-- Difficulty caption), never Normal or HC from text; a successful
-- acknowledgment is shown on the next ordinary scan and a failed Apply leaves
-- the confirmed value; world entry keeps it; late load and replacement are
-- read from the current globals; the rendered Panel caption follows on cold
-- boot, scan and offline reload.
-- GUARD (holds at 9bfb2bb9): confirmed 1 with the literal Normal label stays
-- Normal; Soul Ash, gain and Intensity do not depend on the difficulty; only
-- the passive difficulty, Soul Ash and Intensity fields are read and nothing
-- is written; no saved setting, extra event or hook; the published Hardcore
-- control still opens and closes the window and scans never run it.
-- SETUP: part 1 loads the real ui/ServerStatus.lua alone with synthetic
-- frames and a synthetic producer model (the server_hud_handoff shape) and
-- reads it through GetSummary (cold) and its own scanner OnUpdate/OnEvent;
-- part 2 is a real TOC boot (format5_support/harness) rendering the real
-- Main, MainViewModel and Panel. Offline characterization only: no native
-- export code, server reply, installed client or zone behaviour is evidenced.
local F=dofile('tests/prototype/format5_support.lua')
local counts={setup=0,expect=0,guard=0}
local failures={}
local function Text(v)
 if type(v)=='number' and v~=v then return 'NaN' end
 return tostring(v)
end
local function Record(kind,ok,label,observed)
 counts[kind]=counts[kind]+1
 local line=kind:upper()..(ok and ' PASS ' or ' FAIL ')..label
 if observed~=nil then line=line..' | observed='..Text(observed) end
 print(line)
 if not ok then failures[#failures+1]=line end
 return ok
end
local function setup(ok,label,observed) return Record('setup',ok and true or false,label,observed) end
local function expect(ok,label,observed) return Record('expect',ok and true or false,label,observed) end
local function guard(ok,label,observed) return Record('guard',ok and true or false,label,observed) end

local NATIVE={MAX_INTENSITY=475,INTENSITY_LEVEL_1=75,INTENSITY_LEVEL_2=200,
 INTENSITY_LEVEL_3=275,INTENSITY_LEVEL_4=400,INTENSITY_LEVEL_5=475}
-- Every field ServerStatus may read from the foreign tables in this file.
-- Versioned addition (updated client, wow.export 0.2.19 capture of
-- hardmode_service.lua 46-60): the service may publish one more zero-argument
-- passive reader, GetInstanceDifficulty (the tier of a foreign-tier instance,
-- nil otherwise). Its field is read on every service to learn whether this
-- provider has it; on the older provider modelled by every pre-existing case
-- the field is absent and nothing is called (Part 1c below counts calls).
-- No other field is added; nothing is written.
local ALLOWED={
 ['ProjectEbonhold.HardmodeService']=true,
 ['ProjectEbonhold.PlayerRunUI']=true,
 ['ProjectEbonhold.Constants']=true,
 ['ProjectEbonhold.HardmodeButton']=true,
 ['HardmodeService.IsDifficultyKnown']=true,
 ['HardmodeService.GetCurrentDifficulty']=true,
 ['HardmodeService.GetInstanceDifficulty']=true,
}

-- Synthetic producer model of the supplied state facts. Its two passive
-- functions count calls and arguments; its transitions are driven only by
-- this test, as the server and the game window would drive them.
local function Producer(o)
 o=o or {}
 local p={current=1,known=false,draft=nil,worldRequests=0,knownCalls=0,getterCalls=0,extraArgs=0,instanceCalls=0}
 if o.nilCurrent then p.current=nil elseif o.current~=nil then p.current=o.current end
 if o.nilKnown then p.known=nil elseif o.known~=nil then p.known=o.known end
 p.api={}
 if not o.noReadiness then
  function p.api.IsDifficultyKnown(...)
   p.knownCalls=p.knownCalls+1;p.extraArgs=p.extraArgs+select('#',...)
   if o.readinessThrows then error('synthetic readiness raises') end
   return p.known
  end
 end
 if not o.noGetter then
  function p.api.GetCurrentDifficulty(...)
   p.getterCalls=p.getterCalls+1;p.extraArgs=p.extraArgs+select('#',...)
   if o.getterThrows then error('synthetic getter raises') end
   return p.current
  end
 end
  -- The updated provider only (o.fresh): the instance tier reader.
  if o.fresh then
   function p.api.GetInstanceDifficulty(...)
    p.instanceCalls=p.instanceCalls+1;p.extraArgs=p.extraArgs+select('#',...)
    if o.instanceThrows then error('synthetic instance reader raises') end
    return o.instance
   end
  end
 -- A nonempty current-data body sets the cache (malformed to 1) and known.
 function p.CurrentDataReply(body)
  if type(body)=='string' and body~='' then p.current=tonumber(body) or 1;p.known=true end
 end
 -- The slider draft: a preview only, the cache is untouched.
 function p.SelectDraft(v) p.draft=v end
 function p.ApplySucceeded(v) p.current=v;p.known=true end
 function p.ApplyFailed() end
 -- World entry asks for data and does not clear the known flag.
 function p.WorldEntry() p.worldRequests=p.worldRequests+1 end
 return p
end

-- A read-and-write log over a foreign table.
local function Watched(backing,label,log)
 return setmetatable({},{
  __index=function(_,k) log[#log+1]=label..'.'..tostring(k);return backing[k] end,
  __newindex=function(_,k,v) log[#log+1]='WRITE '..label..'.'..tostring(k);backing[k]=v end})
end

local function FontString(text)
 local r={text=text}
 function r:GetText() return self.text end
 function r:SetText(t) self.text=t end
 return r
end
local function Plain(regions,children,parent)
 local f={regionList=regions or {},childList=children or {},parent=parent,scripts={}}
 function f:GetRegions() return unpack(self.regionList) end
 function f:GetChildren() return unpack(self.childList) end
 function f:GetParent() return self.parent end
 function f:GetScript(event) return self.scripts[event] end
 return f
end
-- The stock run HUD: root, header with the Soul Ash and multiplier texts, and
-- the published Hardcore button holding the compact tier label.
local function StockRoot(compact)
 local label,ash,gain=FontString(compact),FontString('76,054'),FontString('+188%')
 local root=Plain()
 root.shown=true
 function root:IsShown() return self.shown end
 function root:Hide() self.shown=false end
 function root:Show() self.shown=true;if self.onShow then self.onShow(self) end end
 function root:SetAlpha() end
 function root:EnableMouse() end
 function root:HookScript(event,fn)
  if event~='OnShow' then return end
  local prior=self.onShow
  self.onShow=function(...) if prior then prior(...) end;return fn(...) end
 end
 local header=Plain({ash,gain},nil,root)
 local button=Plain({label},nil,header)
 header.childList={button}
 root.childList={header}
 root.soulPointsText=ash
 root.hardmodeTierText=label
 return root,button,label
end
-- The open Hardcore window: a slider exposing the draft and a checked control
-- captioned with the draft.
local function DraftWindow(v)
 local caption=v==1 and 'Normal' or ('Hardcore '..tostring((tonumber(v) or 1)-1))
 local slider=Plain()
 function slider:GetValue() return v end
 local selected=Plain({FontString(caption)})
 function selected:GetChecked() return true end
 local window=Plain({},{slider,selected})
 window.shown=true
 function window:IsShown() return self.shown end
 function window:Show() self.shown=true end
 function window:Hide() self.shown=false end
 return window
end

-- A fresh copy of the real module in synthetic globals.
local function Host(o)
 o=o or {}
 local h={log={},refreshes=0,hookCalls=0,toggles=0,producer=o.producer}
 NexusDB={soulAshHudMode='nexus'}
 h.saved=F.Serialize(NexusDB)
 Nexus={Panel={VisibilityFacts=function() return {ready=true,committed=true} end,
  Refresh=function() h.refreshes=h.refreshes+1 end}}
 UIParent={};HardmodeFrame=nil
 hooksecurefunc=function() h.hookCalls=h.hookCalls+1 end
 EbonholdIntensityData={intensity=275}
 local backing={Constants=NATIVE}
 -- The producer window toggle, as the published control runs it.
 local function Toggle()
  h.toggles=h.toggles+1
  if HardmodeFrame and HardmodeFrame:IsShown() then HardmodeFrame:Hide();return end
  HardmodeFrame=DraftWindow(h.producer and h.producer.draft or 1)
 end
 function h.InstallRoot(compact)
  local root,button,label=StockRoot(compact)
  button.scripts.OnClick=Toggle
  backing.HardmodeButton=button
  ProjectEbonholdPlayerRunFrame=root
  h.root,h.label=root,label
 end
 function h.SetService(p)
  h.producer=p
  backing.HardmodeService=p and Watched(p.api,'HardmodeService',h.log) or nil
 end
 function h.ReplaceProjectEbonhold(p)
  local button=backing.HardmodeButton
  backing={Constants=NATIVE,HardmodeButton=button}
  h.SetService(p)
  ProjectEbonhold=Watched(backing,'ProjectEbonhold',h.log)
 end
 function h.ShowDraft(v) HardmodeFrame=DraftWindow(v) end
 if o.noRoot then ProjectEbonholdPlayerRunFrame=nil else h.InstallRoot(o.compact or 'Normal') end
 if o.serviceValue~=nil then backing.HardmodeService=o.serviceValue
 elseif not o.noService then h.SetService(o.producer) end
 ProjectEbonhold=Watched(backing,'ProjectEbonhold',h.log)
 local scanner
 CreateFrame=function(_,name)
  local f={name=name,scripts={},events={}}
  function f:RegisterEvent(e) self.events[#self.events+1]=e end
  function f:SetScript(event,fn) self.scripts[event]=fn end
  if name=='NexusServerStatusScanner' then scanner=f end
  return f
 end
 dofile('ui/ServerStatus.lua')
 h.status=Nexus.ServerStatus
 h.status.Init()
 assert(scanner and scanner.scripts.OnUpdate and scanner.scripts.OnEvent,'SETUP the real scanner is created')
 h.scanner=scanner
 function h.Tick() scanner.scripts.OnUpdate(scanner,1.0) end
 function h.Enter() scanner.scripts.OnEvent(scanner,'PLAYER_ENTERING_WORLD') end
 return h
end

local function Expected(v)
 if v==nil then return 'nil/nil' elseif v==1 then return 'Normal/nil' end
 local tier='HC'..(v-1)
 return tier..'/'..tier
end
local function Difficulty(s) return tostring(s.mode)..'/'..tostring(s.tier) end
local function Show(h) return Difficulty(h.status.GetSummary()) end
local function Independent(h,s,label,noRoot)
 guard(s.intensity==275 and s.intensityLevel==3 and s.intensityMax==475,
  label..': Intensity is read independently of the difficulty',Text(s.intensity)..'/'..Text(s.intensityLevel))
 if noRoot then
  guard(s.ash==nil and s.gain==nil,label..': with no HUD root no balance or gain is invented',Text(s.ash)..'/'..Text(s.gain))
 else
  guard(s.ash=='76,054' and s.gain=='+188%',label..': Soul Ash and gain are read independently of the difficulty',
   Text(s.ash)..'/'..Text(s.gain))
 end
end
local function Passive(h,label)
 local bad={}
 for _,entry in ipairs(h.log) do if not ALLOWED[entry] then bad[#bad+1]=entry end end
 guard(#bad==0,label..': only the passive difficulty, Soul Ash and Intensity fields are read and nothing is written',
  table.concat(bad,','))
 guard(F.Serialize(NexusDB)==h.saved,label..': no setting or remembered difficulty is saved')
 guard(#h.scanner.events==1 and h.scanner.events[1]=='PLAYER_ENTERING_WORLD',
  label..': the scanner registers only its existing world-entry event',table.concat(h.scanner.events,','))
 guard(h.hookCalls==0,label..': no callback hook is installed',h.hookCalls)
end

----------------------------------------------------------------------------
-- Part 1a: one read per case, cold GetSummary and scanner path.
----------------------------------------------------------------------------
local CASES={}
local function Add(kind,label,want,claim,o)
 o=o or {}
 o.kind,o.label,o.want,o.claim=kind,label,want,claim
 CASES[#CASES+1]=o
end
Add('GUARD','known1/compactNormal -> Normal',Expected(1),'a confirmed 1 stays the explicit Normal',
 {producer={current=1,known=true}})
Add('EXPECT','known6/compactNormal -> HC5',Expected(6),'a confirmed 6 is HC5 whatever the stale compact label says',
 {producer={current=6,known=true}})
Add('EXPECT','unknown placeholder1/compactNormal -> unknown',Expected(nil),'the unconfirmed placeholder 1 is unknown, not Normal',
 {producer={current=1,known=false}})
for v=1,6 do
 Add(v==1 and 'GUARD' or 'EXPECT','confirmed '..v..'/compactNormal',Expected(v),
  'confirmed value '..v..' is '..Expected(v),{producer={current=v,known=true}})
end
Add('EXPECT','known1/compactHardcore2 -> Normal',Expected(1),'a compact Hardcore label does not override a confirmed Normal',
 {producer={current=1,known=true},compact='Hardcore 2'})
for _,v in ipairs({
 {'nil',{nilCurrent=true}},{'false',{current=false}},{'string 0',{current='0'}},
 {'string 1',{current='1'}},{'string 6',{current='6'}},{'0',{current=0}},{'7',{current=7}},
 {'-1',{current=-1}},{'1.5',{current=1.5}},{'5.5',{current=5.5}},{'NaN',{current=0/0}},
 {'+infinity',{current=math.huge}},{'-infinity',{current=-math.huge}},{'a table',{current={}}},
}) do
 local o=v[2];o.known=true
 Add('EXPECT','known with getter '..v[1]..'/compactNormal -> unknown',Expected(nil),
  'a getter value outside a finite integer 1..6 is unknown, never coerced',{producer=o})
end
for _,v in ipairs({
 {'false',{known=false}},{'nil',{nilKnown=true}},{'1',{known=1}},{'string true',{known='true'}},{'a table',{known={}}},
}) do
 local o=v[2];o.current=6
 Add('EXPECT','readiness '..v[1]..' with cached 6/compactNormal -> unknown',Expected(nil),
  'readiness that is not exactly true is unknown, whatever the cache holds',{producer=o})
end
Add('EXPECT','getter raises -> unknown',Expected(nil),'a raising getter is unknown',
 {producer={current=6,known=true,getterThrows=true}})
Add('EXPECT','readiness raises -> unknown',Expected(nil),'a raising readiness function is unknown',
 {producer={current=6,known=true,readinessThrows=true}})
Add('EXPECT','missing getter -> unknown',Expected(nil),'a service without its getter is unknown',
 {producer={current=6,known=true,noGetter=true}})
Add('EXPECT','missing readiness -> unknown',Expected(nil),'a service without its readiness function is unknown',
 {producer={current=6,known=true,noReadiness=true}})
Add('EXPECT','missing service -> unknown',Expected(nil),'no hardmode service is unknown, not the compact Normal',{noService=true})
Add('EXPECT','service that is not a table -> unknown',Expected(nil),'an unusable service value is unknown',{serviceValue='loaded'})
Add('EXPECT','confirmed HC1 with a selected HC5 draft -> HC1',Expected(2),'the selected draft is a preview, never the difficulty',
 {producer={current=2,known=true},draft=6})
Add('EXPECT','unknown with a selected HC5 draft -> unknown',Expected(nil),'a selected draft confirms nothing',
 {producer={current=1,known=false},draft=6})
Add('EXPECT','no HUD root with a confirmed service -> HC3',Expected(4),'the service is read without any HUD frame',
 {producer={current=4,known=true},noRoot=true})
Add('GUARD','no HUD root with an unknown service -> unknown',Expected(nil),'nothing is invented without HUD or confirmation',
 {producer={current=1,known=false},noRoot=true})

local function RunCase(c)
 for _,path in ipairs({'cold GetSummary','scanner'}) do
  -- The client's own instance query, present only in the updated-provider
  -- cases that state it (Part 1c); absent everywhere else, as before.
  IsInInstance=c.inInstance~=nil and function() return c.inInstance end or nil
  local p=c.producer and Producer(c.producer) or nil
  local h=Host({producer=p,noService=c.noService,serviceValue=c.serviceValue,noRoot=c.noRoot,compact=c.compact})
  if c.draft then h.ShowDraft(c.draft) end
  if path=='scanner' then h.Tick() end
  local s=h.status.GetSummary()
  local label=c.label..' ['..path..']'
  local got=Difficulty(s)
  print('OBSERVED',label,'difficulty='..got,'readinessCalls='..Text(p and p.knownCalls),
   'getterCalls='..Text(p and p.getterCalls))
  local check=c.kind=='EXPECT' and expect or guard
  check(got==c.want,label..': '..c.claim,got)
  if p and p.api.IsDifficultyKnown and p.api.GetCurrentDifficulty then
   expect(p.knownCalls>=1,label..': the readiness gate is consulted on this read',p.knownCalls)
  end
  if p then guard(p.extraArgs==0,label..': the service functions are called with zero arguments',p.extraArgs) end
  if p and not c.producer.fresh then
   guard(p.instanceCalls==0 and p.api.GetInstanceDifficulty==nil,
    label..': the older provider has no instance reader and none is called',p.instanceCalls)
  end
  if p and c.producer.fresh then
   guard(p.instanceCalls==1,label..': the updated provider\'s instance reader is called once per read',p.instanceCalls)
  end
  Independent(h,s,label,c.noRoot)
  Passive(h,label)
  IsInInstance=nil
 end
end
----------------------------------------------------------------------------
-- Part 1c (versioned: updated provider, 2026-11 capture). The content's tier
-- inside a foreign-tier instance is the instance tier, never the player's own;
-- nil from the instance reader is not proof of the own tier inside an
-- instance (the client's own note: after a /reload there it answers nil until
-- the next map change), so there it is unknown; outside an instance the own
-- confirmed tier applies exactly as before. Every pre-existing case above
-- keeps the older provider and its results.
----------------------------------------------------------------------------
Add('EXPECT','updated: own HC1, instance tier 4 -> HC3',Expected(4),'the foreign instance tier is shown, not the own tier',
 {producer={current=2,known=true,fresh=true,instance=4}})
Add('EXPECT','updated: unknown own tier, instance tier 3 -> HC2',Expected(3),'the instance tier is the content tier even before the own tier is known',
 {producer={current=1,known=false,fresh=true,instance=3}})
for _,v in ipairs({{'7',7},{'0',0},{'1.5',1.5},{'string 4','4'},{'NaN',0/0}}) do
 Add('EXPECT','updated: instance tier '..v[1]..' -> unknown',Expected(nil),'an instance tier outside a finite integer 1..6 is unknown, never the own tier',
  {producer={current=3,known=true,fresh=true,instance=v[2]}})
end
Add('EXPECT','updated: instance reader raises -> unknown',Expected(nil),'a raising instance reader is unknown, never the own tier',
 {producer={current=3,known=true,fresh=true,instanceThrows=true}})
Add('EXPECT','updated: no instance tier inside an instance -> unknown',Expected(nil),'the reload gap inside an instance is unknown, not the own HC2',
 {producer={current=3,known=true,fresh=true,instance=nil},inInstance=1})
Add('EXPECT','updated: no instance tier, instance query missing -> unknown',Expected(nil),'without the client instance query the own tier is not claimed',
 {producer={current=3,known=true,fresh=true,instance=nil}})
Add('EXPECT','updated: no instance tier outside an instance -> HC2',Expected(3),'outside an instance the own confirmed tier applies',
 {producer={current=3,known=true,fresh=true,instance=nil},inInstance=false})
Add('EXPECT','updated: outside an instance, own tier unconfirmed -> unknown',Expected(nil),'outside an instance the readiness gate still applies',
 {producer={current=3,known=false,fresh=true,instance=nil},inInstance=false})
for _,c in ipairs(CASES) do RunCase(c) end

----------------------------------------------------------------------------
-- Part 1b: producer transitions observed by the ordinary scanner.
----------------------------------------------------------------------------
do -- S1 draft, failed Apply, successful acknowledgment
 local p=Producer({current=3,known=true})
 local h=Host({producer=p})
 h.Tick()
 expect(Show(h)=='HC2/HC2','S1: confirmed HC2 is shown on the first ordinary scan',Show(h))
 local refreshes=h.refreshes
 p.SelectDraft(6);h.ShowDraft(6);h.Tick()
 expect(Show(h)=='HC2/HC2','S1: the open Hardcore window selecting HC5 is a preview, not the difficulty',Show(h))
 p.ApplyFailed();h.Tick()
 expect(Show(h)=='HC2/HC2','S1: a failed Apply leaves confirmed HC2',Show(h))
 expect(h.refreshes==refreshes,'S1: the draft and the failed Apply do not refresh the panel',h.refreshes-refreshes)
 HardmodeFrame=nil
 p.ApplySucceeded(5);h.Tick()
 expect(Show(h)=='HC4/HC4','S1: a successful acknowledgment of 5 is HC4 on the next ordinary scan',Show(h))
 expect(h.refreshes==refreshes+1,'S1: that change refreshes the panel once',h.refreshes-refreshes)
 local after=h.refreshes
 h.Tick();h.Tick()
 guard(h.refreshes==after,'S1: unchanged scans refresh nothing',h.refreshes-after)
 Independent(h,h.status.GetSummary(),'S1')
 Passive(h,'S1')
end

do -- S2 world entry keeps the last confirmed state
 local p=Producer({current=4,known=true})
 local h=Host({producer=p})
 h.Tick()
 expect(Show(h)=='HC3/HC3','S2: confirmed HC3 before the zone change',Show(h))
 p.WorldEntry();h.Enter();h.InstallRoot('Normal');h.Tick()
 setup(p.known==true and p.worldRequests==1,'S2: the producer model requested data and kept its known flag')
 expect(Show(h)=='HC3/HC3','S2: world entry and a new HUD root with the literal Normal label keep the last confirmed HC3',Show(h))
 guard(h.root:IsShown()==false,'S2: the new HUD root is discovered and suppressed')
 p.CurrentDataReply('2');h.Tick()
 expect(Show(h)=='HC1/HC1','S2: a later current-data reply of 2 is HC1 on the ordinary scan',Show(h))
 p.CurrentDataReply('not-a-number');h.Tick()
 guard(Show(h)=='Normal/nil','S2 LIMIT: the producer coerces a malformed nonempty reply to 1; the consumer shows that confirmed 1 as Normal and cannot recover the provenance',Show(h))
 p.CurrentDataReply('');h.Tick()
 guard(Show(h)=='Normal/nil','S2: an empty reply changes nothing in the producer model',Show(h))
 guard(p.extraArgs==0,'S2: zero-argument calls throughout',p.extraArgs)
 Passive(h,'S2')
end

do -- S3 late load, replacement and unload
 local h=Host({noService=true})
 h.Tick()
 expect(Show(h)=='nil/nil','S3: before the service loads the difficulty is unknown, not the compact Normal',Show(h))
 local a=Producer({current=3,known=true});h.SetService(a);h.Tick()
 expect(Show(h)=='HC2/HC2','S3: a late-loaded confirmed service is read on the next scan',Show(h))
 local b=Producer({current=5,known=true});h.SetService(b)
 local aCalls=a.knownCalls+a.getterCalls
 h.Tick()
 expect(Show(h)=='HC4/HC4','S3: a replacement service is read from the current global',Show(h))
 guard(a.knownCalls+a.getterCalls==aCalls,'S3: the replaced service is not read again',a.knownCalls+a.getterCalls-aCalls)
 local c=Producer({current=2,known=true});h.ReplaceProjectEbonhold(c);h.Tick()
 expect(Show(h)=='HC1/HC1','S3: a replaced ProjectEbonhold table is read from the current global',Show(h))
 h.SetService(nil);h.Tick()
 expect(Show(h)=='nil/nil','S3: an unloaded service is unknown, not the last HC1',Show(h))
 local d=Producer({current=6,known=false});h.SetService(d);h.Tick()
 expect(Show(h)=='nil/nil','S3: a newly loaded service that is not known yet stays unknown',Show(h))
 d.CurrentDataReply('6');h.Tick()
 expect(Show(h)=='HC5/HC5','S3: its first confirmation is shown on the next scan',Show(h))
 ProjectEbonhold=nil;h.Tick()
 expect(Show(h)=='nil/nil','S3: no ProjectEbonhold at all is unknown',Show(h))
 Passive(h,'S3')
end

do -- S4 the exact published Hardcore control route is preserved
 local p=Producer({current=2,known=true})
 local h=Host({producer=p})
 h.Tick()
 expect(Show(h)=='HC1/HC1','S4: confirmed HC1 before the window opens',Show(h))
 p.SelectDraft(6)
 local opened=h.status.OpenHardcoreMenu()
 guard(opened==true and HardmodeFrame~=nil and HardmodeFrame:IsShown() and h.toggles==1,
  'S4: the Nexus control opens the window through the published Hardcore control, once',h.toggles)
 h.Tick()
 expect(Show(h)=='HC1/HC1','S4: the open window selecting HC5 does not replace confirmed HC1',Show(h))
 for _=1,5 do h.Tick() end
 guard(h.toggles==1,'S4: scans never run the Hardcore control',h.toggles)
 local closed=h.status.OpenHardcoreMenu()
 guard(closed==true and not HardmodeFrame:IsShown() and h.toggles==2,'S4: the same control closes it',h.toggles)
 Passive(h,'S4')
end

----------------------------------------------------------------------------
-- Part 2: the real TOC boot, Main, MainViewModel and Panel caption.
----------------------------------------------------------------------------
Nexus=nil;NexusDB=nil;ProjectEbonhold=nil;ProjectEbonholdPlayerRunFrame=nil
HardmodeFrame=nil;EbonholdIntensityData=nil;hooksecurefunc=nil
local consumerReads={}
local function InstallHud(H,compact,producer)
 HardmodeFrame=nil;EbonholdIntensityData=nil
 local root=CreateFrame('Frame','ProjectEbonholdPlayerRunFrame',UIParent)
 local header=CreateFrame('Frame',nil,root)
 local button=CreateFrame('Button',nil,header)
 local tier=button:CreateFontString(nil);tier:SetText(compact)
 local ash=header:CreateFontString(nil);ash:SetText('76,054')
 local gain=header:CreateFontString(nil);gain:SetText('+188%')
 root.hardmodeTierText=tier;root.soulPointsText=ash;root.multiplierText=gain
 ProjectEbonhold.PlayerRunUI={GetUIElements=function() return {soulPointsText=ash} end}
 ProjectEbonhold.HardmodeService=producer and Watched(producer.api,'HardmodeService',consumerReads) or nil
 H.hud={root=root,tier=tier,producer=producer}
end
local function Install(compact,o)
 return function(H) InstallHud(H,compact,o and Producer(o) or nil) end
end
local function Settle(H) H.Advance(2.5,.05) end
local function Rendered(H,label,kind,mode,tier)
 local check=kind=='EXPECT' and expect or guard
 local want=tostring(mode)..'/'..tostring(tier)
 local summary=Nexus.ServerStatus.GetSummary()
 check(Difficulty(summary)==want,label..': ServerStatus summary',Difficulty(summary))
 guard(summary.ash=='76,054' and summary.gain=='+188%',label..': Soul Ash and gain are unchanged by the difficulty source',
  Text(summary.ash)..'/'..Text(summary.gain))
 local model=Nexus.Panel._lastModel
 local shown=model and type(model.serverStatus)=='table' and Difficulty(model.serverStatus) or 'none'
 check(shown==want,label..': Main and MainViewModel carry the same difficulty to the Panel',shown)
 local boxes={}
 for _,frame in ipairs(H.frames) do
  if rawget(frame,'_summary') and frame:GetParent()==NexusPanel then boxes[#boxes+1]=frame end
 end
 setup(#boxes==1 and boxes[1]:IsShown(),label..': one rendered difficulty card is shown',#boxes)
 local caption=boxes[1] and boxes[1].regions[1]:GetText() or 'none'
 -- The Panel's current caption contract: a Hardcore tier and an unknown mode
 -- keep the red caption; a known Normal (no tier) is neutral.
 local colour=(tier==nil and mode=='Normal') and '|cffd9d9d9' or '|cffff6b5f'
 local expected=colour..(tier or mode or 'Difficulty')..'|r'
 check(caption==expected,label..': the rendered Panel caption',caption)
 guard(Nexus.Panel.VisibilityFacts().committed==true,label..': the panel render committed')
 guard(HardmodeFrame==nil,label..': no Hardcore window was opened')
 guard(#H.actions==0,label..': no game action',#H.actions)
 print('CONSUMER',label,'caption='..caption)
end

local db=F.Database({});db.soulAshHudMode='nexus'
local H=F.Boot(db,Install('Normal',{current=6,known=true}));Settle(H)
setup(Nexus.StartupStatus().coreReady==true,'C: start-up completed')
Rendered(H,'C1 cold boot known6/compactNormal -> HC5','EXPECT','HC5','HC5')
setup(H.hud.tier:GetText()=='Normal','C1: the compact label still reads its literal Normal')
local P=H.hud.producer
P.SelectDraft(2);P.ApplyFailed();Settle(H)
Rendered(H,'C2 failed Apply keeps confirmed HC5','EXPECT','HC5','HC5')
P.ApplySucceeded(3);Settle(H)
Rendered(H,'C3 successful acknowledgment on the ordinary scan','EXPECT','HC2','HC2')
P.WorldEntry();H.Fire('PLAYER_ENTERING_WORLD');Settle(H)
setup(P.known==true and P.worldRequests==1,'C4: the producer model kept its known flag across world entry')
Rendered(H,'C4 world entry keeps the last confirmed HC2','EXPECT','HC2','HC2')
ProjectEbonhold.HardmodeService=nil;Settle(H)
Rendered(H,'C5 unloaded service is the generic Difficulty caption','EXPECT',nil,nil)
local Q=Producer({current=2,known=true})
ProjectEbonhold.HardmodeService=Watched(Q.api,'HardmodeService',consumerReads);Settle(H)
Rendered(H,'C6 late-loaded confirmed service','EXPECT','HC1','HC1')
H=F.Reload(Install('Normal',{}));Settle(H)
Rendered(H,'C7 reload unknown placeholder1/compactNormal -> unknown','EXPECT',nil,nil)
H.hud.producer.CurrentDataReply('4');Settle(H)
Rendered(H,'C8 first current-data reply after reload','EXPECT','HC3','HC3')
H=F.Reload(Install('Normal',{current=1,known=true}));Settle(H)
Rendered(H,'C9 reload explicit known1 Normal','GUARD','Normal',nil)
local bad={}
for _,entry in ipairs(consumerReads) do
 -- Versioned (see ALLOWED): the instance reader's field is read to learn
 -- whether the provider has it; the older provider here has none, so only the
 -- two passive service functions are ever called.
 if entry~='HardmodeService.IsDifficultyKnown' and entry~='HardmodeService.GetCurrentDifficulty'
  and entry~='HardmodeService.GetInstanceDifficulty' then bad[#bad+1]=entry end
end
expect(#consumerReads>0,'C: the real boot consults the hardmode service',#consumerReads)
guard(#bad==0,'C: only the two passive service functions are read through the real boot',table.concat(bad,','))

print('SUMMARY server_status_difficulty_authority setup='..counts.setup..' expect='..counts.expect
 ..' guard='..counts.guard..' failed='..#failures)
if #failures>0 then
 error(#failures..' difficulty authority check(s) failed: '..table.concat(failures,' || '),0)
end
print('PASS server_status_difficulty_authority: synthetic producer model only; native client and server behaviour NOT_RUN')
