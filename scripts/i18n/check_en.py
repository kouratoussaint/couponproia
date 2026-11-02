#!/usr/bin/env python3
"""Liste les textes de l'interface sans traduction anglaise (D5).

Chaque texte affiché passe par tr('texte français') ou trf('texte avec {0}', [...]).
Ce script lit app/lib, puis compare avec app/assets/i18n/en.json (clé = texte français).

Usage :  python3 scripts/i18n/check_en.py            # liste les manques
         python3 scripts/i18n/check_en.py --add      # ajoute les manques (valeur = français, à traduire)
"""
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'app')
EN = os.path.join(ROOT, 'assets', 'i18n', 'en.json')
PATTERN = re.compile(r"""\btrf?\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""")
PLACEHOLDER = re.compile(r'\{\d+\}')


def unescape(raw: str) -> str:
    return (raw.replace("\\'", "'").replace('\\"', '"').replace('\\n', '\n')
            .replace('\\$', '$').replace('\\\\', '\\'))


def wrapped_texts():
    for folder, _, files in os.walk(os.path.join(ROOT, 'lib')):
        for name in files:
            if not name.endswith('.dart') or name == 'tr.dart':
                continue
            path = os.path.join(folder, name)
            with open(path, encoding='utf-8') as f:
                for m in PATTERN.finditer(f.read()):
                    raw = m.group(1) if m.group(1) is not None else m.group(2)
                    yield os.path.relpath(path, ROOT), unescape(raw)


def main() -> int:
    with open(EN, encoding='utf-8') as f:
        en = json.load(f)
    missing = sorted({(p, t) for p, t in wrapped_texts() if t not in en})
    for path, text in missing:
        print(f'{path}: {text!r}')
    bad = [k for k, v in en.items()
           if not set(PLACEHOLDER.findall(v)) <= set(PLACEHOLDER.findall(k))]
    for k in bad:
        print(f'valeur {{n}} absente du français : {k!r}')
    if '--add' in sys.argv and missing:
        for _, text in missing:
            en.setdefault(text, text)
        with open(EN, 'w', encoding='utf-8') as f:
            json.dump(en, f, ensure_ascii=False, indent=1, sort_keys=True)
            f.write('\n')
        print(f'{len(missing)} texte(s) ajouté(s) en français : à traduire dans en.json.')
    print(f'{len(missing)} manquant(s), {len(bad)} incohérence(s).')
    return 1 if (missing and '--add' not in sys.argv) or bad else 0


if __name__ == '__main__':
    sys.exit(main())
