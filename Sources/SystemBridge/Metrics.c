#include "SystemBridge.h"
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <sys/proc_info.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <net/if_var.h>
#include <IOKit/IOKitLib.h>
#include <signal.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h>

int mm_processes(MMProcess *out, int capacity) {
    mach_timebase_info_data_t timebase; mach_timebase_info(&timebase);
    int bytes = proc_listallpids(NULL, 0);
    int allocated = bytes + 512;
    pid_t *pids = calloc(allocated, sizeof(pid_t));
    int count = proc_listallpids(pids, allocated * sizeof(pid_t)), written = 0;
    for (int i = 0; i < count && written < capacity; i++) {
        if (pids[i] <= 0) continue;
        struct proc_bsdinfo bsd = {0};
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) continue;
        MMProcess *p = &out[written++];
        memset(p, 0, sizeof(*p));
        p->pid = pids[i]; p->ppid = bsd.pbi_ppid; p->uid = bsd.pbi_uid;
        p->start = bsd.pbi_start_tvsec * 1000000ULL + bsd.pbi_start_tvusec;
        proc_pidpath(p->pid, p->path, sizeof(p->path));
        strlcpy(p->name, bsd.pbi_name[0] ? bsd.pbi_name : bsd.pbi_comm, sizeof(p->name));
        struct rusage_info_v6 usage = {0};
        int status = proc_pid_rusage(p->pid, RUSAGE_INFO_V6, (rusage_info_t *)&usage);
        p->energy_available = status == 0;
        if (status != 0) status = proc_pid_rusage(p->pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage);
        if (status == 0) {
            p->accessible = true;
            // rusage CPU times are Mach ticks, unlike proc_taskinfo's nanoseconds.
            p->cpu_ns = (uint64_t)(((__uint128_t)usage.ri_user_time + usage.ri_system_time) * timebase.numer / timebase.denom);
            p->memory = usage.ri_phys_footprint;
            p->read_bytes = usage.ri_diskio_bytesread;
            p->write_bytes = usage.ri_diskio_byteswritten;
            p->energy_nj = usage.ri_energy_nj;
        } else {
            struct proc_taskinfo task = {0};
            if (proc_pidinfo(p->pid, PROC_PIDTASKINFO, 0, &task, sizeof(task)) == sizeof(task)) {
                p->accessible = true; p->memory = task.pti_resident_size;
                p->cpu_ns = task.pti_total_user + task.pti_total_system;
            }
        }
    }
    free(pids);
    return written;
}
int mm_cwd(int pid, char *out, int size) {
    struct proc_vnodepathinfo info = {0};
    if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, sizeof(info)) != sizeof(info)) return -1;
    strlcpy(out, info.pvi_cdir.vip_path, size); return 0;
}
int mm_signal(int pid, uint64_t start, int sig) {
    struct proc_bsdinfo bsd = {0};
    if (pid <= 1 || pid == getpid()) return EPERM;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) return ESRCH;
    if (bsd.pbi_start_tvsec * 1000000ULL + bsd.pbi_start_tvusec != start) return ESRCH;
    if (bsd.pbi_uid != getuid()) return EPERM;
    return kill(pid, sig) == 0 ? 0 : errno;
}
MMSystem mm_system(void) {
    MMSystem s = {0};
    host_cpu_load_info_data_t cpu;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, (host_info_t)&cpu, &count) == KERN_SUCCESS) {
        s.user = cpu.cpu_ticks[CPU_STATE_USER]; s.system = cpu.cpu_ticks[CPU_STATE_SYSTEM];
        s.idle = cpu.cpu_ticks[CPU_STATE_IDLE]; s.nice = cpu.cpu_ticks[CPU_STATE_NICE];
    }
    vm_statistics64_data_t vm = {0}; count = HOST_VM_INFO64_COUNT;
    vm_size_t page; host_page_size(mach_host_self(), &page);
    size_t size = sizeof(s.total_memory); sysctlbyname("hw.memsize", &s.total_memory, &size, NULL, 0);
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        s.wired = vm.wire_count * (uint64_t)page;
        s.compressed = vm.compressor_page_count * (uint64_t)page;
        s.cached = (vm.purgeable_count + vm.external_page_count) * (uint64_t)page;
        // free_count already includes speculative pages, which also belong to
        // the file-backed cache. Keep the free and cached buckets disjoint.
        s.free_memory = (vm.free_count > vm.speculative_count ? vm.free_count - vm.speculative_count : 0) * (uint64_t)page;
        s.app_memory = (vm.internal_page_count > vm.purgeable_count ? vm.internal_page_count - vm.purgeable_count : 0) * (uint64_t)page;
    }
    struct xsw_usage swap; size = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0) s.swap = swap.xsu_used;
    size = sizeof(s.pressure); sysctlbyname("kern.memorystatus_vm_pressure_level", &s.pressure, &size, NULL, 0);
    getloadavg(&s.load, 1);
    // NET_RT_IFLIST2 provides 64-bit counters; getifaddrs wraps at 4 GB.
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0}; size_t network_size = 0;
    if (sysctl(mib, 6, NULL, &network_size, NULL, 0) == 0) {
        char *network = malloc(network_size);
        if (sysctl(mib, 6, network, &network_size, NULL, 0) == 0) {
            for (char *next = network; next < network + network_size; ) {
                struct if_msghdr *header = (struct if_msghdr *)next;
                if (!header->ifm_msglen) break;
                if (header->ifm_type == RTM_IFINFO2) {
                    struct if_msghdr2 *info = (struct if_msghdr2 *)next;
                    struct sockaddr_dl *address = (struct sockaddr_dl *)(info + 1);
                    char name[IFNAMSIZ] = {0};
                    if (address->sdl_nlen < IFNAMSIZ) memcpy(name, address->sdl_data, address->sdl_nlen);
                    if (!strncmp(name, "en", 2) || !strncmp(name, "pdp_ip", 6)) {
                        s.net_in += info->ifm_data.ifi_ibytes; s.net_out += info->ifm_data.ifi_obytes;
                    }
                }
                next += header->ifm_msglen;
            }
        }
        free(network);
    }
    // Physical whole-device counters avoid counting APFS containers twice.
    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &it) == KERN_SUCCESS) {
        io_object_t obj;
        while ((obj = IOIteratorNext(it))) {
            CFTypeRef stats = IORegistryEntryCreateCFProperty(obj, CFSTR("Statistics"), kCFAllocatorDefault, 0);
            if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
                int64_t n = 0;
                CFNumberRef value = CFDictionaryGetValue(stats, CFSTR("Bytes (Read)"));
                if (value && CFNumberGetValue(value, kCFNumberSInt64Type, &n)) s.disk_read += n;
                value = CFDictionaryGetValue(stats, CFSTR("Bytes (Write)")); n = 0;
                if (value && CFNumberGetValue(value, kCFNumberSInt64Type, &n)) s.disk_write += n;
            }
            if (stats) CFRelease(stats); IOObjectRelease(obj);
        }
        IOObjectRelease(it);
    }
    return s;
}

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCKeyInfo;
typedef struct { uint32_t key; SMCVersion version; SMCPLimit limit; SMCKeyInfo info;
    uint8_t result, status, command; uint32_t data32; uint8_t bytes[32]; } SMCData;
