#!/usr/bin/env python3
"""Regression acceptance for PBT provenance, controls and target isolation."""
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source_hashes(module):
    return {str(p.relative_to(module)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in module.rglob('*') if p.is_file() and
            (p.suffix == '.mbt' or p.name in ('moon.pkg', 'moon.pkg.json', 'moon.mod'))
            and not any(part.startswith('.') or part == '_build' for part in p.relative_to(module).parts)}


def run(module, output, *flags):
    before = source_hashes(module)
    result = subprocess.run(['moon', 'run', 'cmd/turtles', '--', '--dir', str(module),
                             '--output-dir', str(output), '--timeout', '120', *flags],
                            cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, flush=True)
    assert result.returncode in (0, 1), result.returncode
    assert source_hashes(module) == before, 'analysis changed source/manifest'
    return json.loads((output / 'report.json').read_text()), result.stdout


def hole_fixture(path, control=False):
    path.mkdir()
    (path / 'moon.mod').write_text('name = "review/pbt_control"\nversion = "0.1.0"\n')
    (path / 'moon.pkg').write_text('import { "moonbitlang/core/quickcheck", } for "test"\n')
    body = 'x + 0' if control else 'if x != -11 { x } else { 0 + x }'
    (path / 'lib.mbt').write_text(f'pub fn hole(x : Int) -> Int {{ {body} }}\n')
    prop = 'x != -11 && @pbt_control.hole(x) == x' if control else '@pbt_control.hole(x) == x'
    (path / 'lib_test.mbt').write_text(f'test "identity" {{ @quickcheck.check((x : Int) => {prop}) }}\n')


with tempfile.TemporaryDirectory(prefix='turtles-pbt-') as tmp:
    temp = Path(tmp)
    module = temp / 'hole'
    hole_fixture(module)
    out = temp / 'reuse'
    amplified, _ = run(module, out, '--pbt-amplify', '4')
    kills = [m['id'] for m in amplified['mutants'] if m.get('amplified')]
    assert kills, 'fixture must exercise amplification-only kill'
    for flags in (('--iterate',), ('--iterate', '--pbt-amplify', '2')):
        # Restore amplification provenance as the prior report for each case.
        (out / 'report.json').write_text(json.dumps(amplified))
        report, _ = run(module, out, *flags)
        rows = {m['id']: m for m in report['mutants']}
        assert all(not rows[mid]['reused'] for mid in kills), rows
        if len(flags) == 1:
            assert all(rows[mid]['outcome'] == 'SURVIVED' for mid in kills), rows
            again, _ = run(module, out, '--iterate')
            assert all(m['outcome'] == 'SURVIVED' for m in again['mutants'] if m['id'] in kills)
    control = temp / 'control'
    hole_fixture(control, control=True)
    report, log = run(control, temp / 'control-out', '--pbt-amplify', '4')
    assert all(m['outcome'] == 'SURVIVED' and not m.get('amplified') for m in report['mutants'])
    assert 'amplified original check/test failed or timed out' in log

    # The full PBT fixture is covered by the preceding CI step. Use this
    # bounded fixture for flag permutations so acceptance stays practical.
    pbt = module
    for i, flags in enumerate((('--emit-properties',), ('--pbt-witness',), ('--pbt-amplify', '4'),
                              ('--emit-properties', '--pbt-witness', '--pbt-amplify', '4'),
                              ('--pbt-amplify', '4', '--pbt-witness', '--emit-properties'))):
        out = temp / f'pbt-{i}'
        report, _ = run(pbt, out, *flags)
        for row in report['mutants']:
            if row.get('amplified'):
                assert row['outcome'] == 'KILLED'
                assert 'witness' not in row and 'witness_skipped' not in row
                assert not (out / 'properties' / (row['id'] + '.mbt')).exists()
        if '--emit-properties' in flags:
            live = {Path(p).name for p in report['properties']}
            assert live == {p.name for p in (out / 'properties').glob('*.mbt')}
        if '--pbt-witness' in flags:
            assert all(m.get('witness_skipped') != 'harness-error' for m in report['mutants'])

    targets = ROOT / 'fixtures/targets'
    out = temp / 'targets'
    for target in ('native', 'js', 'wasm', 'wasm-gc', 'all'):
        report, log = run(targets, out, '--target', target, '--iterate', '--pbt-witness',
                          '--emit-properties', '--pbt-amplify', '4')
        assert all(not m['reused'] for m in report['mutants']), 'cross-target reuse'
        survivors = [m for m in report['mutants'] if m['outcome'] == 'SURVIVED']
        assert survivors and all(m.get('witness') == 'none' and 'witness_skipped' not in m for m in survivors), survivors
        assert {m['path'] for m in survivors} == ({'common.mbt', 'native_only.mbt'} if target in ('native', 'all') else {'common.mbt'})
        assert not any(m['path'] in report['inactive_files'] for m in report['mutants'])
        live = {Path(p).name for p in report['properties']}
        assert live == {p.name for p in (out / 'properties').glob('*.mbt')}
print('PBT acceptance: PASS')
