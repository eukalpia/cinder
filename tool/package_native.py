"""Package native Cinder binaries and separate symbols using only Python's stdlib."""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile
import zipfile

from native_notices import collect_notices


ROOT = Path(__file__).resolve().parent.parent
LICENSES = {'LICENSE': 'LICENSE', 'NOTICE': 'NOTICE.md',
            'THIRD_PARTY_LICENSES': 'THIRD_PARTY_LICENSES'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_file(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'Expected a regular file: {path}')
    data = path.read_bytes()
    if not data:
        raise ValueError(f'File is empty: {path}')
    return data


def package_version():
    match = re.search(r'^version:\s*[\'\"]?([^\s\'\"]+)',
                      (ROOT / 'pubspec.yaml').read_text(encoding='utf-8'), re.MULTILINE)
    if match is None:
        raise ValueError('Root pubspec.yaml has no version')
    return match.group(1)


def write_archive(path, root, files):
    if path.suffix == '.zip':
        with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED,
                             compresslevel=9) as archive:
            for name, (data, mode) in sorted(files.items()):
                info = zipfile.ZipInfo(f'{root}/{name}', (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | mode) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, data, compresslevel=9)
    else:
        with path.open('wb') as destination:
            with gzip.GzipFile(filename='', mode='wb', fileobj=destination,
                               mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode='w') as archive:
                    for name, (data, mode) in sorted(files.items()):
                        info = tarfile.TarInfo(f'{root}/{name}')
                        info.size, info.mode, info.mtime = len(data), mode, 0
                        archive.addfile(info, io.BytesIO(data))


def archive_files(path):
    files = {}

    def add(name, data, mode):
        member = PurePosixPath(name)
        if (member.is_absolute() or '..' in member.parts or '\\' in name or
                len(member.parts) < 2 or name in files):
            raise ValueError(f'Invalid or duplicate archive member: {name}')
        files[name] = (data, mode & 0o777)

    if path.suffix == '.zip':
        with zipfile.ZipFile(path) as archive:
            for info in archive.infolist():
                mode = info.external_attr >> 16
                if info.is_dir() or stat.S_IFMT(mode) != stat.S_IFREG:
                    raise ValueError(f'Unexpected archive member: {info.filename}')
                add(info.filename, archive.read(info), mode)
    else:
        with tarfile.open(path, 'r:gz') as archive:
            for info in archive.getmembers():
                if not info.isfile():
                    raise ValueError(f'Unexpected archive member: {info.name}')
                with archive.extractfile(info) as source:
                    add(info.name, source.read(), info.mode)
    return files


def verify_archive(path):
    checksum_path = path.with_name(path.name + '.sha256')
    expected_checksum = f'{digest(path.read_bytes())}  {path.name}\n'
    if checksum_path.read_text(encoding='utf-8') != expected_checksum:
        raise ValueError(f'Archive checksum does not match: {path}')
    files = archive_files(path)
    manifests = [name for name in files if name.endswith('/manifest.json')]
    if len(manifests) != 1:
        raise ValueError(f'Expected exactly one manifest: {path}')
    manifest_name = manifests[0]
    manifest = json.loads(files[manifest_name][0])
    root = manifest['archive_root']
    if manifest_name != f'{root}/manifest.json':
        raise ValueError('Manifest root does not match archive layout')
    records = manifest['files']
    expected = {f'{root}/{entry["path"]}' for entry in records}
    if len(expected) != len(records) or set(files) != expected | {manifest_name}:
        raise ValueError('Archive files do not match manifest')
    for entry in records:
        data, mode = files[f'{root}/{entry["path"]}']
        if (len(data) != entry['bytes'] or digest(data) != entry['sha256'] or
                mode != int(entry['mode'], 8)):
            raise ValueError(f'Manifest mismatch: {entry["path"]}')
    names = {entry['path'] for entry in records}
    if not set(LICENSES).issubset(names):
        raise ValueError('Archive is missing license notices')
    extension = '.exe' if manifest['target_os'] == 'windows' else ''
    if manifest['component'] == 'runtime':
        binaries = {f'bin/cinder{extension}', f'bin/cinder-demo{extension}'}
        if names != binaries | set(LICENSES):
            raise ValueError('Runtime archive contains unexpected or missing files')
        if any(not files[f'{root}/{name}'][1] & 0o111 for name in binaries):
            raise ValueError('Executable modes were lost')
    elif manifest['component'] == 'symbols':
        symbols = names - set(LICENSES)
        expected_symbols = {f'symbols/{name}{extension}.debug'
                            for name in ('cinder', 'cinder-demo')}
        if symbols != expected_symbols:
            raise ValueError('Expected separate debugging symbols for both programs')
    else:
        raise ValueError('Unknown archive component')
    return manifest


