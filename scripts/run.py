"""Parse private client configuration without executing shell code."""
import argparse
import os
from pathlib import Path
import shlex
import stat
import sys

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {'NQ_UPLOAD_KEY', 'NQ_UPLOAD_URL'}

def load_config(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise ValueError('Client configuration must be a regular, non-symlink file.')
    if stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise ValueError('Client configuration is readable by others; run chmod 600 on it first.')
    if path.stat().st_size > 16384:
        raise ValueError('Client configuration is too large.')
    values = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        parts = shlex.split(line, comments=True)
        if not parts:
            continue
        if parts[0] == 'export':
            parts = parts[1:]
        if len(parts) != 1 or '=' not in parts[0]:
            raise ValueError('Invalid client configuration; only KEY=value assignments are accepted.')
        key, value = parts[0].split('=', 1)
        if key not in ALLOWED or key in values or any(ord(c) < 32 for c in value):
            raise ValueError('Unsupported/duplicate client configuration key or control characters.')
        values[key] = value
    return values

def main():
    parser = argparse.ArgumentParser(description='Guided benchmark launch. Defaults to local reports. Sharing sends raw logs, never automatically redacted.')
    parser.add_argument('--config', help='Private client.env path; default service/client.env if present')
    parser.add_argument('--share', action='store_true', help='Use configured service; noninteractive use additionally requires --consent-upload')
    args, cli = parser.parse_known_args()
    env = os.environ.copy()
    path = Path(args.config) if args.config else ROOT / 'service/client.env'
    if args.config or path.exists():
        try:
            env.update(load_config(path))
        except (ValueError, OSError) as error:
            parser.error(str(error))
    share = args.share
    if not share and env.get('NQ_UPLOAD_URL') and sys.stdin.isatty() and '--upload-url' not in cli:
        share = input('Configured service found. Share RAW reports (may contain IPs), after final review? [y/N] ').lower() == 'y'
    if share:
        if not env.get('NQ_UPLOAD_URL') or not env.get('NQ_UPLOAD_KEY'):
            parser.error('Sharing needs NQ_UPLOAD_URL and NQ_UPLOAD_KEY in a private client configuration.')
        if '--upload-url' in cli:
            parser.error('Use either --share or --upload-url, not both.')
        if '--consent-upload' not in cli:
            if not sys.stdin.isatty():
                parser.error('Noninteractive --share requires --consent-upload.')
            if args.share and input('Allow RAW report upload after final review? [y/N] ').lower() != 'y':
                return 0
            cli.append('--consent-upload')
        cli.extend(['--upload-url', env['NQ_UPLOAD_URL']])
    os.execvpe('bash', ['bash', str(ROOT / 'NodeQuality.sh'), *cli], env)

if __name__ == '__main__':
    main()
