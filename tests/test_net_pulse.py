import importlib.util
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('net', Path(__file__).resolve().parents[1] / 'net_pulse.py')
net = importlib.util.module_from_spec(spec)
spec.loader.exec_module(net)


class CounterTests(unittest.TestCase):
    SAMPLE = ('Inter-|   Receive                                                |  Transmit\n'
              ' face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop\n'
              '    lo:  100 2 0 0 0 0 0 0  100 2 0 0 0 0 0 0\n'
              'wlp2s0: 1000 10 1 2 0 0 0 0  500 5 3 4 0 0 0 0\n')

    def test_interface_counters_parsed_per_direction(self):
        d = net.netdev(self.SAMPLE)
        self.assertEqual(d['wlp2s0']['rx'], 1000)
        self.assertEqual(d['wlp2s0']['tx'], 500)
        self.assertEqual(d['wlp2s0']['rxErrors'], 1)
        self.assertEqual(d['wlp2s0']['txDropped'], 4)
        self.assertIn('lo', d)

    def test_counter_reset_and_new_interface_read_zero_not_negative(self):
        before = net.netdev(self.SAMPLE)
        after = net.netdev(self.SAMPLE.replace('1000 10 1 2', '4 10 1 2'))
        r = net.rates(before, after, 2.0)
        self.assertEqual(r['wlp2s0']['rx'], 0)
        self.assertEqual(net.rates({}, after, 2.0)['wlp2s0']['tx'], 0)
        self.assertEqual(net.rates(before, after, 0)['wlp2s0']['rx'], 0)

    def test_rate_is_bytes_per_second(self):
        after = net.netdev(self.SAMPLE.replace('1000 10 1 2', '3000 10 1 2'))
        self.assertEqual(net.rates(net.netdev(self.SAMPLE), after, 2.0)['wlp2s0']['rx'], 1000.0)


class WifiTests(unittest.TestCase):
    LINK = ('Connected to da:b3:70:d9:ce:c5 (on wlp2s0)\n\tSSID: ILoveMyWifi\n\tfreq: 5805.0\n'
            '\tsignal: -50 dBm\n\trx bitrate: 324.0 MBit/s VHT-MCS 8 40MHz VHT-NSS 2\n'
            '\ttx bitrate: 400.0 MBit/s VHT-MCS 9 40MHz short GI VHT-NSS 2\n')
    STATION = ('Station da:b3:70:d9:ce:c5 (on wlp2s0)\n\tsignal avg:\t-46 [-46, -54] dBm\n'
               '\ttx retries:\t7\n\ttx failed:\t2\n\tbeacon loss:\t1\n\tconnected time:\t3680 seconds\n'
               '\trx bytes:\t989337984\n\ttx bytes:\t254430028\n')
    INFO = '\tchannel 161 (5805 MHz), width: 40 MHz, center1: 5795 MHz\n\ttxpower 30.00 dBm\n'

    def test_association_detail(self):
        w = net.wifi_link('wlp2s0', self.LINK, self.STATION, self.INFO)
        self.assertEqual(w['ssid'], 'ILoveMyWifi')
        self.assertEqual(w['bssid'], 'da:b3:70:d9:ce:c5')
        self.assertEqual(w['channel'], 161)
        self.assertEqual(w['width'], 40)
        self.assertEqual(w['signal'], -50)
        self.assertEqual(w['signalAvg'], -46)
        self.assertEqual(w['txBitrate'], 400.0)
        self.assertEqual(w['rxBitrate'], 324.0)
        self.assertEqual(w['generation'], 'Wi-Fi 5')
        self.assertEqual(w['txPower'], 30.0)
        self.assertEqual(w['retries'], 7)
        self.assertEqual(w['connectedSeconds'], 3680)
        # -50 dBm maps to a 100-point quality scale, not a raw percentage of dBm.
        self.assertEqual(w['quality'], 100)

    def test_disconnected_radio_reports_nothing_rather_than_zero(self):
        self.assertEqual(net.wifi_link('wlp2s0', 'Not connected.', '', ''), {})

    def test_generation_follows_the_phy_mode(self):
        for mode, gen in [('EHT-MCS 13', 'Wi-Fi 7'), ('HE-MCS 11', 'Wi-Fi 6'), ('VHT-MCS 9', 'Wi-Fi 5'), ('MCS 15', 'Wi-Fi 4'), ('', 'legacy')]:
            self.assertEqual(net.parse_bitrate('100.0 MBit/s ' + mode)['generation'], gen)

    def test_band_boundaries(self):
        self.assertEqual(net.band_for(2462), '2.4 GHz')
        self.assertEqual(net.band_for(5805), '5 GHz')
        self.assertEqual(net.band_for(5975), '6 GHz')
        self.assertEqual(net.band_for(None), '')

    def test_scan_groups_by_ssid_and_keeps_the_strongest_ap(self):
        raw = ('*:AA\\:11:Home:Infra:161:5805 MHz:1170 Mbit/s:80 MHz:70:WPA2\n'
               ' :BB\\:22:Home:Infra:6:2437 MHz:130 Mbit/s:20 MHz:90:WPA2\n'
               ' :CC\\:33::Infra:1:2412 MHz:130 Mbit/s:20 MHz:40:\n')
        rows = net.wifi_list(raw)
        self.assertEqual(len(rows), 2)
        home = rows[0]
        self.assertEqual(home['ssid'], 'Home')
        self.assertEqual(home['aps'], 2)
        self.assertTrue(home['inUse'])
        # The connected access point wins over a stronger one the radio is not on.
        self.assertEqual(home['channel'], 161)
        self.assertEqual(sorted(home['bands']), ['2.4 GHz', '5 GHz'])
        hidden = rows[1]
        self.assertTrue(hidden['hidden'])
        self.assertEqual(hidden['security'], 'Open')

    def test_escaped_colons_in_nmcli_output(self):
        self.assertEqual(net.nm_split('a\\:b:c'), ['a:b', 'c'])


