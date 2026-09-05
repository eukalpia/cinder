"""Collect native distribution notices from the SDK and runtime dependency graphs."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urljoin, urlsplit
from urllib.request import url2pathname


def required_bytes(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'Missing regular license file: {path}')
    data = path.read_bytes()
    if not data:
        raise ValueError(f'License file is empty: {path}')
    return data


def runtime_licenses(graph, config_path):
    """Follow runtime edges, including shared dependencies also used by tests."""
    nodes = {package['name']: package for package in graph['packages']}
    config = json.loads(config_path.read_text(encoding='utf-8'))
    roots = {package['name']: package['rootUri'] for package in config['packages']}
    pending, visited, licenses = [graph['root']], set(), {}
    while pending:
        name = pending.pop()
        if name in visited:
            continue
        visited.add(name)
        if name not in nodes or name not in roots:
            raise ValueError(f'Dependency graph or package config is missing {name}')
        package = nodes[name]
        # dependencies includes dev dependencies on the root; directDependencies
        # is the explicit runtime edge list in dart pub deps --json.
        if 'directDependencies' not in package:
            raise ValueError(f'Dependency graph has no runtime edge list for {name}')
        pending.extend(package['directDependencies'])
        uri = urlsplit(urljoin(config_path.resolve().as_uri(), roots[name]))
        if uri.scheme != 'file' or uri.netloc not in ('', 'localhost'):
            raise ValueError(f'Unsupported package root URI for {name}: {roots[name]}')
        root = Path(url2pathname(uri.path))
        candidates = [root / candidate for candidate in
                      ('LICENSE', 'LICENSE.txt', 'LICENSE.md', 'COPYING')]
        license_path = next((path for path in candidates if path.exists()), None)
        if license_path is None:
            raise ValueError(f'Missing runtime dependency license: {name} {package["version"]} in {root}')
        data = required_bytes(license_path)
        key = (name, package['version'], hashlib.sha256(data).hexdigest())
        licenses[key] = data
    return licenses


def native_runtime_notices(repository, version):
    directory = repository / 'tool/licenses' / f'dart-{version}'
    manifest = json.loads(required_bytes(directory / 'manifest.json'))
    if manifest.get('schema_version') != 1 or manifest.get('dart_version') != version:
        raise ValueError(f'Native runtime license manifest does not match Dart {version}')
    if manifest.get('bundle_file') != 'NOTICES':
        raise ValueError('Native runtime license manifest must reference NOTICES')
    data = required_bytes(directory / 'NOTICES')
    if hashlib.sha256(data).hexdigest() != manifest.get('bundle_sha256'):
        raise ValueError(f'Native runtime license bundle checksum does not match: {directory}')
    return data


def collect_notices(repository, dart_executable, expected_version):
    compiler = Path(shutil.which(dart_executable) or dart_executable).resolve()
    sdk = compiler.parent.parent
    version_path = sdk / 'version'
    if not version_path.is_file():
        raise ValueError(f'Cannot locate SDK version beside {compiler}; supply --dart-executable')
    version = version_path.read_text(encoding='utf-8').strip()
    if version != expected_version:
        raise ValueError(f'Dart SDK version {version} does not match declared {expected_version}')
    sdk_license = required_bytes(sdk / 'LICENSE')
    native_licenses = native_runtime_notices(repository, version)
    licenses = {}
    for package_root in (repository, repository / 'packages/cinder_cli'):
        graph = json.loads(subprocess.check_output(
            [str(compiler), 'pub', 'deps', '--json'], cwd=package_root))
        licenses.update(runtime_licenses(graph, package_root / '.dart_tool/package_config.json'))

    records = [('Dart SDK', version, sdk_license),
               ('Dart native runtime dependencies', version, native_licenses)]
    records.extend((name, version, data)
                   for (name, version, _), data in sorted(licenses.items()))
    output = bytearray(required_bytes(repository / 'THIRD_PARTY_LICENSES'))
    metadata = []
    for name, version, data in records:
        output.extend(('\n\n' + '=' * 80 + f'\n{name} {version}\n' + '=' * 80 + '\n\n').encode())
        output.extend(data)
        metadata.append({'name': name, 'version': version,
                         'license_sha256': hashlib.sha256(data).hexdigest()})
    return bytes(output), metadata
