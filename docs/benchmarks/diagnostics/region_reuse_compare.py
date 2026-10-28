"""Reproduce the archived v0.2 region-reuse performance comparison.

This diagnostic builds two local Git snapshots and runs the actual benchmark
helpers. It writes only below out/region-reuse-comparison. Exit 1 means the
candidate exceeded the diagnostic slowdown threshold; it is not a CI test.
"""
from pathlib import Path
import subprocess, sys, statistics, re, json, argparse
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--odin', required=True, help='Path to the documented Odin compiler')
parser.add_argument('--speed', action='store_true', help='Use -o:speed for both snapshots')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
work = root/'out/region-reuse-comparison'
work.mkdir(parents=True, exist_ok=True)
odin = str(Path(args.odin).resolve())
refs = {'baseline':'96461223cdbf43080acb957276c045ad704f4606', 'candidate':'3e31c743298f758b4cafd4f425e296a59cd95e34'}
main = '''main :: proc() {
    allocator_state := Bench_Allocator_State{backing = context.allocator}
    context.allocator = bench_allocator(&allocator_state)
    measure_regions(&allocator_state)
    measure_tree(10_000, &allocator_state)
    context.allocator = allocator_state.backing
}
'''
for name, ref in refs.items():
    dest = work/name
    if not dest.exists():
        dest.mkdir(parents=True)
        archive = subprocess.Popen(['git','-C',str(root),'archive',ref],stdout=subprocess.PIPE)
        subprocess.run(['tar','-xf','-','-C',str(dest)],stdin=archive.stdout,check=True)
        archive.stdout.close()
        if archive.wait(): raise RuntimeError('archive failed')
    source = (dest/'benchmarks/main.odin').read_text()
    probe = dest/'probe'
    probe.mkdir(exist_ok=True)
    (probe/'main.odin').write_text(source.rsplit('main :: proc()',1)[0]+main)
    print('BUILD',name,flush=True)
    subprocess.run([odin,'build',str(probe),*(['-o:speed'] if args.speed else []),'-out:'+str(work/name)+'-probe'],check=True)
records = []
log = work/('matched-speed.txt' if args.speed else 'matched-default.txt')
with log.open('w') as output:
    for i,name in enumerate(['baseline','candidate','candidate','baseline','baseline','candidate']):
        result = subprocess.run([str(work/name)+'-probe'],capture_output=True,text=True,check=True)
        output.write(f'PROCESS {i+1} {name} {refs[name]}\n'+result.stdout)
        reuse = int(re.search(r'reused_for_unrelated_sibling wall_ns (\d+)', result.stdout)[1])
        tree = result.stdout.split('tree 10000\n')[1]
        initial = int(re.search(r'initial wall_ns (\d+)',tree)[1])
        unchanged = int(re.search(r'root_invalidated_unchanged wall_ns (\d+)',tree)[1])
        records.append({'name':name,'region_reuse_ns':reuse,'initial_10k_ns':initial,'unchanged_10k_ns':unchanged})
medians = {name:{key:statistics.median(r[key] for r in records if r['name']==name) for key in ['region_reuse_ns','initial_10k_ns','unchanged_10k_ns']} for name in refs}
ratio=medians['candidate']['region_reuse_ns']/medians['baseline']['region_reuse_ns']
summary={'refs':refs,'records':records,'medians':medians,'region_ratio':ratio,'failed':ratio>1.5 and medians['candidate']['region_reuse_ns']>1_000_000}
(work/('comparison-speed.json' if args.speed else 'comparison-default.json')).write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2),flush=True)
print('Raw output:', log, flush=True)
print('REGION REUSE '+('FAIL' if summary['failed'] else 'PASS'),flush=True)
sys.exit(int(summary['failed']))
