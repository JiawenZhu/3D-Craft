#!/usr/bin/env python3
"""Build/install a phone test app using the same Firebase origin as release.
Preflight the live API before replacing the installed app.
"""
import json, os, pathlib, plistlib, subprocess, tempfile, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
def main():
    url='https://3d-craft.web.app'
    env={k:v for k,v in os.environ.items() if k != 'CRAFT_REVIEW_URL'}
    # Refuse to replace a working installed app with an unconfigured cloud API.
    import urllib.request
    with urllib.request.urlopen(url+'/api/health',timeout=20) as response:
        status=json.load(response) if response.headers.get_content_type()=='application/json' else {}
        if status.get('status')!='ok' or status.get('generationReady') is not True:
            raise RuntimeError('Cloud API is not ready; the installed app was left unchanged.')
    derived='/tmp/craft-gallery-device'; log='/tmp/craft-phone-review-build.log'
    subprocess.run(['xcodegen','generate','--spec','ios/project.yml'],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
    with open(log,'w') as output:
        os.chmod(log,0o600)
        result=subprocess.run(['xcodebuild','-project','ios/CraftStudio.xcodeproj','-scheme','CraftStudio','-sdk','iphoneos','-configuration','Debug','-destination','generic/platform=iOS','-derivedDataPath',derived,'-allowProvisioningUpdates','build'],cwd=ROOT,env=env,stdout=output,stderr=subprocess.STDOUT)
    if result.returncode:
        print('Build failed; review the private build log.');return result.returncode
    app=pathlib.Path(derived)/'Build/Products/Debug-iphoneos/CraftStudio.app'
    built=plistlib.loads((app/'Info.plist').read_bytes()).get('CraftStudioAPIURL')
    if built!=url: raise RuntimeError('Refusing to install: the cloud URL was not embedded in this build.')
    device=sys.argv[1] if len(sys.argv)>1 else 'EBD02F3E-4F9E-5BF1-92A4-7237951A687C'
    subprocess.run(['xcrun','devicectl','device','install','app','--device',device,str(app)],check=True)
    launched=subprocess.run(['xcrun','devicectl','device','process','launch','--device',device,'studio.craft.ios'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    if launched.returncode:
        print('Installed with the verified cloud URL. Unlock the iPhone and open 3D Craft to finish verification.')
    else: print('Installed and launched. Verified the shared cloud URL.')
    return 0
if __name__=='__main__':sys.exit(main())
