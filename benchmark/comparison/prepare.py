"""Build every adapter before a serial PTY comparison (macOS or Linux)."""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent


def executable(value):
    found = shutil.which(value)
    if found is None:
        raise ValueError(f'Executable not found: {value}')
    # rustup selects cargo/rustc from argv[0]; Python venvs also rely on the
    # invoked path. Dereferencing these symlinks changes the command semantics.
    return str(Path(found).absolute())


def output(command, **kwargs):
    return subprocess.check_output(command, text=True, **kwargs).strip()


def source_hash(directory):
    digest = hashlib.sha256()
    for path in sorted(path for path in directory.rglob('*.dart') if path.is_file()):
        digest.update(str(path.relative_to(directory)).encode())
        digest.update(b'\0')
        digest.update(path.read_bytes())
        digest.update(b'\0')
    return digest.hexdigest()


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', default='v1.0.0-rc.1')
    parser.add_argument('--output', type=Path, default=HERE / 'bin')
    for name in ['dart', 'node', 'bun', 'go', 'npm']:
        parser.add_argument(f'--{name}', default=name)
    parser.add_argument('--extended', action='store_true', help='also build Ratatui, FTXUI, Textual and workspace-v1 adapters')
    for name, default in [('cargo', 'cargo'), ('rustc', 'rustc'), ('cmake', 'cmake'), ('cxx', 'c++'), ('python', sys.executable)]:
        parser.add_argument(f'--{name}', default=default)
    parser.add_argument('--build-jobs', type=int, default=4)
    args = parser.parse_args()
    commands = {name: executable(getattr(args, name))
                for name in ['dart', 'node', 'bun', 'go', 'npm']}
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    baseline = output(['git', 'rev-parse', '--verify', args.baseline + '^{commit}'], cwd=ROOT)
    current = output(['git', 'rev-parse', 'HEAD'], cwd=ROOT)
    environment = dict(os.environ)
    environment['PATH'] = str(Path(commands['node']).parent) + os.pathsep + environment['PATH']

    subprocess.run([commands['dart'], 'pub', 'get'], cwd=ROOT, check=True)
    measured_lock = destination / 'measured-pubspec.lock'
    shutil.copyfile(ROOT / 'pubspec.lock', measured_lock)
    subprocess.run([commands['dart'], 'compile', 'exe', str(HERE / 'cinder.dart'),
                    '-o', str(destination / 'cinder-optimized')], cwd=ROOT, check=True)
    with tempfile.TemporaryDirectory(prefix='cinder_baseline_') as temporary:
        source = Path(temporary)
        archive = source / 'source.tar'
        subprocess.run(['git', 'archive', '-o', str(archive), baseline, 'lib', 'pubspec.yaml'],
                       cwd=ROOT, check=True)
        subprocess.run(['tar', '-xf', str(archive), '-C', str(source)], check=True)
        shutil.copyfile(HERE / 'cinder.dart', source / 'adapter.dart')
        shutil.copyfile(ROOT / 'pubspec.lock', source / 'pubspec.lock')
        subprocess.run([commands['dart'], 'pub', 'get', '--enforce-lockfile'], cwd=source, check=True)
        baseline_hash = source_hash(source / 'lib')
        subprocess.run([commands['dart'], 'compile', 'exe', str(source / 'adapter.dart'),
                        '-o', str(destination / 'cinder-baseline')], cwd=source, check=True)

    subprocess.run([commands['npm'], 'ci'], cwd=HERE / 'javascript', env=environment, check=True)
    subprocess.run([commands['go'], 'build', '-trimpath', '-o', str(destination / 'bubbletea'), '.'],
                   cwd=HERE / 'bubbletea', check=True)
    dependencies = json.loads((HERE / 'javascript/package.json').read_text())['dependencies']
    artifacts = [destination / name for name in ['cinder-baseline', 'cinder-optimized', 'bubbletea']]
    artifacts.append(measured_lock)
    artifacts.extend(HERE / name for name in [
        'cinder.dart', 'javascript/ink.mjs', 'javascript/opentui.ts',
        'javascript/package.json', 'javascript/package-lock.json',
        'bubbletea/main.go', 'bubbletea/go.mod', 'bubbletea/go.sum',
        'prepare.py', 'run_matrix.py', 'run_pty.py', 'make_workloads.py',
        'summarize.py', 'requirements.txt',
    ])
    configuration = {
        'baseline_commit': baseline,
        'current_commit': current,
        'current_worktree_dirty': bool(output(['git', 'status', '--porcelain'], cwd=ROOT)),
        'source_sha256': {'baseline_lib': baseline_hash, 'current_lib': source_hash(ROOT / 'lib'),
                          'dart_lock': file_hash(measured_lock),
                          'adapter': hashlib.sha256((HERE / 'cinder.dart').read_bytes()).hexdigest()},
        'artifacts_sha256': {str(path): file_hash(path) for path in artifacts},
        'versions': {**{name: output([commands[name], '--version'])
                        for name in ['dart', 'node', 'bun']},
                     'go': output([commands['go'], 'version'], cwd=HERE / 'bubbletea'), **dependencies,
                     'bubbletea': output([commands['go'], 'list', '-m', 'charm.land/bubbletea/v2'],
                                         cwd=HERE / 'bubbletea')},
        'driver': {'python': sys.version, 'executable': sys.executable,
                   'packages': {name: importlib.metadata.version(name)
                                for name in ['psutil', 'pyte', 'wcwidth']}},
        'host': {'platform': platform.platform(), 'machine': platform.machine(),
                 'logical_cpus': os.cpu_count()},
        'go_binary_build_info': output([commands['go'], 'version', '-m', str(destination / 'bubbletea')],
                                       cwd=HERE / 'bubbletea'),
        'adapters': {
            'cinder-baseline': [str(destination / 'cinder-baseline')],
            'cinder-optimized': [str(destination / 'cinder-optimized')],
            'ink': [commands['node'], str(HERE / 'javascript/ink.mjs')],
            'opentui': [commands['bun'], str(HERE / 'javascript/opentui.ts')],
            'bubbletea': [str(destination / 'bubbletea')],
        },
    }
    if args.extended:
        from prepare_extended import prepare_extended
        prepare_extended(args, commands, destination, configuration)
    (destination / 'commands.json').write_text(json.dumps(configuration, indent=2) + '\n')
    print(f'Adapters ready. Matrix configuration: {destination / "commands.json"}')


if __name__ == '__main__':
    main()
