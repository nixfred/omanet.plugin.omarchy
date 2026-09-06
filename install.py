#!/usr/bin/env python3
"""Install Net Pulse with timestamped rollback copies; take the stock network widget's bar slot, preserve everything else."""
from pathlib import Path
import datetime
import json
import os
import shutil
import subprocess

FILES = ['manifest.json', 'Panel.qml', 'Model.js', 'NetChip.qml', 'HistoryGraph.qml', 'net_pulse.py', 'README.md']
source = Path(__file__).resolve().parent
home = Path.home()
config = home / '.config/omarchy/shell.json'
dest = home / '.config/omarchy/plugins/nixfred.net-pulse'
unit = home / '.config/systemd/user/net-pulse.service'
entry = {'id': 'nixfred.net-pulse', 'displayMode': 0, 'animated': True}
SECTIONS = ('left', 'center', 'right')


def ident(e):
    return e.get('id') if isinstance(e, dict) else e


def place(layout):
    """Put the widget in the bar. Returns where it landed, for the closing message.

    A reinstall must not shuffle the bar: an entry that already exists is
    rewritten where it sits, keeping the readout and animation the user chose.
    Otherwise it takes the stock network widget's slot, or goes to the far right.
    """
    present = any(ident(e) == 'nixfred.net-pulse' for s in SECTIONS for e in layout.get(s, []))
    replaces = 'nixfred.net-pulse' if present else 'omarchy.network'
    placed = False
    for section in SECTIONS:
        kept = []
        for e in layout.get(section, []):
            if ident(e) == replaces and not placed:
                merged = dict(entry)
                if isinstance(e, dict):
                    merged.update({k: v for k, v in e.items() if k != 'id'})
                kept.append(merged)
                placed = True
                continue
            if ident(e) == 'nixfred.net-pulse':
                continue
            kept.append(e)
        layout[section] = kept
    if not placed:
        layout['right'].append(entry)
    return ' in its existing bar slot' if present else ' in place of omarchy.network' if placed else ' at the far right'


def load_config():
    try:
        data = json.loads(config.read_text())
    except ValueError as e:
        raise SystemExit('shell.json is not valid JSON, nothing was changed: ' + str(e))
    if not isinstance(data.get('bar'), dict) or not isinstance(data['bar'].get('layout'), dict):
        raise SystemExit('shell.json has no bar.layout, nothing was changed.')
    return data


# Validate before touching anything. Copying first left a half-upgraded plugin
# behind whenever the config turned out to be unusable.
missing = [n for n in FILES + ['net-pulse.service'] if not (source / n).is_file()]
if missing:
    raise SystemExit('Incomplete source tree, nothing was changed. Missing: ' + ', '.join(missing))
if not config.is_file():
    raise SystemExit('No ' + str(config) + '; is this an Omarchy shell? Nothing was changed.')
load_config()

stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
backup = home / '.local/state/omarchy/backups' / ('net-pulse-' + stamp)
backup.mkdir(parents=True)
shutil.copy2(config, backup / 'shell.json')
if dest.exists():
    shutil.copytree(dest, backup / 'plugin')
if unit.exists():
    shutil.copy2(unit, backup / 'net-pulse.service')

dest.mkdir(parents=True, exist_ok=True)
for name in FILES:
    shutil.copy2(source / name, dest / name)
unit.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(source / 'net-pulse.service', unit)

# Re-read immediately before writing. The shell saves its own bar edits, and the
# copy validated above is now several file copies old. A unique temporary name
# keeps two installers from truncating each other's file.
data = load_config()
where = place(data['bar']['layout'])
tmp = config.with_suffix('.net-pulse.%d.tmp' % os.getpid())
tmp.write_text(json.dumps(data, indent=2) + '\n')
tmp.replace(config)

failed = []
for args, what in [(['systemctl', '--user', 'daemon-reload'], 'reload systemd'),
                   (['systemctl', '--user', 'enable', '--now', 'net-pulse.service'], 'enable net-pulse.service'),
                   (['systemctl', '--user', 'restart', 'net-pulse.service'], 'restart net-pulse.service'),
                   (['omarchy-shell', 'shell', 'rescanPlugins'], 'tell the shell to rescan plugins')]:
    try:
        if subprocess.run(args, capture_output=True).returncode:
            failed.append(what)
    except OSError:
        failed.append(what)

print('Installed Net Pulse' + where + '. Backup: ' + str(backup))
if failed:
    print('The bar was updated but these steps did not complete: ' + '; '.join(failed))
    print('There will be no telemetry until net-pulse.service runs. Restore ' + str(backup / 'shell.json') + ' to undo the bar change.')
