#!/usr/bin/env python3
"""Exhaust the *modeled* DFHack 53.14-r2 native naming products.

This checks the generated Lua selectors and generated raw forms, not a second
copy of the compiler's pool-building algorithm. It is not a game-creation test.
The model follows Translation.cpp generateName(), its repeated-word rejection,
translateName(), and df.language.xml's component ordering. The optional slots
contain DF's -1 no-word sentinel, so every branch must render one reviewed full
composition. Artifact names are explicit edits and have no native selector.

Upstream sources (DFHack 53.14-r2):
  https://github.com/DFHack/dfhack/blob/53.14-r2/library/modules/Translation.cpp
  https://github.com/DFHack/df-structures/blob/53.14-r2/df.language.xml

Run with --source to verify the exact inspected Translation.cpp snapshot.
Use --export-products PATH to export the modeled strings for independent book
corpus research (this mode deliberately does not filter existing reservations).
Repeated word tokens, repeated logical roots, unknown words and stacked native
compositions fail this audit. Passing is not a substitute for testing DF's own
native generator in the game; the source inspected here is DFHack's equivalent.
"""

import argparse
from collections import Counter
import hashlib
import itertools
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
SOURCE_SHA256 = 'aa6908d2775b97058e0127c9e5bc16fd1366f57890f62d8367659137d0b19962'
APPROVED = {
    'squad', 'civilization', 'government', 'tavern', 'guildhall', 'library',
    'hospital', 'business', 'artifact', 'road', 'tunnel', 'bridge', 'wall',
}
NATIVE_TYPES = APPROVED - {'artifact'}
# Native name components, in df.language.xml order. Values refer to the six
# selector positions: FrontCompound, RearCompound, FirstName, Adjectives,
# TheX, OfX. Note that HyphenCompound precedes TheX in the rendered name.
FRONT, REAR, ADJ1, ADJ2, HYPHEN, THE, OF = range(7)


def normalize(text):
    return re.sub('[^a-z0-9]', '', text.lower())


def generated_inputs(raw=None, lua=None):
    if raw is None:
        raw = (ROOT / 'objects/language_forthammer_khazalid.txt').read_text(encoding='cp437')
    translations = dict(re.findall(r'\[T_WORD:([^:\]]+):([^\]]*)\]', raw))
    forms = {}
    for match in re.finditer(r'\[WORD:([^\]]+)\]([\s\S]*?)(?=\[WORD:|\[TRANSLATION:|\Z)', raw):
        noun = re.search(r'\[NOUN:([^:\]]*):([^\]]*)\]', match[2])
        if noun:
            forms[match[1]] = noun[1], noun[2]
    if lua is None:
        lua = (ROOT / 'scripts_modactive/internal/forthammer-names/data.lua').read_text()
    block = re.search(r'\["native_pools"\]=\{\n(.*?)\n\}', lua, re.S)
    assert block, 'Generated Lua native_pools section missing'
    pools = {}
    for line in block[1].splitlines():
        entry = re.fullmatch(r'\["([a-z]+)"\]=(\{.*\}),?', line)
        assert entry, 'Unexpected native-pool Lua shape: ' + line
        # These generated tables contain lists of ASCII tokens or integer -1.
        pools[entry[1]] = json.loads(entry[2].replace('{', '[').replace('}', ']'))
    assert set(pools) == NATIVE_TYPES, 'Missing or unapproved native naming type'
    return pools, translations, forms


def general_shapes():
    # The switch always selects OfX, FirstAdjective, or both. SecondAdjective
    # is possible only with FirstAdjective. HyphenCompound is independent.
    for adjectives, of_word in ((0, True), (1, False), (1, True), (2, False), (2, True)):
        for hyphen in (False, True):
            shape = {THE: 2}
            if adjectives:
                shape[ADJ1] = 3
            if adjectives == 2:
                shape[ADJ2] = 3
            if of_word:
                shape[OF] = 5
            if hyphen:
                shape[HYPHEN] = 4
            yield shape


def shapes(category):
    assert category in NATIVE_TYPES, 'No native selector is provided for this category'
    yield from general_shapes()


def products(category, selectors):
    for shape in shapes(category):
        slots = sorted(shape)
        choices = [selectors[shape[slot]] for slot in slots]
        for tokens in itertools.product(*choices):
            words = [token for token in tokens if token != -1]
            if len(words) != len(set(words)):
                continue  # Translation.cpp's pairwise word-index rejection.
            # DF's rejection/rendering checks omit components whose index is -1.
            yield {slot: token for slot, token in zip(slots, tokens) if token != -1}


def capitalize(text):
    return text[:1].upper() + text[1:]


def render(product, translations, forms):
    native, english = [], []
    compound = [product[i] for i in (FRONT, REAR) if i in product]
    phrase = [product[i] for i in (ADJ1, ADJ2, HYPHEN, THE) if i in product]
    if compound:
        native.append(capitalize(''.join(translations[t] for t in compound)))
        english.append(capitalize(''.join(forms[t][0] for t in compound)))
    if phrase:
        native.append(capitalize(''.join(translations[t] for t in phrase)))
        english.append('the' if english else 'The')
        english.extend(capitalize(forms[t][0]) for t in phrase)
    if OF in product:
        token = product[OF]
        native.append(capitalize(translations[token]))
        english.extend(('of' if english else 'Of', capitalize(forms[token][0])))
    return ' '.join(native), ' '.join(english)


