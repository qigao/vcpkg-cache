"""Independent RFC 5280 certificate-chain checks. Python standard library only."""
from __future__ import annotations
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone


def pem(der: bytes) -> bytes:
    text = base64.b64encode(der)
    return b'-----BEGIN CERTIFICATE-----\n' + b'\n'.join(text[i:i+64] for i in range(0,len(text),64)) + b'\n-----END CERTIFICATE-----\n'


def run(command: list[str]) -> dict:
    try:
        p = subprocess.run(command, capture_output=True, text=True, timeout=30)
        return {'command':command, 'exit':p.returncode, 'stdout':p.stdout, 'stderr':p.stderr}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {'command':command, 'exit':None, 'stdout':'', 'stderr':str(exc)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--fixtures', type=Path, default=Path(__file__).with_name('fixtures.json'))
    ap.add_argument('--out', type=Path, required=True)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument('--oracle', action='store_true')
    mode.add_argument('--provider', type=Path)
    ap.add_argument('--openssl', default='openssl')
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    raw = args.fixtures.read_bytes()
    if hashlib.sha256(raw).hexdigest() != '30f4a68d5d1658e33a6f88395a9d9fceb2930886065730485abada06a9593f67':
        raise ValueError('Corpus fingerprint changed; review the fixtures before updating this gate')
    doc = json.loads(raw)
    now = datetime.now(timezone.utc)
    first,last = map(datetime.fromisoformat, doc['clock_window_utc'])
    if not first < now < last:
        raise ValueError('Fixture clock window expired/not active; refresh fixtures, do not disable time validation')
    if doc['schema'] != 1 or len(doc['cases']) != 19 or len(doc['certificates']) != 31:
        raise ValueError('Unexpected fixture schema or corpus count')
    certs = {}
    for name,entry in doc['certificates'].items():
        if not re.fullmatch(r'[a-z0-9-]+', name):
            raise ValueError('Unsafe certificate ID')
        der = base64.b64decode(entry['der'], validate=True)
        if not 0 < len(der) <= 4096 or hashlib.sha256(der).hexdigest() != entry['sha256']:
            raise ValueError('Corrupt or oversized fixture: '+name)
        certs[name] = der
    records = []
    ids = set()
    for case in doc['cases']:
        name = case['id']
        if name in ids or not re.fullmatch(r'[a-z0-9-]+', name):
            raise ValueError('Duplicate or unsafe case ID')
        ids.add(name)
        if type(case['accept']) is not bool or not 1 <= len(case['chain']) <= 6:
            raise ValueError('Invalid case declaration')
        folder = args.out / name
        folder.mkdir(exist_ok=True)
        chain = [certs[n] for n in case['chain']]
        root = certs[case['root']]
        (folder/'chain.der').write_bytes(b''.join(chain))
        (folder/'root.der').write_bytes(root)
        record = {'id':name, 'expected_accept':case['accept'], 'chain_sha256':hashlib.sha256(b''.join(chain)).hexdigest(), 'root_sha256':hashlib.sha256(root).hexdigest()}
        if args.oracle:
            (folder/'leaf.pem').write_bytes(pem(chain[0]))
            (folder/'untrusted.pem').write_bytes(b''.join(map(pem,chain[1:])))
            (folder/'root.pem').write_bytes(pem(root))
            command = [args.openssl,'verify','-no-CApath','-no-CAstore','-x509_strict','-purpose','sslserver','-CAfile',str(folder/'root.pem')]
            if len(chain)>1:
                command += ['-untrusted',str(folder/'untrusted.pem')]
            result = run(command + [str(folder/'leaf.pem')])
            errors = list(map(int,re.findall(r'error (\d+) at \d+ depth lookup:',result['stderr'])))
            matched = (result['exit']==0 and ': OK' in result['stdout']) if case['accept'] else (result['exit']==2 and case['openssl_error'] in errors)
            record['openssl_errors'] = errors
        else:
            result = run([str(args.provider.resolve()),str(folder/'chain.der'),str(folder/'root.der')])
            try:
                status = json.loads(result['stdout'])
            except (ValueError,TypeError):
                status = {}
            if not isinstance(status, dict):
                status = {}
            accepted = result['exit']==0 and status.get('return')==1 and status.get('verify_result')==0
            rejected = result['exit']==1 and status.get('return') in (-1,0)
            matched = accepted if case['accept'] else rejected
            record['provider_status'] = status
        record.update(result)
        record['pass'] = bool(matched)
        records.append(record)
        print(('PASS' if matched else 'FAIL') + ' ' + name, flush=True)
    report = {'suite':'gmssl-independent-x509-v1','mode':'oracle' if args.oracle else 'provider','utc':now.isoformat(),'fixtures_sha256':hashlib.sha256(raw).hexdigest(),'passed':sum(r['pass'] for r in records),'total':len(records),'all_positive_controls_pass':all(r['pass'] for r in records if r['expected_accept']),'cases':records}
    if args.oracle:
        report['openssl_version'] = run([args.openssl,'version','-a'])
    report['environment'] = {key:os.getenv(key) for key in ['RUNNER_OS','RUNNER_ARCH','VCPKG_TOOL_REVISION','VCPKG_SCRIPTS_REVISION','GITHUB_SHA']}
    (args.out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"{report['mode']}: {report['passed']}/{report['total']}; positive controls: {report['all_positive_controls_pass']}")
    return 0 if all(r['pass'] for r in records) else 1

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError,KeyError,OSError,TypeError) as exc:
        print('HARNESS ERROR: '+str(exc),file=sys.stderr)
        sys.exit(2)
