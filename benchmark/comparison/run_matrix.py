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
    parser.add_argument('--suite', choices=['rc2', 'expanded-grid', 'data'], default='rc2')
    parser.add_argument('--records', type=int, default=50000, help='initial record count for the data suite')
    parser.add_argument('--arrival-interval-ms', type=int, choices=[4, 20],
                        help='data suite only: independent fixed-arrival input schedule')
    parser.add_argument('--event-deadline-ms', type=float, default=5000)
    args = parser.parse_args()
    if args.arrival_interval_ms is not None and args.suite != 'data':
        parser.error('fixed arrivals require --suite data')
    if not math.isfinite(args.event_deadline_ms) or args.event_deadline_ms <= 0:
        parser.error('event-deadline-ms must be finite and positive')
    if min(args.rounds, args.frames, args.width) < 1 or args.height < 2:
        parser.error('rounds, frames, and width must be positive; height must be at least two')
    if (args.warmup < 0 or args.settle_seconds < 0 or
            not math.isfinite(args.settle_seconds) or not 1 <= args.fps <= 120):
        parser.error('warmup and settle time must be nonnegative; fps must be between 1 and 120')
    configuration = json.loads(args.commands.read_text())
    if args.suite != 'rc2':
        key = 'data_adapters' if args.suite == 'data' else 'extended_adapters'
        if key not in configuration:
            parser.error('prepare with --extended before selecting this suite')
        configuration['adapters'] = configuration[key]
    if not configuration.get('adapters'):
        parser.error('commands must contain at least one adapter')
    for path, expected in configuration.get('artifacts_sha256', {}).items():
        if hashlib.sha256(Path(path).read_bytes()).hexdigest() != expected:
            parser.error(f'Prepared adapter artifact changed: {path}; prepare again')
    if args.output.exists() and any(args.output.iterdir()):
        parser.error('output directory must be empty to preserve previous trial evidence')
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'configuration.json').write_text(json.dumps(configuration, indent=2) + '\n')
    if args.suite == 'data':
        from data_workload import workload
        spec = workload(args.width, args.height, args.fps, args.records)
        cases = {spec['name']: spec}
    else:
        cases = workloads(args.width, args.height, args.fps)
    matrix = {key: getattr(args, key) for key in
              ['rounds', 'frames', 'warmup', 'settle_seconds', 'fps', 'width', 'height']}
    matrix.update(workloads=list(cases), seed=20260905, suite=args.suite,
                  records=args.records if args.suite == 'data' else None,
                  arrival_interval_ms=args.arrival_interval_ms,
                  event_deadline_ms=args.event_deadline_ms)
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
        arrival_flags = [] if args.arrival_interval_ms is None else [
            '--arrival-interval-ms', str(args.arrival_interval_ms),
            '--event-deadline-ms', str(args.event_deadline_ms),
        ]
        subprocess.run([
            sys.executable, str(Path(__file__).with_name('run_pty.py')),
            '--workload', str((args.output / f'{case}.json').resolve()),
            '--result', str(result.resolve()), '--label', adapter,
            '--terminal-output', configuration.get('adapter_details', {}).get(adapter, {}).get('terminal_output', 'stdout'),
            '--frames', str(args.frames), '--warmup', str(args.warmup),
            '--settle-seconds', str(args.settle_seconds),
            *arrival_flags,
            '--', *configuration['adapters'][adapter],
        ], check=True)


if __name__ == '__main__':
    main()
