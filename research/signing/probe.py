"""Disposable macOS code-identity experiment. Never signs or launches Sage Keys.
No TCC APIs, trust overrides, user keychain, release, or durable secret storage.
Only JSON evidence leaves the runner; keys, keychains and fixtures are destroyed.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

assert sys.platform == 'darwin' and os.environ.get('GITHUB_ACTIONS') == 'true'
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
work=Path(tempfile.mkdtemp(prefix='sage-signing-research-',dir=os.environ['RUNNER_TEMP']))
keychain=work/'disposable.keychain-db'
password=secrets.token_hex(32)
env=dict(os.environ,LAB_IDENTITY_PASSWORD=password)
report={'scope':'Code identity only; no TCC authorization or Sage Keys build',
        'trustOverrides':False,'tests':{},'signatures':{},'privateKeysExportedToArtifact':False}

def run(args,label,required=True):
    # Never include command arguments in exceptions: keychain passwords are arguments.
    try:
        p=subprocess.run(list(map(str,args)),capture_output=True,text=True,env=env,timeout=45)
    except subprocess.TimeoutExpired:
        raise RuntimeError(label+' timed out') from None
    text=(p.stdout+p.stderr).replace(password,'[redacted]')
    if required and p.returncode:
        raise RuntimeError(label+' failed: '+text)
    return p.returncode,text

def check(name,condition):
    report['tests'][name]=bool(condition)
    if not condition:raise RuntimeError(name+' failed')

def identity(name):
    folder=work/name;folder.mkdir()
    config=folder/'openssl.cnf'
    config.write_text('''[req]
prompt=no
distinguished_name=dn
x509_extensions=ext
[dn]
CN=Sage Keys Disposable Research
[ext]
basicConstraints=critical,CA:TRUE
keyUsage=critical,digitalSignature,keyCertSign
extendedKeyUsage=critical,codeSigning
''')
    cert=folder/'cert.pem';key=folder/'key.pem';p12=folder/'identity.p12'
    run(['/usr/bin/openssl','req','-new','-newkey','rsa:2048','-x509','-sha256','-nodes',
         '-days','7','-config',config,'-keyout',key,'-out',cert], 'generate disposable certificate')
    run(['/usr/bin/openssl','pkcs12','-export','-inkey',key,'-in',cert,'-out',p12,
         '-passout','env:LAB_IDENTITY_PASSWORD'],'encode disposable identity')
    _,fingerprint=run(['/usr/bin/openssl','x509','-in',cert,'-noout','-fingerprint','-sha1'],'public fingerprint')
    fingerprint=fingerprint.strip().split('=')[1].replace(':','')
    run(['/usr/bin/security','import',p12,'-k',keychain,'-P',password,'-T','/usr/bin/codesign'],'import into disposable keychain')
    run(['/usr/bin/security','set-key-partition-list','-S','apple-tool:,apple:,codesign:',
         '-s','-k',password,keychain],'allow codesign to use disposable key')
    key.unlink();p12.unlink()
    return fingerprint

def fixture(name,revision,identifier='io.github.annecat-bit.signing-research'):
    app=work/(name+'.app');contents=app/'Contents';binary=contents/'MacOS'/'Probe'
    binary.parent.mkdir(parents=True)
    (contents/'Resources').mkdir()
    (contents/'Resources'/'revision.txt').write_text(revision)
    (contents/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier,
        'CFBundleExecutable':'Probe','CFBundleName':'Identity Research','CFBundlePackageType':'APPL',
        'CFBundleVersion':revision,'CFBundleShortVersionString':revision,'LSMinimumSystemVersion':'13.0'}))
    source=work/(name+'.c');source.write_text('#include <stdio.h>\nint main(void){puts("Research revision '+revision+'");return 0;}\n')
    run(['/usr/bin/xcrun','clang','-target','arm64-apple-macos13.0',source,'-o',binary],'compile isolated fixture')
    return app

def sign(app,signer):
    args=['/usr/bin/codesign','--force','--sign',signer,'--options','runtime','--timestamp=none']
    if signer!='-':args+=['--keychain',keychain]
    run(args+[app],'sign '+app.stem)
    run(['/usr/bin/codesign','--verify','--deep','--strict',app],'verify '+app.stem)
    _,info=run(['/usr/bin/codesign','--display','-r-','--verbose=4',app],'read public signature')
    dr=re.search(r'^(?:# )?designated => (.+)$',info,re.M).group(1)
    cdhash=re.search(r'^CDHash=(.+)$',info,re.M).group(1)
    report['signatures'][app.stem]={'dr':dr,'cdhash':cdhash,'details':info.replace(str(work),'[temporary]')}
    return dr,cdhash

def satisfies(app,requirement):
    code,text=run(['/usr/bin/codesign','--verify','--strict','-R',requirement,app],'cross-check',required=False)
    return {'satisfied':code==0,'exitCode':code,'output':text.replace(str(work),'[temporary]')}

try:
    report['system']=run(['/usr/bin/sw_vers'],'OS version')[1].strip()
    report['architecture']=run(['/usr/bin/uname','-m'],'architecture')[1].strip()
    run(['/usr/bin/security','create-keychain','-p',password,keychain],'create disposable keychain')
    run(['/usr/bin/security','set-keychain-settings','-lut','600',keychain],'keychain timeout')
    run(['/usr/bin/security','unlock-keychain','-p',password,keychain],'unlock disposable keychain')
    adhocA=fixture('adhoc-a','1');adhocB=fixture('adhoc-b','2')
    ra,ha=sign(adhocA,'-');rb,hb=sign(adhocB,'-')
    report['adhoc']={'bSatisfiesA':satisfies(adhocB,ra),'aSatisfiesB':satisfies(adhocA,rb)}
    check('adhoc_hashes_change',ha!=hb)
    check('adhoc_identity_breaks',not report['adhoc']['bSatisfiesA']['satisfied'] and not report['adhoc']['aSatisfiesB']['satisfied'])
    one=identity('identity-one');two=identity('same-name-new-identity')
    report['certificateSHA1']={'original':one,'sameNameNewKey':two}
    check('same_name_is_not_same_identity',one!=two)
    a=fixture('persistent-a','1');b=fixture('persistent-b','2')
    da,ha=sign(a,one)
    run(['/usr/bin/security','lock-keychain',keychain],'lock between builds')
    run(['/usr/bin/security','unlock-keychain','-p',password,keychain],'reopen the same identity')
    db,hb=sign(b,one)
    report['persistent']={'bSatisfiesA':satisfies(b,da),'aSatisfiesB':satisfies(a,db)}
    check('new_content_changes_hash',ha!=hb)
    check('same_identity_retains_default_dr',da==db)
    check('same_identity_mutually_satisfies_dr',all(x['satisfied'] for x in report['persistent'].values()))
    impostor=fixture('same-name-new-key','2');sign(impostor,two)
    otherID=fixture('same-key-other-id','2','io.github.annecat-bit.signing-research.other');sign(otherID,one)
    report['negativeControls']={'newKey':satisfies(impostor,da),'otherIdentifier':satisfies(otherID,da),
                                'certificateCannotMatchOldAdhoc':satisfies(b,ra)}
    check('new_key_cannot_impersonate',not report['negativeControls']['newKey']['satisfied'])
    check('different_identifier_rejected',not report['negativeControls']['otherIdentifier']['satisfied'])
    check('changing_away_from_adhoc_is_migration',not report['negativeControls']['certificateCannotMatchOldAdhoc']['satisfied'])
    code,text=run(['/usr/sbin/spctl','--assess','--type','execute','--verbose=3',b],'Gatekeeper assessment',required=False)
    report['gatekeeper']={'exitCode':code,'output':text.replace(str(work),'[temporary]')}
    report['result']='code-identity checks passed; TCC and user installation NOT tested'
except Exception as e:
    report['result']='blocked';report['error']=str(e).replace(password,'[redacted]')
finally:
    cleanup=run(['/usr/bin/security','delete-keychain',keychain],'delete disposable keychain',required=False)[0]
    shutil.rmtree(work)
    report['cleanup']={'keychainDeletionExitCode':cleanup,'temporaryDirectoryRemoved':not work.exists()}
    (out/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))
if report['result']=='blocked':sys.exit(1)
