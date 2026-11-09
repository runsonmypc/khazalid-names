#!/usr/bin/env python3
"""Build independent naming products; never discover or modify game installations."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'source'
VERSION = '0.1.0'
DOCS = ['README.md', 'docs/PLAYER-GUIDE.md', 'docs/CAPACITIES.md', 'docs/SOURCES.md', 'docs/PROVENANCE.md', 'CHANGELOG.md']
# Exact product identity tokens, not arbitrary vocabulary or game raw IDs.
IDENTITIES = [
    ('forthammer-name-pools', 'khazalid-name-pools'),
    ('forthammer-names', 'khazalid-names'),
    ('forthammer_names', 'khazalid_names'),
    ('forthammer-local/khazalid-name-pools', 'khazalid-names/native-pools'),
    ('FORTHAMMER_KHAZALID', 'KHAZALID_NAMES'),
    ('FH_KHAZ_', 'KN_KHAZ_'),
    ('language_forthammer_khazalid', 'language_khazalid_names'),
    ('entity_forthammer_names', 'entity_khazalid_names'),
    ('ForthammerLocal', 'KhazalidNames'),
    ('Forthammer names:', 'Khazalid names:'),
    ('FORTHAMMER_PROBE_LAB', 'KHAZALID_NAMES_PROBE_LAB'),
    ('fh-quality-gui-quality-check', 'khazalid-test-gui-quality-check'),
]
GUARDS = {
    'scripts_modactive/forthammer-name-pools.lua': "return false",
    'scripts_modactive/internal/forthammer-names/pools.lua': 'return',
    'scripts_modactive/internal/forthammer-names/adapter.lua': "return nil, 'Khazalid Names cannot run alongside ForthammerLocal.'",
}
BASELINE = json.loads((ROOT/'baseline.json').read_text())


def digest(data):
    return hashlib.sha256(data).hexdigest()


def rename(text):
    for old,new in IDENTITIES:
        text = text.replace(old,new)
    return text


def transform(path, data, profile):
    if profile == 'fork':
        return path, data
    # Latin-1 is a byte-preserving view: raw CP437 and UTF-8 source text remain intact.
    text = rename(data.decode('latin1'))
    if path in ('tools/names/natural_artifact_setup.lua', 'tools/names/natural_artifact_check.lua'):
        text = text.replace("lab=='/tmp/forthammer-probe-cc9yblvy'", "lab:match('^/tmp/khazalid%-probe%-[%w_-]+$')")
    if path in ('tools/names/artifact_adapter_check.lua', 'tools/names/artifact_facts_check.lua'):
        # Native vanilla fixtures use its DRAGON raw. Keep model STAR_DRAGON coverage.
        text = text.replace("raw.creature_id == 'STAR_DRAGON'", "raw.creature_id == 'DRAGON'")
        text = text.replace("raw.creature_id=='STAR_DRAGON'", "raw.creature_id=='DRAGON'")
        text = text.replace("[creature.race].creature_id=='STAR_DRAGON'", "[creature.race].creature_id=='DRAGON'")
    if path == 'tools/names/artifact_facts_check.lua':
        text = text.replace("        local gun=weapon('ITEM_WEAPON_HANDGUN')\n        check(reader.read(gun).facts.type.thrund and not reader.read(gun).facts.type.grund,'native handgun confused by skill')", "        -- HANDGUN native fixture unavailable in vanilla; model check retained.")
        # These materials belong to the private fork. Their exclusion remains
        # covered by models; vanilla native evidence explicitly records skips.
        text = text.replace("        body(amulet,'INORGANIC:GUNPOWDER');check(next(reader.read(amulet).facts.material)==nil,'native gunpowder became stone')", "        -- GUNPOWDER native fixture unavailable in vanilla; model check retained.")
        text = text.replace("        body(amulet,'INORGANIC:WARPSTONE');check(next(reader.read(amulet).facts.material)==nil,'native warpstone became mundane metal/stone')", "        -- WARPSTONE native fixture unavailable in vanilla; model check retained.")
        text = text.replace("ipairs{'INORGANIC:IRON','CREATURE:DWARF:BONE','INORGANIC:WARPSTONE'}", "ipairs{'INORGANIC:IRON','CREATURE:DWARF:BONE'}")
        text = text.replace("local result={model_assertions=", "local result={skipped_native={'HANDGUN (fork-only)', 'GUNPOWDER (fork-only)', 'WARPSTONE (fork-only)'},model_assertions=")
    if path in GUARDS:
        anchor = "    for _,mod in ipairs(require('script-manager').get_active_mods()) do\n"
        if text.count(anchor) != 1:
            raise ValueError('Conflict-guard anchor changed: '+path)
        text = text.replace(anchor, anchor+"        if mod.id == 'ForthammerLocal' then "+GUARDS[path]+" end\n")
    return rename(path), text.encode('latin1')


def source_files():
    files = {str(p.relative_to(SOURCE)):p for p in SOURCE.rglob('*') if p.is_file() and '__pycache__' not in p.parts}
    if set(files) != set(BASELINE):
        raise ValueError('Source allowlist differs: '+str(set(files)^set(BASELINE)))
    for path,p in files.items():
        if p.is_symlink():
            raise ValueError('Symlink source forbidden: '+path)
    return files


def generated_check():
    subprocess.run([sys.executable,str(SOURCE/'tools/names/build.py'),'--check'],check=True,cwd=SOURCE)


def render(profile, output):
    files = source_files()
    generated_check()
    output.mkdir(parents=True,exist_ok=True)
    for path,p in files.items():
        target,data = transform(path,p.read_bytes(),profile)
        dest = output/target;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
    if profile == 'standalone':
        (output/'info.txt').write_text('info\n\n[ID:KhazalidNames]\n[NUMERIC_VERSION:1]\n[DISPLAYED_VERSION:0.1.0]\n[EARLIEST_COMPATIBLE_NUMERIC_VERSION:1]\n[EARLIEST_COMPATIBLE_DISPLAYED_VERSION:0.1.0]\n[NAME:Khazalid Names]\n[DESCRIPTION:Sourced Khazalid naming for Dwarf Fortress with DFHack. Requires a new world; do not combine with ForthammerLocal.]\n[AUTHOR:Khazalid Names contributors]\n',encoding='ascii')
    return output


def build(profile):
    # Build in a new directory so failed validation never leaves a half-built product.
    parent=ROOT/'build';parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=parent) as temp:
        stage=render(profile,Path(temp)/'product')
        target=parent/profile/('KhazalidNames' if profile=='standalone' else 'ForthammerNaming')
        target.parent.mkdir(exist_ok=True)
        if target.exists(): shutil.rmtree(target)
        shutil.move(str(stage),target)
    print(target)
    return target


def package():
    product=build('standalone')
    paths=['info.txt']+[rename(p) for p in BASELINE if p.startswith(('objects/','scripts_modactive/'))]
    content={p:(product/p).read_bytes() for p in paths}
    for p in DOCS:
        content[p]=(ROOT/p).read_bytes()
    manifest={p:digest(data) for p,data in sorted(content.items())}
    content['MANIFEST.json']=(json.dumps(manifest,indent=2)+'\n').encode()
    dist=ROOT/'dist';dist.mkdir(exist_ok=True)
    archive=dist/f'KhazalidNames-{VERSION}.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p,data in sorted(content.items()):
            entry=zipfile.ZipInfo('KhazalidNames/'+p,date_time=(1980,1,1,0,0,0))
            entry.create_system=3;entry.external_attr=0o100644<<16;entry.compress_type=zipfile.ZIP_DEFLATED
            z.writestr(entry,data,compresslevel=9)
    (dist/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (dist/(archive.name+'.sha256')).write_text(digest(archive.read_bytes())+'  '+archive.name+'\n')
    print(archive)
    return archive


def export_fork(destination, apply=False, checkpoint=None):
    destination=Path(destination).resolve()
    generated_check();files=source_files()
    expected = BASELINE
    if checkpoint:
        record=json.loads(Path(checkpoint).read_text())
        if record['destination'] != str(destination) or set(record['files']) != set(BASELINE):
            raise ValueError('Export checkpoint does not match destination/allowlist')
        expected=record['files']
    changes=[]
    # Verify every source destination before any writes. Export touches only this allowlist.
    for path,p in files.items():
        dest=destination/path
        if not dest.is_file() or dest.is_symlink() or destination not in dest.resolve().parents or digest(dest.read_bytes()) not in (expected[path], digest(p.read_bytes())):
            raise ValueError('Destination drift; export refused: '+path)
        if p.read_bytes()!=dest.read_bytes():changes.append((p,dest))
    if apply:
        for p,dest in changes: dest.write_bytes(p.read_bytes())
        record={'destination':str(destination),'files':{path:digest(p.read_bytes()) for path,p in files.items()}}
        out=ROOT/'build'/'fork-export-checkpoint.json';out.parent.mkdir(exist_ok=True)
        out.write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps({'mode':'apply' if apply else 'dry-run','changed':[str(d.relative_to(destination)) for _,d in changes],'verified':len(files)},indent=2))


def check():
    generated_check();source_files()
    subprocess.run([sys.executable,'-m','unittest','discover','-s',str(ROOT/'tests')],cwd=ROOT,check=True)
    subprocess.run([sys.executable,'-m','unittest','discover','-s','tools/names','-p','test_*.py'],cwd=SOURCE,check=True)
    with tempfile.TemporaryDirectory() as temp:
        stage=render('standalone',Path(temp)/'standalone')
        subprocess.run([sys.executable,'tools/names/build.py','--check'],cwd=stage,check=True)
        subprocess.run([sys.executable,'-m','unittest','discover','-s','tools/names','-p','test_*.py'],cwd=stage,check=True)
        for test in ['quality_check.lua','artifact_facts_check.lua']:
            subprocess.run([sys.executable,'tools/checks/run_lua.py','tools/names/'+test],cwd=stage,check=True)
        subprocess.run([sys.executable,'tools/checks/run_lua.py',str(ROOT/'tests/activation.lua')],cwd=stage,check=True)
    print('Standalone source, profiles and model checks passed. Native game tests are separate.')


def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='command',required=True)
    b=sub.add_parser('build');b.add_argument('--profile',choices=['standalone','fork'],default='standalone')
    sub.add_parser('check');sub.add_parser('package')
    e=sub.add_parser('export-fork');e.add_argument('destination');e.add_argument('--apply',action='store_true');e.add_argument('--checkpoint')
    args=parser.parse_args()
    if args.command=='build':build(args.profile)
    elif args.command=='check':check()
    elif args.command=='package':package()
    else:export_fork(args.destination,args.apply,args.checkpoint)

if __name__=='__main__':main()
