#!/usr/bin/env python3
"""Static source/encoding/selector checks; native behavior is a separate lab gate."""
import json
import re
import unittest
import tempfile
from pathlib import Path
import build
import test_native_products as native_products
import catalog


class NamingRaws(unittest.TestCase):
    def setUp(self):
        self.data = json.loads(build.DATA.read_text())
        self.files = build.compile_files()
        self.raw = self.files[build.ROOT/'objects/language_forthammer_khazalid.txt'].decode('cp437')

    def test_reproducibility_and_encoding(self):
        self.assertEqual(self.files, build.compile_files())
        for path, content in self.files.items():
            self.assertEqual(content, path.read_bytes(), path)
        self.assertNotIn('\ufffd', self.raw)
        self.assertEqual(self.raw.count('['), self.raw.count(']'))

    def test_unique_words_and_complete_translation(self):
        definitions = re.findall(r'\[WORD:([^\]]+)\]', self.raw)
        translated = re.findall(r'\[T_WORD:([^:]+):([^\]]*)\]', self.raw)
        self.assertEqual(len(definitions), len(set(definitions)))
        self.assertEqual(len(translated), len(dict(translated)))
        fallback = json.loads(build.DATA.with_name('vanilla-dwarf.json').read_text())
        self.assertEqual(set(dict(translated)), set(definitions) | set(fallback))
        self.assertTrue(all(dict(translated)[k] == v for k,v in fallback.items()))
        self.assertTrue(all(dict(translated)[k].isascii() for k in definitions))
        self.assertTrue(all(dict(translated)[k] for k in definitions))

    def test_semantic_product_and_reservations(self):
        roots = self.data['roots']
        reserved = {build.normalize(n) for n in self.data['reserved']}
        for motif in self.data['motifs']:
            self.assertEqual(roots[motif]['role'], 'motif')
            for obj in self.data['family_objects']:
                self.assertEqual(roots[obj]['role'], 'craft')
                self.assertNotEqual(motif,obj)
                self.assertNotIn(build.normalize(motif+obj),reserved)
        for root in roots.values():
            self.assertRegex(root['source'], r'^DPG:4[4-7]$')
            self.assertTrue(root['gloss'])
        self.assertNotIn('grund',self.data['family_objects'])  # excludes attested Durazgrund

    def test_additional_types_and_sources(self):
        packs = [json.loads(p.read_text()) for p in build.DATA.with_name('types').glob('*.json')]
        reserved = {build.normalize(n) for p in packs for n in p.get('reserved', [])}
        for pack in packs:
            seen = set()
            self.assertTrue(pack['evidence'], pack['category'])
            for pattern in pack['patterns']:
                name = ''.join(pattern['parts'])
                self.assertTrue(name.isascii())
                self.assertLessEqual(len(name),64)
                key = build.normalize(name)
                self.assertNotIn(key,seen)
                self.assertNotIn(key,reserved)
                seen.add(key)
                self.assertTrue(pattern['note'])
                self.assertTrue(pattern['sources'])
                self.assertEqual(len(pattern['parts']), len(set(pattern['parts'])))
                for part in pattern['parts']:
                    root = pack['roots'][part]
                    self.assertTrue(build.reviewed_root(part, root), (part,root))
                    self.assertTrue(root['gloss'])
            self.assertEqual(len(seen),len(pack['patterns']))

    def test_supplemental_vocabulary_is_explicit(self):
        self.assertTrue(build.reviewed_root('agril', {'gloss':'silver metal','source':'DSS:101'}))
        self.assertFalse(build.reviewed_root('invented', {'gloss':'silver metal','source':'DSS:101'}))
        self.assertFalse(build.reviewed_root('agril', {'gloss':'gold','source':'DSS:101'}))
        self.assertFalse(build.reviewed_root('agril', {'gloss':'silver metal','source':'DSS:102'}))

    def test_diversity_report_counts_sets(self):
        report = catalog.diversity()
        catalogs = catalog.catalog()
        for category, counts in report['categories'].items():
            self.assertEqual(counts['spellings'],len(catalogs[category]))
            self.assertLessEqual(counts['appearance_variant_families'],counts['spellings'])
            self.assertGreater(counts['appearance_variant_families'],0)
        for pair, count in report['cross_category_shared_spellings'].items():
            left,right = pair.split('/')
            self.assertEqual(count,len(set(catalogs[left]) & set(catalogs[right])))

    def test_artifact_grouped_compositions(self):
        pack = json.loads(build.DATA.with_name('types').joinpath('artifact.json').read_text())
        triples = [p for p in pack['patterns'] if len(p['parts']) == 3]
        self.assertTrue(triples, 'artifact expansion must include grouped three-part imagery')
        for pattern in triples:
            self.assertTrue(pattern.get('grouping'), pattern['parts'])
            self.assertIn('[', pattern['grouping'])
            self.assertIn(']', pattern['grouping'])
        self.assertTrue(all(len(p['parts']) in (2, 3) for p in pack['patterns']))

    def test_complete_family_words_and_preserved_products(self):
        roots = self.data['roots']
        families = {tuple(p['parts']) for p in self.data['family_patterns']}
        rejected = {tuple(p) for p in self.data['rejected_material_pairs']}
        self.assertEqual(len(families), len(self.data['family_patterns']))
        self.assertTrue({(m,o) for m in self.data['motifs'] for o in self.data['family_objects']} - rejected <= families)
        self.assertFalse(families & rejected)
        reserved = {build.normalize(n) for n in self.data['reserved']}
        for path in build.DATA.with_name('types').glob('*.json'):
            reserved.update(build.normalize(n) for n in json.loads(path.read_text()).get('reserved', []))
        translations = dict(re.findall(r'\[T_WORD:([^:]+):([^\]]*)\]', self.raw))
        # Figure and Site use FrontCompound + RearCompound in either selector
        # direction. Both selectors install the same complete front token and
        # absent rear, so their exhaustive translated products are these labels.
        words = {k:v for k,v in translations.items() if k.startswith('FH_KHAZ_FAMILY_')}
        self.assertEqual(set(words.values()), {''.join(p) for p in families})
        self.assertEqual(len(words),len(families))
        for parts in families:
            self.assertIn(len(parts),(2,3))
            self.assertEqual(len(set(parts)),len(parts))
            self.assertNotIn(build.normalize(''.join(parts)),reserved)
        holds = {tuple(p) for p in self.data['hold_patterns']}
        self.assertEqual(len(holds),len(self.data['hold_patterns']))
        old_holds = {(m,o,h) for m in self.data['motifs'] for o in self.data['hold_objects'] for h in self.data['hold_heads']}
        self.assertTrue({p for p in old_holds if p[:2] not in rejected} <= holds)
        for parts in holds:
            self.assertEqual(len(set(parts)),3)
            self.assertNotIn(parts[-2],('irkul','ruf'))
            self.assertNotIn(build.normalize('karak'+''.join(parts)),reserved)
        for category, head in self.data['place_heads'].items():
            place_families = {p for p in families if len(p) == 2 and p[-1] in self.data['place_emblem_objects']}
            names = {m+head for m in self.data['motifs']} | {''.join(p)+head for p in place_families}
            self.assertEqual(len(names),len(place_families)+len(self.data['motifs']),category)
            for parts in place_families:
                self.assertNotIn(head,parts)
                self.assertNotIn(parts[-1],('irkul','ruf'))
            self.assertFalse({build.normalize(n) for n in names} & reserved)

    def test_grouped_family_material_emblems(self):
        patterns = self.data['family_patterns']
        pairs = {tuple(p['parts']) for p in patterns if len(p['parts']) == 2}
        triples = [p for p in patterns if len(p['parts']) == 3]
        self.assertEqual(len(pairs),141, 'preserve the reviewed native pair catalog')
        self.assertEqual(len(triples),160)
        for pattern in triples:
            qualifier, material, craft = pattern['parts']
            self.assertIn((material,craft),pairs)
            allowed = ('bryn','lok') if material == 'galaz' else ('kol','zan','gorl','skarrenruf','bryn','lok')
            self.assertIn(qualifier,allowed)
            self.assertIn(material,('duraz','azul','galaz','wutroth'))
            gloss = self.data['roots']
            self.assertEqual(pattern['grouping'],gloss[qualifier]['gloss']+' ['+gloss[material]['gloss']+' '+gloss[craft]['gloss']+']')
            self.assertTrue(pattern['note'])
            self.assertTrue(pattern['sources'])
        # Adding triple shared labels must not extend unrelated place products.
        catalogs = catalog.catalog()
        self.assertEqual(len(catalogs['hold']),524)
        for category in self.data['place_heads']:
            self.assertEqual(len(catalogs[category]),140)

    def test_compiler_rejects_ungrouped_family_triple(self):
        from unittest.mock import patch
        data = json.loads(build.DATA.read_text())
        del next(p for p in data['family_patterns'] if len(p['parts']) == 3)['grouping']
        original_read = Path.read_text
        def altered_read(path, *args, **kwargs):
            return json.dumps(data) if path == build.DATA else original_read(path,*args,**kwargs)
        with patch.object(Path,'read_text',altered_read):
            with self.assertRaisesRegex(AssertionError,'family grouping'):
                build.compile_files()

    def test_reserved_identity_material_derivatives(self):
        from unittest.mock import patch
        original_read = Path.read_text
        artifact_path = build.DATA.with_name('types')/'artifact.json'
        for path, field in ((build.DATA,'family_patterns'), (artifact_path,'patterns')):
            data = json.loads(path.read_text())
            # All words and the material-object base are individually valid;
            # only insertion into reserved Kolgrund makes this unacceptable.
            data[field].append({'parts':['kol','azul','grund'],
                                'grouping':'black [metal hammer]',
                                'gloss':'black metal hammer',
                                'sources':['DPG:43'], 'note':'Regression fixture.'})
            def altered_read(target, *args, **kwargs):
                return json.dumps(data) if target == path else original_read(target,*args,**kwargs)
            with patch.object(Path,'read_text',altered_read):
                with self.assertRaisesRegex(AssertionError,'reserved material derivative'):
                    build.compile_files()
        # Brynduraz is a protected identity, but adding an independent final
        # object head makes Bryndurazmakaz a different symbolic composition.
        # This policy must not degrade into a blanket subsequence ban.
        self.assertIn(['bryn','duraz','makaz'],[p['parts'] for p in self.data['family_patterns']])
        self.assertIn('FH_KHAZ_FAMILY_BRYNDURAZMAKAZ',self.raw)

    def test_lua_string_encoding(self):
        self.assertEqual(build.lua('‘Dwarf’'), '"\\226\\128\\152Dwarf\\226\\128\\153"')
        for path, content in self.files.items():
            if path.suffix == '.lua': self.assertNotRegex(content.decode('ascii'), r'(?<!\\)\\u[0-9a-fA-F]{4}')

    def native_inputs(self):
        lua = self.files[build.ROOT/'scripts_modactive/internal/forthammer-names/data.lua'].decode('ascii')
        return native_products.generated_inputs(self.raw, lua)

    def test_native_finite_compositions_and_sentinels(self):
        pools, translations, forms = self.native_inputs()
        self.assertNotIn('artifact', pools)  # Explicit edit, no native artifact generator.
        self.assertNotIn('[WORD:FH_KHAZ_POOL_', self.raw)
        packs = [json.loads(p.read_text()) for p in build.DATA.with_name('types').glob('*.json')]
        for pack in packs:
            tokens = {'FH_KHAZ_TYPE_' + pack['category'].upper() + '_' + ''.join(p['parts']).upper()
                      for p in pack['patterns']}
            self.assertTrue(tokens.issubset(translations))  # All explicit proposals remain.
            if pack['category'] != 'artifact':
                self.assertEqual(set(pools[pack['category']][2]), tokens)
                self.assertEqual([pools[pack['category']][i] for i in (0,1,3,4,5)], [[-1]] * 5)
        report = native_products.audit((pools, translations, forms))
        expected = sum(len(pack['patterns']) for pack in packs if pack['category'] != 'artifact')
        self.assertEqual(sum(row['accepted_component_assignments'] for row in report['categories'].values()), expected)
        self.assertEqual(sum(row['distinct_native_names'] for row in report['categories'].values()), expected)

    def test_native_model_rejects_optional_words_and_invalid_sentinels(self):
        for replacement in (-2, 'FH_KHAZ_TYPE_SQUAD_KOLGRONG'):
            pools, translations, forms = self.native_inputs()
            pools['squad'][3] = [replacement]
            with self.assertRaisesRegex(AssertionError, 'Optional native slot'):
                native_products.audit((pools, translations, forms))
        pools, translations, forms = self.native_inputs()
        pools['artifact'] = pools['squad']
        with self.assertRaisesRegex(AssertionError, 'unapproved native naming type'):
            native_products.audit((pools, translations, forms))

    def test_native_scope(self):
        entity=self.files[build.ROOT/'objects/entity_forthammer_names.txt'].decode('ascii')
        self.assertEqual(re.findall(r'\[SELECT_ENTITY:([^\]]+)\]',entity),['MOUNTAIN'])
        self.assertNotIn('[SELECT_SYMBOL:',entity)
        self.assertNotIn('[SELECT_SYMBOL:SITE:',entity)  # government, not physical site
        self.assertNotRegex(self.raw, r'\[(?:FRONT_COMPOUND|REAR_COMPOUND|THE_NOUN|THE_COMPOUND|OF_NOUN|ADJ:)')
        self.assertNotIn('[TRANSLATION:DWARF]',self.raw)

    def test_corpus_scan_ocr_boundaries(self):
        names = {'family':['Kolkron'],'person-male':['Bardin Kolkron'], 'forename-male':['Bardin']}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'book.md').write_text('BardinKolkron\nBar-din Kol-kron\nxxKolkronyy\nBardin\nKolkro\u0131n\n')
            report = catalog.scan(names,root)
        self.assertEqual([v['name'] for v in report['hits']], ['Bardin Kolkron']*2)
        self.assertEqual(report['full_person_names_covered'],1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'book.md').write_text('Kl\u0131 nka\n\u017ftromez')
            report = catalog.scan({'family':['Klinka','Stromez']},root)
        self.assertEqual(report['hits'],[])


if __name__ == '__main__':
    unittest.main()
