"""Generate independent official float32 CPU reference vectors for #1126.

Download google/embeddinggemma-2 at 914f7f89142e33e77833254d9c9b90c3cef7303b
separately. This script never downloads models or modifies a model cache.
"""

import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path

import torch
from sentence_transformers import SentenceTransformer


def digest(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    weights_hash = digest(args.model_dir / "model.safetensors")
    if weights_hash != "197a32965d4b1105faf060417baa899e193fb73cd401f42ec9295234d5553d79":
        raise ValueError("The reference requires the pinned official EG2 checkpoint.")
    corpus_path = Path(__file__).parents[2] / "fixtures/embeddings/embeddinggemma2_retrieval.json"
    corpus = json.loads(corpus_path.read_text())
    torch.set_num_threads(8)
    model = SentenceTransformer(
        str(args.model_dir),
        device="cpu",
        model_kwargs={"torch_dtype": torch.float32},
        config_kwargs={"vision_config": None, "audio_config": None},
    )
    documents = [f"title: {doc['title'] if doc['title'] is not None else 'none'} | text: {doc['text']}" for doc in corpus["documents"]]
    queries = [query["text"] for query in corpus["queries"]]
    results = {}
    for dimensions in [768, 512, 256, 128]:
        # Use the official model's named query prompt, not the Dart formatter.
        query_vectors = model.encode(queries, prompt_name="SearchQuery", truncate_dim=dimensions, normalize_embeddings=True)
        document_vectors = model.encode(documents, truncate_dim=dimensions, normalize_embeddings=True)
        scores = query_vectors @ document_vectors.T
        results[str(dimensions)] = {
            "queries": query_vectors.tolist(),
            "documents": document_vectors.tolist(),
            "scores": scores.tolist(),
            "top1": scores.argmax(axis=1).tolist(),
        }
    output = {
        "model": "google/embeddinggemma-2",
        "revision": "914f7f89142e33e77833254d9c9b90c3cef7303b",
        "weights_sha256": weights_hash,
        "corpus_sha256": digest(corpus_path),
        "dtype": "float32",
        "device": "cpu",
        "versions": {name: importlib.metadata.version(name) for name in ["torch", "transformers", "sentence-transformers"]},
        "dimensions": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps({key: value for key, value in output.items() if key != "dimensions"}, indent=2))
    print("top1:", {key: value["top1"] for key, value in results.items()})


if __name__ == "__main__":
    main()
