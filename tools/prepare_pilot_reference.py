#!/usr/bin/env python3
"""Extract only two reference modules from the user's supplied, hash-bound archive.
The original third-party source is not shipped in the prototype runtime package.
"""
import argparse,hashlib,pathlib,zipfile
p=argparse.ArgumentParser();p.add_argument('archive',type=pathlib.Path);p.add_argument('destination',type=pathlib.Path);a=p.parse_args()
expected='d471335ce243a7c0a42b1c2b22434bc757dca1ba40b852e8ded2545d7902190e'
if hashlib.sha256(a.archive.read_bytes()).hexdigest()!=expected:p.error('This is not the supplied LoadoutPilot 1.3.6 patch-103 reference')
with zipfile.ZipFile(a.archive) as z:
 for relative in ['Domain/EchoSelectionPolicy.lua','Engine/WishlistPlanner.lua']:
  name='LoadoutPilot/'+relative;target=a.destination/relative
  data=z.read(name)
  if target.exists() and target.read_bytes()!=data:p.error('Refusing to overwrite different reference: '+str(target))
  target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
print(a.destination.resolve())
