"""Read-only local model server for LiteRT embedding Chrome qualification."""
import argparse
import http.server
import json
import pathlib
import re


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model-path', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--port', type=int, default=5197)
    args = parser.parse_args()
    if args.port == 8080:
        parser.error('Port 8080 is reserved.')
    model = pathlib.Path(args.model_path)
    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)

    class Handler(http.server.BaseHTTPRequestHandler):
        def end_headers(self):
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type,Range')
            self.send_header('Cross-Origin-Resource-Policy', 'cross-origin')
            super().end_headers()

        def do_OPTIONS(self):
            self.send_response(204)
            self.end_headers()

        def do_GET(self):
            if self.path == '/native.json':
                body = (output / 'native-cpu.json').read_bytes()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if self.path != '/model.litertlm':
                self.send_error(404)
                return
            size = model.stat().st_size
            range_header = self.headers.get('Range')
            begin, end = 0, size - 1
            if range_header:
                match = re.fullmatch(r'bytes=(\d+)-(\d*)', range_header)
                if not match:
                    self.send_error(416)
                    return
                begin = int(match[1])
                end = min(int(match[2]) if match[2] else end, end)
            self.send_response(206 if range_header else 200)
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Content-Length', str(end - begin + 1))
            if range_header:
                self.send_header('Content-Range', f'bytes {begin}-{end}/{size}')
            self.end_headers()
            try:
                with model.open('rb') as stream:
                    stream.seek(begin)
                    remaining = end - begin + 1
                    while remaining:
                        chunk = stream.read(min(remaining, 1024 * 1024))
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        remaining -= len(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def do_POST(self):
            if self.path != '/results' or int(self.headers.get('Content-Length', '0')) > 1024 * 1024:
                self.send_error(400)
                return
            body = self.rfile.read(int(self.headers['Content-Length']))
            values = json.loads(body)
            (output / 'web.json').write_text(json.dumps(values))
            self.send_response(204)
            self.end_headers()

    http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()


if __name__ == '__main__':
    main()
