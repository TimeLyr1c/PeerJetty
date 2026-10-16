#!/usr/bin/env python3
"""Signed DMG upgrade of real PeerJetty sources using test-only isolated startup."""
from pathlib import Path
import http.server,os,plistlib,signal,subprocess,tempfile,threading,time,uuid
root=Path(__file__).resolve().parents[1]
subprocess.run([str(root/'Scripts/swift.sh'),'build','--product','PeerJetty'],cwd=root,check=True)
bin=Path(subprocess.check_output([str(root/'Scripts/swift.sh'),'build','--show-bin-path'],cwd=root,text=True).strip())
framework=root/'.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64'
tools=root/'.build/sparkle-tools/bin'
base=Path.home()/'Applications/PeerJetty-Isolated-Updater';base.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='actual-app-',dir=base) as directory:
 run=Path(directory);public=run/'server';public.mkdir();data=run/'data';data.mkdir(mode=0o700)
 objects=[bin/'PeerCore.o'] if (bin/'PeerCore.o').exists() else list((bin/'PeerCore.build').glob('*.o'))
 command=['/usr/bin/swiftc','-D','PEERJETTY_TESTING','-parse-as-library','-module-cache-path',str(root/'.module-cache'),'-I',str(bin),'-I',str(bin/'Modules'),'-F',str(framework),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',*map(str,objects),*map(str,(root/'Sources/PeerJetty').glob('*.swift')),str(root/'Tests/ActualAppUpdateTests/ActualAppUpdate.swift'),'-o',str(run/'PeerJetty')]
 subprocess.run(command,cwd=root,check=True)
 # Existing key-generation fixture creates only a new disposable seed, not release keys.
 subprocess.run(['/usr/bin/swiftc','-parse-as-library','-module-cache-path',str(root/'.module-cache'),'-F',str(framework),'-framework','Sparkle',str(root/'Tests/InAppUpdateTests/Fixture.swift'),'-o',str(run/'key-tool')],check=True)
 pub=subprocess.check_output([str(run/'key-tool'),'--key',str(run/'private-seed')],env={**os.environ,'DYLD_FRAMEWORK_PATH':str(framework)},text=True).strip()
 class Handler(http.server.SimpleHTTPRequestHandler):
  def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(public),**kwargs)
  def log_message(self,*args):pass
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
 prefix=f'http://127.0.0.1:{server.server_port}/';identifier='app.peerjetty.test.actual-upgrade.'+uuid.uuid4().hex
 def make_app(parent,build):
  app=parent/'PeerJetty.app';(app/'Contents/MacOS').mkdir(parents=True);(app/'Contents/Resources').mkdir()
  subprocess.run(['ditto',str(run/'PeerJetty'),str(app/'Contents/MacOS/PeerJetty')],check=True)
  subprocess.run(['ditto',str(root/'Sources/PeerCore/Resources'),str(app/'Contents/Resources')],check=True)
  info=plistlib.loads((root/'Info.plist').read_bytes());info.update(CFBundleIdentifier=identifier,CFBundleVersion=str(build),FixtureRoot=str(data),SUFeedURL=prefix+'appcast.xml',SUPublicEDKey=pub,NSAppTransportSecurity={'NSAllowsArbitraryLoads':True,'NSAllowsLocalNetworking':True})
  (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
  subprocess.run(['python3',str(root/'Scripts/embed_sparkle.py'),str(app)],check=True)
  subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
  return app
 newdir=run/'new';newdir.mkdir();new=make_app(newdir,1001)
 subprocess.run(['hdiutil','create','-volname','PeerJetty Isolated Update','-srcfolder',str(newdir),'-format','UDZO','-ov',str(public/'PeerJetty.dmg')],check=True,stdout=subprocess.DEVNULL)
 subprocess.run([str(tools/'generate_appcast'),'--ed-key-file',str(run/'private-seed'),'--download-url-prefix',prefix,'--maximum-deltas','0',str(public)],check=True)
 old=make_app(run,1000)
 with (run/'launch.log').open('w') as log:
  process=subprocess.Popen(['open','-n','-W',str(old)],stdout=log,stderr=subprocess.STDOUT)
  deadline=time.monotonic()+90;result=data/'result.txt'
  try:
   while time.monotonic()<deadline and not result.exists():time.sleep(0.2)
   if not result.exists():raise RuntimeError('No actual App relaunch marker; log: '+(run/'launch.log').read_text()[-2000:])
   message=result.read_text();assert message.startswith('PASS:'),message
   assert plistlib.loads((old/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='1001'
   subprocess.run(['codesign','--verify','--strict','--deep',str(old)],check=True)
   print(message)
  finally:
   # Restrict cleanup to executable paths inside this exact disposable folder.
   for line in subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines():
    fields=line.strip().split(None,1)
    if len(fields)==2 and fields[1].startswith(str(run)+'/'):
     try:os.kill(int(fields[0]),signal.SIGTERM)
     except ProcessLookupError:pass
   try:process.wait(timeout=10)
   except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=5)
   server.shutdown();subprocess.run(['defaults','delete',identifier],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

try:base.rmdir()
except OSError:pass