static io_connect_t smc = 0;
static uint32_t fourcc(const char *key) { return (uint8_t)key[0]<<24 | (uint8_t)key[1]<<16 | (uint8_t)key[2]<<8 | (uint8_t)key[3]; }
double mm_smc_read(const char *key) {
    if (!smc) {
        io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
        if (!service) return NAN;
        kern_return_t r = IOServiceOpen(service, mach_task_self(), 0, &smc); IOObjectRelease(service);
        if (r != KERN_SUCCESS) { smc = 0; return NAN; }
    }
    SMCData in = {0}, out = {0}; size_t size = sizeof(out);
    in.key = fourcc(key); in.command = 9;
    if (IOConnectCallStructMethod(smc, 2, &in, sizeof(in), &out, &size) != KERN_SUCCESS || out.result || !out.info.size) return NAN;
    in.info = out.info; in.command = 5; uint32_t type = out.info.type; size = sizeof(out);
    if (IOConnectCallStructMethod(smc, 2, &in, sizeof(in), &out, &size) != KERN_SUCCESS || out.result) return NAN;
    if (type == fourcc("sp78")) return (int16_t)((out.bytes[0]<<8) | out.bytes[1]) / 256.0;
    if (type == fourcc("fpe2")) return ((out.bytes[0]<<8) | out.bytes[1]) / 4.0;
    if (type == fourcc("flt ")) { float f; memcpy(&f, out.bytes, 4); return isfinite(f) ? f : NAN; }
    if (type == fourcc("ui8 ")) return out.bytes[0];
    if (type == fourcc("ui16")) return (out.bytes[0]<<8) | out.bytes[1];
    return NAN;
}
void mm_smc_close(void) { if (smc) IOServiceClose(smc); smc = 0; }
