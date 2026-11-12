#include "llama.h"
#include "ggml-backend.h"
#include "backend_selection.h"
#include "vector_serialization.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <csignal>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <link.h>
#include <stdexcept>
#include <sstream>
#include <string>
#include <unistd.h>
#include <vector>

namespace {
std::string binding, case_id;
int sequence = 0;
std::string hex(const std::string & value) {
    static const char digits[] = "0123456789abcdef";
    std::string out;
    for (unsigned char c : value) { out += digits[c >> 4]; out += digits[c & 15]; }
    return out;
}
void require(bool value, const char * message) {
    if (!value) throw std::runtime_error(message);
}
void emit(const char * event, const std::string & fields = "") {
    std::cout << "{\"schema\":1,\"binding\":\"" << binding
              << "\",\"case_id\":\"" << case_id << "\",\"pid\":" << getpid()
              << ",\"sequence\":" << sequence++ << ",\"event\":\"" << event << "\""
              << fields << "}\n" << std::flush;
}
void watchdog(int) {
    const char message[] = "ANDROID_QUALIFICATION_NATIVE_DEADLINE\n";
    (void)write(STDERR_FILENO, message, sizeof(message) - 1);
    _exit(124);
}
void maps() {
    std::ifstream input("/proc/self/maps");
    require(input.good(), "native maps unavailable");
    std::string line, payload;
    while (std::getline(input, line)) {
        if (line.find("libllama") != std::string::npos ||
            line.find("libggml") != std::string::npos ||
            line.find("libllamadart_android_qualification.so") != std::string::npos) {
            payload += line + "\n";
        }
    }
    require(payload.size() <= 24 * 1024, "native maps exceed protocol bound");
    emit("maps", ",\"maps_hex\":\"" + hex(payload) + "\"");
}
std::vector<llama_token> tokenize(const llama_vocab * vocab, const std::string & text) {
    std::vector<llama_token> tokens(text.size() + 32);
    int count = llama_tokenize(vocab, text.data(), text.size(), tokens.data(), tokens.size(), true, true);
    require(count > 0, "tokenization failed");
    tokens.resize(count);
    return tokens;
}
void fill(llama_batch & batch, const std::vector<llama_token> & tokens, int position = 0, bool embeddings = false) {
    batch.n_tokens = tokens.size();
    for (int i = 0; i < batch.n_tokens; i++) {
        batch.token[i] = tokens[i]; batch.pos[i] = position + i;
        batch.n_seq_id[i] = 1; batch.seq_id[i][0] = 0;
        batch.logits[i] = embeddings || i == batch.n_tokens - 1;
    }
}
void generate(llama_model * model, llama_context * context) {
    const auto * vocab = llama_model_get_vocab(model);
    auto tokens = tokenize(vocab, "The capital of France is");
    auto batch = llama_batch_init(512, 0, 1);
    auto * sampler = llama_sampler_init_greedy();
    require(sampler, "greedy sampler unavailable");
    try {
        fill(batch, tokens);
        require(llama_decode(context, batch) == 0, "prompt decode failed");
        const int prompt_tokens = tokens.size();
        std::string text, ids;
        bool eog = false;
        for (int i = 0; i < 24; i++) {
            const auto token = llama_sampler_sample(sampler, context, -1);
            if (llama_vocab_is_eog(vocab, token)) { eog = true; break; }
            if (i) ids += ",";
            ids += std::to_string(token);
            std::vector<char> piece(256);
            int size = llama_token_to_piece(vocab, token, piece.data(), piece.size(), 0, false);
            if (size < 0) {
                piece.resize(-size);
                size = llama_token_to_piece(vocab, token, piece.data(), piece.size(), 0, false);
            }
            require(size >= 0, "token piece failed"); text.append(piece.data(), size);
            llama_sampler_accept(sampler, token);
            fill(batch, {token}, prompt_tokens + i);
            require(llama_decode(context, batch) == 0, "generation decode failed");
        }
        emit("generation", ",\"prompt_tokens\":" + std::to_string(prompt_tokens) +
             ",\"output_hex\":\"" + hex(text) + "\",\"token_ids\":[" + ids +
             "],\"eog\":" + (eog ? "true" : "false"));
    } catch (...) { llama_sampler_free(sampler); llama_batch_free(batch); throw; }
    llama_sampler_free(sampler); llama_batch_free(batch);
}
void embed(llama_model * model, llama_context * context, bool probe_only) {
    const std::vector<std::string> timed_phases = {"first", "warmup-1", "warmup-2",
        "measured-1", "measured-2", "measured-3", "measured-4", "measured-5"};
    const auto phases = probe_only ? std::vector<std::string>{"probe"} : timed_phases;
    require(!(llama_model_has_encoder(model) && llama_model_has_decoder(model)), "encoder-decoder unsupported");
    const bool encoder = llama_model_has_encoder(model) && !llama_model_has_decoder(model);
    const int width = llama_model_n_embd_out(model);
    require(width == 768, "embedding width mismatch");
    auto batch = llama_batch_init(1024, 0, 1);
    try {
        for (int input = 0; input < 2; input++) {
            std::string text = "title: none | text: coffee";
            if (input) for (int i = 1; i < 38; i++) text += " coffee";
            const auto tokens = tokenize(llama_model_get_vocab(model), text);
            require(tokens.size() == size_t(input ? 46 : 9), "embedding token count mismatch");
            for (const auto & phase : phases) {
                const auto start = std::chrono::steady_clock::now();
                if (auto memory = llama_get_memory(context)) llama_memory_clear(memory, true);
                llama_set_embeddings(context, true);
                fill(batch, tokens, 0, true);
                require((encoder ? llama_encode(context, batch) : llama_decode(context, batch)) == 0,
                        "embedding operation failed");
                const auto pooling = llama_pooling_type(context);
                const float * values = pooling == LLAMA_POOLING_TYPE_NONE
                    ? llama_get_embeddings_ith(context, tokens.size() - 1)
                    : llama_get_embeddings_seq(context, 0);
                if (!values) values = llama_get_embeddings(context);
                require(values, "embedding output unavailable");
                const std::vector<float> raw(values, values + width);
                llama_set_embeddings(context, false);
                const double elapsed = std::chrono::duration<double, std::milli>(
                    std::chrono::steady_clock::now() - start).count();
                // Preserve the actual IEEE bytes before any numerical predicate.
                emit("embedding_raw", ",\"input\":" + std::to_string(input) +
                    ",\"phase\":\"" + phase + "\",\"tokens\":" + std::to_string(tokens.size()) +
                    ",\"vector_f32_le_hex\":\"" + hex(std::string(
                        reinterpret_cast<const char *>(raw.data()), raw.size() * sizeof(float))) + "\"");
                const auto vector = android_qualification::normalized_vector_json(raw);
                emit("embedding", ",\"input\":" + std::to_string(input) +
                    ",\"phase\":\"" + phase + "\",\"tokens\":" + std::to_string(tokens.size()) +
                    ",\"operation_ms\":" + std::to_string(elapsed) +
                    ",\"vector\":[" + vector + "]");
            }
        }
    } catch (...) { llama_set_embeddings(context, false); llama_batch_free(batch); throw; }
    llama_batch_free(batch);
}
} // namespace

