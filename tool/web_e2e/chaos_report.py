"""Summarises what chaos_gateway.py accepted during a wallet-paid upload test.

    python3 -I chaos_report.py <state.json>

One line per transaction header the app posted, then the totals. The upload
worked when every header has all its bytes ("complete") and there are no
invalid proofs or mismatches. A header with missing bytes is what a user
would see as a file that never appears: paid for, but its data never stored.
Exits 1 if anything is wrong, and 2 (NOTHING STORED) if no header was
stored at all, which is not a pass.
"""
import json, sys

state = json.load(open(sys.argv[1]))
txs, events = state['txs'], state['events']
bad = 0
for tid, t in txs.items():
    got = sum(t['chunks'].values())
    done = got >= t['data_size']
    bad += not done
    print(f"{tid}  {got}/{t['data_size']} bytes  header posted {t['header_posts']}x  "
          f"{'complete' if done else 'MISSING CHUNKS'}")
invalid, mismatched = len(events.get('invalid_proofs', [])), len(events.get('mismatches', []))
print(json.dumps({'headers': len(txs), 'incomplete': bad, 'tx_posts': events['tx_posts'],
                  'chunk_posts': events['chunk_posts'], 'faults_injected': events['faults'],
                  'invalid_proofs': invalid, 'mismatches': mismatched}))
if not txs:
    # Not a pass: nothing was uploaded, or every header was failed on purpose.
    print('NOTHING STORED: no transaction header reached the gateway')
    sys.exit(2)
ok = bad == 0 and invalid == 0 and mismatched == 0
print('OK' if ok else 'PROBLEMS')
sys.exit(0 if ok else 1)
