"""Exercise the real ugrep byte-stream protocol used by FSX's content design."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

parser = argparse.ArgumentParser()
parser.add_argument('ugrep', type=Path)
args, remaining = parser.parse_known_args()
UGREP = str(args.ugrep.resolve())
FORMAT = '--format={"line":%n,"offset":%b,"text":%J}%~'


class Protocol(unittest.TestCase):
    def invoke(self, pattern, data, mode='-F', cwd=None):
        return subprocess.run(
            [UGREP, '-J1', mode, '--color=never', '--line-buffered',
             '--label=fsx-input', FORMAT, '-e', pattern, '--', '-'],
            input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            cwd=cwd, timeout=20)

    def records(self, result):
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        self.assertEqual(result.stderr, b'')
        return [json.loads(line) for line in result.stdout.splitlines()]

    def test_literal_records_and_exact_utf8_offsets(self):
        rows = self.records(self.invoke('needle', 'zero\n猫 needle needle\n'.encode()))
        self.assertEqual(rows, [
            {'line': 2, 'offset': 9, 'text': '猫 needle needle'},
            {'line': 2, 'offset': 16, 'text': '猫 needle needle'}])

    def test_json_escaping_and_leading_option_characters(self):
        rows = self.records(self.invoke('-needle', b'"-needle"\t\\file\n'))
        self.assertEqual(rows, [{'line': 1, 'offset': 1, 'text': '"-needle"\t\\file'}])

    def test_literal_and_pcre2_are_distinct(self):
        result = self.invoke('a.b', b'aXb\n')
        self.assertEqual((result.returncode, result.stdout), (1, b''))
        self.assertEqual(self.records(self.invoke('a.b', b'aXb\n', '-P')),
                         [{'line': 1, 'offset': 0, 'text': 'aXb'}])
        # Lookbehind requires PCRE2; no alternative matcher may substitute.
        self.assertEqual(self.records(self.invoke(r'(?<=prefix)needle',
                         b'prefixneedle\n', '-P'))[0]['offset'], 6)

    def test_multiline_text_is_one_json_frame(self):
        rows = self.records(self.invoke(r'one\ntwo', b'one\ntwo\n', '-P'))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0], {'line': 1, 'offset': 0, 'text': 'one\ntwo'})

    def test_no_match_and_invalid_regex_exit_codes(self):
        for data in [b'', b'other\n']:
            result = self.invoke('needle', data)
            self.assertEqual((result.returncode, result.stdout), (1, b''))
        result = self.invoke('[', b'input\n', '-P')
        self.assertGreater(result.returncode, 1)
        self.assertNotEqual(result.stderr, b'')

    def test_interactive_configuration_is_not_loaded(self):
        with tempfile.TemporaryDirectory(prefix='ugrep-config-', dir=Path.cwd()) as directory:
            Path(directory, '.ugrep').write_text('ignore-case\n', encoding='utf-8')
            result = self.invoke('NEEDLE', b'needle\n', cwd=directory)
            self.assertEqual((result.returncode, result.stdout), (1, b''))

    def test_pipe_output_beyond_kernel_buffer(self):
        data = b'needle\n' * 20000
        rows = self.records(self.invoke('needle', data))
        self.assertEqual(len(rows), 20000)
        self.assertEqual(rows[-1], {'line': 20000, 'offset': 139993, 'text': 'needle'})


if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining])
