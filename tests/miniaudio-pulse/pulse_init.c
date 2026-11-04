#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include <stdio.h>
#include <string.h>

typedef struct { unsigned connect_failures; unsigned wait_failures; } observations;
static void on_log(void* data, ma_uint32 level, const char* message) {
    observations* seen = data;
    if (level == MA_LOG_LEVEL_ERROR) fprintf(stderr, "%s\n", message);
    if (strstr(message, "Failed to connect PulseAudio context.")) ++seen->connect_failures;
    if (strstr(message, "Waiting for connection failed.")) ++seen->wait_failures;
}

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    int immediate = strcmp(argv[1], "invalid-address") == 0;
    if (!immediate && strcmp(argv[1], "absent-server") != 0) return 2;
    observations seen = {0};
    ma_log log;
    if (ma_log_init(NULL, &log) != MA_SUCCESS) return 3;
    if (ma_log_register_callback(&log, ma_log_callback_init(on_log, &seen)) != MA_SUCCESS) return 4;
    for (unsigned i = 0; i < 32; ++i) {
        ma_context context;
        ma_context_config config = ma_context_config_init();
        ma_backend backend = ma_backend_pulseaudio;
        config.pLog = &log;
        config.pulse.pServerName = immediate ? "invalid-address:" : "unix:/tmp/qigao-miniaudio-pulse-absent/server.sock";
        config.pulse.tryAutoSpawn = MA_FALSE;
        ma_result result = ma_context_init(&backend, 1, &config, &context);
        if (result == MA_SUCCESS) {
            ma_context_uninit(&context);
            fprintf(stderr, "Unexpected successful connection\n");
            return 5;
        }
        if (result != MA_NO_BACKEND) {
            fprintf(stderr, "Unexpected result %d at iteration %u\n", result, i);
            return 6;
        }
        /* Failed initialization owns its cleanup: uninit is only valid on success. */
    }
    ma_log_uninit(&log);
    fprintf(stderr, "scenario=%s iterations=32 result=%d connect_failures=%u wait_failures=%u\n",
            argv[1], MA_NO_BACKEND, seen.connect_failures, seen.wait_failures);
    if (immediate) return seen.connect_failures == 32 && seen.wait_failures == 0 ? 0 : 7;
    return seen.connect_failures == 0 && seen.wait_failures == 32 ? 0 : 8;
}
