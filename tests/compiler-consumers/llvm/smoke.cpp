#include <cstdio>
#include <string>
int main() {
    std::string value = "LLVM-MinGW C++ smoke PASS";
    if (value.empty()) return 1;
    std::puts(value.c_str());
    return 0;
}
