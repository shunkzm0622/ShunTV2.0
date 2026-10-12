#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
echo '==> Building ShunTV seek controls dylib'
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" \
  -miphoneos-version-min=13.0 -fobjc-arc -dynamiclib \
  -Wl,-install_name,@executable_path/Frameworks/ShunSeekControls.dylib \
  -framework Foundation -framework UIKit -framework AVFoundation -framework WebKit \
  ShunSeekControls.m -o ShunSeekControls.dylib

python3 -u - <<'PY'
import os, plistlib, shutil, subprocess, zipfile
from pathlib import Path
source=Path('ShunTV_1.0_based_on_TQMTV_2.0_unsigned.ipa')
assert source.is_file(), f'Missing {source}'
root=Path('work');shutil.rmtree(root,ignore_errors=True);root.mkdir()
with zipfile.ZipFile(source) as z:z.extractall(root)
apps=list((root/'Payload').glob('*.app'))
assert len(apps)==1, f'Expected 1 app, found {len(apps)}'
app=apps[0]
with (app/'Info.plist').open('rb') as f:p=plistlib.load(f)
assert p['CFBundleIdentifier']=='com.nqt.shuntv', 'Unexpected app ID'
assert p['CFBundleShortVersionString']=='1.0', 'Unexpected version'
exe=app/p['CFBundleExecutable']
assert exe.is_file(),f'Missing binary: {exe}'
frameworks=app/'Frameworks'; frameworks.mkdir(exist_ok=True)
shutil.copy2('ShunSeekControls.dylib',frameworks/'ShunSeekControls.dylib')
patched=exe.with_name(exe.name+'.patched')
patched.unlink(missing_ok=True)
load_name='@executable_path/Frameworks/ShunSeekControls.dylib'
print('==> Injecting seek UI library into the video player executable',flush=True)
subprocess.run(['./insert_dylib','--strip-codesig',load_name,str(exe),str(patched)],
               stdin=subprocess.DEVNULL,check=True,timeout=40)
assert patched.is_file(),'insert_dylib returned without writing executable'
result=subprocess.run(['otool','-L',str(patched)],check=True,capture_output=True,text=True)
assert load_name in result.stdout,'ShunSeekControls is not loaded by executable'
os.replace(patched,exe);exe.chmod(0o755)
for signature in app.rglob('_CodeSignature'):
    if signature.is_dir():shutil.rmtree(signature)
for profile in app.rglob('embedded.mobileprovision'):
    if profile.is_file():profile.unlink()
output=Path('ShunTV_1.0_SeekControls_unsigned.ipa')
with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
    for p in (root/'Payload').rglob('*'):
        if p.is_file():z.write(p,p.relative_to(root))
print('==> Created',output,'size',output.stat().st_size, 'bytes',flush=True)
PY
