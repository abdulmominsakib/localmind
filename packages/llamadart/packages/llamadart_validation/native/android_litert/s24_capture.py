"""Bounded lossless capture codec matching the private Dart S24 evidence codec."""
import base64
import hashlib
import json
import re

MAXIMUM_CAPTURE_BYTES = 8 * 1024 * 1024


def require(value, message):
    if not value:
        raise ValueError(message)


def utf8_length(text, maximum):
    require(isinstance(text, str) and len(text) <= maximum, 'Capture text bound')
    size = 0
    for value in map(ord, text):
        require(not 0xd800 <= value <= 0xdfff, 'Unpaired capture surrogate')
        size += 1 if value < 0x80 else 2 if value < 0x800 else 3 if value < 0x10000 else 4
        require(size <= maximum, 'Capture text exceeds claimed size')
    return size


def decode_capture(value):
    require(isinstance(value, dict), 'Capture object required')
    size = value.get('bytes'); digest = value.get('sha256')
    require(type(size) is int and 0 <= size <= MAXIMUM_CAPTURE_BYTES, 'Capture size invalid')
    require(isinstance(digest, str) and len(digest) == 64 and re.fullmatch('[a-f0-9]{64}', digest), 'Capture digest invalid')
    require(('base64' in value) != ('utf8' in value), 'Exactly one capture encoding required')
    if 'base64' in value:
        encoded = value['base64']
        require(isinstance(encoded, str) and len(encoded) == ((size + 2) // 3) * 4, 'Capture base64 bound')
        try:
            raw = base64.b64decode(encoded, validate=True)
        except (ValueError, UnicodeError) as error:
            raise ValueError('Capture base64 invalid') from error
        require(base64.b64encode(raw).decode() == encoded, 'Noncanonical capture base64')
    else:
        text = value['utf8']
        require(utf8_length(text, size) == size, 'Capture text size differs')
        raw = text.encode('utf-8', errors='strict')
    require(len(raw) == size and hashlib.sha256(raw).hexdigest() == digest, 'Capture hash/length mismatch')
    return raw


def encode_capture(raw):
    require(isinstance(raw, bytes) and len(raw) <= MAXIMUM_CAPTURE_BYTES, 'Capture bytes invalid')
    identity = {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
    encoded = {**identity, 'base64': base64.b64encode(raw).decode()}
    # Dart's strict UTF-8 decoder consumes the leading BOM, so retain its bytes.
    if raw.startswith(b'\xef\xbb\xbf'):
        return encoded
    try:
        text = raw.decode('utf-8', errors='strict')
        require(text.encode('utf-8') == raw, 'Changed capture UTF-8')
        candidate = {**identity, 'utf8': text}
        compact = lambda value: json.dumps(value, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
        if len(compact(candidate)) < len(compact(encoded)):
            return candidate
    except UnicodeError:
        pass
    return encoded
