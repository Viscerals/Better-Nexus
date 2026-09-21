#!/usr/bin/env python3
"""Isolated Lua 5.4 offline runner using the container's system library.
This is test tooling, not a WoW runtime and is never packaged into Nexus.
"""
import ctypes,sys
lib=ctypes.CDLL('liblua5.4.so.0')
P=ctypes.c_void_p; I=ctypes.c_int; S=ctypes.c_char_p
lib.luaL_newstate.restype=P
lib.luaL_openlibs.argtypes=[P]
lib.luaL_loadfilex.argtypes=[P,S,S];lib.luaL_loadfilex.restype=I
lib.luaL_loadstring.argtypes=[P,S];lib.luaL_loadstring.restype=I
lib.lua_pcallk.argtypes=[P,I,I,I,ctypes.c_longlong,P];lib.lua_pcallk.restype=I
lib.lua_tolstring.argtypes=[P,I,ctypes.POINTER(ctypes.c_size_t)];lib.lua_tolstring.restype=S
lib.lua_close.argtypes=[P]
L=lib.luaL_newstate();lib.luaL_openlibs(L)
compat=b'''unpack=table.unpack; loadstring=load; math.mod=math.fmod;
function setfenv(fn, env)
 if type(fn)=='number' then fn=debug.getinfo(fn+1,'f').func end
 local i=1; while true do local n=debug.getupvalue(fn,i); if not n then break end;
  if n=='_ENV' then debug.upvaluejoin(fn,i,function() return env end,1);break end;i=i+1 end
 return fn
end
function getfenv(fn)
 if fn==nil then return _G end
 if type(fn)=='number' then if fn==0 then return _G end;fn=debug.getinfo(fn+1,'f').func end
 local i=1;while true do local n,v=debug.getupvalue(fn,i);if n=='_ENV' then return v end;if not n then return _G end;i=i+1 end
end
package.preload.bit=function()
 local function norm(x) return math.floor(tonumber(x) or 0) & 0xffffffff end
 local function signed(x) x=x&0xffffffff; return x>=0x80000000 and x-0x100000000 or x end
 local function fold(op,a,...) local r=norm(a);for i=1,select('#',...) do r=op(r,norm(select(i,...))) end;return signed(r) end
 return {band=function(a,...)return fold(function(x,y)return x&y end,a,...)end,
 bor=function(a,...)return fold(function(x,y)return x|y end,a,...)end,
 bxor=function(a,...)return fold(function(x,y)return x~y end,a,...)end,
 bnot=function(a)return signed(~norm(a))end,lshift=function(a,n)return signed(norm(a)<<(n&31))end,
 rshift=function(a,n)return signed(norm(a)>>(n&31))end,arshift=function(a,n)return signed(signed(norm(a))>>(n&31))end,
 tobit=function(a)return signed(norm(a))end,tohex=function(a,n)return string.format('%08x',norm(a))end}
end
arg={}
'''
rc=lib.luaL_loadstring(L,compat)
if not rc: rc=lib.lua_pcallk(L,0,-1,0,0,None)
if not rc: rc=lib.luaL_loadfilex(L,sys.argv[1].encode(),None)
if not rc: rc=lib.lua_pcallk(L,0,-1,0,0,None)
if rc:
 m=lib.lua_tolstring(L,-1,None);print((m or b'Lua failed').decode('utf8','replace'),file=sys.stderr)
lib.lua_close(L);sys.exit(bool(rc))
