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
        self.root = Path(self.temporary.name).resolve()
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
            'pins': {'app/Moonlight': self.pin}, 'integration_sha256': digest.hexdigest(),
            'files': {}, 'project_base': ''}))
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

    def test_changed_recipe_updates_same_project_through_prepare(self):
        def generate(destination):
            (destination/'Moonlight.xcodeproj').mkdir(parents=True)
            (destination/prepare_client.PROJECT).write_text('team = upstream\n')
            (destination/'source.txt').write_text(self.recipe.read_text())
        with patch.object(prepare_client, 'generate_client', side_effect=generate):
            import shutil
            shutil.rmtree(self.destination)
            prepare_client.prepare(self.destination)
            (self.destination/prepare_client.PROJECT).write_text('team = local\n')
            self.recipe.write_text('updated recipe\n')
            prepare_client.prepare(self.destination)
            self.assertEqual((self.destination/'source.txt').read_text(), 'updated recipe\n')
            self.assertEqual((self.destination/prepare_client.PROJECT).read_text(), 'team = local\n')



class ClientUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.local = root/'local'
        self.incoming = root/'incoming'
        self.local.mkdir()
        self.incoming.mkdir()
        self.project = prepare_client.PROJECT
        self.base_project = 'header\nteam = original\nseparator\n\n\nsource = original\n'
        for folder in [self.local, self.incoming]:
            (folder/self.project).parent.mkdir()
            (folder/self.project).write_text(self.base_project)
            (folder/'source.m').write_text('original source\n')
        self.previous = prepare_client.record_generation(self.local, {'integration_sha256': 'old'})
        self.record = self.local/'pyrowave-preparation.json'
        self.record.write_text(json.dumps(self.previous))

    def update(self):
        manifest = prepare_client.record_generation(self.incoming, {'integration_sha256': 'new'})
        prepare_client.update_client(self.local, self.incoming, self.previous, manifest)
        return manifest

    def test_source_update_preserves_signing_user_data_and_local_only_edits(self):
        (self.local/self.project).write_text(self.base_project.replace('team = original', 'team = local'))
        (self.incoming/self.project).write_text(self.base_project.replace('source = original', 'source = updated'))
        (self.local/'user.xcuserstate').write_bytes(b'local Xcode state')
        (self.local/'source.m').write_text('local code edit\n')
        (self.incoming/'new.m').write_text('new source\n')
        (self.incoming/'new.m').chmod(0o755)
        manifest = self.update()
        project = (self.local/self.project).read_text()
        self.assertIn('team = local', project)
        self.assertIn('source = updated', project)
        self.assertEqual((self.local/'source.m').read_text(), 'local code edit\n')
        self.assertEqual((self.local/'user.xcuserstate').read_bytes(), b'local Xcode state')
        self.assertEqual((self.local/'new.m').stat().st_mode & 0o777, 0o755)
        self.assertEqual(json.loads(self.record.read_text()), manifest)
        self.previous = manifest
        self.update()
        self.assertEqual((self.local/self.project).read_text(), project)

    def test_source_conflict_writes_nothing(self):
        (self.incoming/'a-new.m').write_text('should not be installed\n')
        (self.incoming/'source.m').write_text('incoming code\n')
        (self.local/'source.m').write_text('local code\n')
        original_record = self.record.read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'Conflicting local changes'):
            self.update()
        self.assertFalse((self.local/'a-new.m').exists())
        self.assertEqual(self.record.read_bytes(), original_record)
        self.assertEqual((self.local/'source.m').read_text(), 'local code\n')

    def test_project_conflict_preserves_original(self):
        (self.local/self.project).write_text(self.base_project.replace('team = original', 'team = local'))
        (self.incoming/self.project).write_text(self.base_project.replace('team = original', 'team = incoming'))
        with self.assertRaisesRegex(RuntimeError, 'Conflicting local changes'):
            self.update()
        self.assertIn('team = local', (self.local/self.project).read_text())
        self.assertNotIn('<<<<<<<', (self.local/self.project).read_text())

    def test_removed_generated_file_is_deleted(self):
        (self.incoming/'source.m').unlink()
        self.update()
        self.assertFalse((self.local/'source.m').exists())

    def test_failed_write_restores_previous_files_and_manifest(self):
        (self.incoming/'source.m').write_text('incoming code\n')
        original_record = self.record.read_bytes()
        replace = prepare_client.os.replace
        def fail_on_record(source, destination):
            if Path(destination).name == 'pyrowave-preparation.json':
                raise OSError('simulated disk error')
            replace(source, destination)
        with patch.object(prepare_client.os, 'replace', side_effect=fail_on_record):
            with self.assertRaisesRegex(OSError, 'simulated disk error'):
                self.update()
        self.assertEqual((self.local/'source.m').read_text(), 'original source\n')
        self.assertEqual(self.record.read_bytes(), original_record)

    def test_symlink_cannot_overwrite_file_outside_checkout(self):
        outside = self.local.parent/'outside'
        outside.write_text('private\n')
        (self.local/'source.m').unlink()
        (self.local/'source.m').symlink_to(outside)
        (self.incoming/'source.m').write_text('incoming code\n')
        with self.assertRaisesRegex(RuntimeError, 'symbolic link'):
            self.update()
        self.assertEqual(outside.read_text(), 'private\n')

    def test_legacy_checkout_with_only_signing_changes_is_adopted(self):
        self.previous = {'integration_sha256': 'legacy'}
        for folder in [self.local, self.incoming]:
            (folder/self.project).write_text('header\nDEVELOPMENT_TEAM = upstream;\nfooter\n')
        (self.local/self.project).write_text('header\nDEVELOPMENT_TEAM = personal;\nfooter\n')
        self.update()
        self.assertIn('personal', (self.local/self.project).read_text())
        self.assertIn('files', json.loads(self.record.read_text()))

    def test_legacy_checkout_with_different_sources_is_preserved(self):
        self.previous = {'integration_sha256': 'legacy'}
        (self.incoming/'source.m').write_text('changed upstream\n')
        with self.assertRaisesRegex(RuntimeError, 'Legacy checkout has no baseline'):
            self.update()
        self.assertEqual((self.local/'source.m').read_text(), 'original source\n')
