#!/usr/bin/env python3
"""Install Net Pulse with timestamped rollback copies; take the stock network widget's bar slot, preserve everything else."""
from pathlib import Path
import datetime
import json
import shutil
import subprocess

source=Path(__file__).resolve().parent
home=Path.home()
config=home/'.config/omarchy/shell.json'
dest=home/'.config/omarchy/plugins/nixfred.net-pulse'
unit=home/'.config/systemd/user/net-pulse.service'
stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
backup=home/'.local/state/omarchy/backups'/('net-pulse-'+stamp)
backup.mkdir(parents=True)
shutil.copy2(config,backup/'shell.json')
if dest.exists():shutil.copytree(dest,backup/'plugin')
if unit.exists():shutil.copy2(unit,backup/'net-pulse.service')
dest.mkdir(parents=True,exist_ok=True)
for name in ['manifest.json','Panel.qml','Model.js','NetChip.qml','HistoryGraph.qml','net_pulse.py','README.md']:
    shutil.copy2(source/name,dest/name)
unit.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(source/'net-pulse.service',unit)
# Read after copying, minimizing the time between config read and atomic write.
data=json.loads(config.read_text())
layout=data['bar']['layout']
entry={'id':'nixfred.net-pulse','displayMode':0,'animated':True}
def ident(e):return e.get('id') if isinstance(e,dict) else e
sections=('left','center','right')
# A reinstall must not shuffle the bar: an entry that already exists is rewritten
# where it sits, keeping the readout and animation the user chose.
present=any(ident(e)=='nixfred.net-pulse' for section in sections for e in layout.get(section,[]))
replaces='nixfred.net-pulse' if present else 'omarchy.network'
placed=False
for section in sections:
    kept=[]
    for e in layout.get(section,[]):
        if ident(e)==replaces and not placed:
            merged=dict(entry)
            if isinstance(e,dict):merged.update({k:v for k,v in e.items() if k!='id'})
            kept.append(merged);placed=True;continue
        if ident(e)=='nixfred.net-pulse':continue
        kept.append(e)
    layout[section]=kept
if not placed:layout['right'].append(entry)
tmp=config.with_suffix('.net-pulse.tmp')
tmp.write_text(json.dumps(data,indent=2)+'\n');tmp.replace(config)
subprocess.run(['systemctl','--user','daemon-reload'],check=True)
subprocess.run(['systemctl','--user','enable','--now','net-pulse.service'],check=True)
subprocess.run(['systemctl','--user','restart','net-pulse.service'],check=True)
subprocess.run(['omarchy-shell','shell','rescanPlugins'],check=True)
print('Installed Net Pulse'+(' in its existing bar slot' if present else ' in place of omarchy.network' if placed else ' at the far right')+'. Backup: '+str(backup))