int main(int argc, char ** argv) {
    setvbuf(stderr, nullptr, _IONBF, 0);
    try {
        require(argc == 8, "expected scenario backend model library-directory binding case deadline");
        const std::string scenario = argv[1], backend = argv[2];
        binding = argv[5]; case_id = argv[6];
        require(binding.size() == 64 && binding.find_first_not_of("0123456789abcdef") == std::string::npos,
                "invalid binding");
        require(case_id.size() < 80 && case_id.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789.-") == std::string::npos,
                "invalid case");
        require(scenario == "probe" || scenario == "a35" || scenario == "pixel8a" || scenario == "pixel8a-probe", "invalid scenario");
        require(backend == "cpu" || backend == "vulkan" || (scenario == "a35" && backend == "vulkan-defaults"),
                "invalid backend");
        const int seconds = std::stoi(argv[7]); require(seconds > 0 && seconds <= 120, "invalid deadline");
        std::signal(SIGALRM, watchdog); alarm(seconds);
        emit("started");
        if (scenario == "probe") {
            std::cerr << "ANDROID_QUALIFICATION_MODEL_FREE_PROBE\n";
            maps(); emit("finished"); return 0;
        }
        ggml_backend_load_all_from_path(argv[4]); llama_backend_init();
        const bool cpu = backend == "cpu";
        ggml_backend_dev_t selected = cpu ? ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU)
                                          : android_qualification::select_vulkan_device();
        ggml_backend_dev_t devices[] = {selected, nullptr};
        require(devices[0], "required backend unavailable; fallback forbidden");
        std::cerr << "ANDROID_QUALIFICATION_SELECTED_BACKEND registry="
            << ggml_backend_reg_name(ggml_backend_dev_backend_reg(selected))
            << " device=" << ggml_backend_dev_name(selected) << "\n";
        auto mp = llama_model_default_params(); mp.n_gpu_layers = cpu ? 0 : 999; mp.devices = devices;
        auto * model = llama_model_load_from_file(argv[3], mp); require(model, "model load failed");
        llama_context * context = nullptr;
        try {
            auto cp = llama_context_default_params();
            cp.n_ctx = 1024; cp.n_batch = cp.n_ubatch = scenario == "a35" ? 512 : 1024;
            cp.n_seq_max = 1; cp.n_threads = cp.n_threads_batch = 4;
            cp.type_k = cp.type_v = GGML_TYPE_F16;
            if (backend != "vulkan-defaults") {
                cp.offload_kqv = false; cp.op_offload = false;
                cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;
            }
            context = llama_init_from_model(model, cp); require(context, "context creation failed");
            require(llama_n_ctx(context) == 1024 && llama_n_batch(context) == cp.n_batch &&
                    llama_n_ubatch(context) == cp.n_ubatch, "effective context geometry mismatch");
            maps();
            std::cerr << "ANDROID_QUALIFICATION_GEOMETRY n_ctx=" << llama_n_ctx(context)
                << " n_batch=" << llama_n_batch(context) << " n_ubatch=" << llama_n_ubatch(context)
                << " kqv=" << cp.offload_kqv << " op=" << cp.op_offload
                << " fa=" << int(cp.flash_attn_type) << "\n";
            if (scenario == "a35") generate(model, context); else embed(model, context, scenario == "pixel8a-probe");
        } catch (...) { if (context) llama_free(context); llama_model_free(model); throw; }
        llama_free(context); llama_model_free(model); llama_backend_free();
        emit("finished"); alarm(0); return 0;
    } catch (const std::exception & error) {
        std::cerr << "ANDROID_QUALIFICATION_ERROR " << error.what() << "\n";
        return 1;
    }
}
