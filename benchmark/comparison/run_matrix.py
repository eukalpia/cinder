"""Run the same PTY cases serially, rotating adapter order reproducibly."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import subprocess
import sys

from make_workloads import workloads


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--commands', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--frames', type=int, default=180)
    parser.add_argument('--warmup', type=int, default=30)
    parser.add_argument('--settle-seconds', type=float, default=6)
    parser.add_argument('--fps', type=int, default=60)
    parser.add_argument('--width', type=int, default=120)
    parser.add_argument('--height', type=int, default=40)
    args = parser.parse_args()
    if min(args.rounds, args.frames, args.width) < 1 or args.height < 2:
        parser.error('rounds, frames, and width must be positive; height must be at least two')
    if (args.warmup < 0 or args.settle_seconds < 0 or
            not math.isfinite(args.settle_seconds) or not 1 <= args.fps <= 120):
        parser.error('warmup and settle time must be nonnegative; fps must be between 1 and 120')
    configuration = json.loads(args.commands.read_text())
    if not configuration.get('adapters'):
        parser.error('commands must contain at least one adapter')
    for path, expected in configuration.get('artifacts_sha256', {}).items():
        if hashlib.sha256(Path(path).read_bytes()).hexdigest() != expected:
            parser.error(f'Prepared adapter artifact changed: {path}; prepare again')
    if args.output.exists() and any(args.output.iterdir()):
        parser.error('output directory must be empty to preserve previous trial evidence')
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'configuration.json').write_text(json.dumps(configuration, indent=2) + '\n')
    cases = workloads(args.width, args.height, args.fps)
    matrix = {key: getattr(args, key) for key in
              ['rounds', 'frames', 'warmup', 'settle_seconds', 'fps', 'width', 'height']}
    matrix.update(workloads=list(cases), seed=20260905)
    (args.output / 'matrix.json').write_text(json.dumps(matrix, indent=2) + '\n')
    for name, spec in cases.items():
        (args.output / f'{name}.json').write_text(json.dumps(spec, indent=2) + '\n')
    generator = random.Random(20260905)
    order = []
    for trial in range(args.rounds):
        case_names = list(cases)
        generator.shuffle(case_names)
        for case in case_names:
            adapters = list(configuration['adapters'])
            generator.shuffle(adapters)
            for adapter in adapters:
                order.append({'round': trial + 1, 'workload': case, 'adapter': adapter})
    (args.output / 'order.json').write_text(json.dumps(order, indent=2) + '\n')
    for entry in order:
        trial, case, adapter = entry['round'], entry['workload'], entry['adapter']
        result = args.output / f'{adapter}-{case}-{trial}.json'
        print(f'round {trial}: {adapter} / {case}', flush=True)
        subprocess.run([
            sys.executable, str(Path(__file__).with_name('run_pty.py')),
            '--workload', str((args.output / f'{case}.json').resolve()),
            '--result', str(result.resolve()), '--label', adapter,
            '--frames', str(args.frames), '--warmup', str(args.warmup),
            '--settle-seconds', str(args.settle_seconds),
            '--', *configuration['adapters'][adapter],
        ], check=True)


if __name__ == '__main__':
    main()
