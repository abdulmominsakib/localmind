#!/usr/bin/env python3
import argparse
import http.server
import os
import socketserver


class CoiStaticHandler(http.server.SimpleHTTPRequestHandler):
    _range: tuple[int, int] | None = None

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "credentialless")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        super().end_headers()

    def send_head(self):  # type: ignore[override]
        self._range = None
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            return super().send_head()

        content_type = self.guess_type(path)
        try:
            file = open(path, "rb")
        except OSError:
            self.send_error(404, "File not found")
            return None

        file_stat = os.fstat(file.fileno())
        file_size = file_stat.st_size
        range_header = self.headers.get("Range")
        byte_range = self._parse_single_byte_range(range_header, file_size)

        if byte_range == "invalid":
            file.close()
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{file_size}")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None

        if byte_range is not None:
            start, end = byte_range
            self._range = (start, end)
            self.send_response(206)
            self.send_header("Content-type", content_type)
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
            self.send_header("Content-Length", str(end - start + 1))
            self.send_header("Last-Modified", self.date_time_string(file_stat.st_mtime))
            self.end_headers()
            return file

        self.send_response(200)
        self.send_header("Content-type", content_type)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(file_size))
        self.send_header("Last-Modified", self.date_time_string(file_stat.st_mtime))
        self.end_headers()
        return file

    def copyfile(self, source, outputfile) -> None:  # type: ignore[override]
        if self._range is None:
            return super().copyfile(source, outputfile)

        start, end = self._range
        source.seek(start)
        remaining = end - start + 1
        while remaining > 0:
            chunk = source.read(min(1024 * 1024, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            remaining -= len(chunk)

    def _parse_single_byte_range(
        self,
        range_header: str | None,
        file_size: int,
    ) -> tuple[int, int] | str | None:
        if not range_header:
            return None
        if not range_header.startswith("bytes=") or "," in range_header:
            return None

        start_text, separator, end_text = range_header[6:].partition("-")
        if separator != "-":
            return None

        try:
            if start_text == "":
                suffix_length = int(end_text)
                if suffix_length <= 0:
                    return "invalid"
                start = max(0, file_size - suffix_length)
                end = file_size - 1
            else:
                start = int(start_text)
                end = int(end_text) if end_text else file_size - 1
        except ValueError:
            return None

        if start < 0 or start >= file_size or end < start:
            return "invalid"

        return (start, min(end, file_size - 1))


class ThreadingTcpServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=7357)
    parser.add_argument("--directory", type=str, required=True)
    args = parser.parse_args()

    handler = lambda *h_args, **h_kwargs: CoiStaticHandler(
        *h_args,
        directory=args.directory,
        **h_kwargs,
    )

    with ThreadingTcpServer(("127.0.0.1", args.port), handler) as httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    raise SystemExit(main())
