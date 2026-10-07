#import "SystemBridge.h"
#import <Foundation/Foundation.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#include <stdatomic.h>

int mm_audio_processes(MMAudioProcess *out, int capacity) {
    if (@available(macOS 14.2, *)) {
        AudioObjectPropertyAddress address = {kAudioHardwarePropertyProcessObjectList, kAudioObjectPropertyScopeGlobal, 0};
        UInt32 size = 0;
        if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size)) return 0;
        AudioObjectID *ids = calloc(1, size);
        if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, ids)) { free(ids); return 0; }
        int n = MIN(capacity, (int)(size / sizeof(AudioObjectID)));
        for (int i = 0; i < n; i++) {
            memset(&out[i], 0, sizeof(out[i])); out[i].object = ids[i];
            address.mSelector = kAudioProcessPropertyPID; UInt32 valueSize = sizeof(pid_t);
            AudioObjectGetPropertyData(ids[i], &address, 0, NULL, &valueSize, &out[i].pid);
            address.mSelector = kAudioProcessPropertyIsRunningOutput; UInt32 running = 0; valueSize = sizeof(running);
            AudioObjectGetPropertyData(ids[i], &address, 0, NULL, &valueSize, &running); out[i].playing = running != 0;
            address.mSelector = kAudioProcessPropertyBundleID; CFStringRef bundle = NULL; valueSize = sizeof(bundle);
            if (!AudioObjectGetPropertyData(ids[i], &address, 0, NULL, &valueSize, &bundle) && bundle) {
                CFStringGetCString(bundle, out[i].bundle, sizeof(out[i].bundle), kCFStringEncodingUTF8); CFRelease(bundle);
            }
        }
        free(ids); return n;
    }
    return 0;
}
typedef struct {
    AudioObjectID tap, device;
    AudioDeviceIOProcID proc;
    _Atomic float gain;
    float current;
} Mixer;
static OSStatus render(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    Mixer *m = context;
    float target = atomic_load_explicit(&m->gain, memory_order_relaxed);
    // The aggregate's physical output precedes its tap input; choose matching stereo tap buffers.
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
        AudioBuffer *dst = &output->mBuffers[b];
        if (!dst->mData) continue;
        memset(dst->mData, 0, dst->mDataByteSize);
        if (!input->mNumberBuffers) continue;
        UInt32 inputOffset = input->mNumberBuffers > output->mNumberBuffers ? input->mNumberBuffers - output->mNumberBuffers : 0;
        const AudioBuffer *src = &input->mBuffers[MIN(inputOffset + b, input->mNumberBuffers-1)];
        if (!src->mData) continue;
        UInt32 samples = MIN(src->mDataByteSize, dst->mDataByteSize) / sizeof(float);
        float *d = dst->mData; const float *s = src->mData;
        for (UInt32 j = 0; j < samples; j++) {
            float gain = m->current + (target - m->current) * MIN(1.0f, (float)j / 384.0f);
            d[j] = s[j] * gain;
        }
    }
    m->current = target; return noErr;
}
MMMixer mm_mixer_create(const uint32_t *objects, int count, float gain, int *error) {
    if (@available(macOS 14.2, *)) {
        Mixer *m = calloc(1, sizeof(Mixer)); atomic_init(&m->gain, gain); m->current = gain;
        NSString *outputUID = nil;
        NSMutableArray *processes = nil;
        CATapDescription *desc = nil;
        NSDictionary *aggregate = nil;
        AudioObjectPropertyAddress a = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, 0};
        AudioObjectID output = 0; UInt32 size = sizeof(output);
        OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &output);
        if (status) goto fail;
        a.mSelector = kAudioDevicePropertyDeviceUID; CFStringRef uid = NULL; size = sizeof(uid);
        status = AudioObjectGetPropertyData(output, &a, 0, NULL, &size, &uid);
        if (status || !uid) goto fail;
        outputUID = CFBridgingRelease(uid);
        processes = [NSMutableArray array];
        for (int i = 0; i < count; i++) [processes addObject:@(objects[i])];
        desc = [[CATapDescription alloc] initWithProcesses:processes andDeviceUID:outputUID withStream:0];
        desc.name = @"Mac Monitor app mixer"; desc.privateTap = YES; desc.muteBehavior = CATapMutedWhenTapped;
        status = AudioHardwareCreateProcessTap(desc, &m->tap); if (status) goto fail;
        aggregate = @{
            @kAudioAggregateDeviceNameKey: @"Mac Monitor Private Mixer",
            @kAudioAggregateDeviceUIDKey: [NSUUID UUID].UUIDString,
            @kAudioAggregateDeviceIsPrivateKey: @YES,
            @kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            @kAudioAggregateDeviceSubDeviceListKey: @[@{@kAudioSubDeviceUIDKey: outputUID}],
            @kAudioAggregateDeviceTapListKey: @[@{@kAudioSubTapUIDKey: desc.UUID.UUIDString, @kAudioSubTapDriftCompensationKey: @YES}],
            @kAudioAggregateDeviceTapAutoStartKey: @YES
        };
        status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)aggregate, &m->device); if (status) goto fail;
        status = AudioDeviceCreateIOProcID(m->device, render, m, &m->proc); if (status) goto fail;
        status = AudioDeviceStart(m->device, m->proc); if (status) goto fail;
        *error = 0; return m;
    fail:
        *error = status; mm_mixer_destroy(m); return NULL;
    }
    *error = -1; return NULL;
}
void mm_mixer_gain(MMMixer mixer, float gain) {
    if (mixer) atomic_store_explicit(&((Mixer *)mixer)->gain, fmaxf(0, fminf(1, gain)), memory_order_relaxed);
}
void mm_mixer_destroy(MMMixer mixer) {
    if (!mixer) return;
    Mixer *m = mixer;
    if (m->proc) { AudioDeviceStop(m->device, m->proc); AudioDeviceDestroyIOProcID(m->device, m->proc); }
    if (m->device) AudioHardwareDestroyAggregateDevice(m->device);
    if (@available(macOS 14.2, *)) { if (m->tap) AudioHardwareDestroyProcessTap(m->tap); }
    free(m);
}
