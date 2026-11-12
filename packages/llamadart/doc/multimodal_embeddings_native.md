# Native llama.cpp multimodal embeddings

Tracking: https://github.com/leehack/llamadart/issues/1072.
Shared contract: [multimodal embeddings](multimodal_embeddings.md).

## Execution and limits

`NativeLlamaBackend` implements both string and content embedding SPIs. The
string route is unchanged. Content requests copy media buffers for the worker
and merge adjacent text verbatim. Text-only content uses the string route;
mixed content uses the model's existing projector.

The capability probe checks the loaded context's pooling/attention mode,
encoder/decoder configuration, projector vision/audio encoders, M-RoPE mode,
exception/exit barriers and optional mixed-batch ABI. A text-only embedding
GGUF reports text only. Text acceptance matches `embed`, including causal
unpooled models; only media requires noncausal MEAN pooling. Missing
`llama_model_n_embd_inp` leaves text unaffected and disables media; the probe
carries `mediaUnsupportedReason` through the engine with the v0.7.0-1 floor. Missing/unknown contexts report all false without
starting a worker. Media needs noncausal MEAN pooling and the v0.7.0-1 guarded
mixed-batch functions. M-RoPE projectors are unavailable because the adapter
passes exactly one position per row. Qualified weights are EmbeddingGemma-2
BF16 with its matching vision/audio projector; other families are unqualified.

Use exactly one media source per part: encoded bytes or local file, or mono
16 kHz Float32 audio. Image URLs, source ambiguity, reserved media markers in
text, and a codec that decodes to the wrong modality are explicitly rejected.
Native media decoding determines codec availability; invalid/empty data fails
with a typed error. Diagnostics do not include media sources or payloads.

All inputs are tokenized and their expanded row counts checked before any
media encode or model decode. Each complete mixed input must fit actual
`n_ctx`, `n_ctx_seq`, `n_batch`, `n_ubatch` and one sequence slot. There is no
chunking, truncation, separate-part pooling, prefix insertion or frame sampling.
Every media chunk is encoded through the guarded mtmd wrapper. Extended-batch
insertion copies each row before the next encode reuses mtmd output, so Dart
does not retain another media copy. Each input
builds one extended batch with tokens/media rows, sequential positions and
embedding output flags, then makes one guarded `llama_dart_process` DECODE.
Output is the full pooled sequence width (768 for the qualified model, whose
input width is 512), with the same normalization as string embeddings.

Cancellation is polled between native calls and after the complete process;
it does not interrupt synchronous media encoding. Await the future before
reusing or unloading. Flags stay alive until the worker settles, including
worker exit. Chunks, decoded bitmaps and extended batches are released on success, error and cancellation. A native caught
exception preserves the existing free-only object policy; cleanup skips
context state writes after that context becomes free-only.

## Embeddings during text generation

The native worker serializes `embed`, `embedBatch` and `embedContentBatch`
behind text generation. Its receive-port listener is async, but the production
ordinary and speculative inference loops have no event-queue awaits. Their
`async*` yields and the worker's `await for` resume in microtasks, which drain
before another port or timer event runs. An embedding sent during generation
therefore starts after generation's counters and terminal response are saved;
it cannot clear memory or invalidate counters in the middle of generation.
Its later execution replaces counters normally. This differs from TTS, whose
setup actually awaits event-queue work and needs explicit exclusion guards.

`worker_embedding_serialization_test.dart` runs the real worker/service with a
small generated CPU GGUF, queues all three embedding requests during prompt
decode and verifies generation completes first in both ordinary and n-gram
speculative modes. A timer also proves the active-context reservation is gone
before event processing resumes. Adding an event-queue await to either loop
breaks the test. Any future asynchronous I/O, timer wait or stream backpressure
in those loops must re-evaluate exclusivity before changing memory or counters.
Direct service consumers that pause a generation stream are outside this worker
guarantee; the public engine uses the worker's unpaused consumer.

## Local qualification

