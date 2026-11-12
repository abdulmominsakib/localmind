"""Regenerate v1 synthetic inputs without dependencies or network access."""
import binascii
from pathlib import Path
import struct
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / 'v1'
root.mkdir(parents=True, exist_ok=True)

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', binascii.crc32(kind + data) & 0xffffffff)

# A stored DEFLATE block makes bytes independent of zlib compression versions.
raw = b''.join(b'\0' + bytes(v for x in range(224) for v in [255 if (x // 16 + y // 16) % 2 else 0] * 3) for y in range(224))
blocks = []
for offset in range(0, len(raw), 65535):
    block = raw[offset:offset + 65535]
    blocks.append(bytes([int(offset + len(block) == len(raw))]) + struct.pack('<HH', len(block), len(block) ^ 65535) + block)
import zlib
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 224, 224, 8, 2, 0, 0, 0)) + chunk(b'IDAT', b'\x78\x01' + b''.join(blocks) + struct.pack('>I', zlib.adler32(raw))) + chunk(b'IEND', b'')
(root / 'checker.png').write_bytes(png)
# Exactly representable 250 Hz square tone, mono 16 kHz signed 16-bit PCM.
pcm = b''.join(struct.pack('<h', 4096 if i % 64 < 32 else -4096) for i in range(16000))
wav = b'RIFF' + struct.pack('<I', 36 + len(pcm)) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, 1, 16000, 32000, 2, 16) + b'data' + struct.pack('<I', len(pcm)) + pcm
(root / 'tone.wav').write_bytes(wav)
