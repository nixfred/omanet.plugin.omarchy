import datetime
import json
from pathlib import Path
import re
import runpy
import shutil
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1]


def install_into(home, layout, times):
    config = home / '.config/omarchy/shell.json'
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(json.dumps({'bar': {'layout': layout}, 'unrelated': True}))
    with patch.object(Path, 'home', return_value=home), patch('subprocess.run'), \
         patch('datetime.datetime') as clock, patch('builtins.print'):
        clock.now.side_effect = times
        for _ in times:
            runpy.run_path(str(SOURCE / 'install.py'))
    return json.loads(config.read_text())


class InstallTests(unittest.TestCase):
    def test_takes_the_stock_network_slot_and_survives_a_repeat_install(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            times = [datetime.datetime(2026, 9, 5, 12, 0, 0, i) for i in (1, 2)]
            data = install_into(home, {
                'left': ['omarchy.clock'],
                'right': [{'id': 'omarchy.tailscale'}, {'id': 'omarchy.network'}, {'id': 'omarchy.monitor'}],
            }, times)
            self.assertTrue(data['unrelated'])
            # The widget lands exactly where the stock one was, and nothing else moves.
            self.assertEqual(data['bar']['layout']['right'], [
                {'id': 'omarchy.tailscale'},
                {'id': 'nixfred.net-pulse', 'displayMode': 0, 'animated': True},
                {'id': 'omarchy.monitor'},
            ])
            self.assertEqual(data['bar']['layout']['left'], ['omarchy.clock'])
            self.assertEqual(data['bar']['layout']['center'], [])
            self.assertEqual(len(list((home / '.local/state/omarchy/backups').iterdir())), 2)

    def test_bare_string_entry_is_upgraded_in_place(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            data = install_into(home, {
                'left': ['omarchy.clock', 'nixfred.net-pulse'],
                'right': [{'id': 'another.plugin', 'option': 42}],
            }, [datetime.datetime(2026, 9, 5, 12, 0, 0, 3)])
            # A string entry becomes a settings object without leaving its section.
            self.assertEqual(data['bar']['layout']['left'], [
                'omarchy.clock',
                {'id': 'nixfred.net-pulse', 'displayMode': 0, 'animated': True},
            ])
            self.assertEqual(data['bar']['layout']['right'], [{'id': 'another.plugin', 'option': 42}])
            self.assertEqual(data['bar']['layout']['center'], [])

    def test_appends_when_neither_widget_is_in_the_bar(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            data = install_into(home, {'right': [{'id': 'another.plugin', 'option': 42}]},
                                [datetime.datetime(2026, 9, 5, 12, 0, 0, 8)])
            self.assertEqual(data['bar']['layout']['right'], [
                {'id': 'another.plugin', 'option': 42},
                {'id': 'nixfred.net-pulse', 'displayMode': 0, 'animated': True},
            ])

    def test_reinstall_keeps_the_slot_and_the_saved_readout(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            layout = {'right': [{'id': 'nixfred.net-pulse', 'displayMode': 3, 'animated': False},
                                {'id': 'omarchy.monitor'}]}
            data = install_into(home, layout, [datetime.datetime(2026, 9, 5, 12, 0, 0, 9)])
            # The widget stays first and keeps the mode the user picked.
            self.assertEqual(data['bar']['layout']['right'], [
                {'id': 'nixfred.net-pulse', 'displayMode': 3, 'animated': False},
                {'id': 'omarchy.monitor'},
            ])

    def test_backup_captures_the_layout_before_the_change(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            install_into(home, {'right': [{'id': 'omarchy.network'}]}, [datetime.datetime(2026, 9, 5, 12, 0, 0, 4)])
            backup = next((home / '.local/state/omarchy/backups').iterdir())
            saved = json.loads((backup / 'shell.json').read_text())
            self.assertEqual(saved['bar']['layout']['right'], [{'id': 'omarchy.network'}])


class GuardTests(unittest.TestCase):
    def refuse(self, home, text):
        config = home / '.config/omarchy/shell.json'
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text(text)
        with patch.object(Path, 'home', return_value=home), patch('subprocess.run'), \
             patch('datetime.datetime') as clock, patch('builtins.print'):
            clock.now.return_value = datetime.datetime(2026, 9, 5, 12, 0, 0, 7)
            with self.assertRaises(SystemExit):
                runpy.run_path(str(SOURCE / 'install.py'))
        # Nothing at all was touched: no backup, no plugin files, no service unit.
        self.assertEqual(config.read_text(), text)
        self.assertFalse((home / '.local/state/omarchy/backups').exists())
        self.assertFalse((home / '.config/omarchy/plugins/nixfred.net-pulse').exists())
        self.assertFalse((home / '.config/systemd/user/net-pulse.service').exists())

    def test_unusable_config_is_refused_before_anything_is_installed(self):
        with tempfile.TemporaryDirectory() as d:
            self.refuse(Path(d), json.dumps({'idle': {}}))
        with tempfile.TemporaryDirectory() as d:
            self.refuse(Path(d), '{not json')

    def test_a_bar_edit_made_during_install_is_not_overwritten(self):
        # The shell saves its own layout changes; the installer must merge into
        # whatever is on disk when it writes, not the copy it validated earlier.
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            config = home / '.config/omarchy/shell.json'
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({'bar': {'layout': {'right': [{'id': 'omarchy.network'}]}}}))
            real_copy = shutil.copy2

            def copy_then_edit(src, dst, *a, **kw):
                out = real_copy(src, dst, *a, **kw)
                if Path(dst).name == 'manifest.json':
                    live = json.loads(config.read_text())
                    live['bar']['layout']['right'].append({'id': 'someone.else'})
                    config.write_text(json.dumps(live))
                return out
            with patch.object(Path, 'home', return_value=home), patch('subprocess.run'), \
                 patch('shutil.copy2', side_effect=copy_then_edit), \
                 patch('datetime.datetime') as clock, patch('builtins.print'):
                clock.now.return_value = datetime.datetime(2026, 9, 5, 12, 0, 0, 11)
                runpy.run_path(str(SOURCE / 'install.py'))
            right = json.loads(config.read_text())['bar']['layout']['right']
            self.assertEqual([e['id'] for e in right], ['nixfred.net-pulse', 'someone.else'])


class AboutTests(unittest.TestCase):
    def test_the_manifest_carries_what_the_about_tab_shows(self):
        manifest = json.loads((SOURCE / 'manifest.json').read_text())
        self.assertRegex(manifest['version'], r'^\d+\.\d+\.\d+$')
        self.assertEqual(manifest['repository'], 'https://github.com/nixfred/omanet.plugin.omarchy')
        self.assertEqual(manifest['homepage'], 'https://nixfred.com')

    def test_the_about_fallbacks_agree_with_the_manifest(self):
        # The panel prefers the plugin registry; these constants are what it
        # shows when the registry is unreachable, so they must not drift.
        panel = (SOURCE / 'Panel.qml').read_text()
        manifest = json.loads((SOURCE / 'manifest.json').read_text())
        for field, key in [('version', 'version'), ('repoUrl', 'repository'), ('siteUrl', 'homepage')]:
            fallback = re.search(r"readonly property string %s:.* : '([^']+)'" % field, panel).group(1)
            self.assertEqual(fallback, manifest[key], field)
        self.assertIn("'About'", panel)


if __name__ == '__main__':
    unittest.main()
