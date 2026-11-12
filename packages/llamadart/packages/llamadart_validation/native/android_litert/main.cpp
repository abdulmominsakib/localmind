// A separate executable process owns every potentially blocking native handle.
#include <dlfcn.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>

namespace {
void* library = nullptr;
std::string binding, case_id;
unsigned sequence = 0;
FILE* protocol = nullptr;
[[noreturn]] void ProtocolFailure() {
  std::fprintf(stderr, "S24_LITERT_CHILD_ERROR protocol capture unavailable\n");
  _exit(74);
}
struct ProtocolOutput {
  ProtocolOutput() {
    // Keep the parent's stdout exclusively for records before loading vendor code.
    const int descriptor = fcntl(STDOUT_FILENO, F_DUPFD_CLOEXEC, 3);
    if (descriptor < 0) ProtocolFailure();
    protocol = fdopen(descriptor, "w");
    if (!protocol) { close(descriptor); ProtocolFailure(); }
    if (dup2(STDERR_FILENO, STDOUT_FILENO) < 0) {
      std::fclose(protocol); protocol = nullptr; ProtocolFailure();
    }
  }
  ~ProtocolOutput() {
    FILE* owned = protocol; protocol = nullptr;
    if (std::fclose(owned) != 0) ProtocolFailure();
  }
  ProtocolOutput(const ProtocolOutput&) = delete;
  ProtocolOutput& operator=(const ProtocolOutput&) = delete;
};
std::string Quote(const std::string& input) {
  std::string output = "\"";
  for (unsigned char c : input) {
    if (c == '\\' || c == '"') { output += '\\'; output += c; }
    else if (c < 32) { char escaped[7]; std::snprintf(escaped, sizeof(escaped), "\\u%04x", c); output += escaped; }
    else output += c;
  }
  return output + '"';
}
std::string Hex(const std::string& input) {
  constexpr char digits[] = "0123456789abcdef";
  std::string result;
  for (unsigned char c : input) { result += digits[c >> 4]; result += digits[c & 15]; }
  return result;
}
void Record(const char* event, const std::string& fields = "") {
  const std::string record = "{\"schema\":1,\"binding\":" + Quote(binding) +
      ",\"case_id\":" + Quote(case_id) + ",\"pid\":" + std::to_string(getpid()) +
      ",\"sequence\":" + std::to_string(sequence) + ",\"event\":" + Quote(event) + fields + "}\n";
  if (!protocol || std::fwrite(record.data(), 1, record.size(), protocol) != record.size() ||
      std::fflush(protocol) != 0) ProtocolFailure();
  ++sequence;
}
std::string Read(const std::string& path, size_t limit) {
  std::ifstream file(path, std::ios::binary);
  if (!file) throw std::runtime_error("child input unavailable");
  std::string result;
  char block[4096];
  while (file) { file.read(block, sizeof(block)); result.append(block, file.gcount()); if (result.size() > limit) throw std::runtime_error("child input limit"); }
  return result;
}
template<class T> T Function(const char* name) {
  auto symbol = dlsym(library, name);
  if (!symbol) throw std::runtime_error(std::string("missing C API export: ") + name);
  return reinterpret_cast<T>(symbol);
}
void Check(int status) {
  if (!status) return;
  const char* error = Function<const char* (*)()>("litert_lm_get_last_error_message")();
  throw std::runtime_error("C API status=" + std::to_string(status) + ": " + (error ? error : ""));
}
using Create = int (*)(void**);
using Delete = void (*)(void*);
using SetInt = int (*)(void*, int);
using SetFloat = int (*)(void*, float);
using SetString = int (*)(void*, const char*);
using SetPointer = int (*)(void*, void*);
struct Owned {
  const char* deletion;
  void* pointer = nullptr;
  ~Owned() { if (pointer) Function<Delete>(deletion)(pointer); }
  void CreateWith(const char* creation) { Check(Function<Create>(creation)(&pointer)); }
};
void Generation(void* engine, const char* fixture, const char* prompt, const std::string& template_text) {
  Owned sampler{"litert_lm_sampler_params_delete"};
  Check(Function<int (*)(int, void**)>("litert_lm_sampler_params_create")(2, &sampler.pointer));
  Check(Function<SetInt>("litert_lm_sampler_params_set_top_k")(sampler.pointer, 1));
  Check(Function<SetFloat>("litert_lm_sampler_params_set_top_p")(sampler.pointer, 0.9f));
  Check(Function<SetFloat>("litert_lm_sampler_params_set_temperature")(sampler.pointer, 0.0f));
  Check(Function<int (*)(void*, int32_t)>("litert_lm_sampler_params_set_seed")(sampler.pointer, 1));
  Owned session{"litert_lm_session_config_delete"}; session.CreateWith("litert_lm_session_config_create");
  Check(Function<SetPointer>("litert_lm_session_config_set_sampler_params")(session.pointer, sampler.pointer));
  Check(Function<SetInt>("litert_lm_session_config_set_max_output_tokens")(session.pointer, 32));
  Owned config{"litert_lm_conversation_config_delete"}; config.CreateWith("litert_lm_conversation_config_create");
  Check(Function<SetPointer>("litert_lm_conversation_config_set_session_config")(config.pointer, session.pointer));
  Owned thinking{"litert_lm_thinking_config_delete"}; thinking.CreateWith("litert_lm_thinking_config_create");
  Check(Function<int (*)(void*, bool)>("litert_lm_thinking_config_set_enable_thinking")(thinking.pointer, false));
  Check(Function<SetPointer>("litert_lm_conversation_config_set_thinking_config")(config.pointer, thinking.pointer));
  Check(Function<SetString>("litert_lm_conversation_config_set_prompt_template")(config.pointer, template_text.c_str()));
  Check(Function<SetString>("litert_lm_conversation_config_set_extra_context")(config.pointer, "{\"enable_thinking\":false}"));
  Owned conversation{"litert_lm_conversation_delete"};
  Check(Function<int (*)(void*, void*, void**)>("litert_lm_conversation_create")(engine, config.pointer, &conversation.pointer));
  Owned args{"litert_lm_conversation_optional_args_delete"}; args.CreateWith("litert_lm_conversation_optional_args_create");
  Check(Function<SetInt>("litert_lm_conversation_optional_args_set_max_output_tokens")(args.pointer, 32));
  const std::string message = "{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":" + Quote(prompt) + "}]}";
  Owned response{"litert_lm_json_response_delete"};
  Check(Function<int (*)(void*, const char*, const char*, void*, void**)>("litert_lm_conversation_send_message")(
      conversation.pointer, message.c_str(), nullptr, args.pointer, &response.pointer));
  const char* json = nullptr;
  Check(Function<int (*)(void*, const char**)>("litert_lm_json_response_get_string")(response.pointer, &json));
  if (!json) throw std::runtime_error("null native response");
  const std::string raw(json);
  if (raw.size() > 20000) throw std::runtime_error("native response byte limit");
  Record("generation", ",\"fixture\":" + Quote(fixture) + ",\"prompt\":" + Quote(prompt) +
      ",\"native_json_hex\":" + Quote(Hex(raw)) + ",\"native_finish\":\"not_exposed_by_sync_native_control\"");
  Owned benchmark{"litert_lm_benchmark_info_delete"};
  Check(Function<int (*)(void*, void**)>("litert_lm_conversation_get_benchmark_info")(conversation.pointer, &benchmark.pointer));
  size_t input_tokens = 0, output_tokens = 0;
  Check(Function<int (*)(void*, size_t, size_t*)>("litert_lm_benchmark_info_get_prefill_token_count_at")(benchmark.pointer, 0, &input_tokens));
  Check(Function<int (*)(void*, size_t, size_t*)>("litert_lm_benchmark_info_get_decode_token_count_at")(benchmark.pointer, 0, &output_tokens));
  Record("generation", ",\"fixture\":" + Quote(fixture) + ",\"input_tokens\":" + std::to_string(input_tokens) + ",\"output_tokens\":" + std::to_string(output_tokens));

}
void Deadline(int) { _exit(124); }
} // namespace

