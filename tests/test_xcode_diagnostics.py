# SPDX-License-Identifier: MIT
import sys
import contextlib
import io
import tempfile
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from xcode_diagnostics import capture, diagnostics


class XcodeDiagnosticsTests(unittest.TestCase):
    def test_compiler_tool_and_plain_diagnostics(self):
        report = diagnostics([
            '/tmp/Moonlight TV/Source.m:42:3: warning: old API [-Wdeprecated-declarations]',
            'libtool: warning: object has no symbols',
            'warning: Metadata extraction skipped. No AppIntents.framework dependency found.',
            '/tmp/PyroWaveRuntime/apple/Renderer.mm:8:4: error: missing type',
            'note: this is context, not another warning',
        ], 65)
        self.assertEqual((report['errors'], report['warnings']), (1, 3))
        self.assertFalse(report['succeeded'])
        self.assertTrue(report['diagnostics'][-1]['owned_source'])

    def test_analyzer_warning_and_fatal_error(self):
        report = diagnostics(['file.mm:1:1: warning: null dereference [core.NullDereference]',
                              'xcodebuild: fatal error: SDK unavailable'], 1)
        self.assertEqual((report['errors'], report['warnings']), (1, 1))

    def test_success_does_not_claim_physical_validation(self):
        report = diagnostics(['** BUILD SUCCEEDED **'], 0)
        self.assertTrue(report['succeeded'])
        self.assertFalse(report['physical_apple_tv_tested'])
        self.assertFalse(report['auto_qualified'])

    def test_capture_preserves_output_and_exit_failure(self):
        import json
        import subprocess
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)/'report'
            with self.assertRaises(subprocess.CalledProcessError), contextlib.redirect_stdout(io.StringIO()):
                capture([sys.executable, '-c', "import sys; print('error: fixture failure'); sys.exit(3)"], output)
            report = json.loads((output/'diagnostics.json').read_text())
            self.assertEqual((report['returncode'], report['errors']), (3, 1))
            self.assertEqual((output/'xcodebuild.log').read_text(), 'error: fixture failure\n')
