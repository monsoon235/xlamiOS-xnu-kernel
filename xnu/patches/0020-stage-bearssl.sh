#!/bin/bash
# Pinned, portable constant-time AES for the SWEET legacy CBC/ECB API.
# The upstream git server (www.bearssl.org/git/BearSSL) is frequently down
# (HTTP 502), so fetch the release tarball instead. It carries the same
# sources for the files staged below and is pinned by SHA-256.
set -euo pipefail
[[ "${MACHINE_CONFIG:-}" == SWEET ]] || exit 0
[[ -f libkern/crypto/corecrypto_aes.c ]] || exit 1
bearssl_sha=6705bba1714961b41a728dfc5debbe348d2966c117649392f8c8139efc83ff14
bearssl_url=https://bearssl.org/bearssl-0.6.tar.gz
bearssl_tmp=$(mktemp -d)
trap 'rm -rf "$bearssl_tmp"' EXIT
curl -fsSL --retry 5 --retry-delay 3 --max-time 180 "$bearssl_url" -o "$bearssl_tmp/bearssl.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then
    echo "${bearssl_sha}  $bearssl_tmp/bearssl.tar.gz" | sha256sum -c -
else
    echo "${bearssl_sha}  $bearssl_tmp/bearssl.tar.gz" | shasum -a 256 -c -
fi
tar -xzf "$bearssl_tmp/bearssl.tar.gz" -C "$bearssl_tmp"
bearssl_src=$(find "$bearssl_tmp" -maxdepth 3 -name inner.h -path '*/src/*' -print -quit | sed 's|/src/inner.h$||')
[[ -f "$bearssl_src/src/inner.h" ]] || { echo "BearSSL source root not found"; exit 1; }
echo "Using BearSSL at $bearssl_src ($bearssl_sha)"
python3 - "$bearssl_src" <<'PY'
from pathlib import Path
import shutil
import sys

source = Path(sys.argv[1])
target = Path('libkern/crypto/sweet_bearssl')
if target.exists():
    raise SystemExit(f'refusing to overwrite existing AES source: {target}')
shutil.copytree(source / 'inc', target / 'inc')
(target / 'src/symcipher').mkdir(parents=True)
for file in ('inner.h', 'config.h'):
    shutil.copy2(source / 'src' / file, target / 'src' / file)
# XNU exports machine/limits.h instead of the userspace limits.h.
header = target / 'src/inner.h'
text = header.read_text()
assert text.count('#include <limits.h>') == 1
header.write_text(text.replace('#include <limits.h>',
    '#if defined(KERNEL)\n#include <machine/limits.h>\n'
    '#else\n#include <limits.h>\n#endif'))
for name in ('aes_ct', 'aes_ct_enc', 'aes_ct_dec', 'aes_ct_cbcenc', 'aes_ct_cbcdec'):
    shutil.copy2(source / 'src/symcipher' / (name + '.c'),
                 target / 'src/symcipher' / (name + '.c'))
# MD5, SHA-1 and SHA-384/512 for the legacy hash APIs, with their codecs.
for name in ('hash/md5.c', 'codec/dec32le.c', 'codec/enc32le.c',
             'hash/sha1.c', 'codec/dec32be.c', 'codec/enc32be.c',
             'hash/sha2big.c', 'codec/dec64be.c', 'codec/enc64be.c'):
    (target / 'src' / name).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / 'src' / name, target / 'src' / name)
shutil.copy2(source / 'LICENSE.txt', target / 'LICENSE.txt')
PY
echo "Staged BearSSL portable AES, MD5, SHA-1 and SHA-384/512 ($bearssl_sha) for SWEET"
