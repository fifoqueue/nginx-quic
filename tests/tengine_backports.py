#!/usr/bin/env python3
"""Run with: python3 tests/tengine_backports.py /absolute/path/to/nginx"""

import datetime
import http.client
import locale
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time


nginx = str(Path(sys.argv[1]).resolve())
locale.setlocale(locale.LC_TIME, "C")

with tempfile.TemporaryDirectory(prefix="nginx-tengine-") as directory:
    root = Path(directory)
    config = root / "nginx.conf"
    common = "daemon off; master_process off; pid nginx.pid; error_log stderr;"
    common += " events { worker_connections 64; }"
    command = [nginx, "-e", "stderr", "-p", directory + "/", "-c", str(config)]

    # Configuration parsing exercises ngx_conf_set_size_slot without allocating
    # the configured buffer.  Boundaries match the native binary's ssize_t.
    gib = 1024 ** 3
    valid = ["0g", "1g", "1G", "1024m", str(sys.maxsize // gib) + "G"]
    invalid = ["g", "-1g", "1.5g", "1gb", "1Gjunk",
               str(sys.maxsize // gib + 1) + "G", str(sys.maxsize + 1)]
    for value in valid + invalid:
        config.write_text(common + " http { client_body_buffer_size "
                          + value + "; }\n")
        result = subprocess.run(command + ["-t"], capture_output=True, text=True)
        assert (result.returncode == 0) == (value in valid), (value, result.stderr)
        if value in invalid:
            assert "invalid value" in result.stderr, result.stderr
    print("PASS: size units, malformed values, and overflow boundaries", flush=True)

    config.write_text(common + r"""
http {
    access_log off;
    log_format start '$request_start_time|$time_local|$msec|$request_time';
    server {
        listen unix:HTTP_SOCKET;
        location /size {
            set $limit_rate $arg_size;
            return 200 '$limit_rate';
        }
        location /time {
            access_log time.log start;
            return 200 '$request_start_time|$time_local|$msec|$request_time';
        }
        location /redirect { rewrite ^ /time last; }
        location /sub.shtml {
            root TEST_ROOT;
            default_type text/html;
            ssi on;
        }
        location /sub-time { return 200 '$request_start_time'; }
    }
}
""".replace("HTTP_SOCKET", str(root / "http.sock")).replace("TEST_ROOT", directory))
    (root / "sub.shtml").write_text(
        '<!--#echo var="request_start_time" -->|'
        '<!--#include virtual="/sub-time" wait="yes" -->|'
        '<!--#echo var="request_start_time" -->')

    def request(path, delay=0):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(5)
            client.connect(str(root / "http.sock"))
            client.sendall(("GET " + path + " HTTP/1.1\r\n"
                            "Host: localhost\r\nConnection: close\r\n").encode())
            time.sleep(delay)
            client.sendall(b"\r\n")
            response = http.client.HTTPResponse(client)
            response.begin()
            body = response.read().decode()
            assert response.status == 200, (response.status, body)
            return body

    def check_time(body, offset):
        start, end, now, elapsed = body.strip().split("|")
        started = datetime.datetime.strptime(start, "%d/%b/%Y:%H:%M:%S %z")
        assert started.strftime("%z") == offset, body
        assert 0 <= float(now) - float(elapsed) - started.timestamp() < 1.01, body
        assert float(elapsed) >= 1, body
        assert start != end, body

    # UTC, positive fractional-hour offset, and negative fractional-hour offset.
    for timezone, offset in [("UTC0", "+0000"), ("NPT-5:45", "+0545"),
                             ("NST3:30", "-0330")]:
        with (root / "stderr").open("w+") as errors:
            process = subprocess.Popen(command, env={**os.environ, "TZ": timezone},
                                       stdout=subprocess.DEVNULL, stderr=errors)
            try:
                for _ in range(100):
                    if (root / "http.sock").exists() or process.poll() is not None:
                        break
                    time.sleep(0.05)
                assert process.poll() is None, (root / "stderr").read_text()
                assert (root / "http.sock").exists(), "nginx did not start"
                assert request("/size?size=1g") == str(gib)
                assert request("/size?size=1G") == str(gib)
                assert request("/size?size=1024m") == str(gib)
                for path in ["/time", "/redirect"]:
                    check_time(request(path, delay=1.1), offset)
                parent, child, again = request("/sub.shtml", delay=1.1).split("|")
                assert parent == again, (parent, child, again)
                date_format = "%d/%b/%Y:%H:%M:%S %z"
                elapsed = (datetime.datetime.strptime(child, date_format)
                           - datetime.datetime.strptime(parent, date_format))
                assert elapsed.total_seconds() >= 1, (parent, child, again)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            assert process.returncode == 0, (root / "stderr").read_text()
        for line in (root / "time.log").read_text().splitlines():
            check_time(line, offset)
        (root / "time.log").unlink()
        print("PASS: request start, redirect, subrequest, log, timezone " + offset,
              flush=True)