int main(int argc, char** argv) {
  // mode, core, model, cache, canonical template, binding, case id.
  if (argc != 8) return 64;
  binding = argv[6]; case_id = argv[7];
  signal(SIGALRM, Deadline); alarm(115);
  ProtocolOutput output;
  setvbuf(stdout, nullptr, _IONBF, 0); setvbuf(stderr, nullptr, _IONBF, 0);
  Record("started", ",\"mode\":" + Quote(argv[1]));
  if (std::string(argv[1]) == "probe") { Record("finished", ",\"model_free_launch\":true"); return 0; }
  try {
    const bool guard = std::string(argv[1]) == "guard";
    const std::string backend = guard ? "gpu" : argv[1];
    if (backend != "cpu" && backend != "gpu") throw std::runtime_error("explicit backend required");
    library = dlopen(argv[2], RTLD_NOW | RTLD_LOCAL);
    if (!library) throw std::runtime_error("bound LiteRT core could not be loaded");
    int major = -1, minor = -1, patch = -1;
    Check(Function<int (*)(int*, int*, int*)>("litert_lm_get_api_version")(&major, &minor, &patch));
    if (major != 1 || minor != 0 || patch < 0) throw std::runtime_error("C API 1.0.x required");
    Check(Function<int (*)(int)>("litert_lm_set_min_log_level")(0));
    const std::string template_text = Read(argv[5], 16000);
    Owned settings{"litert_lm_engine_settings_delete"};
    Check(Function<int (*)(const char*, const char*, const char*, const char*, void**)>("litert_lm_engine_settings_create")(
        argv[3], backend.c_str(), nullptr, nullptr, &settings.pointer));
    Check(Function<SetInt>("litert_lm_engine_settings_set_num_threads")(settings.pointer, 4));
    Check(Function<SetInt>("litert_lm_engine_settings_set_max_num_tokens")(settings.pointer, 1024));
    Check(Function<SetString>("litert_lm_engine_settings_set_cache_dir")(settings.pointer, argv[4]));
    Check(Function<int (*)(void*)>("litert_lm_engine_settings_enable_benchmark")(settings.pointer));
    Owned speculative{"litert_lm_speculative_decoding_config_delete"}; speculative.CreateWith("litert_lm_speculative_decoding_config_create");
    Check(Function<SetInt>("litert_lm_speculative_decoding_config_set_mode")(speculative.pointer, 0));
    Check(Function<SetPointer>("litert_lm_engine_settings_set_speculative_decoding_config")(settings.pointer, speculative.pointer));
    Owned engine{"litert_lm_engine_delete"};
    const int engine_status = Function<int (*)(void*, void**)>("litert_lm_engine_create")(settings.pointer, &engine.pointer);
    if (guard) {
      if (!engine_status || engine.pointer) throw std::runtime_error("expected GPU guard did not refuse before engine creation");
      const char* error = Function<const char* (*)()>("litert_lm_get_last_error_message")();
      Record("finished", ",\"guard_refused\":true,\"native_error\":" + Quote(error ? error : ""));
      return 0;
    }
    Check(engine_status);
    std::ifstream maps("/proc/self/maps"); std::string line, selected;
    while (std::getline(maps, line)) {
      if (line.find("LiteRt") != std::string::npos || line.find("webgpu") != std::string::npos || line.find("GemmaModelConstraint") != std::string::npos) selected += line + '\n';
    }
    Record("maps", ",\"raw_hex\":" + Quote(Hex(selected)) + ",\"c_api_version\":\"1.0." + std::to_string(patch) + "\"");
    Generation(engine.pointer, "hello", "Reply with one short sentence saying hello.", template_text);
    Generation(engine.pointer, "arithmetic", "What is 3 + 4? Reply with only the number.", template_text);
    // Free every handle before the terminal process receipt.
  } catch (const std::exception& error) {
    std::fprintf(stderr, "S24_LITERT_CHILD_ERROR %s\n", error.what());
    return 1;
  }
  Record("finished", ",\"engine_deleted\":true");
  alarm(0);
  return 0;
}
