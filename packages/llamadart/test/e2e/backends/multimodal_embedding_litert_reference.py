"""Standalone upstream C API control for the native embedding E2E outputs."""
import argparse
import ctypes as c
import os
import json
parser = argparse.ArgumentParser()
parser.add_argument('--model-path', required=True)
parser.add_argument('--runtime-dir', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
root = os.path.abspath(args.runtime_dir)
for n in ['libLiteRt.dylib', 'libLiteRtMetalAccelerator.dylib', 'libLiteRtWebGpuAccelerator.dylib', 'libLiteRtTopKMetalSampler.dylib', 'libLiteRtTopKWebGpuSampler.dylib']:
    try:
        c.CDLL(root + '/' + n, mode=c.RTLD_GLOBAL)
    except OSError:
        pass
lib = c.CDLL(root + '/libLiteRtLm.dylib', mode=c.RTLD_GLOBAL)

def fn(name, restype, args):
    f = getattr(lib, 'litert_lm_' + name)
    f.restype = restype
    f.argtypes = args
    return f
P = c.c_void_p
S = c.c_size_t
create = fn('embedding_engine_settings_create', P, [c.c_char_p] * 4)
settings = create(os.fsencode(args.model_path), b'cpu', b'cpu', b'cpu')
fn('embedding_engine_settings_set_cache_dir', None, [P, c.c_char_p])(settings, (os.environ['TMPDIR'] + '/reference-cache').encode())
os.makedirs(os.environ['TMPDIR'] + '/reference-cache', exist_ok=True)
fn('embedding_engine_settings_set_max_input_length', None, [P, c.c_int])(settings, 1024)
engine = fn('embedding_engine_create', P, [P])(settings)
fn('embedding_engine_settings_delete', None, [P])(settings)
print('engine', bool(engine), flush=True)
if not engine:
    raise SystemExit(1)
options = fn('embedding_options_create', P, [])()
fn('embedding_options_set_input_overflow_strategy', None, [P, c.c_int])(options, 2)
fn('embedding_options_set_normalize', None, [P, c.c_bool])(options, True)
compute = fn('embedding_engine_compute_embedding', P, [P, c.POINTER(P), S, P])
import glob, math
vectors = {}
for key in ['text', 'black', 'checker', 'silence', 'tone', 'mixed']:
    parts = []
    for path in sorted(glob.glob(args.output + '/' + key + '-*.bin')):
        kind = int(path.rsplit('-', 1)[1].split('.')[0])
        content = open(path, 'rb').read()
        data = fn('input_data_create', P, [c.c_int, P, S])(kind, content, len(content))
        parts.append(data)
    response = compute(engine, (P * len(parts))(*parts), len(parts), options)
    if not response:
        raise RuntimeError(key)
    size = fn('embedding_response_get_size', S, [P])(response)
    values = fn('embedding_response_get_values', c.POINTER(c.c_float), [P])(response)
    vectors[key] = list(values[:size])
    fn('embedding_response_delete', None, [P])(response)
    for part in parts:
        fn('input_data_delete', None, [P])(part)
with open(args.output + '/reference.json', 'w') as f:
    json.dump(vectors, f)
native = json.load(open(args.output + '/native-cpu.json'))
for k, a in vectors.items():
    b = native[k]
    dot = sum((x * y for x, y in zip(a, b)))
    aa = sum((x * x for x in a))
    bb = sum((x * x for x in b))
    print(k, 'cosine', dot / (aa * bb) ** 0.5, 'relL2', (sum(((x - y) ** 2 for x, y in zip(a, b))) / aa) ** 0.5, flush=True)
fn('embedding_options_delete', None, [P])(options)
fn('embedding_engine_delete', None, [P])(engine)
