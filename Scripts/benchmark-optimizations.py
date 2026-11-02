#!/usr/bin/env python3
"""Focused macOS production-source comparisons; never checks out another revision."""
import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile

SCENARIOS = ('disabled-gates', 'identical-profile-settings', 'profile-switch', 'unchanged-profile-rename')
SOURCES = ('Models/ActivityGate.swift', 'Models/Profile.swift', 'Services/ProfileManager.swift',
           'Models/QuickTimerDuration.swift', 'Models/WorkSchedule.swift', 'Models/ActivityMethod.swift')
BASELINE = 'b53797a96f36f3ff22e960d6f3583b306f5b6a0c'


def stats(values):
    return f'{statistics.median(values):.6f} [{min(values):.6f}, {max(values):.6f}]'


def verdict(a, b):
    # Darwin timeval reports microseconds. Require 10ms as a conservative useful floor.
    if max(statistics.median(a), statistics.median(b)) < .01 or max(a) >= min(b) and max(b) >= min(a):
        return 'inconclusive (CPU resolution floor or sample ranges overlap)'
    delta = statistics.median(a) - statistics.median(b)
    return f'candidate {"lower" if delta > 0 else "higher"} CPU by {abs(delta):.6f}s per batch; separated sample ranges; attribution requires a hotspot profiler'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', default='benchmark-results')
    parser.add_argument('--iterations', type=int, default=1000)
    args = parser.parse_args()
    if args.iterations < 1:
        parser.error('iterations must be positive')
    root = Path(__file__).resolve().parents[1]
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    records = []
    report = ['# Focused optimization comparison', '',
              'Status: incomplete; see errors and raw records if the job failed.', '',
              'Scope: synchronous method CPU and wall time with five fake profiles and isolated UserDefaults. '
              'No app launch, event posting, permissions request, network, or whole-app CPU/battery claim. '
              'Setup, initialization, reload, and verification are outside timing. '
              'Process CPU excludes cfprefsd and other system services; persistence calls do not imply durable disk flush.', '',
              'Each side uses swiftc -O -swift-version 5, its own module and executable, and the same harness. '
              'A generated helper aliases Combine.ObservableObject and Combine.Published because imports are file scoped '
              'and production ProfileManager imports only Foundation. Production source bytes are unchanged.', '',
              'Six paired samples alternate AB/BA after one excluded warmup per side per scenario. '
              'Numbers are median [min, max] seconds. Slower-side median CPU below 0.010s or overlapping ranges is inconclusive. '
              'The microsecond getrusage representation is not a guarantee of effective timer resolution.', '',
              'Separate time -l runs capture whole-process resource counters including setup/verification. '
              'These are not repetition timings or hotspot profiles. Source suggests system queries and profile '
              'serialization/persistence as affected paths; resource counters alone cannot establish their quantitative share '
              'or a bottleneck. Performance attribution remains inconclusive without hotspot profiling. '
              'Batches run back-to-back rather than at the app default of one simulation tick per 45 seconds; '
              'batch savings must not be presented as whole-app CPU or battery savings.', '']

    def run(command):
        result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=90)
        records.append({'command': list(map(str, command)), 'status': result.returncode,
                        'stdout': result.stdout, 'stderr': result.stderr})
        if result.returncode:
            raise RuntimeError(f'command failed: {command}')
        return result.stdout

    try:
        if platform.system() != 'Darwin':
            raise RuntimeError('Native macOS required; no simulated measurements')
        refs = {side: run(['git', 'rev-parse', ref + '^{commit}']).strip()
                for side, ref in [('baseline', args.baseline), ('candidate', args.candidate)]}
        if refs['baseline'] != BASELINE:
            raise RuntimeError('baseline must resolve to exact pre-optimization commit')
        environment = []
        for command in (['uname', '-a'], ['swiftc', '--version'], ['xcodebuild', '-version'],
                        ['sysctl', 'hw.ncpu', 'hw.physicalcpu', 'hw.logicalcpu'], ['uptime'], ['pmset', '-g', 'batt']):
            result = subprocess.run(command, text=True, capture_output=True, timeout=30)
            environment.append({'command': command, 'status': result.returncode,
                                'stdout': result.stdout, 'stderr': result.stderr})
        (out / 'environment.json').write_text(json.dumps(environment, indent=2))
        report += [f'Baseline `{refs["baseline"]}`; candidate `{refs["candidate"]}`.', '',
                   'Battery availability is recorded once in environment.json from pmset; no battery estimate is derived.', '',
                   '']
        with tempfile.TemporaryDirectory(prefix='alwayson-benchmark-') as temporary:
            binaries = {}
            for side, ref in refs.items():
                directory = Path(temporary) / side
                directory.mkdir()
                paths = []
                for source in SOURCES:
                    path = directory / Path(source).name
                    path.write_bytes(subprocess.check_output(['git', 'show', f'{ref}:AlwaysOn/Sources/{source}'], cwd=root))
                    paths.append(str(path))
                helper = directory / 'CombineAliases.swift'
                helper.write_text('import Combine\ntypealias ObservableObject = Combine.ObservableObject\ntypealias Published<T> = Combine.Published<T>\n')
                binary = directory / 'benchmark'
                run(['swiftc', '-O', '-wmo', '-swift-version', '5', '-module-name', f'Benchmark_{side}',
                     *paths, str(helper), str(root / 'Scripts/OptimizationBenchmark.swift'), '-o', str(binary)])
                binaries[side] = str(binary)
            for scenario in SCENARIOS:
                report += ['| Scenario | Side | CPU seconds | Wall seconds |', '|---|---|---|---|']
                def sample(side, label, resource=False):
                    queries = args.iterations if scenario == 'disabled-gates' and side == 'baseline' else 0
                    command = [binaries[side], scenario, str(args.iterations), str(queries)]
                    if resource:
                        command = ['/usr/bin/time', '-l', *command]
                    raw = run(command)
                    record = records[-1]
                    (out / f'{scenario}-{side}-{label}.json').write_text(json.dumps(record, indent=2))
                    if resource:
                        (out / f'{scenario}-{side}-resources.txt').write_text(record['stderr'])
                    data = json.loads(raw)
                    if data['failures'] or data['checksum'] != args.iterations or data['iterations'] != args.iterations:
                        raise RuntimeError('invalid workload result')
                    return data
                for side in binaries:
                    sample(side, 'warmup')
                samples = {side: [] for side in binaries}
                for pair in range(6):
                    for side in (('baseline', 'candidate') if pair % 2 == 0 else ('candidate', 'baseline')):
                        samples[side].append(sample(side, str(pair)))
                for side in binaries:
                    data = samples[side]
                    report.append(f'| {scenario} | {side} | {stats([d["cpu_seconds"] for d in data])} | {stats([d["wall_seconds"] for d in data])} |')
                    sample(side, 'resources', True)
                report += ['', f'{scenario}: {verdict([d["cpu_seconds"] for d in samples["baseline"]], [d["cpu_seconds"] for d in samples["candidate"]])}.', '']
        report[2] = 'Status: completed; all workload checks passed. Interpret each scenario separately.'
    except Exception as error:
        report += ['', f'ERROR: {error}']
        raise
    finally:
        (out / 'raw.json').write_text(json.dumps(records, indent=2))
        markdown = '\n'.join(report) + '\n'
        (out / 'report.md').write_text(markdown)
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
                summary.write(markdown)


if __name__ == '__main__':
    main()
