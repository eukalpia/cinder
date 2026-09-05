"""Distribution contracts, archive integrity, and executable permissions."""
import argparse
from contextlib import redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import package_native
import native_notices


class NativePackageTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in package_native.LICENSES.values():
            (self.root / name).write_text(f'Notice from {name}\n')
        (self.root / 'pubspec.yaml').write_text('name: cinder\nversion: 1.2.3-rc.4\n')
        self.addCleanup(patch.stopall)
        patch.object(package_native, 'ROOT', self.root).start()
        patch.object(package_native, 'collect_notices', return_value=(
            b'Notice from THIRD_PARTY_LICENSES\n', [])).start()

    def arguments(self, target=None):
        target = target or ('windows' if os.name == 'nt' else 'linux')
        native = self.root / target
        (native / 'symbols').mkdir(parents=True)
        extension = '.exe' if target == 'windows' else ''
        for name in ('cinder', 'cinder-demo'):
            binary = native / (name + extension)
            binary.write_bytes(b'Executable payload: ' + name.encode())
            binary.chmod(0o751)
            (native / 'symbols' / (name + extension + '.debug')).write_bytes(
                b'Debugging payload: ' + name.encode())
        return argparse.Namespace(
            input=native, symbols=None, output=self.root / 'archives' / target,
            target_os=target, target_arch='x64', version=None,
            commit='a' * 40, dart_version='3.13.3', dart_executable='dart',
        )

    def build(self, args):
        with redirect_stdout(io.StringIO()):
            package_native.build(args)
        return sorted([*args.output.glob('*.zip'), *args.output.glob('*.tar.gz')])

    @unittest.skipIf(os.name == 'nt', 'POSIX mode preservation is checked on native POSIX runners')
    def test_tar_payload_notices_symbols_and_modes(self):
        args = self.arguments()
        archives = self.build(args)
        self.assertEqual(len(archives), 2)
        for archive_path in archives:
            component = 'symbols' if '-symbols.tar.gz' in archive_path.name else 'runtime'
            with tarfile.open(archive_path) as archive:
                members = {item.name.split('/', 1)[1]: item for item in archive.getmembers()}
                expected = {'LICENSE', 'NOTICE', 'THIRD_PARTY_LICENSES', 'manifest.json'}
                expected |= ({'symbols/cinder.debug', 'symbols/cinder-demo.debug'}
                             if component == 'symbols' else {'bin/cinder', 'bin/cinder-demo'})
                self.assertEqual(set(members), expected)
                self.assertTrue(all(item.isfile() for item in members.values()))
                self.assertEqual(archive.extractfile(members['NOTICE']).read(), b'Notice from NOTICE.md\n')
                manifest = json.load(archive.extractfile(members['manifest.json']))
                self.assertEqual(manifest['source_commit'], args.commit)
                self.assertEqual(manifest['version'], '1.2.3-rc.4')
                self.assertEqual(manifest['component'], component)
                for entry in manifest['files']:
                    payload = archive.extractfile(members[entry['path']]).read()
                    self.assertEqual(entry['sha256'], hashlib.sha256(payload).hexdigest())
                    self.assertEqual(entry['bytes'], len(payload))
                if component == 'runtime':
                    self.assertEqual(archive.extractfile(members['bin/cinder-demo']).read(),
                                     (args.input / 'cinder-demo').read_bytes())
                    if os.name != 'nt':
                        self.assertEqual(members['bin/cinder-demo'].mode, 0o751)

    def test_windows_zip_keeps_exe_names_and_regular_executable_modes(self):
        args = self.arguments('windows')
        archives = self.build(args)
        self.assertEqual(len(archives), 2)
        runtime = next(path for path in archives if '-symbols.zip' not in path.name)
        with zipfile.ZipFile(runtime) as archive:
            binary = next(item for item in archive.infolist() if item.filename.endswith('/bin/cinder.exe'))
            self.assertEqual(stat.S_IFMT(binary.external_attr >> 16), stat.S_IFREG)
            self.assertEqual(stat.S_IMODE(binary.external_attr >> 16), 0o755)
            self.assertEqual(archive.read(binary), (args.input / 'cinder.exe').read_bytes())
            self.assertFalse(any('.debug' in name for name in archive.namelist()))
        symbols = next(path for path in archives if '-symbols.zip' in path.name)
        with zipfile.ZipFile(symbols) as archive:
            self.assertTrue(any(name.endswith('/symbols/cinder-demo.exe.debug') for name in archive.namelist()))

    def test_corrupted_archive_is_rejected_before_reading(self):
        archive = self.build(self.arguments())[0]
        archive.write_bytes(archive.read_bytes() + b'corruption')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            package_native.verify_archive(archive)

    def test_modified_payload_is_rejected_even_with_updated_archive_checksum(self):
        archives = self.build(self.arguments('windows'))
        archive = next(path for path in archives if '-symbols.zip' not in path.name)
        with zipfile.ZipFile(archive) as source:
            entries = [(item, source.read(item)) for item in source.infolist()]
        with zipfile.ZipFile(archive, 'w') as destination:
            for item, payload in entries:
                if item.filename.endswith('/bin/cinder.exe'):
                    payload = b'Replaced binary'
                destination.writestr(item, payload)
        archive.with_name(archive.name + '.sha256').write_text(
            f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n')
        with self.assertRaisesRegex(ValueError, 'Manifest mismatch'):
            package_native.verify_archive(archive)

    def test_missing_symbols_prevent_distribution(self):
        args = self.arguments()
        extension = '.exe' if args.target_os == 'windows' else ''
        (args.input / f'symbols/cinder-demo{extension}.debug').unlink()
        with self.assertRaisesRegex(ValueError, 'regular file'):
            self.build(args)
        self.assertEqual(list(args.output.glob('*')), [])

    def test_existing_distribution_is_not_overwritten(self):
        args = self.arguments()
        archives = self.build(args)
        before = {path: path.read_bytes() for path in archives}
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            self.build(args)
        self.assertEqual(before, {path: path.read_bytes() for path in archives})

    def test_existing_symbols_do_not_leave_a_partial_runtime_distribution(self):
        args = self.arguments()
        archives = self.build(args)
        runtime = next(path for path in archives if '-symbols.' not in path.name)
        runtime.unlink()
        checksum = runtime.with_name(runtime.name + '.sha256')
        checksum.unlink()
        before = {path.name: path.read_bytes() for path in args.output.iterdir()}
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            self.build(args)
        self.assertEqual(before, {path.name: path.read_bytes() for path in args.output.iterdir()})

    def test_archive_rejects_path_traversal_and_symbolic_links(self):
        for name, symbolic in [('root/../escape', False), ('root/link', True)]:
            with self.subTest(name=name):
                path = self.root / 'invalid.tar.gz'
                with tarfile.open(path, 'w:gz') as archive:
                    entry = tarfile.TarInfo(name)
                    if symbolic:
                        entry.type, entry.linkname = tarfile.SYMTYPE, '/outside'
                    archive.addfile(entry, io.BytesIO())
                with self.assertRaises(ValueError):
                    package_native.archive_files(path)

    def test_same_inputs_produce_identical_archives(self):
        args = self.arguments()
        first = {path.name: path.read_bytes() for path in self.build(args)}
        args.output = self.root / 'second-output'
        second = {path.name: path.read_bytes() for path in self.build(args)}
        self.assertEqual(first, second)


class NativeNoticesTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.config = self.root / '.dart_tool/package_config.json'
        self.config.parent.mkdir()
        packages = []
        for name in ('app', 'direct', 'shared', 'dev_only'):
            directory = self.root / ('package ' + name)
            directory.mkdir()
            (directory / 'LICENSE').write_bytes(f'Full original license: {name}\n'.encode())
            packages.append({'name': name, 'rootUri': '../package%20' + name})
        self.config.write_text(json.dumps({'packages': packages}))
        self.graph = {'root': 'app', 'packages': [
            {'name': 'app', 'version': '1.0.0', 'directDependencies': ['direct'],
             'dependencies': ['direct', 'dev_only'], 'devDependencies': ['dev_only']},
            {'name': 'direct', 'version': '2.0.0', 'directDependencies': ['shared']},
            {'name': 'shared', 'version': '3.0.0', 'directDependencies': ['direct']},
            {'name': 'dev_only', 'version': '4.0.0', 'directDependencies': ['shared']},
        ]}
        self.bundle_directory = self.root / 'tool/licenses/dart-3.13.3'
        self.bundle_directory.mkdir(parents=True)
        bundle = b'Full native runtime dependency licenses\n'
        (self.bundle_directory / 'NOTICES').write_bytes(bundle)
        (self.bundle_directory / 'manifest.json').write_text(json.dumps({
            'schema_version': 1, 'dart_version': '3.13.3', 'bundle_file': 'NOTICES',
            'bundle_sha256': hashlib.sha256(bundle).hexdigest(),
        }))

    def test_runtime_closure_keeps_shared_dependencies_and_excludes_dev_only(self):
        licenses = native_notices.runtime_licenses(self.graph, self.config)
        self.assertEqual({name for name, _, _ in licenses}, {'app', 'direct', 'shared'})
        self.assertIn(b'Full original license: shared\n', licenses.values())
        self.assertTrue(all(hashlib.sha256(data).hexdigest() == key[2]
                            for key, data in licenses.items()))

    def test_missing_runtime_license_fails_but_dev_only_license_is_not_required(self):
        (self.root / 'package dev_only/LICENSE').unlink()
        native_notices.runtime_licenses(self.graph, self.config)
        (self.root / 'package shared/LICENSE').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing runtime dependency license: shared 3.0.0'):
            native_notices.runtime_licenses(self.graph, self.config)

    def test_sdk_version_must_match_the_build(self):
        sdk = self.root / 'sdk'
        (sdk / 'bin').mkdir(parents=True)
        (sdk / 'version').write_text('3.13.3\n')
        with self.assertRaisesRegex(ValueError, 'does not match'):
            native_notices.collect_notices(self.root, str(sdk / 'bin/dart'), '3.12.0')

    def test_native_runtime_bundle_rejects_changed_bytes(self):
        (self.bundle_directory / 'NOTICES').write_bytes(b'Changed dependency notices')
        with self.assertRaisesRegex(ValueError, 'bundle checksum'):
            native_notices.native_runtime_notices(self.root, '3.13.3')

    def test_native_runtime_bundle_rejects_a_different_sdk_version(self):
        manifest_path = self.bundle_directory / 'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['dart_version'] = '3.12.0'
        manifest_path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, 'does not match Dart'):
            native_notices.native_runtime_notices(self.root, '3.13.3')

    def test_union_preserves_original_notices_sdk_and_distinct_dependency_versions(self):
        sdk = self.root / 'sdk'
        (sdk / 'bin').mkdir(parents=True)
        (sdk / 'version').write_text('3.13.3\n')
        (sdk / 'LICENSE').write_bytes(b'Full SDK license\n')
        (self.root / 'THIRD_PARTY_LICENSES').write_bytes(b'Original project notices\n')
        second_config = self.root / 'packages/cinder_cli/.dart_tool/package_config.json'
        second_config.parent.mkdir(parents=True)
        config = json.loads(self.config.read_text())
        for package in config['packages']:
            package['rootUri'] = (self.root / ('package ' + package['name'])).as_uri()
        second_config.write_text(json.dumps(config))
        second_graph = json.loads(json.dumps(self.graph))
        second_graph['packages'][1]['version'] = '2.1.0'
        with patch.object(native_notices.subprocess, 'check_output', side_effect=[
                json.dumps(self.graph).encode(), json.dumps(second_graph).encode()]):
            notices, metadata = native_notices.collect_notices(
                self.root, str(sdk / 'bin/dart'), '3.13.3')
        self.assertTrue(notices.startswith(b'Original project notices\n'))
        self.assertIn(b'Full SDK license\n', notices)
        self.assertIn(b'Full native runtime dependency licenses\n', notices)
        native_record = next(entry for entry in metadata if entry['name'] == 'Dart native runtime dependencies')
        self.assertEqual(native_record['license_sha256'], hashlib.sha256(
            b'Full native runtime dependency licenses\n').hexdigest())
        self.assertEqual(notices.count(b'Full original license: shared\n'), 1)
        self.assertNotIn(b'dev_only', notices)
        self.assertEqual({entry['version'] for entry in metadata if entry['name'] == 'direct'},
                         {'2.0.0', '2.1.0'})


if __name__ == '__main__':
    unittest.main()
