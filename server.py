# Boolooavatar local server: no accounts, no limits. Run:  python server.py
import http.server, socketserver, threading, queue, os, socket

PORT = 8765
DIR = os.path.dirname(os.path.abspath(__file__))
PAGES = {'/': 'boolooavatar-v3.html', '/index.html': 'boolooavatar-v3.html',
         '/boolooavatar-v3.html': 'boolooavatar-v3.html',
         '/remote': 'remote.html', '/remote.html': 'remote.html'}
clients, lock = [], threading.Lock()

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def send_text(self, body, ctype='text/plain; charset=utf-8', code=200):
        b = body if isinstance(body, bytes) else body.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(b)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        p = self.path.split('?')[0]
        if p == '/ping':
            return self.send_text('boolooavatar')
        if p == '/status':
            with lock:
                return self.send_text(str(len(clients)))
        if p == '/trigger':
            from urllib.parse import parse_qs
            qs = parse_qs(self.path.split('?', 1)[1]) if '?' in self.path else {}
            def idx(v):
                try: return max(0, min(4, int(v[0]) - 1))
                except Exception: return 0
            if 'clip' in qs: m = '{"t":"clip","i":%d}' % idx(qs['clip'])
            elif 'emoji' in qs: m = '{"t":"react","i":%d}' % idx(qs['emoji'])
            elif 'play' in qs: m = '{"t":"play"}'
            else: m = None
            if m:
                with lock:
                    for c in clients: c.put(m)
            return self.send_text('ok')
        if p == '/events':
            q = queue.Queue()
            with lock:
                clients.append(q)
            try:
                self.send_response(200)
                self.send_header('Content-Type', 'text/event-stream')
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                self.wfile.write(b': hi\n\n'); self.wfile.flush()
                while True:
                    try:
                        msg = q.get(timeout=10)
                        self.wfile.write(('data: ' + msg + '\n\n').encode('utf-8'))
                    except queue.Empty:
                        self.wfile.write(b': ka\n\n')
                    self.wfile.flush()
            except Exception:
                pass
            finally:
                with lock:
                    if q in clients: clients.remove(q)
            return
        if p in PAGES:
            try:
                with open(os.path.join(DIR, PAGES[p]), 'rb') as f:
                    return self.send_text(f.read(), 'text/html; charset=utf-8')
            except FileNotFoundError:
                return self.send_text('File not found: ' + PAGES[p], code=404)
        self.send_text('Not found', code=404)

    def do_POST(self):
        if self.path.split('?')[0] != '/cmd':
            return self.send_text('Not found', code=404)
        n = int(self.headers.get('Content-Length') or 0)
        msg = self.rfile.read(n).decode('utf-8', 'ignore').replace('\n', ' ')
        with lock:
            for q in clients: q.put(msg)
        self.send_text('ok')

class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80)); ip = s.getsockname()[0]; s.close(); return ip
    except Exception:
        return 'YOUR-PC-IP'

if __name__ == '__main__':
    print('Boolooavatar server is running. Keep this window open.\n')
    print('  On this PC (and in OBS):  http://localhost:%d/' % PORT)
    print('  Avatar only (OBS):        http://localhost:%d/#clean' % PORT)
    print('  Phone remote (same Wi-Fi): http://%s:%d/remote\n' % (lan_ip(), PORT))
    try:
        S(('0.0.0.0', PORT), H).serve_forever()
    except KeyboardInterrupt:
        pass
