"""A fake Arweave gateway for wallet-paid (AR) upload tests. It never touches a
real network, so nothing is ever paid for.

    python3 -I chaos_gateway.py <port> <state.json> [failure_rate]

launch.js sends the app's POST /tx, POST /chunk and GET /tx/{id}/status here
(AR_UPLOADS=chaos). It records what it accepted in state.json;
chaos_report.py summarises that.

failure_rate (default 0) is the chance that a request misbehaves on purpose:
a 400 broadcast failure, a 502/504, a 20 s stall, a dropped connection, or
(for POST /tx only) the header is stored but the client is told it failed.
0.2 to 0.5 exercises the uploader's retries.

A chunk is only accepted for a data root whose header was stored, and only
when its proof is valid, as a real node checks it: the merkle path must lead
from the header's data_root to a leaf for that offset, and the chunk's bytes
must hash to that leaf. A chunk sent again for an offset it already holds must
carry the same bytes; anything else is recorded as a mismatch.
"""
import json, os, random, sys, threading, time, base64, hashlib
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

PORT, STATE = int(sys.argv[1]), sys.argv[2]
RATE = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
lock = threading.Lock()
# id -> {data_root, data_size, header_posts, chunks: {offset: size}}
txs = {}
by_root = {}
events = {'tx_posts': 0, 'chunk_posts': 0, 'faults': {}, 'invalid_proofs': [], 'mismatches': []}


def b64d(v):
    return base64.urlsafe_b64decode(v + '=' * (-len(v) % 4))


def h(*parts):
    return hashlib.sha256(b''.join(parts)).digest()


def validate_path(node_id, dest, left, right, path):
    """arweave-js validatePath: the leaf's (data_hash, left, right) or None."""
    if right <= 0:
        return None
    if dest >= right:
        return validate_path(node_id, 0, right - 1, right, path)
    if dest < 0:
        return validate_path(node_id, 0, 0, right, path)
    if len(path) == 64:
        data_hash, note = path[:32], path[32:]
        if h(h(data_hash), h(note)) != node_id:
            return None
        return data_hash, left, right
    if len(path) < 96 + 64:
        return None
    l, r, note = path[:32], path[32:64], path[64:96]
    if h(h(l), h(r), h(note)) != node_id:
        return None
    off = int.from_bytes(note, 'big')
    if dest < off:
        return validate_path(l, dest, left, min(right, off), path[96:])
    return validate_path(r, dest, max(left, off), right, path[96:])


def save():
    with open(STATE, 'w') as f:
        json.dump({'txs': txs, 'events': events}, f)


def fault(kind):
    events['faults'][kind] = events['faults'].get(kind, 0) + 1


BROADCAST_FAIL = json.dumps({'successCount': 0, 'preferredSuccessCount': 0, 'failureCount': 3,
                             'results': [{'peer': 'http://x:1984', 'success': False, 'statusCode': 400}] * 3})


class H(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *a):
        pass

    def reply(self, status, body=b'', ctype='text/plain'):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header('content-type', ctype)
        self.send_header('access-control-allow-origin', '*')
        self.send_header('content-length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def drop(self):
        # Close without answering: the client sees a network error.
        self.close_connection = True
        try:
            self.connection.shutdown(2)
        except Exception:
            pass

    def chaos(self, allow_ghost=False):
        """Returns a fault name to apply, or None."""
        if random.random() >= RATE:
            return None
        kinds = ['400', '502', '504', 'stall', 'drop']
        if allow_ghost:
            kinds.append('ghost')
        return random.choice(kinds)

    def do_GET(self):
        p = self.path.split('?')[0]
        if p == '/tx_anchor':
            return self.reply(200, base64.urlsafe_b64encode(os.urandom(48)).decode().rstrip('='))
        if p.startswith('/price/'):
            return self.reply(200, '1000000')
        if p.startswith('/tx/') and p.endswith('/status'):
            tid = p.split('/')[2]
            with lock:
                known = tid in txs
            if known and random.random() < 0.5:
                # Pending, as a node answers for a transaction in its mempool.
                return self.reply(202, 'Pending')
            # A gateway's index often lags a just-posted header.
            return self.reply(404, 'Not Found.')
        if p == '/info':
            return self.reply(200, json.dumps({'network': 'chaos.N.1', 'height': 1}), 'application/json')
        return self.reply(404, 'Not Found.')

    def do_POST(self):
        n = int(self.headers.get('content-length') or 0)
        body = json.loads(self.rfile.read(n) or b'{}')
        p = self.path.split('?')[0]
        if p == '/tx':
            f = self.chaos(allow_ghost=True)
            with lock:
                events['tx_posts'] += 1
                tid = body['id']
                if f in (None, 'ghost'):
                    t = txs.setdefault(tid, {'data_root': body['data_root'], 'data_size': int(body['data_size']),
                                             'header_posts': 0, 'chunks': {}})
                    t['header_posts'] += 1
                    by_root[body['data_root']] = tid
                if f:
                    fault('tx_' + f)
                save()
            if f == 'ghost':
                # Stored, but the client is told it failed.
                return self.reply(500, 'Internal Server Error')
            if f:
                return self.apply(f)
            return self.reply(200, 'OK')
        if p == '/chunk':
            f = self.chaos()
            with lock:
                events['chunk_posts'] += 1
                root = body.get('data_root')
                tid = by_root.get(root)
                if tid is None:
                    save()
                    return self.reply(400, BROADCAST_FAIL, 'application/json')
                if f:
                    fault('chunk_' + f)
                    save()
                else:
                    t = txs[tid]
                    chunk = b64d(body['chunk'])
                    leaf = validate_path(b64d(t['data_root']), int(body['offset']), 0, t['data_size'],
                                         b64d(body['data_path']))
                    ok = (leaf is not None and int(body['data_size']) == t['data_size']
                          and hashlib.sha256(chunk).digest() == leaf[0] and len(chunk) == leaf[2] - leaf[1])
                    if not ok:
                        events['invalid_proofs'].append({'tx': tid, 'offset': body['offset']})
                        save()
                        return self.reply(400, json.dumps({'error': 'invalid_proof'}), 'application/json')
                    key = str(leaf[1])
                    digest = hashlib.sha256(chunk).hexdigest()
                    prev = t.setdefault('chunk_hashes', {}).get(key)
                    if prev is not None and prev != digest:
                        events['mismatches'].append({'tx': tid, 'start': leaf[1]})
                    t['chunk_hashes'][key] = digest
                    t['chunks'][key] = len(chunk)
                    save()
            if f:
                return self.apply(f)
            return self.reply(200, json.dumps({'successCount': 3, 'preferredSuccessCount': 3, 'failureCount': 0,
                                               'results': []}), 'application/json')
        return self.reply(404, 'Not Found.')

    def apply(self, f):
        if f == '400':
            return self.reply(400, BROADCAST_FAIL, 'application/json')
        if f in ('502', '504'):
            return self.reply(int(f), 'Bad Gateway' if f == '502' else 'Gateway Timeout')
        if f == 'stall':
            time.sleep(20)
            return self.reply(504, 'Gateway Timeout')
        if f == 'drop':
            return self.drop()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('access-control-allow-origin', '*')
        self.send_header('access-control-allow-headers', '*')
        self.send_header('access-control-allow-methods', 'GET, POST, OPTIONS')
        self.send_header('content-length', '0')
        self.end_headers()


save()
ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
