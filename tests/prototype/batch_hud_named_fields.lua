-- Group 8 (S6-C2, S6-H1): passive Soul Ash from the named native HUD fields,
-- and exact-widget ownership of a hook-only hide.
-- Native (static data, never executed): player_run_ui.lua creates the root
-- ProjectEbonholdPlayerRunFrame with named fields soulPointsText (350-353),
-- multiplierText (355-362) and hardmodeTierText (292-297), updates them at
-- 1916-1951 ("%s" FormatThousands, "+%.0f%%", "Hardcore N"/"Normal"), and
-- PlayerRunUI.GetUIElements exposes soulPointsText (2183-2201).
-- ui/ServerStatus.lua concatenates every text in traversal order and takes
-- the first unlabelled number of three or more digits, so "42" then "+150%"
-- reads Soul Ash 150; and its OnShow hook hides a widget without recording
-- that it did, so that hide is never given back when the replacement fails.
-- EXPECT (fails at 8c): with the named fields (and provider) Soul Ash is 42 in
-- either traversal order; a named field holding "+150%" and a frame with no
-- named field and only "+150%" give an unknown ash (nil), never 150; a legacy
-- frame "42","+150%" never reports 150; a widget hidden only by the hook is
-- given back exactly once when the replacement becomes unavailable.
-- GUARD (holds at 8c): gain "+150%" and tier HC2 unchanged; a comma balance
-- "1,234" and an explicit "Soul Ash: 42" label still parse; "Normal" mode
-- unchanged; the normal scanner hide is given back once; a merely
-- foreign-hidden widget is never forced on; a hook hide that failed is never
-- given back; a widget the player hides after a give-back is not re-shown;
-- the OnShow hook is installed once. Scraped text stays non-authoritative.
-- SETUP: the real ServerStatus module alone with synthetic frames and panel
-- facts, as section6_status_parser_and_hook / server_hud_handoff.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_hud_named_fields')
local printable=B.printable

local function FS(text)
 local r={text=text}
 function r:GetText() return self.text end
 function r:SetText(t) self.text=t end
 return r
end
local function Plain(regions,children)
 local f={}
 function f:GetRegions() return unpack(regions or {}) end
 function f:GetChildren() return unpack(children or {}) end
 return f
end
-- o.header/o.button: region lists; o.named: root fields; o.provider: the
-- GetUIElements answer; o.shown: initial visibility (default shown).
local function Host(o)
 o=o or {}
 NexusDB={soulAshHudMode='nexus'};Nexus={};UIParent={}
 EbonholdIntensityData=nil;HardmodeFrame=nil
 local facts={ready=true,committed=true}
 Nexus.Panel={VisibilityFacts=function() return facts end}
 local root={shown=o.shown~=false,showCalls=0,hideCalls=0,hooks={},installs=0}
 function root:IsShown() return self.shown end
 function root:Hide() self.shown=false;self.hideCalls=self.hideCalls+1 end
 function root:Show()
  self.shown=true;self.showCalls=self.showCalls+1
  if self.hooks.OnShow then self.hooks.OnShow(self) end
 end
 function root:HookScript(event,fn)
  self.installs=self.installs+1
  local prior=self.hooks[event]
  self.hooks[event]=function(...) if prior then prior(...) end;return fn(...) end
 end
 local button=Plain(o.button)
 local header=Plain(o.header,{button})
 function root:GetRegions() return unpack(o.rootRegions or {}) end
 function root:GetChildren() return header end
 for k,v in pairs(o.named or {}) do root[k]=v end
 ProjectEbonhold=o.provider and {PlayerRunUI={GetUIElements=function() return o.provider end}} or nil
 ProjectEbonholdPlayerRunFrame=root
 local scanner
 CreateFrame=function()
  scanner={scripts={}}
  function scanner:RegisterEvent() end
  function scanner:SetScript(event,fn) self.scripts[event]=fn end
  return scanner
 end
 dofile('ui/ServerStatus.lua')
 local status=Nexus.ServerStatus;status.Init()
 return root,status,function() scanner.scripts.OnUpdate(scanner,1) end,
  function() facts={ready=false,committed=false} end
end
-- A native-shaped HUD: header regions in the given order, the tier text in
-- the Hardcore button, the named root fields and the GetUIElements provider.
local function Native(soulText,order)
 local soul,mult=FS(soulText),FS('|cff00ff00+150%|r')
 local catchup,tier=FS(''),FS('|cffFF4444Hardcore 2|r')
 local header=order=='multiplier-first' and {mult,soul,catchup} or {soul,mult,catchup}
 return {header=header,button={tier},
  named={soulPointsText=soul,multiplierText=mult,hardmodeTierText=tier},
  provider={soulPointsText=soul}}