Windows split bundles export guarded allocation/processing from `llamadart.dll`,
extended-batch functions from `llama.dll`, and projector/chunk accessors from
`mtmd.dll`. The service reuses its existing mtmd fallback library for the media
probe and calls. Every used accessor is resolved before media is advertised;
genuine absence retains typed unsupported behavior without restricting text.
In `dart build cli` bundles with the executable in `bin/` and DLLs in `lib/`,
an early mtmd lookup miss is retried when backend initialization finds the
module directory. After backend initialization, its bundled mtmd library takes
precedence over bare names on the DLL search path. The pre-initialization
log-level lookup still uses bare names, so a foreign `mtmd.dll` on `PATH` can
win then; a successfully resolved API remains cached.
Windows export routing has host-independent unit coverage and is checked against
the published v0.7.0-1 windows-arm64 export tables. EmbeddingGemma-2 BF16 media
execution passed the 11-case `embedding-gguf-cpu` pack on Windows x64 CPU after
[#1198](https://github.com/leehack/llamadart/pull/1198).

No test downloads weights or SDK artifacts. The local-only
`native-multimodal-embeddings` scenario requires:

- `LLAMADART_EMBEDDING_MODELS_DIR`: directory containing
  `gguf/embeddinggemma-2-BF16.gguf` and
  `gguf/mmproj-embeddinggemma-2-BF16.gguf`, revision
  `ggml-org/embeddinggemma-2-GGUF@bfcd2987`.
- `LLAMADART_EMBEDDING_REFERENCE_CPU` and
  `LLAMADART_EMBEDDING_REFERENCE_METAL`: JSON arrays of six normalized vectors
  from the reference below. Metal is skipped on non-macOS hosts.

The reference uses only upstream APIs, headers from pinned llama.cpp
`620d2225cc436ab0b001e3200e590e3b286ef9ab`, and the actual v0.7.0-1 runtime
library consumed by Dart. It mirrors the owner's
[`embedding_smoke.cpp`](https://github.com/leehack/llamadart-native/blob/daffc7f/tools/embedding_smoke.cpp)
algorithm and adds arbitrary ordered parts and JSON output. Use a clean local
checkout of those pinned headers; do not compile against a moving native
checkout's headers.

Extract the C++ block to a temporary `embedding-reference.cpp`. With
`LLAMA_CPP_SOURCE` pointing to that pinned source and `NATIVE_LIBRARY_DIR` to
the directory of the consumed v0.7.0-1 `libllamadart.dylib`:

```sh
clang++ -std=c++17 -O2 -I"$LLAMA_CPP_SOURCE/include" \
  -I"$LLAMA_CPP_SOURCE/ggml/include" -I"$LLAMA_CPP_SOURCE/tools/mtmd" \
  "$TMPDIR/embedding-reference.cpp" -L"$NATIVE_LIBRARY_DIR" -lllamadart \
  -Wl,-rpath,"$NATIVE_LIBRARY_DIR" -o "$TMPDIR/embedding-reference"
for device in cpu metal; do
  "$TMPDIR/embedding-reference" \
    "$LLAMADART_EMBEDDING_MODELS_DIR/gguf/embeddinggemma-2-BF16.gguf" \
    "$LLAMADART_EMBEDDING_MODELS_DIR/gguf/mmproj-embeddinggemma-2-BF16.gguf" \
    "$device" "$TMPDIR/reference-$device.json"
done
export LLAMADART_EMBEDDING_REFERENCE_CPU="$TMPDIR/reference-cpu.json"
export LLAMADART_EMBEDDING_REFERENCE_METAL="$TMPDIR/reference-metal.json"
dart run tool/testing/run_local_e2e.dart --scenario native-multimodal-embeddings --dry-run
dart run tool/testing/run_local_e2e.dart --scenario native-multimodal-embeddings
```

The six vectors cover text, black/checkerboard images, silence/440 Hz mono
16 kHz PCM and interleaved text/image/audio/image. Every vector must have
cosine >= 0.9998 and relative L2 < 2% against the matching CPU/Metal reference.
The test also checks string/content exact parity, raw/normalized outputs,
adjacent-text equivalence with media, batch order, whole-batch source/capacity
preflight, cancellation and text/media reuse. Synthetic images/audio establish
wiring and media sensitivity, not retrieval quality. This scenario qualifies
macOS arm64 CPU/Metal; Linux x64, Windows x64, Android and iOS CPU qualification
comes from the `embedding-gguf-cpu`
[validation pack](cross_platform_validation.md#multimodal-embedding-pack).

## Upstream-only reference

```cpp
#include "llama.h"
#include "mtmd.h"
#include <vector>
#include <string>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <stdexcept>
static void check(bool ok) { if (!ok) throw std::runtime_error("reference failed"); }
int main(int argc, char**argv) {
 check(argc==5); bool metal=std::string(argv[3])=="metal";
 llama_backend_init(); auto mp=llama_model_default_params(); mp.n_gpu_layers=metal?-1:0;
 auto*m=llama_model_load_from_file(argv[1],mp); check(m);
 auto cp=llama_context_default_params(); cp.n_ctx=cp.n_batch=cp.n_ubatch=2048;
 cp.n_threads=cp.n_threads_batch=8; cp.embeddings=true;
 if(!metal) {cp.offload_kqv=false;cp.op_offload=false;cp.flash_attn_type=LLAMA_FLASH_ATTN_TYPE_DISABLED;}
 auto*c=llama_init_from_model(m,cp); check(c);
 auto pp=mtmd_context_params_default(); pp.use_gpu=metal; pp.n_threads=8;
 auto*p=mtmd_init_from_file(argv[2],m,pp); check(p);
 std::vector<unsigned char> pixels(224*224*3,0);
 auto*black=mtmd_bitmap_init(224,224,pixels.data());
 for(int y=0;y<224;y++)for(int x=0;x<224;x++)for(int k=0;k<3;k++)pixels[(y*224+x)*3+k]=((x/16+y/16)%2)?255:0;
 auto*checker=mtmd_bitmap_init(224,224,pixels.data());
 std::vector<float> pcm(16000,0); auto*silence=mtmd_bitmap_init_from_audio(pcm.size(),pcm.data());
 for(int i=0;i<16000;i++)pcm[i]=0.2*std::sin(2*3.141592653589793*440*i/16000);
 auto*tone=mtmd_bitmap_init_from_audio(pcm.size(),pcm.data());
 std::string marker=mtmd_default_marker();
 std::vector<std::string> prompts={"The Eiffel Tower is in Paris.",marker,marker,marker,marker,"first "+marker+" between "+marker+" last "+marker};
 std::vector<std::vector<const mtmd_bitmap*>> inputs={{},{black},{checker},{silence},{tone},{black,tone,checker}};
 std::ofstream out(argv[4]); out<<std::setprecision(17)<<"[";
 for(int q=0;q<6;q++) {
  if(auto mem=llama_get_memory(c))llama_memory_clear(mem,true);
  if(q==0) {
   auto*v=llama_model_get_vocab(m);std::vector<llama_token>t(128);
   int n=llama_tokenize(v,prompts[q].data(),prompts[q].size(),t.data(),t.size(),true,true);check(n>0);
   auto b=llama_batch_init(n,0,1);b.n_tokens=n;
   for(int i=0;i<n;i++){b.token[i]=t[i];b.pos[i]=i;b.n_seq_id[i]=1;b.seq_id[i][0]=0;b.logits[i]=1;}
   check(llama_decode(c,b)==0);llama_batch_free(b);
  } else {
   auto*chunks=mtmd_input_chunks_init();mtmd_input_text text{prompts[q].data(),prompts[q].size(),true,true};
   check(mtmd_tokenize(p,chunks,&text,inputs[q].data(),inputs[q].size())==0);
   auto*b=llama_batch_ext_init(c);check(b);std::vector<std::vector<float>>copies;
   int width=llama_model_n_embd_inp(m);llama_pos pos=0;
   for(size_t k=0;k<mtmd_input_chunks_size(chunks);k++) {
    auto*chunk=mtmd_input_chunks_get(chunks,k);size_t n=mtmd_input_chunk_get_n_tokens(chunk);
    const llama_token*t=nullptr;const float*e=nullptr;
    if(mtmd_input_chunk_get_type(chunk)==MTMD_INPUT_CHUNK_TYPE_TEXT)t=mtmd_input_chunk_get_tokens_text(chunk,&n);
    else {check(mtmd_encode_chunk(p,chunk)==0);auto*output=mtmd_get_output_embd(p);check(output);copies.emplace_back(output,output+n*width);e=copies.back().data();}
    check(pos+n<=llama_n_ubatch(c));
    for(size_t i=0;i<n;i++,pos++) {int idx=t?llama_batch_ext_add_token(b,0,t[i]):llama_batch_ext_add_embd(b,0,{e+i*width,1,size_t(width)});
     check(idx>=0);check(llama_batch_ext_set_pos(b,idx,&pos));check(llama_batch_ext_set_output_embd(b,idx,true));}
   }
   check(llama_process(c,LLAMA_PROCESS_TYPE_DECODE,b)==0);llama_batch_ext_free(b);mtmd_input_chunks_free(chunks);
  }
  auto*e=llama_get_embeddings_seq(c,0);check(e);int width=llama_model_n_embd_out(m);check(width==768);double norm=0;
  for(int j=0;j<width;j++)norm+=double(e[j])*e[j];norm=std::sqrt(norm);
  if(q)out<<",";out<<"[";for(int j=0;j<width;j++){if(j)out<<",";out<<double(e[j])/norm;}out<<"]";
 }
 out<<"]\n";out.close();mtmd_bitmap_free(black);mtmd_bitmap_free(checker);mtmd_bitmap_free(silence);mtmd_bitmap_free(tone);
 mtmd_free(p);llama_free(c);llama_model_free(m);llama_backend_free();
}
```
