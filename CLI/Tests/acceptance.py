#!/usr/bin/env python3
import json
from datetime import datetime, timedelta, timezone
import plistlib
import shutil
import os
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from urllib.parse import urlsplit, parse_qs

HELPER = Path(sys.argv.pop(1)).resolve()

class CommandHelperAcceptance(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.app = self.root / 'Always On.app'
        self.helper = self.make_app(self.app, '2.3', '45')
        self.log = self.root / 'opens.jsonl'
        fake = self.root / 'open'
        fake.write_text(
            '#!/usr/bin/env python3\n'
            'import json, os, sys\n'
            'with open(os.environ["OPEN_LOG"], "a") as f: f.write(json.dumps(sys.argv[1:]) + "\\n")\n'
            'if os.environ.get("OPEN_STATUS"):\n'
            '    path = os.path.join(os.environ["HOME"], "Library/Application Support/AlwaysOn/status.json")\n'
            '    os.makedirs(os.path.dirname(path), exist_ok=True)\n'
            '    with open(path, "w") as f: f.write(os.environ["OPEN_STATUS"])\n'
            'key = "OPEN_FINISH_EXIT" if sys.argv[-1].startswith("alwayson://finish?") else "OPEN_EXIT"\n'
            'sys.exit(int(os.environ.get(key, "0")))\n')
        fake.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.root), PATH=str(self.root) + os.pathsep + os.environ.get('PATH', ''), OPEN_LOG=str(self.log), ALWAYSON_URL_OPENER=str(fake))

    def make_app(self, app, version, build):
        helper = app / 'Contents/Helpers/alwayson'
        helper.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(HELPER, helper)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.alwayson.app',
            'CFBundleShortVersionString': version, 'CFBundleVersion': build}))
        return helper

    def test_version_and_exact_app_routing(self):
        directory = self.root / 'bin'
        self.assertEqual(self.invoke('install', '--directory', str(directory)).returncode, 0)
        env = dict(self.env, PATH=str(directory) + os.pathsep + self.env['PATH'])
        def version():
            return subprocess.run(['alwayson', '--version'], env=env, text=True, capture_output=True)
        self.assertEqual(version().stdout, 'AlwaysOn 2.3 (45)\n')
        info = self.app / 'Contents/Info.plist'
        data = plistlib.loads(info.read_bytes())
        data.update(CFBundleShortVersionString='2.4', CFBundleVersion='46')
        info.write_bytes(plistlib.dumps(data))
        self.assertEqual(version().stdout, 'AlwaysOn 2.4 (46)\n')
        other_app = self.root / 'Other App.app'
        other = self.make_app(other_app, '9.0', '99')
        self.assertEqual(subprocess.run([str(other), 'version'], env=env, capture_output=True, text=True).stdout,
                         'AlwaysOn 9.0 (99)\n')
        self.assertEqual(subprocess.run([str(other), 'start'], env=env).returncode, 0)
        self.assertEqual(self.events()[-1], ['-a', str(other_app), 'alwayson://start'])
        self.assertEqual(self.invoke('start').returncode, 0)
        self.assertEqual(self.events()[-1], ['-a', str(self.app), 'alwayson://start'])
        # Explicit install can repoint a verified bundle; uninstall cannot remove another app's link.
        self.assertNotEqual(subprocess.run([str(other), 'uninstall', '--directory', str(directory)], env=env,
                                         capture_output=True).returncode, 0)
        self.assertEqual(subprocess.run([str(other), 'install', '--directory', str(directory)], env=env).returncode, 0)
        self.assertEqual((directory / 'alwayson').resolve(), other)

    def test_unbundled_refuses_install_and_controls(self):
        unbundled = self.root / 'unbundled-alwayson'
        shutil.copy2(HELPER, unbundled)
        for action in ['install', 'uninstall', 'start', 'run']:
            args = [str(unbundled), action]
            if action == 'run': args += ['--', sys.executable, '-c', 'print("unexpected")']
            result = subprocess.run(args, env=self.env, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('full AlwaysOn app', result.stderr)
        self.assertEqual(self.events(), [])
        result = subprocess.run([str(unbundled), '--version'], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.stdout, 'AlwaysOn development/unbundled (no app version)\n')

    def test_uninstall_idempotent_and_preserves_conflicts(self):
        directory = self.root / 'bin'
        args = ['--directory', str(directory)]
        self.assertEqual(self.invoke('uninstall', *args).returncode, 0)
        self.assertEqual(self.invoke('install', *args).returncode, 0)
        link = directory / 'alwayson'
        self.assertEqual(self.invoke('uninstall', *args).returncode, 0)
        self.assertFalse(link.is_symlink())
        self.assertEqual(self.invoke('uninstall', *args).returncode, 0)
        link.write_text('preserve')
        self.assertNotEqual(self.invoke('uninstall', *args).returncode, 0)
        self.assertEqual(link.read_text(), 'preserve')
        link.unlink()
        link.symlink_to('/unrelated/missing')
        self.assertNotEqual(self.invoke('uninstall', *args).returncode, 0)
        self.assertEqual(os.readlink(link), '/unrelated/missing')

    def invoke(self, *args, **kwargs):
        kwargs.setdefault('env', self.env)
        return subprocess.run([str(self.helper), *args], text=True, capture_output=True, **kwargs)

    def events(self):
        events = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        # Foundation and Python use different canonical spellings for macOS /tmp.
        # Compare the actual application directory, preserving flags and URL payloads.
        for event in events:
            if len(event) == 3 and event[0] == '-a':
                event[1] = str(Path(event[1]).resolve())
        return events

    def token(self, event, action):
        self.assertEqual(event[:2], ["-a", str(self.app)])
        self.assertEqual(len(event), 3)
        url = urlsplit(event[-1])
        self.assertEqual((url.scheme, url.netloc, url.path, url.fragment), ('alwayson', action, '', ''))
        query = parse_qs(url.query, strict_parsing=True)
        self.assertEqual(set(query), {'token'})
        self.assertEqual(len(query['token']), 1)
        value = query['token'][0]
        uuid.UUID(value)
        return value

    def pair(self, events):
        self.assertEqual(len(events), 2)
        self.assertEqual(self.token(events[0], 'run'), self.token(events[1], 'finish'))

    def status_json(self, **fields):
        status = {'version': 1, 'pid': os.getpid(), 'state': 'active',
                  'source': 'timer', 'endsAt': '2100-01-01T00:00:00Z', 'isSuspended': False,
                  'hasAccessibilityPermission': True, 'profile': 'Work', 'profiles': ['Work', 'Deep Home']}
        status.update(fields)
        return json.dumps({key: value for key, value in status.items() if value is not None})

    def write_status(self, pid=None, **fields):
        status = {'version': 1, 'pid': os.getpid() if pid is None else pid, 'state': 'active',
                  'source': 'timer', 'endsAt': '2100-01-01T00:00:00Z', 'isSuspended': False,
                  'hasAccessibilityPermission': True, 'profile': 'Work', 'profiles': ['Work', 'Deep Home']}
        status.update(fields)
        path = self.root / 'Library/Application Support/AlwaysOn/status.json'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({key: value for key, value in status.items() if value is not None}))
        return path

    def dead_pid(self):
        proc = subprocess.Popen([sys.executable, '-c', 'pass'])
        proc.wait()
        return proc.pid

    def test_public_requests(self):
        for args, expected in [(('start',), 'alwayson://start'),
                               (('stop',), 'alwayson://stop'),
                               (('toggle',), 'alwayson://toggle'),
                               (('timer', '30'), 'alwayson://timer?minutes=30'),
                               (('pause',), 'alwayson://pause'),
                               (('pause', '15'), 'alwayson://pause?minutes=15'),
                               (('resume',), 'alwayson://resume'),
                               (('add', '15'), 'alwayson://add?minutes=15')]:
            result = self.invoke(*args)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('request', result.stdout)
            self.assertEqual(self.events()[-1], ["-a", str(self.app), expected])
        result = self.invoke('until', '2100-01-01T00:00:00Z')
        self.assertEqual(result.returncode, 0, result.stderr)
        url = urlsplit(self.events()[-1][-1])
        self.assertEqual(url.netloc, 'until')
        self.assertEqual(parse_qs(url.query), {'date': ['2100-01-01T00:00:00Z']})

    def test_invalid_requests_do_not_launch(self):
        for args in [(), ('unknown',), ('start', 'extra'), ('run', '--'),
                     ('timer', '0'), ('timer', '1441'), ('timer', '1.5'),
                     ('timer', '+1'), ('until', '00:00'), ('until', '25:00'),
                     ('pause', '0'), ('pause', '1441'), ('pause', '1.5'), ('pause', '5', '6'),
                     ('resume', 'x'), ('add',), ('add', '0'), ('add', '1441'), ('add', '1.5'), ('add', '5', '6'),
                     ('until', '2000-01-01T00:00:00Z'), ('until', 'nope'),
                     ('status', 'extra'), ('status', '--json', 'extra'),
                     ('profile', 'a', 'b'), ('profile', ' ')]:
            self.assertNotEqual(self.invoke(*args).returncode, 0, args)
        self.assertEqual(self.events(), [])
        self.assertEqual(self.invoke('help').returncode, 0)

    def test_resume_and_add_are_confirmed(self):
        self.write_status(state='paused', source='manual', endsAt=None)
        result = self.invoke('resume', env=dict(self.env, OPEN_STATUS=self.status_json(source='manual', endsAt=None)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.write_status(source='timer', endsAt=self.iso(30))
        result = self.invoke('add', '15', env=dict(self.env, OPEN_STATUS=self.status_json(source='timer', endsAt=self.iso(45))))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_stdin_is_inherited(self):
        result = self.invoke('run', '--', sys.executable, '-c',
                             'import sys; print(sys.stdin.read().upper())', input='hello')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'HELLO\n')
        self.pair(self.events())

    def test_install_repeat_and_symlink_invocation(self):
        directory = self.root / 'new' / 'bin'
        result = self.invoke('install', '--directory', str(directory))
        self.assertEqual(result.returncode, 0, result.stderr)
        link = directory / 'alwayson'
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.resolve(), self.helper.resolve())
        self.assertEqual(self.invoke('install', '--directory', str(directory)).returncode, 0)
        result = subprocess.run([str(link), 'install', '--directory', str(directory)],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), [])

    def test_install_default_and_refuses_existing_entries(self):
        self.env['HOME'] = str(self.root)
        result = self.invoke('install')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / '.local/bin/alwayson').resolve(), self.helper.resolve())
        directory = self.root / 'occupied'
        directory.mkdir()
        link = directory / 'alwayson'
        link.write_text('keep me')
        result = self.invoke('install', '--directory', str(directory))
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Installed', result.stdout)
        self.assertEqual(link.read_text(), 'keep me')
        link.unlink()
        link.symlink_to('/unrelated/missing')
        result = self.invoke('install', '--directory', str(directory))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(os.readlink(link), '/unrelated/missing')
        self.assertEqual(self.events(), [])

    def test_invalid_bundle_refuses_install_and_control(self):
        info = self.app / 'Contents/Info.plist'
        data = plistlib.loads(info.read_bytes())
        data['CFBundleIdentifier'] = 'com.example.unrelated'
        info.write_bytes(plistlib.dumps(data))
        self.assertNotEqual(self.invoke('install').returncode, 0)
        self.assertNotEqual(self.invoke('start').returncode, 0)
        self.assertEqual(self.events(), [])

    def test_help(self):
        self.assertEqual(self.invoke('--help').returncode, 0)

    def test_status_reports_the_running_app(self):
        self.write_status()
        result = self.invoke('status')
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertTrue(lines[0].startswith('AlwaysOn is active (timer) until '), lines)
        self.assertIn('Profile: Work', lines)
        result = self.invoke('status', '--json')
        self.assertEqual(result.returncode, 0, result.stderr)
        status = json.loads(result.stdout)
        self.assertEqual(status['state'], 'active')
        self.assertEqual(status['source'], 'timer')
        self.assertEqual(status['endsAt'], '2100-01-01T00:00:00Z')
        self.assertEqual(status['profiles'], ['Work', 'Deep Home'])
        self.assertEqual(self.events(), [])

    def test_status_wording_for_other_states(self):
        self.write_status(state='paused', source='manual', endsAt=None, resumesAt='2100-01-01T00:00:00Z',
                          hasAccessibilityPermission=False)
        lines = self.invoke('status').stdout.splitlines()
        self.assertTrue(lines[0].startswith('AlwaysOn is paused (manual), resuming at '), lines)
        self.assertIn('Accessibility permission is missing.', lines)
        self.write_status(state='off', source=None, endsAt=None)
        self.assertEqual(self.invoke('status').stdout.splitlines()[0], 'AlwaysOn is off.')

    def test_status_ignores_missing_stale_and_foreign_files(self):
        for prepare in [lambda: None,
                        lambda: self.write_status(pid=self.dead_pid()),
                        lambda: self.write_status(version=2),
                        lambda: self.write_status().write_text('not json')]:
            prepare()
            result = self.invoke('status')
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, '')
            self.assertIn("isn't running", result.stderr)

    def test_profile_lists_and_switches(self):
        self.write_status()
        result = self.invoke('profile')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['* Work', '  Deep Home'])
        self.assertEqual(self.events(), [])
        env = dict(self.env, OPEN_STATUS=self.status_json(profile='Deep Home'))
        result = self.invoke('profile', 'deep home', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith('AlwaysOn is active'), result.stdout)
        url = urlsplit(self.events()[-1][-1])
        self.assertEqual(url.netloc, 'profile')
        self.assertEqual(parse_qs(url.query), {'name': ['deep home']})

    def iso(self, minutes):
        return (datetime.now(timezone.utc) + timedelta(minutes=minutes)).strftime('%Y-%m-%dT%H:%M:%SZ')

    def test_confirmed_requests_print_the_new_state(self):
        cases = [
            (dict(state='off', source=None, endsAt=None), ('start',), dict(state='active', source='manual', endsAt=None), 'AlwaysOn is active'),
            (dict(), ('stop',), dict(state='off', source=None, endsAt=None), 'AlwaysOn is off'),
            (dict(), ('toggle',), dict(state='paused', source='manual', endsAt=None), 'AlwaysOn is paused'),
            (dict(state='off', source=None, endsAt=None), ('timer', '30'), dict(source='timer', endsAt=self.iso(30)), 'AlwaysOn is active (timer)'),
            (dict(), ('pause', '15'), dict(state='paused', source='manual', endsAt=None, resumesAt=self.iso(15)), 'AlwaysOn is paused'),
        ]
        for before, args, after, expected in cases:
            with self.subTest(args=args):
                self.write_status(**before)
                result = self.invoke(*args, env=dict(self.env, OPEN_STATUS=self.status_json(**after)))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(result.stdout.startswith(expected), result.stdout)

    def test_until_is_confirmed_by_its_end_time(self):
        self.write_status(state='off', source=None, endsAt=None)
        end = '2100-01-01T00:00:00Z'
        result = self.invoke('until', end, env=dict(self.env, OPEN_STATUS=self.status_json(source='until', endsAt=end)))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unconfirmed_request_exits_3(self):
        self.write_status(state='off', source=None, endsAt=None)
        result = self.invoke('start')
        self.assertEqual(result.returncode, 3)
        self.assertIn("didn't confirm the start request", result.stderr)
        self.assertIn('Current status: AlwaysOn is off.', result.stderr)
        self.assertEqual(self.events()[-1], ["-a", str(self.app), 'alwayson://start'])

    def test_unconfirmed_request_names_missing_permission(self):
        self.write_status(state='off', source=None, endsAt=None, hasAccessibilityPermission=False)
        result = self.invoke('timer', '30')
        self.assertEqual(result.returncode, 3)
        self.assertIn('Accessibility permission', result.stderr)

    def test_wrong_end_time_is_not_confirmation(self):
        self.write_status(state='off', source=None, endsAt=None)
        result = self.invoke('timer', '30', env=dict(self.env, OPEN_STATUS=self.status_json(source='timer', endsAt=self.iso(90))))
        self.assertEqual(result.returncode, 3)

    def test_transport_failure_is_still_exit_1(self):
        self.write_status()
        result = self.invoke('stop', env=dict(self.env, OPEN_EXIT='9'))
        self.assertEqual(result.returncode, 1)

    def test_profile_rejects_unknown_names_when_the_app_reports(self):
        self.write_status()
        result = self.invoke('profile', 'Nope')
        self.assertEqual(result.returncode, 1)
        self.assertIn('No profile named', result.stderr)
        self.assertEqual(self.events(), [])

    def test_profile_without_a_running_app(self):
        self.assertEqual(self.invoke('profile').returncode, 1)
        result = self.invoke('profile', 'Work')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events()[-1], ["-a", str(self.app), 'alwayson://profile?name=Work'])

    def test_run_warns_when_the_session_is_not_confirmed(self):
        self.write_status(state='off', source=None, endsAt=None, hasAccessibilityPermission=False)
        result = self.invoke('run', '--', sys.executable, '-c', 'print("ran")')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'ran\n')
        self.assertIn('Accessibility permission', result.stderr)
        self.pair(self.events())

    def test_run_is_quiet_when_the_session_is_confirmed(self):
        self.write_status(source='command')
        result = self.invoke('run', '--', sys.executable, '-c', 'print("ran")')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        self.pair(self.events())

    def test_arguments_output_and_success(self):
        args = ['space here', "quote'\"", '$(touch nope); * | &']
        code = 'import json,sys; print(json.dumps(sys.argv[1:])); print("stderr marker", file=sys.stderr)'
        result = self.invoke('run', '--', sys.executable, '-c', code, *args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), args)
        self.assertIn('stderr marker', result.stderr)
        self.pair(self.events())

    def test_failure_status(self):
        result = self.invoke('run', '--', sys.executable, '-c', 'import sys; sys.exit(37)')
        self.assertEqual(result.returncode, 37)
        self.pair(self.events())

    def test_finish_transport_failure_preserves_child_status(self):
        self.env['OPEN_FINISH_EXIT'] = '9'
        for status in [0, 37]:
            with self.subTest(status=status):
                if self.log.exists():
                    self.log.unlink()
                result = self.invoke('run', '--', sys.executable, '-c', f'import sys; print("completed"); sys.exit({status})')
                self.assertEqual(result.returncode, status)
                self.assertEqual(result.stdout.strip(), 'completed')
                self.assertIn('finish transport failed (9)', result.stderr)
                self.pair(self.events())

    def test_missing_executable_releases(self):
        result = self.invoke('run', '--', str(self.root / 'does-not-exist'))
        self.assertNotEqual(result.returncode, 0)
        self.pair(self.events())

    def test_open_failure_prevents_child(self):
        self.env['OPEN_EXIT'] = '1'
        marker = self.root / 'ran'
        result = self.invoke('run', '--', sys.executable, '-c', 'import pathlib,sys; pathlib.Path(sys.argv[1]).touch()', str(marker))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(marker.exists())
        events = self.events()
        self.assertGreaterEqual(len(events), 1)
        self.token(events[0], 'run')

    def test_overlapping_tokens_and_streaming(self):
        code = 'import sys,time; print("ready", flush=True); print("error ready", file=sys.stderr, flush=True); time.sleep(1)'
        procs = [subprocess.Popen([str(self.helper), 'run', '--', sys.executable, '-c', code], env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
        self.addCleanup(lambda: [p.kill() for p in procs if p.poll() is None])
        for p in procs:
            self.assertEqual(p.stdout.readline().strip(), 'ready')
            self.assertEqual(p.stderr.readline().strip(), 'error ready')
            self.assertIsNone(p.poll(), 'output must arrive while child is running')
        for p in procs:
            out, err = p.communicate(timeout=10)
            self.assertEqual(p.returncode, 0, err)
        events = self.events()
        self.assertEqual(len(events), 4)
        runs = [self.token(e, 'run') for e in events if urlsplit(e[-1]).netloc == 'run']
        finishes = [self.token(e, 'finish') for e in events if urlsplit(e[-1]).netloc == 'finish']
        self.assertEqual(len(runs), 2)
        self.assertEqual(len(set(runs)), 2)
        self.assertCountEqual(runs, finishes)
        for token in runs:
            self.assertLess(next(i for i,e in enumerate(events) if urlsplit(e[-1]).netloc == 'run' and parse_qs(urlsplit(e[-1]).query)['token'][0] == token), next(i for i,e in enumerate(events) if urlsplit(e[-1]).netloc == 'finish' and parse_qs(urlsplit(e[-1]).query)['token'][0] == token))

    def start_ready_child(self, code):
        proc = subprocess.Popen([str(self.helper), 'run', '--', sys.executable, '-c', code], env=self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        self.assertEqual(proc.stdout.readline().strip(), 'ready')
        return proc

    def test_sigterm_is_forwarded_and_session_released(self):
        code = ('import signal,sys,time\n'
                'signal.signal(signal.SIGTERM, lambda *a: (print("child got term", flush=True), sys.exit(5)))\n'
                'print("ready", flush=True)\n'
                'time.sleep(30)')
        proc = self.start_ready_child(code)
        proc.send_signal(signal.SIGTERM)
        out, err = proc.communicate(timeout=10)
        self.assertIn('child got term', out)
        self.assertEqual(proc.returncode, 5, err)
        self.pair(self.events())

    def test_child_killed_by_forwarded_signal_reports_shell_status(self):
        proc = self.start_ready_child('import time; print("ready", flush=True); time.sleep(30)')
        proc.send_signal(signal.SIGHUP)
        _, err = proc.communicate(timeout=10)
        self.assertEqual(proc.returncode, 128 + signal.SIGHUP, err)
        self.pair(self.events())

    def test_sigint_waits_for_child_cleanup(self):
        # Ctrl-C reaches the whole foreground process group; the helper must not kill the child mid-cleanup
        code = ('import signal,sys,time\n'
                'def stop(*a):\n'
                '    time.sleep(0.3); print("cleaned up", flush=True); sys.exit(0)\n'
                'signal.signal(signal.SIGINT, stop)\n'
                'print("ready", flush=True)\n'
                'time.sleep(30)')
        proc = subprocess.Popen([str(self.helper), 'run', '--', sys.executable, '-c', code], env=self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        self.assertEqual(proc.stdout.readline().strip(), 'ready')
        os.killpg(proc.pid, signal.SIGINT)
        out, err = proc.communicate(timeout=10)
        self.assertIn('cleaned up', out)
        self.assertEqual(proc.returncode, 0, err)
        self.pair(self.events())

if __name__ == '__main__':
    unittest.main(verbosity=2)
