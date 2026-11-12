// Model-free channel checks include the unchanged production translation unit.
#include <cstring>
#include <iostream>

#ifndef S24_CHILD_SOURCE
#define S24_CHILD_SOURCE "main.cpp"
#endif
#define main S24ChildMain
#include S24_CHILD_SOURCE
#undef main

int main(int argc, char** argv) {
  if (argc != 2) return 64;
  if (std::strcmp(argv[1], "probe") == 0) {
    char* arguments[] = {argv[0], const_cast<char*>("probe"),
        const_cast<char*>("/missing-runtime"), const_cast<char*>("/missing-model"),
        const_cast<char*>("/missing-cache"), const_cast<char*>("/missing-template"),
        const_cast<char*>("fixture-binding"), const_cast<char*>("fixture-case")};
    return S24ChildMain(8, arguments);
  }
#ifndef S24_OLD_PROTOCOL_CONTROL
  if (std::strcmp(argv[1], "closed-stdout") == 0) close(STDOUT_FILENO);
  if (std::strcmp(argv[1], "closed-stderr") == 0) close(STDERR_FILENO);
  ProtocolOutput output;
#endif
  binding = "fixture-binding"; case_id = "fixture-case";
  Record("started");
  std::printf("INFO: Loaded OpenCL library with dlopen.\n");
  std::fflush(stdout);
  std::fprintf(stderr, "vendor stderr\n");
  std::fflush(stderr);
  std::cout << "vendor cout\n" << std::flush;
#ifndef S24_OLD_PROTOCOL_CONTROL
  if (std::strcmp(argv[1], "broken-protocol") == 0) close(fileno(protocol));
#endif
  Record("finished");
  return 0;
}
