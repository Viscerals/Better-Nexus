-- #36: diagnostic text is cut to its byte cap at a UTF-8 character boundary.
-- DiagnosticHistory.SafeText and the error log cut with a raw string.sub, so
-- a multibyte character that crossed the cap was split and valid input
-- became invalid text in the Log Viewer and the support report.
--
-- Policy for input that is ALREADY invalid: it is cut by the same rule and
-- is not repaired; the cut never makes valid input invalid.
--
-- Real TOC boot; synthetic text.
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0)
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local D,E,I=Nexus.DiagnosticHistory,Nexus.Errors,Nexus.Identity
local function Hex(s) return (s:gsub('.',function(c) return string.format('%02X',c:byte()) end)) end

local TWO,THREE,FOUR='\195\169','\226\130\172','\240\159\152\128' -- e-acute, euro, emoji
-- 1. ASCII exactly at the cap is unchanged.
check(D.SafeText('abcde',5)=='abcde','ASCII at the cap is unchanged')
check(D.SafeText('abcdef',5)=='abcde','ASCII over the cap is cut at the cap')
-- 2.-4. A character that crosses the cap is left out whole.
check(D.SafeText('A'..TWO,2)=='A','a two-byte character crossing the cap is left out: '..Hex(D.SafeText('A'..TWO,2)))
check(D.SafeText('A'..THREE,3)=='A','a three-byte character crossing the cap is left out: '..Hex(D.SafeText('A'..THREE,3)))
check(D.SafeText('A'..THREE,2)=='A','also when the cap falls after its first byte')
check(D.SafeText('A'..FOUR,4)=='A','a four-byte character crossing the cap is left out: '..Hex(D.SafeText('A'..FOUR,4)))
check(D.SafeText('A'..FOUR,5)=='A'..FOUR,'a character that fits is kept')
-- 5. Every cap over a mixed valid string gives valid text within the cap.
local mixed='a'..TWO..'b'..THREE..FOUR..'c'..THREE..TWO
for cap=1,#mixed+1 do
 local cut=D.SafeText(mixed,cap)
 check(#cut<=cap and I.ValidUtf8(cut) and mixed:sub(1,#cut)==cut,
  'cap '..cap..' gives a valid prefix within the cap: '..Hex(cut))
end
-- 6. Control characters are still replaced.
check(D.SafeText('a\nb\tc',10)=='a b c','control characters become spaces')
-- 7. Format stays bounded and valid.
local formatted=D.Format(5,'%s',THREE..THREE)
check(#formatted<=5 and I.ValidUtf8(formatted),'Format is bounded and valid: '..Hex(formatted))
-- 8. Already-invalid input is cut by the same rule, not repaired.
check(D.SafeText('\255abc',2)=='\255a','invalid input keeps its bytes up to the cap: '..Hex(D.SafeText('\255abc',2)))

-- The error log: message (2000 bytes plus "...") and source (64 bytes).
E.Clear()
local message=string.rep('x',1999)..THREE
E.Record(string.rep('s',63)..TWO,message)
local entry=E.Latest()
check(entry and I.ValidUtf8(entry.message),'a long error message stays valid UTF-8: ..'..Hex(entry.message:sub(-6)))
-- (The log applies its cap on Record and again on the stored entry, so the
-- marker may carry one more dot; that is existing behaviour.)
check(entry.message:sub(1,1999)==string.rep('x',1999) and not entry.message:find('[\128-\255]')
 and entry.message:sub(-3)=='...',
 'and the character that crossed the cap is left out whole: ..'..Hex(entry.message:sub(-6)))
check(I.ValidUtf8(entry.source) and entry.source==string.rep('s',63),
 'a long source stays valid UTF-8: ..'..Hex(entry.source:sub(-4)))

-- The shared helper keeps the display sanitizer's result.
check(I.SanitizeText('A'..THREE,3)=='A','Identity.SanitizeText keeps its boundary behaviour')

print('PASS utf8_safe_truncation checks='..checks)
