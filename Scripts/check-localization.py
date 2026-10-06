#!/usr/bin/env python3
"""Check supported catalogs, format fields and source references (macOS plutil)."""
from pathlib import Path
import json
import plistlib
import re
import subprocess

root = Path(__file__).resolve().parents[1]
resources = root / 'Sources/PeerCore/Resources'
catalogs = {}
for language in ('en', 'zh-Hans'):
    folder = resources / (language + '.lproj')
    for path in folder.iterdir():
        subprocess.run(['/usr/bin/plutil', '-lint', str(path)], check=True, stdout=subprocess.DEVNULL)
    table = json.loads(subprocess.check_output(['/usr/bin/plutil', '-convert', 'json', '-o', '-', str(folder / 'Localizable.strings')]))
    plural = plistlib.loads((folder / 'Localizable.stringsdict').read_bytes())
    catalogs[language] = (table, plural)
assert catalogs['en'][0].keys() == catalogs['zh-Hans'][0].keys(), 'String keys differ'
assert catalogs['en'][1].keys() == catalogs['zh-Hans'][1].keys(), 'Plural keys differ'
for key, template in catalogs['en'][0].items():
    assert sorted(re.findall(r'%\d+\$@', template)) == sorted(re.findall(r'%\d+\$@', catalogs['zh-Hans'][0][key])), key
for key, spec in catalogs['en'][1].items():
    variables = set(spec) - {'NSStringLocalizedFormatKey'}
    assert variables == set(catalogs['zh-Hans'][1][key]) - {'NSStringLocalizedFormatKey'}, key
    for language in catalogs:
        for variable in variables:
            rule = catalogs[language][1][key][variable]
            assert rule['NSStringFormatSpecTypeKey'] == 'NSStringPluralRuleType' and rule['NSStringFormatValueTypeKey'] == 'ld' and 'other' in rule, key
keys = set(catalogs['en'][0]) | set(catalogs['en'][1])
for path in (root / 'Sources').rglob('*.swift'):
    text = path.read_text()
    for key in re.findall(r'(?:L10n\.(?:text|message)|PeerError\.localized)\("([^"]+)"', text):
        assert key in keys, (path, key)
    if path.parent.name in ('PeerCore', 'PeerJetty'):
        assert not any(re.search('[\u3400-\u9fff]', value) for value in re.findall(r'"(?:\\.|[^"\\])*"', text)), ('Unextracted Chinese string', path)
allowlist = re.findall(r'^    "([^"]+)": (\d+),$', (root / 'Sources/PeerCore/Localization.swift').read_text(), re.M)
for key, fields in allowlist:
    assert key in catalogs['en'][0], ('Remote diagnostic must use a plain string template', key)
    for language in catalogs:
        assert len(re.findall(r'%\d+\$@', catalogs[language][0][key])) == int(fields), ('Remote field count', key)
print('PASS: {} bilingual entries, format fields, diagnostic allowlist and source coverage'.format(len(keys)))
