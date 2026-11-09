#!/usr/bin/env python3
"""Compile reviewed naming data. --check detects stale outputs; never edits saves."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = Path(__file__).with_name('lexicon.json')


def normalize(value):
    return re.sub('[^a-z0-9]', '', value.lower())


def lua(value):
    if isinstance(value, str):
        return '"' + ''.join(('\\' + chr(b)) if b in (34,92) else chr(b) if 32 <= b <= 126 else ('\\%03d' % b) for b in value.encode('utf-8')) + '"'
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    if isinstance(value, dict):
        return '{\n' + ',\n'.join('[' + lua(k) + ']=' + lua(v) for k, v in value.items()) + '\n}'
    raise TypeError(type(value))


# Additional glossary entries individually checked against the official printed
# source. A registered book/page alone cannot authorize arbitrary vocabulary.
SUPPLEMENTAL_ROOTS = {
    'brog': ('bread', 'DSS:101'),
    'goruz': ('horn', 'DSS:102'),
    'hirn': ('horn (instrument)', 'DSS:102'),
    'drin': ('road', 'DSS:102'),
    'izril': ('jewels', 'DSS:103'),
    'kuchungkuchung': ('water pump', 'DSS:103'),
    'muzkhgrum': ('blast furnace slag', 'DSS:103'),
    'ori': ('work', 'DSS:103'),
    'thrag': ('wound', 'DSS:104'),
    'thrynaz': ('laws', 'DSS:104'),
    'tiwaz': ('rest', 'DSS:104'),
    'un': ('and', 'DSS:104'),
    'wutraz': ('spear', 'DSS:105'),
    'wulthrung': ('money', 'DSS:105'),
    'zagaz': ('remembering', 'DSS:105'),
    'zaraz': ('gift', 'DSS:105'),
    'agril': ('silver metal', 'DSS:101'),
    'izor': ('copper', 'DSS:103'),
    'mizpal': ('volcanic glass', 'DSS:103'),
    'zunthrum': ('statues', 'DSS:105'),
    'dron': ('thunder', 'DSS:102'),
    'lhune': ('moonlight', 'DSS:103'),
    'mhornar': ('shadow', 'DSS:103'),
    'nar': ('sunrise', 'DSS:103'),
    'yar': ('sunset', 'DSS:105'),
    'varr': ('sea', 'DSS:105'),
    'wyr': ('snow', 'DSS:105'),
    'skaud': ('song', 'DSS:104'),
}


def reviewed_root(name, root):
    return bool(re.fullmatch(r'DPG:4[4-7]', root['source'])) or (
        root['gloss'], root['source']) == SUPPLEMENTAL_ROOTS.get(name)


def compile_files():
    data = json.loads(DATA.read_text())
    fallback = json.loads(DATA.with_name('vanilla-dwarf.json').read_text())
    registry = json.loads(DATA.with_name('sources.json').read_text())
    packs = [json.loads(p.read_text()) for p in sorted(DATA.with_name('types').glob('*.json'))]
    for pack in packs:
        data['reserved'].extend(pack.get('reserved', []))
    data['reserved'] = sorted(set(data['reserved']))
    reserved = {normalize(v) for v in data['reserved']}
    roots = data['roots']
    rejected_pairs = {tuple(parts) for parts in data['rejected_material_pairs']}
    def coherent(parts):
        assert not any(tuple(parts[i:i+2]) in rejected_pairs for i in range(len(parts)-1)), parts
    def no_material_disguise(parts):
        # Editorial identity protection: inserting only a material must not
        # disguise a reserved two-root name with the same final object head.
        # This deliberately does not ban every reserved-root subsequence.
        if len(parts) == 3 and parts[1] in {'azul', 'duraz', 'galaz', 'wutroth', 'angaz', 'agril', 'izor', 'mizpal'}:
            assert normalize(parts[0] + parts[2]) not in reserved, ('reserved material derivative', parts)
    words, trans, person, site = [], {}, [], []

    def word(key, definition, translation, pool):
        token = 'FH_KHAZ_' + key.upper()
        assert token not in trans
        assert all(c not in translation for c in '[]:\n\r')
        translation.encode('ascii')
        # Placement flags would leak these words into global/non-Dwarf pools.
        definition = re.sub(r'\[(?:FRONT_COMPOUND|REAR_COMPOUND|THE_NOUN|THE_COMPOUND|OF_NOUN)[^\]]*\]\n?', '', definition)
        definition = re.sub(r'\[ADJ:([^\]]+)\]', r'[NOUN:\1:\1]', definition)
        definition = re.sub(r'\[ADJ_DIST:[^\]]+\]\n?', '', definition)
        words.append(f'[WORD:{token}]\n' + definition + '\n')
        trans[token] = translation
        pool.append(token)
        return token

    for sex, names in data['forenames'].items():
        assert len(names) == len(set(names))
        for name in names:
            assert normalize(name) not in reserved
            word('GIVEN_' + name, f'[NOUN:{name}:{name}]\n[THE_NOUN_SING]', name.lower(), person)
    for motif in data['motifs']:
        gloss = roots[motif]['gloss']
        word('MOTIF_' + motif, f'[ADJ:{gloss}]\n[ADJ_DIST:2]\n[FRONT_COMPOUND_ADJ]', motif, person)
    for obj in data['family_objects']:
        gloss = roots[obj]['gloss']
        word('CRAFT_' + obj, f'[NOUN:{gloss}:{gloss}]\n[REAR_COMPOUND_NOUN_SING]\n[THE_COMPOUND_NOUN_SING]\n[OF_NOUN_SING]', obj, person)
    data['families'] = []
    family_seen = set()
    for pattern in data['family_patterns']:
        parts = pattern['parts']
        assert len(parts) in (2, 3) and len(set(parts)) == len(parts)
        if len(parts) == 3:
            assert pattern.get('grouping'), ('family grouping is required', parts)
        assert all(p in roots for p in parts)
        coherent(parts)
        no_material_disguise(parts)
        name = ''.join(parts).capitalize()
        assert normalize(name) not in reserved and name not in family_seen, name
        family_seen.add(name)
        gloss = ' '.join(roots[p]['gloss'] for p in parts)
        sources = list(dict.fromkeys([roots[p]['source'] for p in parts] + pattern['sources']))
        assert all(ref in registry for ref in sources)
        token = word('FAMILY_' + name, f'[NOUN:{gloss}:{gloss}]', name.lower(), person)
        family = dict(name=name, roots=parts, gloss=gloss, token=token,
                      sources=sources, status=pattern['note'])
        if pattern.get('grouping'):
            family['grouping'] = pattern['grouping']
        data['families'].append(family)
    # A complete architectural label can stand alone, but must not become a
    # second geographical/architectural head (e.g. dome-stream or vault-dome).
    data['place_families'] = [family for family in data['families']
                              if len(family['roots']) == 2
                              and family['roots'][-1] in data['place_emblem_objects']]
    word('HOLD_PREFIX', '[PREFIX:hold of ]\n[FRONT_COMPOUND_PREFIX]\n[ADJ:enduring]\n[ADJ_DIST:2]', 'karak ', site)
    data['holds'] = []
    for parts in data['hold_patterns']:
        coherent(parts)
        assert len(parts) == 3 and len(set(parts)) == 3 and all(p in roots for p in parts)
        suffix = ''.join(parts).capitalize()
        name = 'Karak ' + suffix
        assert normalize(name) not in reserved
        gloss = ' '.join(roots[w]['gloss'] for w in parts)
        token = word('HOLD_' + suffix, f'[NOUN:{gloss}:{gloss}]', suffix, site)
        data['holds'].append({'name': name, 'gloss': 'hold of the ' + gloss, 'token': token,
                              'roots': ['karak'] + parts})
    data['types'], data['native_pools'] = {}, {}
    data['source_registry'] = registry
    for pack in packs:
        for reference in [r['source'] for r in pack['roots'].values()] + [e['source'] for e in pack['evidence']]:
            assert reference in registry, ('unregistered source',reference)
        category = pack['category']
        assert re.fullmatch('[a-z]+', category)
        assert category not in data['types']
        candidates, seen = [], set()
        for pattern in pack['patterns']:
            parts = pattern['parts']
            coherent(parts)
            assert len(parts) >= 2 and all(p in pack['roots'] for p in parts)
            assert len(parts) == len(set(parts)), (category, 'repeated root', parts)
            name = ''.join(parts).capitalize()
            key = normalize(name)
            assert key not in reserved and key not in seen, (category, name)
            seen.add(key)
            assert len(name) <= 64
            if category == 'artifact':
                no_material_disguise(parts)
                assert len(parts) in (2, 3), ('artifact composition length', parts)
                if len(parts) == 3:
                    assert pattern.get('grouping'), ('artifact grouping is required', parts)
            assert all(reviewed_root(p, pack['roots'][p]) for p in parts), ('unreviewed root', category, parts)
            assert all(pack['roots'][p]['source'] in registry for p in parts)
            assert all(reference in registry for reference in pattern['sources']), ('unregistered pattern source',category)
            token = word('TYPE_' + category + '_' + name, '[NOUN:' + pattern['gloss'] + ':' + pattern['gloss'] + ']', name.lower(), [])
            sources = list(dict.fromkeys([pack['roots'][p]['source'] for p in parts] + pattern['sources']))
            candidate = dict(name=name, roots=parts, gloss=pattern['gloss'], sources=sources,
                             status=pattern['note'], token=token, category=category)
            if pattern.get('grouping'):
                candidate['grouping'] = pattern['grouping']
            candidates.append(candidate)
        assert candidates, category
        data['types'][category] = dict(candidates=candidates, roots=pack['roots'], evidence=pack['evidence'])
        if category != 'artifact':
            # Native general/squad templates always select FirstName (TheX).
            # Keep the entire reviewed composition in that component. Explicit
            # no-word sentinels suppress optional adjective/compound/of slots,
            # preventing DF from reversing roots or stacking unrelated motifs.
            # Nonempty selector vectors avoid the arbitrary-word fallback.
            data['native_pools'][category] = [
                [-1], [-1], [candidate['token'] for candidate in candidates],
                [-1], [-1], [-1],
            ]
    language = 'language_forthammer_khazalid\n\n[OBJECT:LANGUAGE]\n\n' + '\n'.join(words)
    language += '\n\n[TRANSLATION:FORTHAMMER_KHAZALID]\n'
    language += '\n'.join(f'[T_WORD:{k}:{v}]' for k,v in (fallback | trans).items()) + '\n'
    entity = '''entity_forthammer_names

[OBJECT:ENTITY]

[SELECT_ENTITY:MOUNTAIN]
[TRANSLATION:FORTHAMMER_KHAZALID]
'''
    return {
        ROOT / 'objects/language_forthammer_khazalid.txt': language.encode('cp437'),
        ROOT / 'objects/entity_forthammer_names.txt': entity.encode('ascii'),
        ROOT / 'scripts_modactive/internal/forthammer-names/data.lua':
            ('-- Generated by tools/names/build.py; edit lexicon.json, not this file.\n--@ module = true\ndata = ' + lua(data) + '\n').encode('ascii'),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    stale = []
    for path, content in compile_files().items():
        if args.check:
            if not path.exists() or path.read_bytes() != content:
                stale.append(str(path.relative_to(ROOT)))
        else:
            path.write_bytes(content)
    if stale:
        raise SystemExit('Stale generated files: ' + ', '.join(stale))
    print('Naming outputs verified' if args.check else 'Naming outputs generated')


if __name__ == '__main__':
    main()