class ResolverTests(unittest.TestCase):
    def test_links_servers_and_domains(self):
        raw = ('Global\n           Protocols: -LLMNR -mDNS DNSSEC=no/unsupported\n'
               'Fallback DNS Servers: 9.9.9.9#dns.quad9.net\n                      1.1.1.1#cloudflare-dns.com\n\n'
               'Link 2 (wlp2s0)\n    Current Scopes: DNS\n         Protocols: +DefaultRoute DNSSEC=no/unsupported\n'
               'Current DNS Server: 8.8.8.8\n       DNS Servers: 9.9.9.9 8.8.8.8\n'
               '        DNS Domain: nixnet.me\n     Default Route: yes\n')
        links = net.resolve_status(raw)
        self.assertEqual([l['name'] for l in links], ['Global', 'wlp2s0'])
        link = links[1]
        self.assertEqual(link['current'], '8.8.8.8')
        self.assertEqual(link['servers'], ['9.9.9.9', '8.8.8.8'])
        self.assertEqual(link['domains'], ['nixnet.me'])
        self.assertTrue(link['defaultRoute'])
        # A wrapped continuation line belongs to the key above it, not to a new key.
        self.assertIn('1.1.1.1#cloudflare-dns.com', links[0]['servers'])


class LocaleTests(unittest.TestCase):
    def test_parsed_commands_run_in_the_c_locale(self):
        # A translated "enabled"/"connected" would otherwise change decisions.
        self.assertEqual(net.C_LOCALE['LC_ALL'], 'C')
        with patch.object(net.subprocess, 'run') as run:
            run.return_value = type('P', (), {'stdout': '', 'returncode': 0})()
            net.run(['nmcli', '-t', 'general'])
        self.assertEqual(run.call_args.kwargs['env']['LC_ALL'], 'C')


