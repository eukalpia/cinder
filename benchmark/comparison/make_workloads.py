"""Write identical precomputed text states for every framework adapter."""
import argparse
import json
from pathlib import Path


def workloads(width, height, fps):
    rows = [
        ''.join(chr(33 + ((x * 17 + y * 31) % 90)) for x in range(width))
        for y in range(height)
    ]
    # Avoid accidental ANSI/control bytes; every visible cell is explicit.
    first = '\n'.join(rows)
    sparse = list(rows)
    row = height // 2
    column = width // 2
    replacement = 'Z' if sparse[row][column] != 'Z' else 'A'
    sparse[row] = sparse[row][:column] + replacement + sparse[row][column + 1:]
    dense = [''.join(chr(33 + ((ord(c) - 32) % 90)) for c in line) for line in rows]
    states = {
        'sparse': [first, '\n'.join(sparse)],
        'dense': [first, '\n'.join(dense)],
        'scroll': [first, '\n'.join(rows[1:] + rows[:1])],
    }
    return {
        name: {'name': name, 'width': width, 'height': height,
               'fps': fps, 'frames': frames}
        for name, frames in states.items()
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--width', type=int, default=120)
    parser.add_argument('--height', type=int, default=40)
    parser.add_argument('--fps', type=int, default=60)
    args = parser.parse_args()
    if min(args.width, args.height, args.fps) <= 0:
        parser.error('width, height, and fps must be positive')
    args.directory.mkdir(parents=True, exist_ok=True)
    for name, spec in workloads(args.width, args.height, args.fps).items():
        (args.directory / f'{name}.json').write_text(json.dumps(spec, indent=2) + '\n')
