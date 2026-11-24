# SPDX-License-Identifier: MIT
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import build_device_benchmark as diagnostic


class DeviceDiagnosticTests(unittest.TestCase):
    def test_device_adapter_requires_the_real_production_factory(self):
        source=diagnostic.device_source((ROOT/'tools/benchmark_client.cpp').read_text())
        self.assertIn('pw_decoder_device_create(&info,false,&created)',source)
        self.assertIn('physical_apple_tv_tested\\\":true',source)
        self.assertIn('production-device-offscreen-split-serial',source)
        self.assertNotIn('value->portable_dequant = true',source)

    def test_timing_breakdown_preserves_normal_scheduling(self):
        original=(ROOT/'tools/benchmark_client.cpp').read_text()
        regular=diagnostic.timing_source(diagnostic.device_source(original))
        isolated=diagnostic.timing_source(diagnostic.device_source(original),True)
        for metric in ['parse_cpu_ms','push_cpu_ms','encode_cpu_ms','commit_cpu_ms','gpu_overlap_ms','timeline_relative_ms']:
            self.assertIn(metric,regular)
        fence='[decode waitUntilCompleted];\n            auto conversion='
        self.assertNotIn(fence,regular)
        self.assertIn(fence,isolated)

    def test_unknown_benchmark_layout_is_rejected(self):
        with self.assertRaises(ValueError):
            diagnostic.device_source('unrecognized benchmark')

    def test_failed_build_restores_managed_files_and_removes_injected_files(self):
        for baseline in [False,True]:
            with self.subTest(baseline=baseline), tempfile.TemporaryDirectory() as temporary:
                root=Path(temporary);client=root/'build/client/original'
                saved={
                    'Limelight/AppDelegate.m':'@implementation AppDelegate\nmethod {\n    return YES;\n}\n',
                    'PyroWaveRuntime/apple/PyroWaveVideoRenderer.mm':'original renderer',
                    'PyroWaveRuntime/metal/pyrowave_decoder.mm':'original decoder',
                    'PyroWaveRuntime/apple/PyroWaveApple5Source.h':'original apple header',
                    'PyroWaveRuntime/metal/shaders/pyrowave_apple5_msl.h':'original metal header',
                }
                for name,text in saved.items():
                    p=client/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
                for name,contents in {
                    'tools/benchmark_client.cpp':(ROOT/'tools/benchmark_client.cpp').read_text(),
                    'tests/dequant_fixture.hpp':'test fixture',
                    'third_party/pyrowave/metal/pyrowave_decoder.mm':'baseline decoder',
                }.items():
                    p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(contents)
                def fail_compile(command,**kwargs):
                    self.assertEqual(command[0],'xcodebuild')
                    self.assertIn('PWRunOfflineDeviceBenchmark',(client/'Limelight/AppDelegate.m').read_text())
                    raise subprocess.CalledProcessError(1,command)
                def revision(command,**kwargs):
                    return 'test-revision\n' if kwargs.get('text') else b'baseline shader'
                argv=['diagnostic','--device-name','test']+(['--baseline'] if baseline else [])
                with patch.object(diagnostic,'ROOT',root),patch.object(diagnostic,'prepare',return_value=client), \
                     patch.object(sys,'argv',argv),patch.object(diagnostic.subprocess,'run',side_effect=fail_compile), \
                     patch.object(diagnostic.subprocess,'check_output',side_effect=revision):
                    with self.assertRaises(subprocess.CalledProcessError): diagnostic.main()
                for name,text in saved.items(): self.assertEqual((client/name).read_text(),text)
                for name in ['PWOfflineBenchmark.cpp','dequant_fixture.hpp']:
                    self.assertFalse((client/'PyroWaveRuntime/apple'/name).exists())
