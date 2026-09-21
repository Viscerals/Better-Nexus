-- Bounded legacy EditBox surface. The native 3.3.5 observation confirms that
-- Button Enable/Disable/IsEnabled are absent, while focus/input APIs exist.
-- Unlike the general harness, this fixture never invents unknown methods.
return function(H)
 local create=CreateFrame
 local supported={GetName=true,GetParent=true,SetScript=true,GetScript=true,HookScript=true,
  SetSize=true,GetWidth=true,GetHeight=true,SetPoint=true,SetFrameLevel=true,
  SetAutoFocus=true,SetNumeric=true,SetMaxLetters=true,SetText=true,GetText=true,
  Show=true,Hide=true,IsShown=true,IsVisible=true,HasFocus=true,SetTextColor=true}
 function CreateFrame(kind,...)
  local f=create(kind,...)
  if kind~='EditBox' then return f end
  local base=getmetatable(f).__index
  f.mouseEnabled=true;f.keyboardEnabled=true
  setmetatable(f,{__index=function(self,key)
   if supported[key]then return base(self,key)end
  end})
  function f:EnableMouse(on)self.mouseEnabled=on==true end
  function f:EnableKeyboard(on)self.keyboardEnabled=on==true end
  function f:SetAlpha(value)self.alpha=value end
  function f:SetFocus()
   local changed=not self.focused;self.focused=true
   if changed and self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self)end
  end
  function f:ClearFocus()
   local changed=self.focused;self.focused=false
   if changed and self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self)end
  end
  return f
 end
 function H.TypeLimit(f,value)
  if not f.limit.keyboardEnabled or not f.limit:HasFocus()then return false end
  f.limit:SetText(value);return true
 end
 function H.OrbButton(label,parent)
  for _,f in ipairs(H.frames)do
   if f.kind=='Button' and f:GetParent()==parent and f:GetText()==label then return f end
  end
  error('Orb control not found: '..label)
 end
 function H.AssertOrbLocked(f,reason)
  assert(not f.limit.mouseEnabled and not f.limit.keyboardEnabled,reason..': maximum accepts input')
  assert(not f.limit:HasFocus(),reason..': maximum retains keyboard focus')
  f.limit:SetFocus();assert(not f.limit:HasFocus(),reason..': locked maximum acquired focus')
  assert(not H.TypeLimit(f,'999'),reason..': locked maximum accepted typing')
 end
end
