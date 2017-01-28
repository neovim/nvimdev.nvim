#!/usr/bin/env python3
"""Splits up the ignored errors into files.

It shaves some time off the linting.
"""
import os
import sys
import json
import logging

from urllib.request import Request, urlopen

logging.basicConfig(format='%(message)s')

url = 'https://raw.githubusercontent.com/neovim/doc/gh-pages/reports/clint/errors.json'
log = logging.getLogger()


def chunked_lines(fp, size=8192):
    buf = b''
    chunk = fp.read(size)
    while chunk:
        buf += chunk
        i = 0
        j = buf.find(b'\n')
        while j != -1:
            yield buf[i:j+1]
            i = j + 1
            j = buf.find(b'\n', i)
        if i != 0:
            buf = buf[i:]
        chunk = fp.read(size)

    if buf:
        i = 0
        j = buf.find(b'\n')
        while j != -1:
            yield buf[i:j+1]
            i = j + 1
            j = buf.find(b'\n', i)
        if i != 0:
            yield buf[i:]


def fileopen(filename, mode):
    dirpath = os.path.dirname(filename)
    if not os.path.isdir(dirpath):
        os.makedirs(dirpath, 0o755, True)
    return open(filename, mode)


def download(output_dir):
    etag = 0
    remote_etag = 0
    sizefile = os.path.join(output_dir, '.errors')

    if os.path.exists(sizefile):
        with open(sizefile, 'rt') as fp:
            try:
                etag = fp.readline()
            except:
                pass
    log.debug('Cache Etag: %s', etag)

    req = Request(url, method='HEAD')
    with urlopen(req) as resp:
        if resp.getcode() != 200:
            log.error('HTTP %d - %s', resp.getcode(), resp.read())
            return
        remote_etag = resp.info().get('Etag', '')
        log.debug('Remote Etag: %s', remote_etag)

    if remote_etag == etag:
        log.debug('No update needed')
        sys.exit(200)

    for root, dirs, files in os.walk(output_dir):
        for f in files:
            if f.endswith('.json'):
                os.remove(os.path.join(root, f))

    handles = {}
    req = Request(url, method='GET')
    with urlopen(req) as resp:
        if resp.getcode() != 200:
            log.error('HTTP %d - %s', resp.getcode(), resp.read())
            return

        for line in chunked_lines(resp):
            err = json.loads(line.decode('utf8'))
            filepath = '%s.json' % os.path.join(output_dir, err[0])

            if filepath not in handles:
                log.debug('Opening: %s', filepath)
                handles[filepath] = fileopen(filepath, 'wb')

            handles[filepath].write(line)

    [h.close() for h in handles.values()]

    with fileopen(sizefile, 'wb') as fp:
        fp.write(remote_etag.encode('utf8'))


if __name__ == '__main__':
    if 'DEBUG' in os.environ:
        log.setLevel(logging.DEBUG)

    if len(sys.argv) < 2:
        sys.exit(1)

    download(sys.argv[1])
