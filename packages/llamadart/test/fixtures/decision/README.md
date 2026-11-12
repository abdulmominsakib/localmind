# Laya decision-model reference

[`laya_0_3_5_reference.json`](../../../packages/llamadart_validation/assets/decision/laya_0_3_5_reference.json)
is the parity fixture for the decision core in `lib/src/core/decision/`, the
decision E2E test and the validation harness's decision cases, which bundle it
as a Flutter asset. Each of its 24 rows holds a state and one question,
the exact sequence token ids and option marker positions, the raw marker and
act-head logits, and the answer the reference returned. `pieces` maps every
tokenizer input text to its token ids, so sequence assembly is tested without a
model or tokenizer. `temperature` and `temperatureByOptions` are the values
Laya applied, already clamped.

Provenance: Python package `laya` 0.3.5 running the official checkpoint
[`convaiinnovations/laya`](https://huggingface.co/convaiinnovations/laya) at
revision `1c5edc17a7acd8701df6fc341c0d179f1c62c982`, FP32 on CPU (Python 3.12,
torch 2.14.0, transformers 5.17.0, numpy 2.5.3, tokenizers 0.23.2). Token ids
come from the checkpoint's Hugging Face tokenizer (`tokenizer/`), not from
llama.cpp. Answers are Laya's JSON, rounded to 4 decimals.

To regenerate with Python 3.12, install the pinned packages, download the
checkpoint, then run the two scripts:

```sh
pip install laya==0.3.5 torch==2.14.0 transformers==5.17.0 numpy==2.5.3 \
  tokenizers==0.23.2 huggingface_hub==1.32.0
hf download convaiinnovations/laya \
  --revision 1c5edc17a7acd8701df6fc341c0d179f1c62c982 --local-dir checkpoint \
  --include rl_agent_config.json --include model.safetensors \
  --include 'tokenizer/*' --include 'encoder/*'
python laya_ref_dump.py rows.json checkpoint
python gen_decision_fixture.py rows.json checkpoint/tokenizer \
  ../../../packages/llamadart_validation/assets/decision/laya_0_3_5_reference.json
```

A regenerated file needs its new SHA256 in the harness's `decision` fixture
(`packages/llamadart_validation/lib/src/decision_catalog.dart`).

The Laya checkpoint and the `laya` package are by Convai Innovations, licensed
under Apache-2.0. The fixture contains their outputs, not model weights.
