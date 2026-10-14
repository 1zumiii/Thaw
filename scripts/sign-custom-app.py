#!/usr/bin/env python3
"""Sign an uninstalled Thaw build inside-out using the persistent local key."""
import pathlib
import plistlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent
app = pathlib.Path(sys.argv[1]).resolve()
if pathlib.Path('/Applications') in app.parents:
    raise SystemExit('Sign a staged build, never the installed app in place.')
with (app / 'Contents/Info.plist').open('rb') as stream:
    if plistlib.load(stream).get('CFBundleIdentifier') != 'com.stonerl.Thaw':
        raise SystemExit('Expected the custom Thaw app.')
identity = subprocess.check_output(['bash', str(root / 'setup-custom-signing.sh')], text=True).strip()
if len(identity) != 40 or any(c not in '0123456789ABCDEF' for c in identity):
    raise SystemExit('Invalid signing certificate fingerprint.')

# Sign every Mach-O leaf first, then each containing bundle from deepest to
# shallowest. Do not preserve the old cdhash-based designated requirements.
magic = {bytes.fromhex(x) for x in ('cffaedfe', 'cefaedfe', 'feedfacf', 'feedface',
                                  'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}
leaves = []
bundles = []
for path in app.rglob('*'):
    if path.is_symlink():
        continue
    if path.is_dir() and path.suffix in ('.app', '.framework', '.xpc', '.appex'):
        bundles.append(path)
    elif path.is_file():
        with path.open('rb') as stream:
            if stream.read(4) in magic:
                leaves.append(path)
for path in sorted(leaves) + sorted(bundles, key=lambda p: len(p.parts), reverse=True) + [app]:
    subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp=none',
                    '--preserve-metadata=identifier,entitlements,flags,runtime', str(path)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)], check=True)
requirement = subprocess.check_output(['codesign', '-d', '-r-', str(app)], stderr=subprocess.DEVNULL, text=True)
if f'certificate leaf = H"{identity.lower()}"' not in requirement or 'cdhash' in requirement:
    raise SystemExit('The app does not have the expected stable certificate requirement.')
print(requirement.strip())
