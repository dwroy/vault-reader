#!/usr/bin/env python3
"""Validate prepared metadata and an optional built .app without exposing credentials."""
import argparse
import plistlib
from pathlib import Path
from urllib.request import Request, urlopen

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path)
parser.add_argument('--check-urls', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
metadata = root / 'docs/app-store'
errors = []
store_locales = ['en-US', 'zh-Hans', 'zh-Hant', 'ja', 'ko', 'es-MX', 'pt-BR', 'fr-FR', 'de-DE', 'ar-SA', 'hi', 'id']
app_locales = ['en', 'zh-Hans', 'zh-Hant', 'ja', 'ko', 'es', 'pt-BR', 'fr', 'de', 'ar', 'hi', 'id']
for locale in store_locales:
    for field, limit in {'name': 30, 'subtitle': 30, 'keywords': 100,
                         'promotional_text': 170, 'description': 4000}.items():
        value = (metadata / locale / (field + '.txt')).read_text().strip()
        if not value or len(value) > limit:
            errors.append(f'{locale}/{field}: {len(value)} characters, limit {limit}')
manifest = plistlib.loads((root / 'VaultReader/Resources/PrivacyInfo.xcprivacy').read_bytes())
assert manifest['NSPrivacyTracking'] is False
assert manifest['NSPrivacyTrackingDomains'] == []
assert manifest['NSPrivacyCollectedDataTypes'] == []
reasons = {x['NSPrivacyAccessedAPIType']: x['NSPrivacyAccessedAPITypeReasons']
           for x in manifest['NSPrivacyAccessedAPITypes']}
for category, reason in [('UserDefaults', 'CA92.1'), ('FileTimestamp', 'C617.1'), ('SystemBootTime', '35F9.1')]:
    if reason not in reasons.get('NSPrivacyAccessedAPICategory' + category, []):
        errors.append(f'Missing privacy reason for {category}')
if args.app:
    info = plistlib.loads((args.app / 'Info.plist').read_bytes())
    for key, expected in [('CFBundleIdentifier', 'com.dwroy.vaultreader'),
                          ('CFBundleShortVersionString', '1.0.0'),
                          ('CFBundleDevelopmentRegion', 'en'),
                          ('ITSAppUsesNonExemptEncryption', False)]:
        if info.get(key) != expected:
            errors.append(f'Unexpected {key}: {info.get(key)}')
    for name in ['PRIVACY', 'SUPPORT']:
        if (args.app / (name + '.md')).read_bytes() != (root / 'docs' / (name + '.md')).read_bytes():
            errors.append(f'Bundled {name} differs from source')
    if plistlib.loads((args.app / 'PrivacyInfo.xcprivacy').read_bytes()) != manifest:
        errors.append('Bundled privacy manifest differs from source')
    if not (args.app / 'renderer/vendor/THIRD-PARTY-NOTICES.txt').is_file():
        errors.append('Missing renderer license notices')
    for locale in app_locales:
        if not (args.app / (locale + '.lproj') / 'Localizable.strings').is_file():
            errors.append(f'Missing app locale: {locale}')
    core = args.app / 'VaultCore_VaultCore.bundle'
    core_locales = {path.parent.name.lower() for path in core.glob('*.lproj/Localizable.strings')}
    for locale in app_locales:
        if locale.lower() + '.lproj' not in core_locales:
            errors.append(f'Missing repository-error locale: {locale}')
    for script in ['arabic', 'devanagari']:
        font = args.app / 'renderer/vendor/fonts' / f'noto-sans-{script}-{script}-wght-normal.woff2'
        if not font.is_file():
            errors.append(f'Missing offline {script} font')
    print(f"Bundle: {info.get('CFBundleShortVersionString')} ({info.get('CFBundleVersion')}), SDK {info.get('DTSDKName')}")
if args.check_urls:
    for name in ['support_url', 'privacy_url']:
        url = (metadata / (name + '.txt')).read_text().strip()
        try:
            with urlopen(Request(url, headers={'User-Agent': 'VaultReader-Release-Check'}), timeout=20) as response:
                if response.status != 200:
                    errors.append(f'{name}: HTTP {response.status}')
        except Exception as error:
            errors.append(f'{name}: {error}')
if errors:
    raise SystemExit('\n'.join(errors))
print('App Store metadata, privacy declarations and requested bundle checks passed.')
if not args.check_urls:
    print('Public URL availability was not checked; use --check-urls after authorized publication.')
