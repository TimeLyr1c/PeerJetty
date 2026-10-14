#!/usr/bin/env python3
"""Real Sparkle installer/relaunch, disposable Apps only. HTTP is loopback-test-only."""
from pathlib import Path
import hashlib,http.server,json,os,plistlib,shutil,subprocess,tempfile,threading,time,uuid,sys
root=Path(__file__).resolve().parents[1]
framework=root/'.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
tools=root/'.build/sparkle-tools/bin'
base=Path.home()/'Applications/PeerJetty-Isolated-Updater';base.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='fixture-',dir=base) as directory:
    run=Path(directory);public=run/'server';public.mkdir();result=run/'result.txt'
    subprocess.run(['/usr/bin/swiftc','-parse-as-library','-module-cache-path',str(root/'.module-cache'),'-F',str(framework.parent),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',str(root/'Tests/InAppUpdateTests/Fixture.swift'),'-o',str(run/'Fixture')],check=True)
    pub=subprocess.check_output([str(run/'Fixture'),'--key',str(run/'private-seed')],env={**os.environ,'DYLD_FRAMEWORK_PATH':str(framework.parent)},text=True).strip()
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(public),**kwargs)
        def log_message(self,*args):pass
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
    prefix=f'http://127.0.0.1:{server.server_port}/'
    identifier='app.peerjetty.isolated.update.'+uuid.uuid4().hex
    def make_app(parent,build):
        app=parent/'Fixture.app';(app/'Contents/MacOS').mkdir(parents=True);(app/'Contents/Frameworks').mkdir();(app/'Contents/Resources').mkdir()
        shutil.copy2(run/'Fixture',app/'Contents/MacOS/Fixture')
        subprocess.run(['/usr/bin/python3',str(root/'Scripts/embed_sparkle.py'),str(app)],check=True)
        info={'CFBundleIdentifier':identifier,'CFBundleName':'PeerJetty Isolated Updater','CFBundleExecutable':'Fixture','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.1.0','CFBundleVersion':str(build),'LSMinimumSystemVersion':'15.0','LSUIElement':True,'FixtureResult':str(result),'SUFeedURL':prefix+'appcast.xml','SUPublicEDKey':pub,'SUEnableAutomaticChecks':False,'SUAllowsAutomaticUpdates':False,'SUVerifyUpdateBeforeExtraction':True,'SURequireSignedFeed':True,'SUSignedFeedFailureExpirationInterval':0,'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True,'NSAllowsArbitraryLoads':True}}
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(app)],check=True)
        return app
    target=run/'new';target.mkdir();new=make_app(target,1001)
    subprocess.run(['/usr/bin/ditto','-c','-k','--keepParent',str(new),str(public/'Fixture.zip')],check=True)
    subprocess.run([str(tools/'generate_appcast'),'--ed-key-file',str(run/'private-seed'),'--download-url-prefix',prefix,'--maximum-deltas','0',str(public)],check=True)
    corrupt='--corrupt' in sys.argv
    if corrupt:
        package=public/'Fixture.zip';data=bytearray(package.read_bytes());data[len(data)//2]^=1;package.write_bytes(data)
    old=make_app(run,1000);sentinel=run/'private-data.json';sentinel.write_text('{"name":"fixture","menu":false,"dock":true,"paired":"fake"}')
    initial=hashlib.sha256(sentinel.read_bytes()).hexdigest()
    process=subprocess.Popen(['/usr/bin/open','-n','-W',str(old)])
    deadline=time.monotonic()+60
    try:
        while time.monotonic()<deadline and not result.exists():time.sleep(0.2)
        if not result.exists():raise RuntimeError('No relaunch marker within 60 seconds')
        message=result.read_text();info=plistlib.loads((old/'Contents/Info.plist').read_bytes())
        if corrupt:
            assert not message.startswith('PASS:') and info['CFBundleVersion']=='1000',message
            print('PASS: modified signed package rejected; installed version unchanged')
        else:
            assert message.startswith('PASS:') and info['CFBundleVersion']=='1001',message
        assert hashlib.sha256(sentinel.read_bytes()).hexdigest()==initial
        subprocess.run(['/usr/bin/codesign','--verify','--strict',str(old)],check=True)
        if not corrupt:print(message);print('PASS: installed-copy replacement, ad hoc signing, signed feed/archive and adjacent private-data preservation')
    finally:
        process.wait(timeout=10);server.shutdown()
        # Only the disposable test domain is touched; production preferences/Keychain are never read.
        subprocess.run(['/usr/bin/defaults','delete',identifier],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

try:base.rmdir()
except OSError:pass
