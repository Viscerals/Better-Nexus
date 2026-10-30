-- Guards for tests/prototype/l10n_pseudo_support.lua (findings
-- FULLUI-FOUNDATION-1 and -2 of the early foundation review at 6b60e1a):
-- 1. CaptureTooltip restores every replaced GameTooltip method name,
--    including names whose raw original was nil (inherited through the
--    harness metatable), after a successful and after a failing callback,
--    and an ordinary tooltip SetText works again afterwards.
-- 2. An unmatched pseudo opener never hides the text after it: the scan
--    still sees that English, and an unbalanced marker is reported.
-- Synthetic offline evidence; native NOT_RUN.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local NAMES={'AddLine','SetText','AddDoubleLine'}

local function rawFields()
 local out={};for _,name in ipairs(NAMES) do out[name]=rawget(GameTooltip,name) end;return out
end
local function sameRaw(before,why)
 for _,name in ipairs(NAMES) do
  check(rawget(GameTooltip,name)==before[name],why..': raw GameTooltip.'..name..' restored (original '..type(before[name])..')')
 end
end

-- 1a. Inherited methods (raw nil) on the success path.
local before=rawFields()
check(before.SetText==nil and before.AddLine==nil,'SETUP the harness tooltip methods are inherited (raw nil)')
local lines=S.CaptureTooltip(function()
 GameTooltip:SetText('Capture heading');GameTooltip:AddLine('Capture line');GameTooltip:AddDoubleLine('Left','Right')
end)
check(#lines==4 and lines[1]=='Capture heading' and lines[4]=='Right','capture records every line in order')
sameRaw(before,'success path')
GameTooltip:SetText('Normal after capture')
check(GameTooltip:GetText()=='Normal after capture','an ordinary SetText works after a capture')

-- 1b. Failure path: the callback raises; the error still propagates and
-- every method is restored first.
local ok,err=pcall(S.CaptureTooltip,function() GameTooltip:AddLine('x');error('callback failed on purpose') end)
check(not ok and tostring(err):find('callback failed on purpose',1,true),'a failing callback error is propagated')
sameRaw(before,'failure path')
GameTooltip:SetText('Normal after failure')
check(GameTooltip:GetText()=='Normal after failure','an ordinary SetText works after a failed capture')

-- 1c. A raw own method present before the capture is put back as the same function.
local own=function(self,t) self.text='own:'..tostring(t) end
rawset(GameTooltip,'SetText',own)
S.CaptureTooltip(function() GameTooltip:SetText('inside') end)
check(rawget(GameTooltip,'SetText')==own,'an own raw method is restored as the same function')
GameTooltip.SetText=nil
GameTooltip:SetText('inherited again')
check(GameTooltip:GetText()=='inherited again','SETUP inherited SetText back')

-- 2. Marker scanning.
local O,C=S.OPEN,S.CLOSE
check(S.LooksUntranslated(O..'Mapped text'..C)==nil,'a balanced marked text is covered')
check(S.LooksUntranslated(O..'Mapped text'..C..' Untranslated')=='Untranslated','trailing English after a balanced span is found')
check(S.LooksUntranslated(O..'Outer '..O..'inner'..C..' tail'..C)==nil,'nested balanced spans are covered')
local found=S.LooksUntranslated(O..'PlayerName Untranslated static heading')
check(found~=nil,'an unmatched opener cannot hide the English after it')
check(S.Unmarked(O..'Untranslated heading'):find('Untranslated heading',1,true),'the text after an unmatched opener stays visible to the scan')
check(S.LooksUntranslated(O..'a'..C..O..'12')~=nil,'an unbalanced marker is reported even without letters after it')
check(S.LooksUntranslated('Untranslated '..C)=='Untranslated','a stray closer does not hide English before it')
check(S.LooksUntranslated('Ashbringer',function(word) return word=='Ashbringer' end)==nil,'explicit data allowance still works')
check(S.LooksUntranslated(O..'Owned by '..C..'Ashbringer',function(word) return word=='Ashbringer' end)==nil,'marked text next to allowed data is covered')
-- 3. Code-shortened seam text: accepted only as a real entry's prefix.
local entries={['x.label.long']=O..'Waiting for the actual game result'..C,
 ['x.status.slot']=O..'Reserved for {name} until it ends'..C}
check(S.IsShortenedSeamText(O..'Waiting for the act...',entries),'a prefix of a real entry plus ... is shortened seam text')
check(S.IsShortenedSeamText('|cffffffff'..O..'Waiting for the actual...:|r',entries),'colour codes and a trailing colon are code-owned')
check(S.IsShortenedSeamText(O..'Reserved for Ashbringer unt...',entries),'a template prefix is compared up to its first placeholder')
check(not S.IsShortenedSeamText(O..'Totally different text...',entries),'a non-entry prefix is not shortened seam text')
check(not S.IsShortenedSeamText(O..'Waiting for the actual game result Untranslated...',entries),'text beyond the entry is not shortened seam text')
check(not S.IsShortenedSeamText(O..'Waiting for the act'..string.char(208)..'...',{['x.y']=O..'Waiting for the act'..string.char(208,159)..C}),'a cut inside a UTF-8 character is not accepted')
check(not S.IsShortenedSeamText(O..'Waiting for the act...'..' tail English',entries),'English after the ellipsis is not accepted')
S.activeEntries=entries
check(S.LooksUntranslated(O..'Waiting for the act...')==nil,'the scan accepts real shortened seam text')
check(S.LooksUntranslated(O..'Totally different text...')~=nil,'the scan still reports a non-entry cut text')
S.activeEntries=nil
print('PASS l10n_pseudo_support_guards checks='..checks..' (synthetic; native NOT_RUN)')
