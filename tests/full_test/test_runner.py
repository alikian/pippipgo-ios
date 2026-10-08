"""Offline checks only: these never start Appium or contact a phone."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('full_test', Path(__file__).resolve().parents[2] / 'scripts/full_test.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def test_existing_server_is_reused(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(runner, 'STATE', Path(folder)), patch.object(runner, 'ready', return_value=True), patch.object(runner.subprocess, 'Popen') as start:
            runner.setup()
            start.assert_not_called()

    def test_new_session_preserves_data_and_has_no_idle_teardown(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(runner, 'STATE', Path(folder)), patch.object(runner, 'setup'), patch.object(runner, 'request', return_value={'sessionId': 'test'}) as send:
            runner.Device('device', 'team')
            caps = send.call_args.args[2]['capabilities']['alwaysMatch']
            self.assertTrue(caps['appium:noReset'])
            self.assertFalse(caps['appium:fullReset'])
            self.assertFalse(caps['appium:useNewWDA'])
            self.assertFalse(caps['appium:shouldTerminateApp'])
            self.assertEqual(caps['appium:newCommandTimeout'], 0)

    def test_saved_session_is_reused(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(runner, 'STATE', Path(folder)), patch.object(runner, 'setup'), patch.object(runner, 'request', return_value='<App/>') as send:
            (Path(folder) / 'session.json').write_text('{"id":"existing"}')
            device = runner.Device('device', 'team')
            self.assertEqual(device.sid, 'existing')
            send.assert_called_once_with('GET', '/session/existing/source', None)

    def test_failed_run_reports_failure_and_preserves_server(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(runner, 'STATE', Path(folder)), patch.object(runner, 'Device', side_effect=RuntimeError('phone locked')), patch.object(runner, 'teardown') as stop:
            args = type('Args', (), {'device': 'device', 'team': 'team'})()
            self.assertEqual(runner.run(args), 1)
            reports = list(Path(folder).glob('report-*.json'))
            self.assertEqual(len(reports), 1)
            self.assertIn('blocked_or_failed', reports[0].read_text())
            stop.assert_not_called()


if __name__ == '__main__':
    unittest.main()
