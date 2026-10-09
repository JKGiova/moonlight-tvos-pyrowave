# SPDX-License-Identifier: MIT
"""Regression checks using real local Git histories and a matching cache."""
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import prepare_client


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root/'app/Moonlight'
        self.source.mkdir(parents=True)
        self.git('init', '--quiet')
        self.git('config', 'user.name', 'Local Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        (self.source/'source.txt').write_text('reviewed source\n')
        self.git('add', 'source.txt')
        self.git('commit', '--quiet', '-m', 'fixture')
        self.pin = self.git('rev-parse', 'HEAD').strip()
        self.recipe = self.root/'recipe.py'
        self.recipe.write_text('fixture preparation recipe\n')
        digest = hashlib.sha256()
        digest.update(b'recipe.py')
        digest.update(self.recipe.read_bytes())
        self.destination = self.root/'build/client'
        self.destination.mkdir(parents=True)
        (self.destination/'pyrowave-preparation.json').write_text(json.dumps({
            'pins': {'app/Moonlight': self.pin}, 'integration_sha256': digest.hexdigest()}))
        self.signing = self.destination/'user-signing.txt'
        self.signing.write_text('user edits must survive\n')
        for name, value in [('ROOT', self.root), ('PINS', {'app/Moonlight': self.pin})]:
            override = patch.object(prepare_client, name, value)
            override.start()
            self.addCleanup(override.stop)
        override = patch.object(prepare_client, 'inputs', return_value=[self.recipe])
        override.start()
        self.addCleanup(override.stop)

    def git(self, *arguments):
        return subprocess.check_output(['git', '-C', str(self.source), *arguments], text=True)

    def test_matching_cache_preserves_local_edits(self):
        self.assertEqual(prepare_client.prepare(self.destination), self.destination)
        self.assertEqual(self.signing.read_text(), 'user edits must survive\n')

    def test_identical_source_at_wrong_commit_is_rejected_even_on_cache_hit(self):
        self.git('commit', '--quiet', '--allow-empty', '-m', 'different revision, identical files')
        with self.assertRaisesRegex(RuntimeError, 'exact upstream pins'):
            prepare_client.prepare(self.destination)
        self.assertEqual(self.signing.read_text(), 'user edits must survive\n')

    def test_dirty_upstream_is_rejected_even_on_cache_hit(self):
        (self.source/'source.txt').write_text('unreviewed changes\n')
        with self.assertRaises(subprocess.CalledProcessError):
            prepare_client.prepare(self.destination)
        self.assertTrue(self.signing.is_file())

    def test_destination_outside_build_is_rejected_without_writing(self):
        with self.assertRaisesRegex(RuntimeError, 'below build'):
            prepare_client.prepare(self.source)
        self.assertFalse((self.source/'pyrowave-preparation.json').exists())

    def test_uninitialized_nested_dependency_is_rejected_on_cache_hit(self):
        (self.source/'.gitmodules').write_text(
            '[submodule "dependency"]\n\tpath = dependency\n\turl = https://example.invalid/fixture.git\n')
        self.git('add', '.gitmodules')
        self.git('update-index', '--add', '--cacheinfo', '160000', self.pin, 'dependency')
        self.git('commit', '--quiet', '-m', 'registered but uninitialized dependency')
        self.pin = self.git('rev-parse', 'HEAD').strip()
        prepare_client.PINS['app/Moonlight'] = self.pin
        record = self.destination/'pyrowave-preparation.json'
        manifest = json.loads(record.read_text())
        manifest['pins']['app/Moonlight'] = self.pin
        record.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(RuntimeError, 'Nested Moonlight dependencies'):
            prepare_client.prepare(self.destination)
        self.assertTrue(self.signing.is_file())
