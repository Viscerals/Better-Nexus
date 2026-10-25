-- Portable desired-behavior regression: actual production adapter/runtime/Journal.
-- Offline synthetic host only; no native trigger/cause is claimed.
local F=dofile(os.getenv('NEXUS_PAUSE_REPRO_SUPPORT') or 'tests/prototype/tome_pause_visibility_support.lua')
local checks,failed=0,{}
local function expect(v,m)checks=checks+1;if not v then failed[#failed+1]=m;print('MISS '..m)end end
local function same(a,b)return F.Same(a,b)end
local function vector(W)return F.Vector(W)end
local cases={
 {name='clear'},
 {name='hidden_bind',popup=true,hidden=true},
 {name='visible_bind',popup=true,hold=true},
 {name='bind_without_visibility_api',popup=true,hold=true,noVisibility=true},
 {name='hidden_after_visible_bind',popup=true,hold=true,hideAfter=true},
 -- Bag occupancy alone must not pause: only a visible bind confirmation does.
 {name='carried_item',bag=true,hold=false},
 {name='unrelated_popup',popup=true,unrelated=true},
 {name='auto_off',auto=false},
 {name='permission_off',permission=false},
 {name='level_two',level=2},
}
for _,route in ipairs({'first','loadout'})do
 for _,case in ipairs(cases)do
  local prefix=route..'/'..case.name
  local W=F.Boot('known',case.permission~=false,case.auto~=false,route)
  local H,A,O=W.H,W.A,W.O
  if case.level then H.playerLevel=case.level;H.Fire('PLAYER_LEVEL_UP',case.level);H.Notify()end
  local present=case.bag==true
  GetContainerNumSlots=function(bag)return bag==0 and 1 or 0 end
  GetContainerItemLink=function(bag,slot)
   if present and bag==0 and slot==1 then return '|cff0070dd|Hitem:990001:0:0:0|h[Tome of Echoes]|h|r' end
  end
  GetItemInfo=function()return 'Tome of Echoes' end
  local parent=CreateFrame('Frame',nil,UIParent)
  local popup=CreateFrame('Frame','StaticPopup1',parent)
  popup.which=case.unrelated and 'DELETE_ITEM' or 'LOOT_BIND'
  popup.text=popup:CreateFontString()
  popup.text:SetText(case.unrelated and 'Do you want to destroy this item?' or 'Using this item will bind it to you')
  if case.popup then popup:Show()else popup:Hide()end
  if case.hidden then parent:Hide()end
  if case.noVisibility then
   -- Legacy-shaped host frame boundary: no IsVisible member. The real harness
   -- popup remains for frame updates; only the stock-popup pool view lacks it.
   StaticPopup1={which=popup.which,text=popup.text,IsShown=function()return popup:IsShown()end}
   expect(StaticPopup1.IsVisible==nil,prefix..' missing visibility API fixture')
  end
  local paused=A.TomeMutationPaused()
  expect(paused==(case.hold==true),prefix..' initial pause follows visible active transaction policy')
  if case.hidden then expect(popup:IsShown()==true and popup:IsVisible()==false,prefix..' hidden-parent control is shown but not visible')end
  local start=H.now
  local guarded=case.auto==false or case.permission==false or case.level==2
  print(string.format('CASE %s shown=%s visible=%s pause=%s',prefix,tostring(popup:IsShown()),tostring(popup:IsVisible()),tostring(paused)))
  for step,key in ipairs({'A','B','A'})do
   F.Pick(W,key);H.Advance(12,.05)
   local facts=F.Facts(W)
   local want=key=='A' and {false,true} or {true,false}
   expect(facts.assignment.sequence==step,prefix..' real picker association '..step)
   expect(facts.assignment.kind==(route=='first' and 'first' or 'loadout'),prefix..' destination '..step)
   if case.hold or guarded then
    expect(#O.calls==0 and facts.attempts==0 and facts.accepted==0,prefix..' no toggle while guarded '..step)
    expect(same(vector(W),{false,false}),prefix..' raw mirror unchanged while guarded '..step)
    if case.hold then
     expect(facts.arm.assignmentSequence==step and facts.arm.gate=='pause' and facts.arm.visited==63 and facts.arm.passed==31,prefix..' normal evaluation retained pause shape '..step)
    end
   else
    expect(facts.arm.assignmentSequence==step,prefix..' normal evaluation follows latest association '..step)
    expect(facts.arm.gate=='eligible',prefix..' open safety gates '..step)
    expect(same(vector(W),want),prefix..' desired mirror after '..key..' '..step)
   end
   print(string.format('TRACE %s step=%d key=%s elapsed=%.3f gate=%s masks=%s/%s seq=%s/%s attempts=%d accepted=%d raw=%s,%s',prefix,step,key,H.now-start,tostring(facts.arm.gate),tostring(facts.arm.visited),tostring(facts.arm.passed),tostring(facts.assignment.sequence),tostring(facts.arm.assignmentSequence),facts.attempts,facts.accepted,tostring(vector(W)[1]),tostring(vector(W)[2])))
  end
  if case.hold then
   H.Advance(25,.05)
   expect(#O.calls==0 and A.TomeMutationPaused()==true,prefix..' persistent trigger renews hold beyond first 20s')
   local removedAt=H.now;present=false
   if case.hideAfter then
    parent:Hide()
    expect(popup:IsShown()==true and popup:IsVisible()==false,prefix..' positive popup now ancestor-hidden only')
   else popup:Hide()end
   H.Advance(19,.05)
   expect(A.TomeMutationPaused()==true and #O.calls==0,prefix..' genuine disappearance retains 20s settling safety')
   H.Advance(9,.05)
   expect(A.TomeMutationPaused()==false,prefix..' hold expires without positive detector')
   expect(same(vector(W),{false,true}) and #O.calls==1,prefix..' final A reconciles after settling expiry')
   print(string.format('RECOVERY %s removed=%.3f final=%.3f calls=%d raw=%s,%s',prefix,removedAt,H.now,#O.calls,tostring(vector(W)[1]),tostring(vector(W)[2])))
  end
  local writes=0
  for _,act in ipairs(H.actions)do if act[1]=='upload' or act[1]=='save' or act[1]=='activate' then writes=writes+1 end end
  expect(writes==0,prefix..' no upload/save/activate action')
  expect(O.boots==1,prefix..' one world; no reset/reload')
 end
end
print(string.format('SUMMARY checks=%d failures=%d native=NOT_RUN nativeTrigger=NOT_ESTABLISHED',checks,#failed))
assert(#failed==0,table.concat(failed,'\n'))
print('PASS hidden-popup pause visibility and genuine holds across real sequential selectors')
