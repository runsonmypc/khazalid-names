import importlib.util
import json
import re
import tempfile
import shutil
import subprocess
import sys
import zipfile
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location('product_build',Path(__file__).resolve().parents[1]/'build.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)

class Profiles(unittest.TestCase):
    def test_fork_exact_parity(self):
        for path,p in b.source_files().items():
            target,data=b.transform(path,p.read_bytes(),'fork')
            self.assertEqual(target,path)
            self.assertEqual(data,p.read_bytes())

    def test_standalone_closure_and_guards(self):
        files=dict(b.transform(p,f.read_bytes(),'standalone') for p,f in b.source_files().items())
        self.assertEqual(len(files),len(b.BASELINE))
        for path,data in files.items():
            if not path.startswith('scripts_modactive/'):continue
            text=data.decode('utf-8')
            self.assertNotIn('FH_KHAZ_',text);self.assertNotIn('FORTHAMMER_KHAZALID',text)
            self.assertNotIn('internal/forthammer-names',text)
            for name in re.findall(r"reqscript\(['\"]([^'\"]+)",text):
                self.assertIn('scripts_modactive/'+name+'.lua',files)
        for path in b.GUARDS:
            text=files[b.rename(path)].decode()
            self.assertIn("mod.id == 'ForthammerLocal'",text)
            self.assertIn("mod.id == 'KhazalidNames'",text)

    def test_drift_refusal_before_any_writes(self):
        with tempfile.TemporaryDirectory() as temp:
            target=Path(temp)
            for path,p in b.source_files().items():
                dest=target/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())
            b.export_fork(target)
            changed=target/'scripts_modactive/forthammer-names.lua'
            changed.write_bytes(b'concurrent edit')
            with self.assertRaisesRegex(ValueError,'Destination drift'):
                b.export_fork(target,True)
            self.assertEqual(changed.read_bytes(),b'concurrent edit')

    def test_unknown_source_rejected(self):
        p=b.SOURCE/'private-test.txt'
        try:
            p.write_text('private')
            with self.assertRaisesRegex(ValueError,'allowlist'):b.source_files()
        finally:p.unlink(missing_ok=True)

    def test_clean_copy_deterministic_package_and_stale_refusal(self):
        with tempfile.TemporaryDirectory() as temp:
            project=Path(temp)/'project'
            shutil.copytree(b.ROOT,project,ignore=shutil.ignore_patterns('build','dist','__pycache__','.git'))
            command=[sys.executable,str(project/'build.py'),'package']
            subprocess.run(command,check=True,stdout=subprocess.DEVNULL)
            archive=project/'dist'/f'KhazalidNames-{b.VERSION}.zip'
            first=archive.read_bytes()
            subprocess.run(command,check=True,stdout=subprocess.DEVNULL)
            self.assertEqual(first,archive.read_bytes())
            with zipfile.ZipFile(archive) as z:
                names=z.namelist()
                self.assertEqual(names,sorted(names))
                self.assertFalse(any('/tools/' in p or '/source/' in p or p.endswith('.png') for p in names))
                manifest=json.loads(z.read('KhazalidNames/MANIFEST.json'))
                for name,sha in manifest.items():
                    self.assertEqual(b.digest(z.read('KhazalidNames/'+name)),sha)
                self.assertEqual(set(names),{'KhazalidNames/'+p for p in manifest}|{'KhazalidNames/MANIFEST.json'})
            generated=project/'source/scripts_modactive/internal/forthammer-names/data.lua'
            generated.write_bytes(generated.read_bytes()+b'-- stale\n')
            result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            self.assertNotEqual(result.returncode,0)
            self.assertIn(b'Stale generated files',result.stdout)

    def test_successive_canonical_exports_with_checkpoint(self):
        with tempfile.TemporaryDirectory() as temp:
            project=Path(temp)/'project';fork=Path(temp)/'fork'
            shutil.copytree(b.ROOT,project,ignore=shutil.ignore_patterns('build','dist','__pycache__','.git'))
            shutil.copytree(project/'source',fork)
            relative='scripts_modactive/forthammer-names.lua'
            source=project/'source'/relative
            source.write_bytes(source.read_bytes()+b'\n-- first reviewed change\n')
            command=[sys.executable,str(project/'build.py'),'export-fork',str(fork),'--apply']
            subprocess.run(command,check=True,stdout=subprocess.DEVNULL)
            self.assertEqual(source.read_bytes(),(fork/relative).read_bytes())
            source.write_bytes(source.read_bytes()+b'\n-- second reviewed change\n')
            checkpoint=project/'build/fork-export-checkpoint.json'
            subprocess.run(command+['--checkpoint',str(checkpoint)],check=True,stdout=subprocess.DEVNULL)
            self.assertEqual(source.read_bytes(),(fork/relative).read_bytes())
            (fork/relative).write_bytes(b'concurrent private edit')
            result=subprocess.run(command+['--checkpoint',str(checkpoint)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual((fork/relative).read_bytes(),b'concurrent private edit')

    def test_native_fixture_profile_preserves_model_coverage(self):
        path='tools/names/artifact_facts_check.lua'
        _,data=b.transform(path,(b.SOURCE/path).read_bytes(),'standalone')
        text=data.decode();models,native=text.split('local model_assertions=assertions',1)
        for token in ['ITEM_WEAPON_HANDGUN','WARPSTONE','GUNPOWDER','STAR_DRAGON']:
            self.assertIn(token,models)
        for call in ["weapon('ITEM_WEAPON_HANDGUN')", "body(amulet,'INORGANIC:WARPSTONE')", "body(amulet,'INORGANIC:GUNPOWDER')", "creature_id=='STAR_DRAGON'"]:
            self.assertNotIn(call,native)
        self.assertIn("creature_id=='DRAGON'",native)
        self.assertIn("skipped_native={'HANDGUN (fork-only)', 'GUNPOWDER (fork-only)', 'WARPSTONE (fork-only)'}",native)
