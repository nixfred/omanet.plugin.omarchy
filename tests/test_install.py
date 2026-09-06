import datetime
import json
from pathlib import Path
import runpy
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


if __name__ == '__main__':
    unittest.main()
