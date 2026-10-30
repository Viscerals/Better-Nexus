-- Test support (dofile only; not a test): a pseudo-locale for the full UI
-- localization tests. It reloads the real core/Localization.lua with one
-- synthetic optional pack built from the real English catalog, activates it
-- for the session and swaps Nexus.Localization, so every consumer that looks
-- the seam up at display time shows the pseudo text. A visible string that
-- still shows plain English after activation did not pass through the seam.
--
-- Pseudo text: "\194\171" .. English .. "\194\187" (U+00AB/U+00BB, two bytes
-- each), or in "long" mode the English with every ASCII letter run doubled in
-- length (an expanded-language model) inside the same marks. Templates keep
-- their placeholders, so the marks enclose the whole rendered sentence. An
-- entry whose pseudo text would break its contract (length) is left out and
-- shows English, which the scan then reports.
-- Synthetic offline evidence only: no glyph, font or native layout claim.
local S={}
local OPEN,CLOSE='\194\171','\194\187'
S.OPEN,S.CLOSE=OPEN,CLOSE

local function readFile(path)
 local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s
end

-- The real English entries, read from the data file without running the TOC.
function S.English()
 local env={}
 local chunk=assert(loadfile('data/LocalizationEnglish.lua'))
 if setfenv then setfenv(chunk,env) end
 chunk()
 return assert(env.Nexus and env.Nexus.LocalizationEnglish)
end

