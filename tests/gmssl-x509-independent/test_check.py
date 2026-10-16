"""Harness tests only. These are not GmSSL implementation acceptance."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent

class HarnessTests(unittest.TestCase):
    def check_driver(self, body, expected_matches):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            driver = path/'fake-driver'
            if body is not None:
                driver.write_text('#!/bin/sh\n'+body+'\n')
                driver.chmod(0o700)
            p = subprocess.run([sys.executable,str(HERE/'check.py'),'--provider',str(driver),
                '--fixtures',str(HERE/'fixtures.json'),'--out',str(path/'out')],
                capture_output=True,text=True,timeout=30)
            self.assertEqual(p.returncode,1,p.stderr)
            report = json.loads((path/'out'/'report.json').read_text())
            self.assertEqual(report['passed'],expected_matches)
            self.assertFalse(report['all_positive_controls_pass'])

    def test_missing_driver_is_not_rejection(self):
        self.check_driver(None,0)

    def test_abnormal_exit_is_not_rejection(self):
        self.check_driver('exit 139',0)

    def test_reject_everything_cannot_pass(self):
        self.check_driver('echo \'{"return":-1,"verify_result":1}\'; exit 1',12)

    def test_wrong_json_type_is_not_rejection(self):
        self.check_driver('echo \'[]\'; exit 1',0)

if __name__ == '__main__':
    unittest.main()
