"""Summarize complete trial sets without selecting the fastest run."""
import argparse
import json
from pathlib import Path
import statistics


def summarize(directory):
    matrix = json.loads((directory / 'matrix.json').read_text())
    configuration = json.loads((directory / 'configuration.json').read_text())
    lines = ['CPU and RSS are medians of independent trials; CPU range includes every trial.',
             'Latency includes frame pacing and PTY observation; it is not uncapped rendering time.\n',
             '| Workload | Adapter | CPU ms/frame (range) | RSS MiB | Bytes/frame | p50 / p95 / p99 ms |',
             '| --- | --- | ---: | ---: | ---: | ---: |']
    for workload in matrix['workloads']:
        for adapter in configuration['adapters']:
            trials = [json.loads((directory / f'{adapter}-{workload}-{trial + 1}.json').read_text())
                      for trial in range(matrix['rounds'])]
            for result in trials:
                if (result['measured_frames'] != matrix['frames'] or
                        result['warmup_frames'] != matrix['warmup'] or
                        result['configured_fps'] != matrix['fps'] or
                        result['width'] != matrix['width'] or
                        result['height'] != matrix['height'] or
                        result['settle_seconds'] != matrix['settle_seconds'] or
                        result['adapter'] != adapter or result['workload'] != workload or
                        result['command'][:-1] != configuration['adapters'][adapter] or
                        result['screen_verified_frames'] != matrix['frames'] + matrix['warmup'] + 1 or
                        not result['terminal_modes_restored']):
                    raise ValueError(f'Incomplete or mismatched trial: {adapter}/{workload}')
            cpu = [trial['cpu_ms_per_frame'] for trial in trials]
            rss = statistics.median(trial['rss_median_bytes'] for trial in trials) / 1024 ** 2
            volume = statistics.median(trial['output_bytes_per_frame'] for trial in trials)
            latency = ' / '.join(f'{statistics.median(trial["latency_ms"][q] for trial in trials):.2f}'
                                 for q in ['p50', 'p95', 'p99'])
            lines.append(f'| {workload} | {adapter} | {statistics.median(cpu):.3f} '
                         f'({min(cpu):.3f}–{max(cpu):.3f}) | {rss:.1f} | {volume:.0f} | {latency} |')
    # Emit only after every trial validates, so redirection cannot leave a
    # plausible partial report when a later trial is absent or mismatched.
    print('\n'.join(lines))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    summarize(parser.parse_args().directory)
