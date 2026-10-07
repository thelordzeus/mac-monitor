#ifndef SYSTEM_BRIDGE_H
#define SYSTEM_BRIDGE_H
#include <stdint.h>
#include <stdbool.h>
#include <CoreAudio/CoreAudio.h>

typedef struct {
    int pid, ppid, uid;
    uint64_t cpu_ns, memory, read_bytes, write_bytes, energy_nj, start;
    bool accessible, energy_available;
    char path[4096], name[256];
} MMProcess;
int mm_processes(MMProcess *out, int capacity);
int mm_cwd(int pid, char *out, int size);
int mm_signal(int pid, uint64_t start, int signal_number);
typedef struct {
    uint64_t user, system, idle, nice;
    uint64_t total_memory, app_memory, wired, compressed, cached, free_memory, swap;
    uint64_t net_in, net_out, disk_read, disk_write;
    double load;
    int pressure;
} MMSystem;
MMSystem mm_system(void);
double mm_smc_read(const char *key);
void mm_smc_close(void);

typedef struct { uint32_t object; int pid; bool playing; char bundle[256]; } MMAudioProcess;
int mm_audio_processes(MMAudioProcess *out, int capacity);
typedef void *MMMixer;
MMMixer mm_mixer_create(const uint32_t *objects, int count, float gain, int *error);
void mm_mixer_gain(MMMixer mixer, float gain);
void mm_mixer_destroy(MMMixer mixer);
#endif