end
local function Parse(label,o)
 local _,status=Host(o)
 local s=status.GetSummary()
 print('OBSERVED',label,'ash='..printable(s.ash),'gain='..printable(s.gain),'tier='..printable(s.tier),'mode='..printable(s.mode))
 return s
end

C.scenario('N named native fields',function()
 local s=Parse('N1',Native('|cffffffff42|r'))
 C.expect(s.ash=='42','N1: Soul Ash is the named soulPointsText value 42, not the percentage',s.ash)
 C.guard(s.gain=='+150%' and s.tier=='HC2','N1: gain and tier unchanged',printable(s.gain)..'/'..printable(s.tier))
 s=Parse('N2',Native('|cffffffff42|r','multiplier-first'))
 C.expect(s.ash=='42','N2: the named value does not depend on traversal order',s.ash)
 s=Parse('N3',Native('|cffffffff1,234|r'))
 C.guard(s.ash=='1,234','N3: a comma balance still parses',s.ash)
end)

C.scenario('R refusal controls',function()
 local s=Parse('R1',Native('|cff00ff00+150%|r'))
 C.expect(s.ash==nil,'R1: a named field that is not a plain balance gives an unknown ash, not 150',s.ash)
 s=Parse('R2',{header={FS('|cff00ff00+150%|r')},button={FS('|cffFF4444Hardcore 2|r')}})
 C.expect(s.ash==nil,'R2: with no named field and only a percentage, ash is unknown, not 150',s.ash)
 s=Parse('R3',{header={FS('42'),FS('+150%')},button={FS('Hardcore 2')}})
 C.expect(s.ash~='150','R3: a legacy frame never reports the percentage as the Soul Ash balance',s.ash)
 s=Parse('R4',{header={FS('Soul Ash: 42'),FS('+150%')},button={FS('Hardcore 2')}})
 C.guard(s.ash=='42','R4: an explicit Soul Ash label still parses',s.ash)
 s=Parse('R5',{header={FS('|cffffffff1,234|r')},button={FS('|cffAAAAAANormal|r')}})
 C.guard(s.mode=='Normal' and s.tier==nil,'R5: the Normal mode is unchanged',printable(s.mode))
end)

C.scenario('H1 hook-only hide is given back once',function()
 local root,status,tick,gone=Host({shown=false})
 tick()
 C.setup(root.shown==false and root.showCalls==0,'H1: the initially hidden widget is neither claimed nor forced')
 root:Show()
 C.setup(root.shown==false and root.showCalls==1,'H1: the actual hook hides an external Show while the replacement displays')
 gone();tick();tick()
 print('OBSERVED','H1 shown='..printable(root.shown),'showCalls='..root.showCalls)
 C.expect(root.shown==true and root.showCalls==2,'H1: the hook-hidden widget is given back exactly once',root.showCalls)
 C.setup(status.VisibilityFacts().replacing==false,'H1: the replacement is really unavailable')
 local calls=root.showCalls
 root:Hide();tick();tick()
 C.guard(root.shown==false and root.showCalls==calls,'H1: a widget the player hides afterwards is not re-shown',root.showCalls)
end)

C.scenario('H2 controls',function()
 local root,_,tick,gone=Host({shown=true})
 for _=1,6 do tick() end
 C.setup(root.shown==false,'H2: the normal scanner hides the shown widget')
 gone();tick();tick()
 C.guard(root.shown==true and root.showCalls==1,'H2: the normal hide is given back exactly once',root.showCalls)
 C.guard(root.installs==1,'H2: the OnShow hook is installed once',root.installs)
 root,_,tick,gone=Host({shown=false})
 tick();gone();tick();tick()
 C.guard(root.shown==false and root.showCalls==0,'H3: a merely foreign-hidden widget is never forced on',root.showCalls)
 root,_,tick,gone=Host({shown=false})
 tick()
 local hide=root.Hide
 root.Hide=function() error('this widget refuses to hide') end
 local ok=pcall(root.Show,root)
 root.Hide=hide
 C.setup(root.shown==true and root.showCalls==1,'H4: the hook could not hide the widget',printable(ok))
 gone();tick();tick()
 C.guard(root.showCalls==1,'H4: a hook hide that never happened is never given back',root.showCalls)
end)

C.finish('(named HUD fields preferred; percentages never ash; hook hide owned exactly)')
