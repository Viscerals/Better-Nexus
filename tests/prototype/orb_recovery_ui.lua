-- 035 part 2c: the player's side of Continue in the Orb window.
--
-- A "Continue..." button appears in the Orb window only while there is something to continue
-- or to read about it. It opens its own small window. Opening it, reading it and closing it send
-- nothing. "Check" starts the strict check, and only the player's click on "Continue" in the
-- window, enabled only for the current ready token, confirms. Closing the window or pressing
-- Cancel cancels a check. A stale click is refused with the reason and changes nothing.
-- Synthetic game and server; native behavior is NOT TESTED.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local failures={}
local function section(name,fn)
 local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function World(opts)
 local H,M,A,O=R.Class(opts)
 local server=R.Server(H,opts and opts.server)
 S.Pass(H,M,A,2)
 return H,M,A,O,server
end
local function Button(H,label,parent)
 for _,b in ipairs(H.frames) do
  if b.kind=='Button' and b:GetText()==label and (not parent or b:GetParent()==parent) then return b end
 end
 return nil
end
local function Until(H,fn,seconds)
 local waited=0
 while waited<(seconds or 20) do
  if fn() then return true end
  H.Advance(.25);waited=waited+.25
 end
 return fn()
end

section('1 the button and the window',function()
 local H,M,A,O,server=World()
 SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel)
 H.Advance(.5)
 check(f.cont and f.cont:IsShown() and f.cont:IsEnabled(),'the Continue button is shown for the class')
 check(f:GetHeight()==445,'the Orb window keeps its size')
 local sent=#H.sent;local reqs=server.requests
 f.cont:Click()
 local w=assert(NexusOrbContinue,'its own window');check(w:IsShown(),'the window opens')
 H.Advance(.5)
 -- The intro names the client-observed spend (no server reply confirms a spend).
 check(w.body:GetText():find('spend observed by this client',1,true) and w.body:GetText():find('No spend and no choice',1,true),'it explains what Continue is: '..w.body:GetText())
 check(w.check:IsEnabled() and not w.go:IsEnabled(),'only Check is available at first')
 check(server.requests==reqs and #H.sent==sent and H.Count('orb-spend')==0 and H.Count('take')==0,'opening it sent and spent nothing')
 -- no receipt: no button
 local H2,M2,A2,O2=S.Fresh()
 SlashCmdList.NEXUS('orbs');local f2=assert(NexusOrbPanel)
 H2.Advance(.5)
 check(f2.cont==nil or not f2.cont:IsShown(),'no receipt, no Continue button')
end)