def build(args):
    version = args.version or package_version()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+-]*', version):
        raise ValueError('Version cannot be used in an archive filename')
    identity = f'cinder-{version}-{args.target_os}-{args.target_arch}'
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    extension = '.exe' if args.target_os == 'windows' else ''
    runtime = {}
    for name in ('cinder', 'cinder-demo'):
        source = args.input / (name + extension)
        mode = 0o755 if args.target_os == 'windows' else stat.S_IMODE(source.stat().st_mode)
        if not mode & 0o111:
            raise ValueError(f'Binary is not executable: {source}')
        runtime[f'bin/{name}{extension}'] = (read_file(source), mode)
    symbol_root = args.symbols or args.input / 'symbols'
    symbols = {}
    if not symbol_root.is_dir() or symbol_root.is_symlink():
        raise ValueError(f'Expected debugging symbols directory: {symbol_root}')
    for name in ('cinder', 'cinder-demo'):
        name += extension + '.debug'
        symbols[f'symbols/{name}'] = (read_file(symbol_root / name), 0o644)

    archive_suffix = '.zip' if args.target_os == 'windows' else '.tar.gz'
    distributions = []
    for component, payload in [('runtime', runtime), ('symbols', symbols)]:
        root = identity + ('-symbols' if component == 'symbols' else '')
        path = destination / (root + archive_suffix)
        checksum = path.with_name(path.name + '.sha256')
        if path.exists() or checksum.exists():
            raise ValueError(f'Refusing to overwrite existing distribution: {path}')
        distributions.append((component, payload, root, path, checksum))

    notices, dependency_licenses = collect_notices(ROOT, args.dart_executable, args.dart_version)
    for component, payload, root, path, checksum in distributions:
        files = dict(payload)
        for name, source in LICENSES.items():
            files[name] = (notices if name == 'THIRD_PARTY_LICENSES' else read_file(ROOT / source), 0o644)
        manifest = {
            'schema_version': 1, 'archive_root': root, 'component': component,
            'version': version, 'target_os': args.target_os, 'target_arch': args.target_arch,
            'source_commit': args.commit, 'dart_version': args.dart_version,
            'dependency_licenses': dependency_licenses,
            'files': [{'path': name, 'bytes': len(data), 'sha256': digest(data),
                       'mode': f'{mode:04o}'}
                      for name, (data, mode) in sorted(files.items())],
        }
        files['manifest.json'] = ((json.dumps(manifest, indent=2) + '\n').encode(), 0o644)
        write_archive(path, root, files)
        checksum.write_text(f'{digest(path.read_bytes())}  {path.name}\n', encoding='utf-8')
        verify_archive(path)
        print(f'Packaged and verified {path}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    package = commands.add_parser('build', help='Create and verify native distributions')
    package.add_argument('--input', type=Path, default=ROOT / 'build/native')
    package.add_argument('--symbols', type=Path)
    package.add_argument('--output', type=Path, default=ROOT / 'build/packages')
    package.add_argument('--target-os', choices=['linux', 'macos', 'windows'], required=True)
    package.add_argument('--target-arch', choices=['x64', 'arm64'], required=True)
    package.add_argument('--version')
    package.add_argument('--commit', default=os.environ.get('GITHUB_SHA', ''))
    package.add_argument('--dart-version', required=True)
    package.add_argument('--dart-executable', default='dart', help='Compiler used for these builds (default: dart on PATH)')
    verify = commands.add_parser('verify', help='Verify every archive and checksum in a directory')
    verify.add_argument('directory', type=Path)
    verify.add_argument('--commit', help='Require this source commit in every manifest')
    args = parser.parse_args()
    if args.command == 'build':
        build(args)
    else:
        archives = sorted([*args.directory.glob('*.zip'), *args.directory.glob('*.tar.gz')])
        if not archives:
            raise ValueError(f'No distribution archives found: {args.directory}')
        for archive in archives:
            manifest = verify_archive(archive)
            if args.commit and manifest['source_commit'] != args.commit:
                raise ValueError(f'Archive belongs to a different source commit: {archive}')
            print(f'Verified {archive}')


if __name__ == '__main__':
    main()