def root_map(pack, selectors, translations):
    reviewed = {''.join(p['parts']): p['parts'] for p in pack['patterns']}
    result = {}
    for token in set(itertools.chain.from_iterable(selectors)) - {-1}:
        assert translations[token] in reviewed, 'Unreviewed native composition: ' + token
        result[token] = reviewed[translations[token]]
    return result


def audit(inputs=None):
    pools, translations, forms = inputs if inputs is not None else generated_inputs()
    assert set(pools) == NATIVE_TYPES, 'Missing or unapproved native naming type'
    lexicon = json.loads((ROOT / 'tools/names/lexicon.json').read_text())
    packs = {p['category']: p for p in (
        json.loads(path.read_text()) for path in (ROOT / 'tools/names/types').glob('*.json'))}
    assert set(packs) == APPROVED
    reserved = {normalize(v) for v in lexicon['reserved']}
    for pack in packs.values():
        reserved.update(normalize(v) for v in pack.get('reserved', []))
    report = {}
    for category, selectors in sorted(pools.items()):
        assert len(selectors) == 6 and all(selectors), 'Empty native selector'
        for slot in (0, 1, 3, 4, 5):
            assert selectors[slot] == [-1], 'Optional native slot could stack or reverse reviewed roots'
        assert -1 not in selectors[2], 'The mandatory name component cannot be absent'
        for token in itertools.chain.from_iterable(selectors):
            if token == -1:
                continue
            assert isinstance(token, str) and token.startswith('FH_KHAZ_TYPE_' + category.upper() + '_'), 'Cross-category or invalid token'
            assert translations[token] and all(forms[token]), 'Empty native word/form'
            assert translations[token].isascii() and all(f.isascii() for f in forms[token]), 'Unsupported encoding'
            # Squad changes TheX to NounPlural. The current authored plural
            # forms intentionally equal the singular sign-name gloss.
            assert forms[token][0] == forms[token][1], 'Extend rendering model for inflected plural'
        roots = root_map(packs[category], selectors, translations)
        names, assignments = set(), set()
        reviewed_names = {''.join(p['parts']).capitalize() for p in packs[category]['patterns']}
        maximum_native = maximum_english = ''
        modeled_draws = 0
        for product in products(category, selectors):
            modeled_draws += 1
            assert len(product.values()) == len(set(product.values())), 'Repeated token accepted by model'
            assert list(product) == [THE], 'Native template stacked or omitted a reviewed composition'
            assignments.add(tuple(sorted(product.items())))
            native, english = render(product, translations, forms)
            assert native and english, 'Empty rendered native name'
            assert normalize(native) not in reserved, 'Reserved native product: ' + native
            assert native in reviewed_names, 'Native output differs from the reviewed finite compositions: ' + native
            assert len(native) <= 64, 'Native product exceeds the authored-name limit: ' + native
            names.add(native)
            if len(native) > len(maximum_native):
                maximum_native = native
            if len(english) > len(maximum_english):
                maximum_english = english
            counts = Counter(root for token in product.values() for root in roots[token])
            repeated = sorted(root for root, count in counts.items() if count > 1)
            assert not repeated, 'Repeated logical roots in native name: ' + native
        assert modeled_draws, 'No accepted native template products'
        assert names == reviewed_names, 'Native pool omits reviewed candidates'
        report[category] = {
            'template_branch_cases': modeled_draws,
            'accepted_component_assignments': len(assignments),
            'distinct_native_names': len(names),
            'maximum_native_length': len(maximum_native),
            'longest_native_example': maximum_native,
            'maximum_english_length': len(maximum_english),
            'longest_english_example': maximum_english,
            'repeated_logical_root_names': 0,
        }
    return {
        'checks': 'PASS',
        'scope': 'Exhaustive modeled general/Squad templates; artifact explicit-only; not actual game creation.',
        'source': 'DFHack 53.14-r2 Translation.cpp',
        'source_sha256': SOURCE_SHA256,
        'finite_composition_check': 'Every native branch emits exactly one complete reviewed composition, with no extra or repeated roots.',
        'categories': report,
    }


def export_products(path):
    pools, translations, forms = generated_inputs()
    rows = []
    for category, selectors in sorted(pools.items()):
        seen = set()
        for product in products(category, selectors):
            native, english = render(product, translations, forms)
            if native in seen:
                continue
            seen.add(native)
            rows.append({
                'category': category, 'native': native,
                'normalizedcompact': normalize(native), 'english': english,
                'components': [{'slot': slot, 'native': translations[token]}
                               for slot, token in sorted(product.items())],
            })
    path.write_text(json.dumps(rows, ensure_ascii=True))
    return len(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, help='Verify matching local Translation.cpp snapshot')
    parser.add_argument('--export-products', type=Path,
                        help='Export all modeled native strings for a separate corpus scan')
    args = parser.parse_args()
    if args.source:
        assert hashlib.sha256(args.source.read_bytes()).hexdigest() == SOURCE_SHA256, 'Native source version mismatch'
    if args.export_products:
        print(json.dumps({'exported_names': export_products(args.export_products),
                          'path': str(args.export_products), 'reserved_names_filtered': False}))
        return
    print(json.dumps(audit(), indent=2))


if __name__ == '__main__':
    main()