section('2 check, ready, continue',function()
 local H,M,A,O,server=World()
 local original=H.Clone(R.Saved())
 SlashCmdList.NEXUS('orbs');local f=NexusOrbPanel
 f.cont:Click();local w=NexusOrbContinue
 w.check:Click()
 check(server.requests>=1,'Check asks the game (read-only)')
 H.Advance(.3)
 check(w.body:GetText():find('Checking',1,true) and not w.go:IsEnabled() and not w.check:IsEnabled(),'while checking: only the cancel is live')
 check(Until(H,function() return w.go:IsEnabled() end),'the Continue button becomes available only when the check is ready')
 check(w.body:GetText():find('unconfirmed',1,true) and w.body:GetText():find('not prove',1,true),'the window carries the full consent text')
 check(#w.body:GetText()<1500,'bounded text')
 check(R.Saved()~=nil and M.Status().pending==true,'nothing is released before the click')
 local sent=#H.sent
 w.go:Click()
 check(R.Saved()==nil and #R.SavedRow('orbRecoveryArchive')==1,'the click archives')
 H.Advance(.5)
 check(w.body:GetText():find('Continued',1,true) and not w.go:IsEnabled(),'the window says it is done; nothing left to confirm')
 check(M.Status().state=='STOPPED' and #H.sent==sent,'stopped, nothing sent')
 check(f.status:GetText():find('Stopped',1,true),'the Orb window shows Stopped')
 w:Hide()
end)

section('3 cancel and close',function()
 local H,M,A,O,server=World()
 SlashCmdList.NEXUS('orbs');NexusOrbPanel.cont:Click();local w=NexusOrbContinue
 w.check:Click();assert(Until(H,function() return w.go:IsEnabled() end))
 w.cancel:Click();H.Advance(.5)
 check(M.ContinueView().stage=='idle' and M.ContinueView().token==nil and not w.go:IsEnabled(),'Cancel returns to the start')
 w.check:Click();assert(Until(H,function() return w.go:IsEnabled() end))
 local token=M.ContinueView().token
 w:Hide();H.Advance(.5)
 check(M.ContinueView().stage=='idle' and select(2,M.ContinueConfirm(token))=='stale_token','closing the window cancels the check; the token is dead')
 check(R.Saved()~=nil,'nothing was released')
end)

section('4 a stale click',function()
 local H,M,A,O,server=World()
 SlashCmdList.NEXUS('orbs');NexusOrbPanel.cont:Click();local w=NexusOrbContinue
 w.check:Click();assert(Until(H,function() return w.go:IsEnabled() end))
 local original=H.Clone(R.Saved())
 H.perks.serverActiveSlot=102                  -- the game changed under the window
 H.Advance(6)
 check(not w.go:IsEnabled() and w.body:GetText():find('changed',1,true),'the window withdraws the confirmation and says why: '..w.body:GetText())
 -- a click that still reaches the handler (the window was not refreshed yet)
 local handler=w.go:GetScript('OnClick')
 handler(w.go)
 check(R.Same(R.Saved(),original) and R.SavedRow('orbRecoveryArchive')==nil,'a stale click changes nothing')
 check(w.notice:GetText()~=nil and w.notice:GetText()~='' and not w.notice:GetText():find('^[%l_]+$'),'and the player is told in words, not with a code: '..tostring(w.notice:GetText()))
end)

section('6 a click confirms what the window showed',function()
 local H,M,A,O,server=World()
 SlashCmdList.NEXUS('orbs');NexusOrbPanel.cont:Click();local w=NexusOrbContinue
 w.check:Click();assert(Until(H,function() return w.go:IsEnabled() end))
 local shown=w.token
 check(shown~=nil and shown==M.ContinueView().token,'the window holds the current token')
 -- the window stops refreshing (a stalled frame); the game side starts a new check with a new token
 w:SetScript('OnUpdate',nil)
 M.ContinueCancel();assert(M.ContinueBegin())
 assert(Until(H,function() return M.ContinueView().stage=='ready' end))
 local newest=M.ContinueView().token
 check(newest~=shown and w.token==shown,'the newest token is not the one the window showed')
 local original=H.Clone(R.Saved())
 w.go:GetScript('OnClick')(w.go)
 check(R.Same(R.Saved(),original) and R.SavedRow('orbRecoveryArchive')==nil,'a click confirms what the window showed, never a newer state: nothing changed')
 check(M.ContinueView().stage=='ready' and M.ContinueView().token==newest,'and the newer check is untouched')
end)

section('5 the help names Continue',function()
 -- the Orb help topic is a long string in ui/Help.lua; it must describe Continue and no longer claim there is no exit
 local f=assert(io.open('ui/Help.lua','rb'));local text=f:read('*a');f:close()
 local orbs=text:match('id="orbs".-id="troubleshooting"') or ''
 check(orbs:find('Continue:',1,true) and orbs:find('Nexus never continues by itself',1,true),'the Orb help describes Continue and says it is never automatic')
 check(not orbs:find('No exit from that block exists yet',1,true),'and no longer says no exit exists')
 check(orbs:find('not prove',1,true) and orbs:find('older answer',1,true),'it states what stays uncertain')
end)

if #failures>0 then error(#failures..' section(s) failed:\n'..table.concat(failures,'\n'),0) end
print('PASS Orb recovery window: explicit Check and Continue, withdrawn on change, cancelled on close checks='..checks)