class SocketTests(unittest.TestCase):
    RAW = ('tcp   ESTAB 0 0 10.0.0.22:1  1.1.1.1:443 users:(("brave",pid=10,fd=1))\n'
           'tcp   ESTAB 0 0 10.0.0.22:2  1.1.1.1:443 users:(("brave",pid=10,fd=2))\n'
           'tcp   SYN-SENT 0 0 10.0.0.22:3 9.9.9.9:443 users:(("brave",pid=10,fd=3))\n'
           'udp   UNCONN 0 0 10.0.0.22:5  10.0.0.1:53 users:(("resolved",pid=11,fd=4))\n'
           'tcp   ESTAB 0 0 10.0.0.22:6  100.64.0.5:22\n'
           'tcp   ESTAB 0 0 10.0.0.22:7  192.168.1.9:80 users:(("curl",pid=12,fd=5))\n')

    def test_grouping_states_and_ownerless_sockets(self):
        with patch.object(net, 'process', return_value=None):
            t = net.talkers(self.RAW, 'x\ny\n')
        rows = {r['name']: r for r in t['rows']}
        # A half-open TCP socket is not an established connection.
        self.assertEqual(rows['brave']['count'], 2)
        self.assertEqual(rows['brave']['tcp'], 2)
        self.assertEqual(rows['resolved']['udp'], 1)
        self.assertEqual(t['anonymous'], 1)
        self.assertEqual(t['total'], 5)
        self.assertEqual(t['listening'], 2)

    def test_remote_hosts_are_classified(self):
        self.assertEqual(net.host_kind('1.1.1.1'), 'internet')
        self.assertEqual(net.host_kind('192.168.1.9'), 'LAN')
        self.assertEqual(net.host_kind('10.0.0.1'), 'LAN')
        self.assertEqual(net.host_kind('172.16.4.4'), 'LAN')
        self.assertEqual(net.host_kind('172.32.4.4'), 'internet')
        self.assertEqual(net.host_kind('100.101.176.48'), 'tailnet')
        self.assertEqual(net.host_kind('100.200.1.1'), 'internet')
        self.assertEqual(net.host_kind('127.0.0.1'), 'loopback')

    def test_one_socket_on_two_descriptors_counts_once(self):
        raw = 'tcp ESTAB 0 0 10.0.0.22:1 1.1.1.1:443 users:(("app",pid=123,fd=3),("app",pid=123,fd=4))\n'
        with patch.object(net, 'process', return_value=None):
            t = net.talkers(raw, '')
        self.assertEqual(t['total'], 1)
        self.assertEqual(t['rows'][0]['count'], 1)
        self.assertEqual(t['rows'][0]['remotes'][0]['count'], 1)

    def test_ipv6_peer_host_extraction(self):
        self.assertEqual(net.peer_host('[2606:4700::1111]:443'), '2606:4700::1111')
        self.assertEqual(net.peer_host('10.0.0.1:53'), '10.0.0.1')
        self.assertEqual(net.peer_host('[fe80::1%wlp2s0]:53'), 'fe80::1')

    def test_tcp_counters_and_socket_pools(self):
        snmp = ('Tcp: RtoAlgorithm ActiveOpens PassiveOpens CurrEstab RetransSegs\n'
                'Tcp: 1 41696 187 73 14527\n')
        s = net.tcp_stats(snmp, 'TCP: inuse 81 orphan 0 tw 55 alloc 84 mem 0\nUDP: inuse 10 mem 1088\n',
                          'TCP6: inuse 7\nUDP6: inuse 3\n')
        self.assertEqual(s['CurrEstab'], 73)
        self.assertEqual(s['RetransSegs'], 14527)
        # IPv6 sockets count too, but the shared alloc/mem figures must not.
        self.assertEqual(s['tcpInuse'], 88)
        self.assertEqual(s['udpInuse'], 13)
        self.assertEqual(s['tcpAlloc'], 84)


class EscapingTests(unittest.TestCase):
    def test_connection_name_keeps_its_colon_not_its_backslash(self):
        c = net.nm_connection('01745084-b1f3-4355-ba68-54cecfd27bdd', 'connection.id:Cafe\\:East\nipv4.method:auto\n')
        self.assertEqual(c['name'], 'Cafe:East')
        self.assertEqual(c['method4'], 'auto')

    def test_wrapped_ipv6_resolver_is_a_server_not_a_field(self):
        # "fd::53" on a continuation line reads exactly like a "fd:" label.
        raw = ('Link 2 (wlp2s0)\n       DNS Servers: 2001:db8::1\n'
               '                    fd::53\n     Default Route: yes\n')
        link = net.resolve_status(raw)[0]
        self.assertEqual(link['servers'], ['2001:db8::1', 'fd::53'])
        self.assertTrue(link['defaultRoute'])


