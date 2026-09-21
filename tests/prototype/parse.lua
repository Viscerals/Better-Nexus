local n=0
for line in io.lines('Nexus.toc')do
 line=line:gsub('\r','')
 if line~='' and not line:match('^#')then
  local path=line:gsub('\\','/')
  if path:match('%.lua$')then local fn,err=loadfile(path);assert(fn,err);n=n+1 end
 end
end
print('PASS compile TOC Lua files='..n..'; interpreter='.._VERSION..'; not a native WoW assertion')
