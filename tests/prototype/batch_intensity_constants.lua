-- Group 4 (S5-C3, S6-C1): passive Intensity levels and bar cap from the
-- supported constants. Native (static data, never executed): constants.lua
-- 15 and 52-56 give MAX_INTENSITY 475 and INTENSITY_LEVEL_1..5 = 75, 200,
-- 275, 400, 475; player_run_ui.lua 2001-2013 shows the level as the highest
-- threshold reached (intensity >= INTENSITY_LEVEL_n) and 1958-1960 / 1978-1980
-- scale the bar by MAX_INTENSITY. ui/ServerStatus.lua reports floor(v/100)
-- (75 -> 0, 275 -> 2, 475 -> 4) and ui/Panel.lua draws a 0..500 bar, ticks at
-- fifths and "Intensity: N / 500".
-- EXPECT (fails at 8c):
--   ServerStatus levels follow the validated dynamic constants: native set
--   75 -> 1, 275 -> 3, 475 -> 5; an alternative valid set (50/150/250/350/450,
--   max 450) gives 50 -> 1, 150 -> 2, 450 -> 5;
--   malformed constants (non-monotonic, NaN, missing, max below level 5, text,
--   infinite, negative) and unavailable constants give an unknown level (nil)
--   instead of a fabricated one;
--   the Panel bar is capped at 475 (a value above is clamped), its ticks sit
--   at the 75/200/275/400 boundaries of 475, the tooltip says "/ 475" with
--   levels 1/3/5 at 75/275/475; with unavailable constants the tooltip claims
--   neither "/ 500" nor a numeric level.
-- GUARD (holds at 8c): values whose level is the same either way (0, 74, 199,
-- 200, 274, 399, 400, 474; 149 and 449 in the alternative set) and the raw
-- intensity value are reported unchanged; no game or network action.
-- SETUP: part 1 loads the real ServerStatus alone with synthetic globals (as
-- server_hud_handoff.lua); part 2 is a real TOC boot rendering the real Panel.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_intensity_constants')
local printable=B.printable
local NATIVE={MAX_INTENSITY=475,INTENSITY_LEVEL_1=75,INTENSITY_LEVEL_2=200,INTENSITY_LEVEL_3=275,
 INTENSITY_LEVEL_4=400,INTENSITY_LEVEL_5=475,ENABLE_BANISH_SYSTEM=true}
local function With(over)
 local t={}
 for k,v in pairs(NATIVE) do t[k]=v end
 for k,v in pairs(over or {}) do if v=='<nil>' then t[k]=nil else t[k]=v end end
 return t
end

----------------------------------------------------------------------------
-- Part 1: the real ServerStatus module alone.
----------------------------------------------------------------------------
local function Summary(project,value)
 NexusDB={soulAshHudMode='nexus'};Nexus={};UIParent={}
 HardmodeFrame=nil;ProjectEbonholdPlayerRunFrame=nil
 ProjectEbonhold=project
 EbonholdIntensityData={intensity=value,areaNameReaper='Synthetic area',onCooldown=false}
 CreateFrame=function()
  local f={scripts={}}
  function f:RegisterEvent() end
  function f:SetScript(event,fn) self.scripts[event]=fn end
  return f
 end
 dofile('ui/ServerStatus.lua')
 Nexus.ServerStatus.Init()
 local s=Nexus.ServerStatus.GetSummary()
 return s.intensityLevel,s.intensity
end
local function Level(constants,value) return Summary({Constants=constants},value) end

C.scenario('N native constants',function()
 for _,c in ipairs({{75,1},{275,3},{475,5}}) do
  local level,raw=Level(NATIVE,c[1])
  print('OBSERVED','N value='..c[1],'level='..printable(level))
  C.expect(level==c[2],'N: '..c[1]..' is Intensity level '..c[2]..' under the supported constants',level)
  C.guard(raw==c[1],'N: the raw value '..c[1]..' is reported unchanged',raw)
 end
 for _,c in ipairs({{0,0},{74,0},{199,1},{200,2},{274,2},{399,3},{400,4},{474,4}}) do
  local level=Level(NATIVE,c[1])
  C.guard((level or 0)==c[2],'N: '..c[1]..' stays level '..c[2],level)
 end
end)