local function expand(text)
 -- Double each ASCII letter run outside {placeholders}.
 local out,i={},1
 while i<=#text do
  local b=text:sub(i,i)
  if b=='{' then
   local close=text:find('}',i,true) or #text
   out[#out+1]=text:sub(i,close);i=close+1
  else
   local s,e=text:find('^[A-Za-z]+',i)
   if s then local w=text:sub(s,e);out[#out+1]=w..w:lower();i=e+1
   else out[#out+1]=b;i=i+1 end
  end
 end
 return table.concat(out)
end

-- entries for every reviewed key; mode "wrap" (default) or "long".
function S.PseudoEntries(mode,english)
 english=english or S.English()
 local out={}
 for key,text in pairs(english) do
  local body=mode=='long' and expand(text) or text
  out[key]=OPEN..body..CLOSE
 end
 return out
end

-- Reloads the seam with the pseudo pack as frFR, initializes it and makes it
-- Nexus.Localization. Returns the module and a restore function.
function S.Activate(mode,entries)
 local real,realPacks=Nexus.Localization,Nexus.LocalizationPacks
 entries=entries or S.PseudoEntries(mode)
 S.activeEntries=entries
 Nexus.LocalizationPacks={frFR={name='Pseudo',entries=entries}}
 local ok,err=pcall(dofile,'core/Localization.lua')
 local module=Nexus.Localization
 Nexus.LocalizationPacks=realPacks
 assert(ok,err)
 assert(module.InitializeActiveLanguage('frFR')=='frFR','pseudo pack adopted')
 local function restore() Nexus.Localization=real end
 return module,restore
end

-- Session-start activation, as a real pack is chosen before the UI exists:
-- call before H.Boot / F.Boot. While the TOC loads core/Localization.lua the
-- pseudo pack replaces frFR in Nexus.LocalizationPacks and frFR is made the
-- session language right after the seam loads (the lifecycle's later call
-- then changes nothing). Returns a function that removes the hook; the hook
-- also removes itself after its one use.
function S.InstallBootHook(mode,entries)
 entries=entries or S.PseudoEntries(mode)
 S.activeEntries=entries
 local realLoadfile=loadfile
 local function uninstall() loadfile=realLoadfile end
 loadfile=function(path,...)
  local chunk,err=realLoadfile(path,...)
  if not chunk or (path~='core/Localization.lua' and path~='core\\Localization.lua') then return chunk,err end
  uninstall()
  return function(...)
   Nexus=Nexus or {}
   local packs=Nexus.LocalizationPacks
   Nexus.LocalizationPacks={frFR={name='Pseudo',entries=entries}}
   local results={chunk(...)}
   Nexus.LocalizationPacks=packs
   assert(Nexus.Localization.InitializeActiveLanguage('frFR')=='frFR','pseudo pack adopted at boot')
   return unpack(results)
  end
 end
 return uninstall
end

function S.IsPseudo(text)
 return type(text)=='string' and text:find(OPEN,1,true)~=nil
end

-- Text left after removing every balanced marked span, colour escapes and
-- textures, and whether the markers were balanced. Only a span whose
-- opener has its matching closer is removed: after an unmatched opener the
-- rest of the text stays (without the opener) so the scan still sees it,
-- and a stray closer is kept as text. `balanced` is false for either case.
function S.Unmarked(text)
 text=tostring(text or '')
 text=text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):gsub('|T.-|t',''):gsub('||','|')
 local out,i,balanced={},1,true
 while true do
  local s=text:find(OPEN,i,true)
  local stray=text:find(CLOSE,i,true)
  if stray and (not s or stray<s) then balanced=false end
  if not s then out[#out+1]=text:sub(i);break end
  out[#out+1]=text:sub(i,s-1)
  local depth,j=1,s+#OPEN
  while depth>0 and j<=#text do
   if text:sub(j,j+#OPEN-1)==OPEN then depth=depth+1;j=j+#OPEN
   elseif text:sub(j,j+#CLOSE-1)==CLOSE then depth=depth-1;j=j+#CLOSE
   else j=j+1 end
  end
  if depth>0 then
   -- No matching closer: keep everything after this opener visible.
   balanced=false
   i=s+#OPEN
  else
   i=j
  end
 end
 return table.concat(out),balanced
end

-- Well-formed UTF-8 (shortest-form scalar sequences), byte by byte.
local function WellFormedUtf8(t)
 local i,n=1,#t
 while i<=n do
  local c=t:byte(i);local w
  if c<0x80 then w=1 elseif c>=0xC2 and c<=0xDF then w=2 elseif c>=0xE0 and c<=0xEF then w=3
  elseif c>=0xF0 and c<=0xF4 then w=4 else return false end
  if i+w-1>n then return false end
  for k=i+1,i+w-1 do local d=t:byte(k);if d<0x80 or d>0xBF then return false end end
  i=i+w
 end
 return true
end
S.WellFormedUtf8=WellFormedUtf8

-- A seam text that the code shortened with "..." (its closing marker is cut
-- off). True only when the whole shown text (colour codes aside) is the
-- opener plus a well-formed UTF-8 prefix of one installed pseudo entry, then
-- "..." and optional trailing ":" or spaces. For a template entry the prefix
-- is compared up to its first placeholder, since slot values follow it.
-- `entries` defaults to the entries the last activation installed.
function S.IsShortenedSeamText(text,entries)
 entries=entries or S.activeEntries
 if type(entries)~='table' then return false end
 local plain=tostring(text or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
 local body=plain:match('^('..OPEN..'.-)%.%.%.[:%s]*$')
 if not body or body:find(CLOSE,1,true) or not WellFormedUtf8(body) or #body<=#OPEN then return false end
 for _,value in pairs(entries) do
  if type(value)=='string' then
   if value:sub(1,#body)==body then return true end
   local brace=value:find('{',1,true)
   if brace and #body>=brace-1 and body:sub(1,brace-1)==value:sub(1,brace-1) then return true end
  end
 end
 return false
end

-- The first English-looking word (two or more ASCII letters) left in the
-- unmarked remainder that `allow` does not accept, or "<unbalanced pseudo
-- marker>" when the markers do not pair up (a cut or malformed pseudo text
-- is never counted as covered). `allow(word, text)` may accept data that is
-- never translated (player, build and Echo names, game identifiers).
function S.LooksUntranslated(text,allow)
 if S.IsShortenedSeamText(text) then return nil end
 local rest,balanced=S.Unmarked(text)
 for word in rest:gmatch('[A-Za-z][A-Za-z\']+') do
  if not (allow and allow(word,text)) then return word end
 end
 if not balanced then return '<unbalanced pseudo marker>' end
 return nil
end

-- Every non-empty text of a visible frame or region under `root` (a frame
-- table) in the harness, depth first. Hidden subtrees are skipped.
function S.VisibleTexts(root,out)
 out=out or {}
 if not root or (root.IsShown and not root:IsShown()) then return out end
 if root.GetText then
  local t=root:GetText()
  if type(t)=='string' and t~='' then out[#out+1]={text=t,frame=root} end
 end
 for _,r in ipairs(root.regions or {}) do
  if (not r.IsShown or r:IsShown()) and r.GetText then
   local t=r:GetText()
   if type(t)=='string' and t~='' then out[#out+1]={text=t,frame=r} end
  end
 end
 for _,c in ipairs(root.children or {}) do S.VisibleTexts(c,out) end
 return out
end

-- Runs fn with GameTooltip's line methods recorded; returns the lines.
-- Every replaced name is restored to its exact raw original afterwards,
-- also when that original was nil (an inherited method) and also when fn
-- fails; fn's error is then raised again.
local TOOLTIP_METHODS={'AddLine','SetText','AddDoubleLine'}
function S.CaptureTooltip(fn,...)
 local lines={}
 local saved={}
 for index,name in ipairs(TOOLTIP_METHODS) do saved[index]=rawget(GameTooltip,name) end
 rawset(GameTooltip,'AddLine',function(_,t) lines[#lines+1]=t end)
 rawset(GameTooltip,'SetText',function(_,t) lines[#lines+1]=t end)
 rawset(GameTooltip,'AddDoubleLine',function(_,a,b) lines[#lines+1]=a;lines[#lines+1]=b end)
 local ok,err=pcall(fn,...)
 for index,name in ipairs(TOOLTIP_METHODS) do rawset(GameTooltip,name,saved[index]) end
 if not ok then error(err,0) end
 return lines
end

-- Runs fn with print and DEFAULT_CHAT_FRAME recorded; returns the lines.
function S.CaptureChat(fn,...)
 local lines,realPrint,frame=({}),print,DEFAULT_CHAT_FRAME
 local realAdd=frame.AddMessage
 print=function(...) local p={};for i=1,select('#',...) do p[i]=tostring((select(i,...))) end;lines[#lines+1]=table.concat(p,' ') end
 frame.AddMessage=function(_,line) lines[#lines+1]=tostring(line) end
 local ok,err=pcall(fn,...)
 print,frame.AddMessage=realPrint,realAdd
 assert(ok,err)
 return lines
end

-- Report helper: the visible texts that still look untranslated.
function S.Untranslated(texts,allow)
 local out={}
 for _,item in ipairs(texts) do
  local text=type(item)=='table' and item.text or item
  local word=S.LooksUntranslated(text,allow)
  if word then out[#out+1]={text=text,word=word} end
 end
 return out
end

S.readFile=readFile
return S