class PingTests(unittest.TestCase):
    def test_timeouts_count_as_loss_and_missing_samples_are_not_zero(self):
        self.assertIsNone(net.summarize([])['avg'])
        self.assertEqual(net.summarize([10.0, 20.0])['avg'], 15.0)
        self.assertEqual(net.summarize([10.0, -1])['loss'], 50)
        # Every probe lost is a real reading, not an absent one.
        self.assertEqual(net.summarize([-1, -1])['avg'], -1)
        self.assertEqual(net.summarize([-1, -1])['loss'], 100)

    def test_only_address_shaped_hosts_are_probed(self):
        for bad in ['', '8.8.8.8; rm -rf /', 'example.com/../x', 'a' * 60]:
            self.assertIsNone(net.ping_start(bad))


class HistoryTests(unittest.TestCase):
    def test_retention_downsampling_and_reboot_gaps(self):
        with tempfile.TemporaryDirectory() as d, patch.object(net, 'STATE', Path(d)):
            db = net.db_open()
            now = 1000000

            def add(ts, rx, boot):
                db.execute('INSERT INTO samples VALUES(?,?,?,?,?,?,?,?)', (ts, rx, 10.0, 12.0, 70.0, 'wlp2s0', boot, net.HISTORY_INTERVAL))
            add(now - 604900, 5.0, 'old')
            add(now - 20, 100.0, 'a')
            add(now - 18, 900.0, 'a')
            add(now - 17, 50.0, 'b')
            db.commit()
            h = net.history(db, 3600, now)
            self.assertEqual(h['count'], 3)
            self.assertEqual(h['peakRx'], 900.0)
            # A reboot splits the bucket so no line is drawn across it.
            self.assertEqual({p[7] for p in h['points']}, {'a', 'b'})
            net.record(db, now, 42.0, 7.0, 11.0, 80.0, 'wlp2s0')
            self.assertEqual(db.execute('SELECT COUNT(*) FROM samples WHERE ts<?', (now - 604800,)).fetchone()[0], 0)
            db.close()
            db = net.db_open()
            self.assertEqual(net.history(db, 3600, now)['count'], 4)
            db.close()

    def test_range_totals_count_only_the_time_actually_recorded(self):
        # A sparse bucket used to be multiplied by its whole width, inventing
        # traffic for every gap: the 7-day view read double the real total.
        with tempfile.TemporaryDirectory() as d, patch.object(net, 'STATE', Path(d)):
            db = net.db_open()
            now = 1000000
            for i in range(4):
                db.execute('INSERT INTO samples VALUES(?,?,?,?,?,?,?,?)',
                           (now - 3000 + i * 16, 1000.0, 500.0, 10.0, 70.0, 'wlp2s0', 'a', 16.0))
            db.commit()
            h = net.history(db, 604800, now)
            # Four samples of 1000 B/s, each covering the 16 seconds it really
            # spanned rather than the nominal 15.
            self.assertEqual(h['count'], 4)
            self.assertEqual(h['totalRx'], 4 * 1000.0 * 16.0)
            self.assertEqual(h['totalTx'], 4 * 500.0 * 16.0)
            # The same samples must total the same however coarsely they are bucketed.
            self.assertEqual(net.history(db, 3600, now)['totalRx'], h['totalRx'])
            db.close()

    def test_the_rollup_outlives_sample_retention(self):
        # Samples are pruned after a week, so a month or a year of usage can
        # only ever come from the hourly rollup.
        with tempfile.TemporaryDirectory() as d, patch.object(net, 'STATE', Path(d)):
            db = net.db_open()
            now = 1757000000.0
            old = now - 30 * 86400
            net.record(db, old, 1000.0, 250.0, 10.0, 70.0, 'wlp2s0', 16.0)
            net.record(db, now, 2000.0, 500.0, 10.0, 70.0, 'wlp2s0', 16.0)
            # The second record is a month past the first, so retention is held
            # back; force it with a continuous write to prove the rollup stays.
            net.record(db, now + 15, 0.0, 0.0, None, None, 'wlp2s0', 15.0)
            db.execute('DELETE FROM samples WHERE ts < ?', (now - 7 * 86400,))
            db.commit()
            self.assertEqual(db.execute('SELECT COUNT(*) FROM samples WHERE ts=?', (old,)).fetchone()[0], 0)
            month = net.usage(db, 2592000, now + 15)
            self.assertAlmostEqual(month['totalRx'], 1000.0 * 16 + 2000.0 * 16)
            self.assertAlmostEqual(month['totalTx'], 250.0 * 16 + 500.0 * 16)
            db.close()

    def test_a_new_rollup_is_backfilled_from_the_samples_already_kept(self):
        with tempfile.TemporaryDirectory() as d, patch.object(net, 'STATE', Path(d)):
            db = net.db_open()
            now = 1757000000.0
            for i in range(4):
                db.execute('INSERT INTO samples VALUES(?,?,?,?,?,?,?,?)',
                           (now - 3000 + i * 16, 1000.0, 500.0, 10.0, 70.0, 'wlp2s0', 'a', 16.0))
            db.execute('DROP TABLE usage')
            db.commit()
            db.close()
            # Reopening is the upgrade path: the week of samples already on disk
            # becomes the rollup rather than the usage tab starting at zero.
            db = net.db_open()
            day = net.usage(db, 86400, now)
            self.assertAlmostEqual(day['totalRx'], 4 * 1000.0 * 16.0)
            self.assertAlmostEqual(day['totalTx'], 4 * 500.0 * 16.0)
            db.close()

    def test_usage_totals_hold_across_every_range_and_bucket(self):
        with tempfile.TemporaryDirectory() as d, patch.object(net, 'STATE', Path(d)):
            db = net.db_open()
            now = 1757000000.0
            for h in range(72):
                hour = int((now - h * 3600) // 3600) * 3600
                db.execute('INSERT INTO usage VALUES(?,?,?,?,?)', (hour, 'wlp2s0', 1e6, 2e5, 3600.0))
            db.commit()
            week = net.usage(db, 604800, now)
            self.assertAlmostEqual(week['totalRx'], 72e6)
            # However coarsely it is bucketed, the bars must sum to the total.
            for seconds in (604800, 2592000, 31536000, 0):
                u = net.usage(db, seconds, now)
                self.assertAlmostEqual(sum(p[1] for p in u['points']), u['totalRx'], msg=str(seconds))
                self.assertAlmostEqual(u['totalRx'], 72e6, msg=str(seconds))
                self.assertLessEqual(len(u['points']), 60, str(seconds))
            db.close()

    def test_coverage_never_claims_more_time_than_passed(self):
        with tempfile.TemporaryDirectory() as d, patch.object(net, 'STATE', Path(d)):
            db = net.db_open()
            now = 1757000000.0
            hour = int(now // 3600) * 3600
            # Two interfaces busy in the same hour is one hour of recording.
            for iface, rx in (('wlp2s0', 1e6), ('tailscale0', 4e5)):
                db.execute('INSERT INTO usage VALUES(?,?,?,?,?)', (hour, iface, rx, 1e5, 3600.0))
            db.commit()
            day = net.usage(db, 86400, now)
            self.assertLessEqual(day['recorded'], 3600.0)
            self.assertLessEqual(day['recorded'], day['seconds'])
            # Busiest interface first, so the heavy one is the row you read.
            self.assertEqual([i[0] for i in day['ifaces']], ['wlp2s0', 'tailscale0'])
            # A year of window with an hour of data must stay an hour of data.
            self.assertLessEqual(net.usage(db, 31536000, now)['recorded'], 3600.0)
            db.close()

    def test_daily_buckets_start_at_local_midnight(self):
        with tempfile.TemporaryDirectory() as d, patch.object(net, 'STATE', Path(d)):
            db = net.db_open()
            now = 1757000000.0
            for h in range(96):
                hour = int((now - h * 3600) // 3600) * 3600
                db.execute('INSERT INTO usage VALUES(?,?,?,?,?)', (hour, 'wlp2s0', 1e6, 1e5, 3600.0))
            db.commit()
            for point in net.usage(db, 2592000, now)['points'][1:]:
                local = time.localtime(point[0])
                self.assertEqual((local.tm_hour, local.tm_min), (0, 0), time.ctime(point[0]))
            db.close()

    def test_an_empty_database_still_answers_every_range(self):
        with tempfile.TemporaryDirectory() as d, patch.object(net, 'STATE', Path(d)):
            db = net.db_open()
            for seconds in net.USAGE_RANGES:
                u = net.usage(db, seconds, 1757000000.0)
                self.assertEqual(u['points'], [])
                self.assertEqual(u['totalRx'], 0)
                self.assertEqual(u['recorded'], 0)
                self.assertIsNone(u['first'])
                self.assertGreater(u['bucket'], 0)
                self.assertGreater(u['seconds'], 0)
            db.close()

    def test_absent_latency_is_stored_as_null(self):
        with tempfile.TemporaryDirectory() as d, patch.object(net, 'STATE', Path(d)):
            db = net.db_open()
            net.record(db, 100.0, 1.0, 2.0, None, None, 'wlp2s0')
            row = net.history(db, 3600, 100.0)['points'][0]
            self.assertIsNone(row[4])
            self.assertIsNone(row[5])
            db.close()


class ActionTests(unittest.TestCase):
    def test_only_known_dns_providers_and_bands_are_accepted(self):
        with patch.object(net.subprocess, 'run') as run:
            for bad in ['Quad9', 'DHCP; reboot', '']:
                with self.assertRaises(RuntimeError):
                    net.action_dns(bad)
            for bad in ['7', 'auto; reboot', '']:
                with self.assertRaises(RuntimeError):
                    net.action_band(bad)
            run.assert_not_called()

    def test_connection_actions_require_a_uuid_and_a_known_direction(self):
        with patch.object(net.subprocess, 'run') as run:
            with self.assertRaises(RuntimeError):
                net.action_connection('up', 'not-a-uuid')
            with self.assertRaises(RuntimeError):
                net.action_connection('delete', '01745084-b1f3-4355-ba68-54cecfd27bdd')
            with self.assertRaises(RuntimeError):
                net.action_autoconnect('01745084-b1f3-4355-ba68-54cecfd27bdd', 'maybe')
            run.assert_not_called()

    def test_public_ip_rejects_a_non_address_reply(self):
        with patch.object(net, 'run', return_value='<html>go away</html>'):
            with self.assertRaises(RuntimeError):
                net.action_public_ip()

    def test_recycled_pid_cannot_focus(self):
        with patch.object(net, 'process', return_value={'start': 'new'}), patch.object(net, 'run') as run:
            with self.assertRaises(RuntimeError):
                net.focus(100, 'old')
            run.assert_not_called()

    def test_environment_allowlist_keeps_credentials_out(self):
        with patch.object(net, 'read', return_value='TOKEN=secret\0HERDR_PANE_ID=w1:p2\0PASSWORD=hunter2\0'):
            self.assertEqual(net.environment(1), {'HERDR_PANE_ID': 'w1:p2'})

    def test_ancestry_cycle_is_bounded(self):
        self.assertIsNone(net.window_for(5, {5: {'ppid': 6}, 6: {'ppid': 5}}, {}))
        self.assertEqual(net.window_for(5, {5: {'ppid': 6}}, {6: {'address': '0xabc'}})['address'], '0xabc')

    def test_unknown_action_rejected(self):
        p = subprocess.run(['python3', str(Path(net.__file__)), 'disconnect-everything'], capture_output=True)
        self.assertEqual(p.returncode, 2)


if __name__ == '__main__':
    unittest.main()
