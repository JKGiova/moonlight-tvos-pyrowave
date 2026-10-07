# SPDX-License-Identifier: MIT
import importlib.util
import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('video_harness',ROOT/'tools/encode_test_video.py')
harness=importlib.util.module_from_spec(spec);spec.loader.exec_module(harness)
class VideoHarnessTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/'fixture.pyrowave'
    def fixture(self):
        # Independently encoded zero-block sequence, valid 128x128 image.
        frame=struct.pack('<II',0x80000000|127|(127<<14),0)
        self.path.write_bytes(b'PYROWAVE'+struct.pack('<8I',128,128,0,0,0,60,1,0)+struct.pack('<I',len(frame))+frame)
    def test_valid_container_and_native_framing(self):
        self.fixture();info=harness.inspect_container(self.path,1,128,128,60)
        self.assertEqual(info['frames'],1)
        result=subprocess.check_output([str(ROOT/'build/portable/framing-check'),str(self.path)],text=True)
        self.assertTrue(json.loads(result)['nonary_framing_validated'])
    def test_truncated_payload_rejected(self):
        self.fixture();self.path.write_bytes(self.path.read_bytes()[:-1])
        with self.assertRaises(RuntimeError):harness.inspect_container(self.path,1,128,128,60)
        self.assertNotEqual(subprocess.run([str(ROOT/'build/portable/framing-check'),str(self.path)],capture_output=True).returncode,0)
    def test_empty_fake_success_rejected(self):
        self.path.write_bytes(b'')
        with self.assertRaises(RuntimeError):harness.inspect_container(self.path,1,128,128,60)
    def test_wrong_profile_rejected(self):
        self.fixture()
        with self.assertRaises(RuntimeError):harness.inspect_container(self.path,1,1920,1080,60)
    def test_missing_frames_rejected(self):
        self.fixture()
        with self.assertRaises(RuntimeError):harness.inspect_container(self.path,2,128,128,60)
    def test_malformed_payload_rejected_by_native_parser(self):
        self.fixture();data=bytearray(self.path.read_bytes());data[-4:]=struct.pack('<I',1);self.path.write_bytes(data)
        self.assertNotEqual(subprocess.run([str(ROOT/'build/portable/framing-check'),str(self.path)],capture_output=True).returncode,0)
    def test_shell_metacharacters_in_path_are_literal(self):
        log=Path(self.tmp.name)/'log with spaces.txt'
        import sys
        harness.run([sys.executable,'-c','import sys; print(sys.argv[1])','$(not-a-command)'],log,10)
        self.assertEqual(log.read_text().strip(),'$(not-a-command)')
if __name__=='__main__':unittest.main()
