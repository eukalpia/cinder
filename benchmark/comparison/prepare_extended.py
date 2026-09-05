"""Build opt-in comparison suites; imported by prepare.py before measurement."""
import json
import os
import shutil
import subprocess
import sys

from prepare import HERE, ROOT, executable, file_hash, output


def prepare_extended(args, commands, destination, configuration):
    cargo, rustc, cmake, cxx = [executable(getattr(args, name)) for name in ['cargo', 'rustc', 'cmake', 'cxx']]
    rust_environment = dict(os.environ, RUSTC=rustc)
    build = destination / 'extended-build'
    subprocess.run([commands['dart'], 'compile', 'exe', str(HERE / 'cinder_data.dart'),
                    '-o', str(destination / 'cinder-data')], cwd=ROOT, check=True)
    subprocess.run([commands['go'], 'build', '-trimpath', '-o', str(destination / 'bubbletea-data'), './data'],
                   cwd=HERE / 'bubbletea', check=True)
    cargo_target = build / 'rust'
    subprocess.run([cargo, 'test', '--release', '--locked', '--manifest-path', str(HERE / 'ratatui/Cargo.toml'),
                    '--target-dir', str(cargo_target)], env=rust_environment, check=True)
    subprocess.run([cargo, 'build', '--release', '--locked', '--manifest-path', str(HERE / 'ratatui/Cargo.toml'),
                    '--target-dir', str(cargo_target)], env=rust_environment, check=True)
    shutil.copy2(cargo_target / 'release/ratatui-comparison', destination / 'ratatui')
    cpp_build = build / 'cpp'
    subprocess.run([cmake, '-S', str(HERE / 'ftxui'), '-B', str(cpp_build),
                    '-DCMAKE_BUILD_TYPE=Release', f'-DCMAKE_CXX_COMPILER={cxx}'], check=True)
    subprocess.run([cmake, '--build', str(cpp_build), '--config', 'Release', '--parallel', str(args.build_jobs)], check=True)
    shutil.copy2(cpp_build / 'ftxui-comparison', destination / 'ftxui')
    python_environment = destination / 'textual-env'
    subprocess.run([args.python, '-m', 'venv', str(python_environment)], check=True)
    # Preserve the venv path: resolving its executable symlink loses the venv.
    python = str(python_environment / 'bin/python')
    subprocess.run([python, '-m', 'pip', 'install', '--require-hashes',
                    '-r', str(HERE / 'textual/requirements.lock')], check=True)
    native = {'ratatui': [str(destination / 'ratatui')],
              'ftxui': [str(destination / 'ftxui')],
              'textual': [python, str(HERE / 'textual/adapter.py')]}
    configuration['extended_adapters'] = {**configuration['adapters'], **native}
    configuration['data_adapters'] = {
        'cinder-optimized': [str(destination / 'cinder-data')],
        'ink': [commands['node'], str(HERE / 'javascript/data_ink.mjs')],
        'opentui': [commands['bun'], str(HERE / 'javascript/data_opentui.ts')],
        'bubbletea': [str(destination / 'bubbletea-data')], **native,
    }
    configuration['versions'].update({
        'rustc': output([rustc, '--version']), 'cargo': output([cargo, '--version']),
        'cmake': output([cmake, '--version']), 'cxx': output([cxx, '--version']),
        'ratatui': '0.30.2', 'crossterm': '0.29.0',
        'ftxui': '6.1.9', 'ftxui_commit': '5cfed50702f52d51c1b189b5f97f8beaf5eaa2a6',
        'nlohmann-json': '3.12.0', 'textual_python': output([python, '--version']),
    })
    configuration['textual_packages'] = json.loads(output([python, '-m', 'pip', 'list', '--format=json']))
    configuration['cargo_dependencies'] = json.loads(output([
        cargo, 'metadata', '--locked', '--format-version', '1',
        '--manifest-path', str(HERE / 'ratatui/Cargo.toml')], env=rust_environment))
    configuration['adapter_details'] = {
        'cinder-optimized': {'render': 'Focus/setState/Text', 'pacing': 'SchedulerBinding target FPS'},
        'ink': {'render': 'React state/Box/Text, incrementalRendering=true', 'pacing': 'Ink maxFps'},
        'opentui': {'render': 'retained TextRenderable.content', 'pacing': 'targetFps and maxFps; native output thread'},
        'bubbletea': {'render': 'Update/View string', 'pacing': 'WithFPS'},
        'ratatui': {'render': 'Crossterm input, Terminal.draw, Paragraph', 'pacing': 'application draw-start minimum period; poll/read consumes queued keys between draws and coalesces changes'},
        'ftxui': {'render': 'ScreenInteractive, CatchEvent, Renderer, vbox/text per visible line', 'pacing': 'application waits before public Loop.RunOnceBlocking drains queued tasks and draws; Renderer records next deadline; dispatch remains frame-batched'},
        'textual': {'render': 'App.on_key/Static.update/Rich Text', 'pacing': 'TEXTUAL_FPS environment setting', 'terminal_output': 'stderr'},
    }
    artifacts = [destination / name for name in ['cinder-data', 'bubbletea-data', 'ratatui', 'ftxui']]
    artifacts += [HERE / name for name in [
        'cinder_data.dart', 'workspace.dart', 'data_workload.py', 'open_arrival.py', 'prepare_extended.py',
        'javascript/workspace.mjs', 'javascript/data_ink.mjs', 'javascript/data_opentui.ts',
        'bubbletea/data/main.go', 'ratatui/Cargo.toml', 'ratatui/Cargo.lock',
        'ratatui/src/main.rs', 'ratatui/src/pacing.rs', 'ratatui/src/workspace.rs',
        'ftxui/CMakeLists.txt', 'ftxui/main.cpp', 'ftxui/workspace.hpp',
        'textual/adapter.py', 'textual/requirements.in', 'textual/requirements.lock',
    ]]
    configuration['artifacts_sha256'].update({str(path): file_hash(path) for path in artifacts})
    configuration['application_files'] = {
        str(path): {'logical_bytes': path.stat().st_size,
                    'allocated_bytes': path.stat().st_blocks * 512,
                    'sha256': file_hash(path)}
        for path in artifacts[:4]
    }
    configuration['build_settings'] = {'rust_profile': 'release', 'cargo_locked': True,
                                       'cpp_configuration': 'Release', 'cpp_build_jobs': args.build_jobs,
                                       'textual_hash_checked': True}
    configuration['build_environment'] = {name: os.environ.get(name) for name in [
        'RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'RUSTC_WRAPPER', 'CXXFLAGS',
        'CPPFLAGS', 'LDFLAGS', 'CMAKE_GENERATOR', 'MACOSX_DEPLOYMENT_TARGET',
    ]}
    configuration['footprint_limit'] = ('application_files covers compiled files only; dynamic libraries, '
        'JS/Python runtimes and production dependencies are additional; extended-build and SDK caches are excluded')
    if sys.platform == 'darwin':
        configuration['native_dynamic_libraries'] = {
            str(path): output(['otool', '-L', str(path)]) for path in artifacts[:4]
        }
