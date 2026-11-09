#!/usr/bin/env python3
"""Count/export reviewed proposals; optionally scan a local book corpus.

The scan accepts inter-letter whitespace and hyphens, with whole-name boundaries.
Full personal names are scanned explicitly, including omitted OCR separators.
Attested forenames alone are excluded from collision research deliberately.
Corpus/OCR completeness remains a limit.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
from build import DATA, normalize


def catalog():
    data = json.loads(DATA.read_text())
    families = [''.join(p['parts']).capitalize() for p in data['family_patterns']]
    result = {'family': families, 'clan': families,
              'hold': ['Karak ' + ''.join(p).capitalize() for p in data['hold_patterns']]}
    for sex, names in data['forenames'].items():
        result['forename-' + sex] = names
        result['person-' + sex] = [first + ' ' + family for first in names for family in families]
    for category, head in data['place_heads'].items():
        place_families = [''.join(p['parts']).capitalize() for p in data['family_patterns']
                          if len(p['parts']) == 2 and p['parts'][-1] in data['place_emblem_objects']]
        result[category] = [(m+head).capitalize() for m in data['motifs']] + [f+head for f in place_families]
    for path in sorted(DATA.with_name('types').glob('*.json')):
        pack = json.loads(path.read_text())
        result[pack['category']] = [''.join(p['parts']).capitalize() for p in pack['patterns']]
    for category, names in result.items():
        assert len(names) == len({normalize(n) for n in names}), category
    return result


def scan(catalogs, directory):
    names_to_scan = {normalize(n): n for category, names in catalogs.items()
                    if not category.startswith('forename-') for n in names}
    trie = {}
    for name in names_to_scan:
        branch = trie
        for char in name:
            branch = branch.setdefault(char, {})
        branch[''] = {}

    def pattern(branch):
        alternatives = [re.escape(char) + r'[\s-]*' + pattern(child)
                        for char, child in branch.items() if char]
        text = '(?:' + '|'.join(alternatives) + ')' if alternatives else ''
        return '(?:' + text + ')?' if '' in branch and text else text

    # Names and normalization are ASCII. Unicode IGNORECASE additionally
    # matches characters such as dotless i that normalize() would discard.
    expression = re.compile(r'(?<![a-z])' + pattern(trie) + r'(?![a-z])', re.I | re.A)
    files = sorted(directory.rglob('*.md'))
    assert files, 'Empty corpus'
    hits, inventory = [], []
    for path in files:
        content = path.read_bytes()
        inventory.append((str(path.relative_to(directory)), hashlib.sha256(content).hexdigest(), len(content)))
        text = content.decode('utf-8')
        for match in expression.finditer(text):
            key = normalize(match[0])
            hits.append({'name':names_to_scan[key], 'file':str(path.relative_to(directory)),
                         'line':text.count('\n',0,match.start())+1,
                         'match':match[0].strip()})
    return {'files':len(files), 'bytes':sum(row[2] for row in inventory),
            'inventory_sha256':hashlib.sha256(json.dumps(inventory).encode()).hexdigest(),
            'distinct_names_scanned':len(names_to_scan),
            'full_person_names_covered':sum(len(v) for k,v in catalogs.items() if k.startswith('person-')),
            'method':'All complete names, including personal names, with optional inter-letter whitespace/hyphens.',
            'hits':hits}


APPEARANCE_ROOTS = {'kol', 'zan', 'gorl', 'skarrenruf', 'bryn'}


def diversity():
    """Editorial appearance grouping, not a count of canonical semantic senses."""
    packs = [json.loads(p.read_text()) for p in sorted(DATA.with_name('types').glob('*.json'))]
    result, names = {}, {}
    for pack in packs:
        patterns = pack['patterns']
        groups = {tuple(p for p in row['parts'] if p not in APPEARANCE_ROOTS)
                  or tuple(row['parts']) for row in patterns}
        names[pack['category']] = {normalize(''.join(row['parts'])) for row in patterns}
        result[pack['category']] = {
            'spellings': len(patterns), 'appearance_variant_families': len(groups),
            'appearance_qualified': sum(any(p in APPEARANCE_ROOTS for p in row['parts']) for row in patterns),
            'distinct_roots': len({p for row in patterns for p in row['parts']}),
            'distinct_nonappearance_roots': len({p for row in patterns for p in row['parts'] if p not in APPEARANCE_ROOTS and p != 'un'}),
            'distinct_terminal_roots': len({row['parts'][-1] for row in patterns}),
        }
    overlap = {left + '/' + right: len(names[left] & names[right])
               for left in sorted(names) for right in sorted(names)
               if left < right and names[left] & names[right]}
    return {'method': 'Strip only black, red, yellow, bright-blue and shining roots; retain remaining root order. Editorial grouping, not grammatical or semantic equivalence. Terminal-root counts describe composition endings, not asserted grammatical heads.',
            'categories': result, 'cross_category_shared_spellings': overlap}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export',type=Path)
    parser.add_argument('--corpus',type=Path)
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    catalogs=catalog()
    report={'capacity':{k:len(v) for k,v in sorted(catalogs.items())},'diversity':diversity()}
    if args.export:args.export.write_text(json.dumps(catalogs,indent=2)+'\n')
    if args.corpus:report['corpus']=scan(catalogs,args.corpus)
    if args.report:args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
