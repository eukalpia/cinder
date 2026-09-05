"""Verify the pinned notice bundle, optionally checking its upstream originals."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen


def digest(data):
    return hashlib.sha256(data).hexdigest()


def selected_notice(data, selection):
    if selection.get('complete_file'):
        return data
    if 'line_start' in selection:
        return b''.join(data.splitlines(keepends=True)[
            selection['line_start'] - 1:selection['line_end_inclusive']])
    notice = data[selection['byte_start']:selection['byte_end_exclusive']]
    return notice + (b'\n' if selection.get('append_newline') else b'')


def verify(fetch=False):
    directory = Path(__file__).resolve().parent
    manifest = json.loads((directory / 'manifest.json').read_text())
    bundle = (directory / manifest['bundle_file']).read_bytes()
    if digest(bundle) != manifest['bundle_sha256']:
        raise ValueError('Native runtime notice bundle checksum mismatch')
    for source in manifest['sources']:
        marker = ('Source: ' + source['url'] + '\n' + '=' * 80 + '\n\n').encode()
        if bundle.count(marker) != 1:
            raise ValueError(f'Missing or duplicate source section: {source["component"]}')
        start = bundle.index(marker) + len(marker)
        notice = bundle[start:start + source['notice_bytes']]
        if digest(notice) != source['notice_sha256']:
            raise ValueError(f'Notice section checksum mismatch: {source["component"]}')
        if fetch:
            with urlopen(source['url'], timeout=30) as response:
                original = response.read()
            if source['url'].endswith('?format=TEXT'):
                original = base64.b64decode(original)
            if len(original) != source['bytes'] or digest(original) != source['sha256']:
                raise ValueError(f'Upstream source checksum mismatch: {source["url"]}')
            if selected_notice(original, source['notice_selection']) != notice:
                raise ValueError(f'Upstream notice selection mismatch: {source["url"]}')
    print(f'Verified {len(manifest["sources"])} source sections for Dart {manifest["dart_version"]}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true', help='also verify pinned upstream originals')
    verify(parser.parse_args().fetch)