C.scenario('V an alternative valid constant set is read dynamically',function()
 local alt={MAX_INTENSITY=450,INTENSITY_LEVEL_1=50,INTENSITY_LEVEL_2=150,INTENSITY_LEVEL_3=250,
  INTENSITY_LEVEL_4=350,INTENSITY_LEVEL_5=450}
 for _,c in ipairs({{50,1},{150,2},{450,5}}) do
  local level=Level(alt,c[1])
  C.expect(level==c[2],'V: '..c[1]..' is level '..c[2]..' under the supplied valid constants',level)
 end
 for _,c in ipairs({{149,1},{449,4}}) do
  local level=Level(alt,c[1])
  C.guard(level==c[2],'V: '..c[1]..' stays level '..c[2],level)
 end
end)

C.scenario('X malformed and unavailable constants',function()
 local cases={
  {'non-monotonic',With({INTENSITY_LEVEL_3=150})},
  {'NaN',With({INTENSITY_LEVEL_4=0/0})},
  {'missing level 5',With({INTENSITY_LEVEL_5='<nil>'})},
  {'maximum below level 5',With({MAX_INTENSITY=400})},
  {'text',With({MAX_INTENSITY='lots'})},
  {'infinite',With({INTENSITY_LEVEL_5=math.huge,MAX_INTENSITY=math.huge})},
  {'negative',With({INTENSITY_LEVEL_1=-5})},
 }
 for _,case in ipairs(cases) do
  local level,raw=Level(case[2],275)
  print('OBSERVED','X',case[1],'level='..printable(level))
  C.expect(level==nil,'X: '..case[1]..' constants give an unknown level, not a fabricated one',level)
  C.guard(raw==275,'X: '..case[1]..': the raw value is still reported',raw)
 end
 for _,case in ipairs({{'no Constants table',{}},{'no ProjectEbonhold',nil},
  {'Constants without Intensity keys',{Constants={ENABLE_BANISH_SYSTEM=true}}}}) do
  local level,raw=Summary(case[2],275)
  C.expect(level==nil,'X: '..case[1]..' gives an unknown level',level)
  C.guard(raw==275,'X: '..case[1]..': the raw value is still reported',raw)
 end
end)

----------------------------------------------------------------------------
-- Part 2: the real Panel in a real TOC boot.
----------------------------------------------------------------------------
local F=dofile('tests/prototype/format5_support.lua')
local H=F.Boot(F.Database(),function()
 for k,v in pairs(NATIVE) do ProjectEbonhold.Constants[k]=v end
end)
C.setup(Nexus.StartupStatus().coreReady==true,'P: start-up reached core-ready')
local function StatusBox()
 local panel=_G.NexusPanel
 for _,f in ipairs(panel and panel.children or {}) do if f.intensityBar then return f end end
end
local function Hit(box)
 for _,f in ipairs(box and box.children or {}) do
  if f.kind=='Button' and f.scripts.OnEnter then return f end
 end
end
local lastRendered
local function Render(value)
 EbonholdIntensityData={intensity=value,areaNameReaper='Synthetic area',onCooldown=false}
 -- Wait for the render of this value (raw or capped), not a fixed delay.
 B.Until(H,function()
  local box=StatusBox()
  local shown=box and box._summary and box._summary.intensity
  return shown~=nil and shown~=lastRendered
 end,200)
 local current=StatusBox()
 lastRendered=current and current._summary and current._summary.intensity
 H.Advance(.4,.05)
 local box=StatusBox()
 local hit=Hit(box)
 local lines=hit and B.V.TooltipLines(function() hit.scripts.OnEnter(hit) end) or {}
 local _,max=0,nil
 if box then _,max=box.intensityBar:GetMinMaxValues() end
 return box,lines,max,box and box.intensityBar:GetValue()
