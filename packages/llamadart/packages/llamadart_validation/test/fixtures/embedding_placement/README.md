# Native embedding placement excerpts

`metal.txt` and `cpu.txt` retain only offload, llama-context construction,
projector selection/type, and compute-reservation lines from the 015-X2 local
EmbeddingGemma-2 BF16 runs on Apple M4 Max, published native v0.7.0-1
(llama.cpp `620d2225cc436ab0b001e3200e590e3b286ef9ab`). No line is edited;
model paths and unrelated metadata are omitted.

The Metal log has one 25/25 offload, one llama context, sixteen
`sched_reserve` allocations (one initial and fifteen after embedding-mode graph
changes), and two `reserve_compute_meta` allocations from the vision/audio
CLIP contexts. CPU scratch allocations also appear in the successful Metal log.
The CPU log is an actual fallback-shaped negative: 0/25 offload, CPU-only
compute, and CPU projector selections.

Pinned upstream `src/llama-context.cpp`, `llama_context::set_embeddings`, marks
a pooled context for reservation when its embeddings flag changes;
`sched_reserve` logs backend compute sizes. `tools/mtmd/clip.cpp`,
`clip_ctx::reserve_compute_meta`, logs the two projector allocations.

Tests also derive single-fault controls from these real excerpts (zero/partial
or removed offload, wrong device, zero/malformed/removed buffer, missing/extra
context, and incomplete/unattributed reservation). These altered controls are
not represented as additional hardware runs.
