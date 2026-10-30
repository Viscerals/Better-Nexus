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
 Nexus.LocalizationPacks={frFR={name='Pseudo',entries=entries or S.PseudoEntries(mode)}}
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

-- Text left after removing every marked span, colour escapes and textures.
function S.Unmarked(text)
 text=tostring(text or '')
 text=text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):gsub('|T.-|t',''):gsub('||','|')
 local out,i={},1
 while true do
  local s=text:find(OPEN,i,true)
  if not s then out[#out+1]=text:sub(i);break end
  out[#out+1]=text:sub(i,s-1)
  local depth,j=1,s+#OPEN
  while depth>0 and j<=#text do
   if text:sub(j,j+#OPEN-1)==OPEN then depth=depth+1;j=j+#OPEN
   elseif text:sub(j,j+#CLOSE-1)==CLOSE then depth=depth-1;j=j+#CLOSE
   else j=j+1 end
  end
  i=j
 end
 return table.concat(out)
end

-- True when the unmarked remainder still holds an English-looking word (two
-- or more ASCII letters) that `allow` does not accept. `allow(word, text)`
-- may accept data that is never translated (player, build and Echo names,
-- game identifiers, numbers with units owned by data).
function S.LooksUntranslated(text,allow)
 local rest=S.Unmarked(text)
 for word in rest:gmatch('[A-Za-z][A-Za-z\']+') do
  if not (allow and allow(word,text)) then return word end
 end
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
function S.CaptureTooltip(fn,...)
 local lines={}
 local saved={}
 for _,name in ipairs({'AddLine','SetText','AddDoubleLine'}) do saved[name]=rawget(GameTooltip,name) end
 GameTooltip.AddLine=function(_,t) lines[#lines+1]=t end
 GameTooltip.SetText=function(_,t) lines[#lines+1]=t end
 GameTooltip.AddDoubleLine=function(_,a,b) lines[#lines+1]=a;lines[#lines+1]=b end
 local ok,err=pcall(fn,...)
 for name,v in pairs(saved) do GameTooltip[name]=v end
 assert(ok,err)
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
