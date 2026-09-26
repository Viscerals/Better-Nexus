-- Quick Start layout fit. The harness has no font renderer, so text fit is a
-- model: word-wrapped visible characters at a per-character width and a line
-- height, checked against the real anchors and sizes of the real window.
--   default      the 10 px small font (0.55 em, 12 px lines), as in the Auto label model
--   conservative a 16 px replacement font wider and taller than the ElvUI font
--                measured natively for 20dabcd (6.27 px per character, 16.1 px
--                lines; the body was cut after 4 lines): 7.0 px and 17 px
-- Native pixel fit is NOT established here; the native run checks it.
local H=dofile('tests/prototype/harness.lua')
local T=dofile('tests/prototype/startup_support.lua');T.Load()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

local BODY="Already have a Saved Build? Assign the Wishlist you want it to follow. "..
 "|cffffd100With Auto ON, Nexus may replace the active Saved Build with a better finished run. "..
 "Keep Auto OFF to leave that slot unchanged.|r\n"..
 "Starting fresh? Import a Wishlist code or copy a Community build into an editable draft."
local HINT="Reopen Help any time with /nexus help. Automation and Orb spending require separate explicit controls."
local SUBTITLE="Plan your Echoes, then choose what to automate."
local BUTTONS={'Set up current build','Import / Create Wishlist','Browse Community builds',
 'Open Leaderboard','Help / Getting Started','Orbs / Lost Memories','Later'}
local MODELS={{name='default',char=5.5,line=12},{name='conservative',char=7.0,line=17}}

Nexus.QuickStart.Show()
local qs=assert(NexusQuickStart,'Quick Start window exists')
local W,Ht=qs:GetWidth(),qs:GetHeight()
local texts,buttons={},{}
for _,c in ipairs(qs.children)do
 if c.kind=='FontString' then texts[c:GetText()]=c end
 if c.kind=='Button' then buttons[c:GetText()]=c end
end
local body,hint,subtitle=texts[BODY],texts[HINT],texts[SUBTITLE]
-- #89 wording is unchanged: exact body, hint and subtitle text.
check(body and body==qs.body,'Quick Start body text is exactly the #89 text')
check(hint,'Quick Start hint text unchanged')
check(subtitle,'Quick Start subtitle text unchanged')
local count=0;for _ in pairs(buttons)do count=count+1 end
check(count==#BUTTONS,'Quick Start keeps its seven buttons')
for _,label in ipairs(BUTTONS)do
 check(buttons[label] and buttons[label]:GetScript('OnClick'),'button "'..label..'" exists with its click handler')
end

-- Rectangles in window coordinates: x right, y DOWN from the window top.
local function anchorOf(region,point)
 local l,t,r,b
 if region==qs then l,t,r,b=0,0,W,Ht else l,t,r,b=unpack(region.rect) end
 local x=point:find('LEFT') and l or point:find('RIGHT') and r or (l+r)/2
 local y=point:find('TOP') and t or point:find('BOTTOM') and b or (t+b)/2
 return x,y
end
local function place(region,w,h)
 check(region:GetNumPoints()==1,'one anchor per region')
 local pt={region:GetPoint(1)}
 local point,rel,relPoint,x,y
 if #pt==3 then point,rel,relPoint,x,y=pt[1],qs,pt[1],pt[2],pt[3]
 else point,rel,relPoint,x,y=pt[1],pt[2],pt[3],pt[4],pt[5] end
 local ax,ay=anchorOf(rel,relPoint)
 ax,ay=ax+x,ay-y
 local left=point:find('LEFT') and ax or point:find('RIGHT') and ax-w or ax-w/2
 local top=point:find('TOP') and ay or point:find('BOTTOM') and ay-h or ay-h/2
 region.rect={left,top,left+w,top+h}
 return region.rect
end
local function inside(label,rect)
 -- Dialog border insets: left 11, right 12, top 12, bottom 11.
 check(rect[1]>=11 and rect[3]<=W-12 and rect[2]>=12 and rect[4]<=Ht-11,label..' lies inside the window border')
end
local function apart(a,b,label)
 check(a[3]<=b[1] or b[3]<=a[1] or a[4]<=b[2] or b[4]<=a[2],label..' do not overlap')
end
local order={'Set up current build','Import / Create Wishlist','Browse Community builds','Open Leaderboard',
 'Help / Getting Started','Orbs / Lost Memories','Later'}
for _,label in ipairs(order)do
 local b=buttons[label];inside('button "'..label..'"',place(b,b:GetWidth(),b:GetHeight()))
end
local bodyRect=place(body,body:GetWidth(),body:GetHeight());inside('body',bodyRect)
local hintRect=place(hint,hint:GetWidth(),hint:GetHeight());inside('hint',hintRect)
for i=1,#order do
 local a=buttons[order[i]].rect
 apart(a,bodyRect,'button "'..order[i]..'" and body');apart(a,hintRect,'button "'..order[i]..'" and hint')
 for j=i+1,#order do apart(a,buttons[order[j]].rect,'buttons "'..order[i]..'" and "'..order[j]..'"') end
end
apart(bodyRect,hintRect,'body and hint')
local firstRow=buttons['Set up current build'].rect[2]
check(bodyRect[4]<=firstRow,'body ends above the first button row')

local function wrapped(text,width,char)
 text=text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
 local lines=0
 for para in (text..'\n'):gmatch('(.-)\n')do
  lines=lines+1;local used=0
  for word in para:gmatch('%S+')do
   local w=#word*char;local gap=used>0 and char or 0
   if used>0 and used+gap+w>width then lines=lines+1;used=w else used=used+gap+w end
  end
 end
 return lines
end
local subtitleTop=37
local sp={subtitle:GetPoint(1)}
check(sp[1]=='TOP' and sp[#sp]==-subtitleTop,'subtitle anchor unchanged')
for _,m in ipairs(MODELS)do
 local bodyLines,hintLines=wrapped(BODY,body:GetWidth(),m.char),wrapped(HINT,hint:GetWidth(),m.char)
 print('QUICKSTART_FIT',m.name,'window',W..'x'..Ht,'body',body:GetWidth()..'x'..body:GetHeight(),'lines',bodyLines,'needs',bodyLines*m.line,
  'hint',hint:GetWidth()..'x'..hint:GetHeight(),'lines',hintLines,'needs',hintLines*m.line)
 check(bodyLines*m.line<=body:GetHeight(),m.name..' font: every body line fits (no cut paragraph)')
 check(hintLines*m.line<=hint:GetHeight(),m.name..' font: every hint line fits')
 check(#SUBTITLE*m.char<=W-24,m.name..' font: subtitle fits on one line')
 check(subtitleTop+m.line<=bodyRect[2],m.name..' font: subtitle line ends above the body')
end
-- The window stays on a 768 px high UI at its offset (centre +55).
check(Ht/2+55<=384 and W<=1024,'window fits the smallest UI height at its offset')

-- Handlers keep their behaviour: Later closes the window and assigns, saves
-- and spends nothing.
local actions,sent=#H.actions,#H.sent
buttons.Later:Click()
check(not qs:IsShown(),'Later closes Quick Start')
check(#H.actions==actions and #H.sent==sent,'closing Quick Start submits nothing')
print('PASS Quick Start text fits its regions in the default and conservative font models; no overlap; inside the window; checks='..checks)
