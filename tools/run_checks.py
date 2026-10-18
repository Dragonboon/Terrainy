#!/usr/bin/env python3
"""Run import and terrain regressions; catch Godot errors even on exit code 0."""
import argparse
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default='godot', help='Godot executable (4.6 tested)')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
checks = [['--editor', '--import']]
checks += [['--script', f'res://tests/{name}.gd'] for name in (
    'terrain_grid_checks', 'terrain_grid_sculpt_checks', 'terrain_edit_regression_checks',
    'terrain_dual_paint_checks', 'terrain_stroke_sampling_checks'
)]
for check in checks:
    command = [args.godot, '--headless', '--path', str(root), *check]
    print('Running:', ' '.join(command), flush=True)
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
    output = result.stdout + result.stderr
    if result.returncode or any(marker in output for marker in ('SCRIPT ERROR:', 'ERROR:', 'WARNING:')):
        print(output)
        sys.exit(result.returncode or 1)
    if '--script' in check:
        print(output.strip())
print('All Terrainy headless checks passed. Interactive editor acceptance is separate.')