end
local function Line(lines,prefix)
 for _,line in ipairs(lines) do local plain=B.Plain(line);if plain:find(prefix,1,true) then return plain end end
end

C.scenario('P native constants on the real Panel',function()
 local box,lines,max,value=Render(475)
 C.setup(box~=nil and box.intensityBar:IsShown(),'P: the real Panel shows the Intensity bar')
 print('OBSERVED','P 475 max='..printable(max),'value='..printable(value),'tooltip='..table.concat(lines,' | '))
 C.expect(max==475,'P: the bar is capped at MAX_INTENSITY 475',max)
 local intensity=Line(lines,'Intensity:') or ''
 C.expect(intensity:find('/ 475',1,true)~=nil and intensity:find('500',1,true)==nil,
  'P: the tooltip states the 475 maximum, not 500',intensity)
 C.expect(Line(lines,'Intensity Level:')=='Intensity Level: 5','P: 475 is shown as level 5',Line(lines,'Intensity Level:'))
 local ticks={}
 for _,tick in ipairs(box and box.intensityTicks or {}) do
  local p=tick.points and tick.points[1]
  local x=p and tonumber(p[4])
  if x then ticks[#ticks+1]=x end
 end
 local width=tonumber(box and box.intensityBar:GetWidth()) or 0
 local want={}
 for i,v in ipairs({75,200,275,400}) do want[i]=width*v/475 end
 local function near(x,list) for _,w in ipairs(list) do if math.abs(x-w)<=1 then return true end end return false end
 local allAtBoundaries,allBoundaries=#ticks>0,true
 for _,x in ipairs(ticks) do if not (near(x,want) or math.abs(x-width)<=1) then allAtBoundaries=false end end
 for _,w in ipairs(want) do if not near(w,ticks) then allBoundaries=false end end
 print('OBSERVED','P ticks width='..width,'x='..table.concat(ticks,','))
 C.expect(allAtBoundaries and allBoundaries,'P: the ticks mark the 75/200/275/400 boundaries of 475',table.concat(ticks,','))
 for _,c in ipairs({{275,3},{75,1}}) do
  local _,l=Render(c[1])
  C.expect(Line(l,'Intensity Level:')=='Intensity Level: '..c[2],'P: '..c[1]..' is shown as level '..c[2],Line(l,'Intensity Level:'))
  C.guard((Line(l,'Intensity:') or ''):find('Intensity: '..c[1],1,true)~=nil,'P: the raw value '..c[1]..' is shown',Line(l,'Intensity:'))
 end
 local _,_,_,clamped=Render(500)
 C.expect(clamped~=nil and clamped<=475,'P: a value above the maximum is drawn at the 475 cap',clamped)
end)

C.scenario('Q unavailable constants on the real Panel',function()
 for k in pairs(NATIVE) do if k~='ENABLE_BANISH_SYSTEM' then ProjectEbonhold.Constants[k]=nil end end
 local box,lines=Render(276)
 C.setup(box~=nil,'Q: the real Panel still renders the status box')
 print('OBSERVED','Q tooltip='..table.concat(lines,' | '))
 local intensity=Line(lines,'Intensity:') or ''
 C.expect(intensity:find('500',1,true)==nil,'Q: the tooltip does not claim a 500 maximum',intensity)
 local level=Line(lines,'Intensity Level:') or ''
 C.expect(level:match('Intensity Level: %d')==nil,'Q: no numeric level is claimed without valid constants',level)
 C.guard(intensity:find('276',1,true)~=nil,'Q: the raw value is still shown',intensity)
end)

C.guard(#H.actions==0 and #H.sent==0,'no game or network action',#H.actions..'/'..#H.sent)
C.finish('(levels and cap follow validated constants; unknown constants are not fabricated)')
