# SPDX-License-Identifier: MIT
"""Capture complete Xcode output and summarize actual diagnostics, without suppression."""
import json
import re
import subprocess

DIAGNOSTIC = re.compile(r'^(?:(?P<location>.+?):)?\s*(?P<severity>fatal error|error|warning):\s*(?P<message>.*)$')
TOOL_DIAGNOSTIC = re.compile(
    r'^(?P<location>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+\S+\[\d+:\d+\])'
    r'\s+(?P<severity>fatal error|error|warning):\s*(?P<message>.*)$')


def diagnostics(lines, returncode):
    entries = []
    for line in lines:
        match = DIAGNOSTIC.match(line.strip()) or TOOL_DIAGNOSTIC.match(line.strip())
        if not match:
            continue
        entry = match.groupdict()
        entry['location'] = entry['location'] or ''
        entry['severity'] = 'error' if entry['severity'] == 'fatal error' else entry['severity']
        entry['owned_source'] = any(path in entry['location'] for path in (
            'PyroWaveRuntime/apple/', 'PyroWaveRuntime/client/', 'PyroWaveRuntime/protocol/'))
        entries.append(entry)
    errors = sum(entry['severity'] == 'error' for entry in entries)
    warnings = sum(entry['severity'] == 'warning' for entry in entries)
    return {'schema_version': 1, 'returncode': returncode, 'succeeded': returncode == 0 and errors == 0,
            'errors': errors, 'warnings': warnings,
            'owned_source_warnings': sum(entry['severity'] == 'warning' and entry['owned_source'] for entry in entries),
            'diagnostics': entries, 'physical_apple_tv_tested': False, 'auto_qualified': False}


def capture(command, directory):
    directory.mkdir(parents=True, exist_ok=False)
    lines = []
    with (directory/'xcodebuild.log').open('w', encoding='utf-8') as output:
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, encoding='utf-8', errors='replace') as process:
            for line in process.stdout:
                print(line, end='', flush=True)
                output.write(line)
                lines.append(line)
            returncode = process.wait()
    report = diagnostics(lines, returncode)
    (directory/'diagnostics.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f"Xcode diagnostics: {report['errors']} errors, {report['warnings']} warnings "
          f"({report['owned_source_warnings']} in owned runtime sources). Report: {directory/'diagnostics.json'}")
    if returncode:
        raise subprocess.CalledProcessError(returncode, command)
    if report['errors']:
        raise RuntimeError('Xcode reported errors despite a zero exit status; inspect diagnostics.json.')
    return report
