"""Regression checks for serial output and fstab validation; no VM required."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class VMChecks(unittest.TestCase):
    def test_fstab_accepts_tabs_and_spaces_but_not_comments(self):
        script = (ROOT / 'scripts/interactive-install-test.sh').read_text()
        program = re.search(r'boot" sudo awk \'(.*?)\'', script, re.S)[1]
        for row, expected in [('UUID=a\t/home\text4\tdefaults\t0 2\n', 0),
                              ('UUID=a /home ext4 defaults 0 2\n', 0),
                              ('# UUID=a /home ext4 defaults 0 2\n', 1),
                              ('UUID=a / ext4 defaults 0 1\n', 1)]:
            result = subprocess.run(['awk', program], input=row, text=True)
            self.assertEqual(result.returncode, expected)

    def test_results_ignore_echoed_commands_and_empty_names(self):
        script = (ROOT / 'scripts/live-boot-test.sh').read_text()
        pattern = re.search(r"grep -a -o '([^']+)'", script)[1]
        fixture = ('c() { echo "CHECK PASS $1"; echo "CHECK FAIL $1"; }\n'
                   'CHECK FAIL \nCHECK PASS desktop-running\n'
                   'CHECK FAIL orca-running\nSONA-PROMPT# CHECK PASS fake\n')
        result = subprocess.run(['grep', '-a', '-o', pattern], input=fixture,
                                text=True, capture_output=True)
        self.assertEqual(result.stdout.splitlines(),
                         ['CHECK PASS desktop-running', 'CHECK FAIL orca-running'])

    def test_completion_patterns_ignore_echo(self):
        script = (ROOT / 'scripts/live-boot-test.sh').read_text()
        for marker in ['DESKTOP-WAIT-DONE', 'PROBE-DONE']:
            pattern = next(line.split(' ', 2)[2] for line in script.splitlines()
                           if line.startswith('expect ') and marker in line)
            self.assertIsNone(re.search(pattern, f"printf '{marker}'\n"))
            self.assertIsNotNone(re.search(pattern, f'\n{marker}\n'))


if __name__ == '__main__':
    unittest.main()
