-- Every annotation word that EchoWeaver gives a board card is shown to the
-- player as a label, not as the raw word; "guaranteed" is stated by the
-- card's "[Guaranteed offer]" prefix (BN-FULL-REVIEW-PRIVATE-BUILD-003).
-- be19854 showed "target satisfied" and "frozen" raw because UserText mapped
-- only the older word "target met". Real EchoWeaver decision, real Readout.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local T,R=Nexus.UserText,Nexus.Readout
local expected={["target satisfied"]="Target already met",frozen="Frozen offer",wanted="Needed",
 filler="Not on Wishlist",["wrong quality"]="Different quality from target"}
for word,label in pairs(expected) do
 check(T.Annotation(word)==label,'"'..word..'" -> '..label..': '..tostring(T.Annotation(word)))
end
-- The words EchoWeaver can emit (logic/EchoWeaver.lua annotations).
local src=assert(io.open('logic/EchoWeaver.lua','rb')):read('*a')
local emitted={}
local block=assert(src:match('annotations%[i%]=(.-)deltas%[i%]'),'fixture: annotation assignment found')
for word in block:gmatch('"([%a ]+)"') do emitted[word]=true end
for _,word in ipairs({'frozen','guaranteed','wanted','target satisfied','wrong quality','filler'}) do
 check(emitted[word],'fixture: EchoWeaver emits "'..word..'"')
end
for word in pairs(emitted) do
 if word~='guaranteed' and expected[word] then
  local line=R.CardLine({spellId=1,name='Echo',quality=2},word)
  check(line:find(expected[word],1,true) and not line:find(word,1,true),'card line shows the label, not "'..word..'": '..line)
 end
end
-- Guaranteed cards keep their existing prefix.
check(R.CardLine({spellId=1,name='Echo',quality=2,isGuaranteed=true},'wanted'):find('[Guaranteed offer]',1,true),'guaranteed prefix kept')
do
 local line=R.CardLine({spellId=1,name='Echo',quality=2,isGuaranteed=true},'guaranteed')
 check(line:find('[Guaranteed offer]',1,true) and not line:find('guaranteed',1,true),'a guaranteed card does not repeat the raw word: '..line)
end
print('PASS panel annotation labels; '..checks..' checks')
