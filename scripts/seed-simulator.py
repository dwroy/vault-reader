#!/usr/bin/env python3
"""Debug-only offline acceptance fixture. Never copy private vault files into source.
Usage: python3 scripts/seed-simulator.py /path/to/vault SIMULATOR_UDID
Reads git HEAD, only Markdown and images <= 1 MiB; does not read untracked files.
"""
import hashlib, json, pathlib, subprocess, sys
vault = pathlib.Path(sys.argv[1]).resolve()
device = sys.argv[2]
container = pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'com.dwroy.vaultreader','data'],text=True).strip())
key = lambda text: hashlib.sha256(text.encode()).hexdigest()
root = container/'Library/Application Support/VaultReader'/key('dwroy/notes')
blobs = root/'blobs'; meta = root/'meta'/key('main')
blobs.mkdir(parents=True,exist_ok=True);meta.mkdir(parents=True,exist_ok=True)
raw = subprocess.check_output(['git','-C',str(vault),'ls-tree','-rlz','HEAD'])
entries=[];pinned=[];count=0
for item in raw.split(b'\0'):
    if not item:continue
    fields, name = item.split(b'\t',1); mode, kind, sha, size = fields.decode().split()
    if kind!='blob':continue
    path=name.decode();entry={'path':path,'sha':sha,'size':int(size),'type':kind};entries.append(entry)
    ext=pathlib.Path(path).suffix.lower()
    if ext=='.md' or (ext in ['.svg','.png','.jpg','.jpeg','.gif','.webp'] and int(size)<=1024*1024):
        data=subprocess.check_output(['git','-C',str(vault),'cat-file','blob',sha]);(blobs/sha).write_bytes(data);count+=1
        if ext in ['.md','.svg']:pinned.append(sha)
(blobs/'pinned.json').write_text(json.dumps(pinned))
tree=subprocess.check_output(['git','-C',str(vault),'rev-parse','HEAD^{tree}'],text=True).strip()
(meta/'tree.json').write_text(json.dumps({'sha':tree,'truncated':False,'tree':entries}))
print(f'Seeded {count} tracked Markdown/image blobs for offline simulator acceptance. No credential used.')
