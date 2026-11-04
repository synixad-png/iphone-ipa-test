// Native iOS sound backend for DoomGeneric. GPL-2.0-or-later.
// Original PCM SFX from the user's IWAD, no substitute/generated sound effects.
// AudioQueue stereo 44.1 kHz, eight channels, volume, stereo separation, linear resampling.
#include <AudioToolbox/AudioToolbox.h>
#include <pthread.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "doomtype.h"
#include "i_sound.h"
#include "w_wad.h"
#include "z_zone.h"

#define DOOM_AUDIO_RATE 44100.0
#define DOOM_AUDIO_CHANNELS 8
#define DOOM_AUDIO_BUFFER_FRAMES 1024
#define DOOM_AUDIO_QUEUE_BUFFERS 4

typedef struct {
    uint8_t *samples;
    uint32_t length;
    uint32_t sampleRate;
} DoomSample;

typedef struct {
    const DoomSample *sample;
    double position;
    double advance;
    float left;
    float right;
} DoomVoice;

static pthread_mutex_t soundLock = PTHREAD_MUTEX_INITIALIZER;
static DoomVoice voices[DOOM_AUDIO_CHANNELS];
static AudioQueueRef audioQueue = NULL;
static AudioQueueBufferRef queueBuffers[DOOM_AUDIO_QUEUE_BUFFERS];
static int audioStarted = 0;
static int audioPaused = 0;
static int useSfxPrefix = 1;
static float userVolume = 0.85f;
static unsigned int callbackCount = 0;
static unsigned int playedSoundCount = 0;
// Legacy Doom sound configuration symbols; iOS uses built-in linear resampling.
int use_libsamplerate = 0;
float libsamplerate_scale = 1.f;

static float limited(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static void mixFrames(int16_t *output, int frames) {
    for (int frame = 0; frame < frames; ++frame) {
        float left = 0.f, right = 0.f;
        for (int voiceIndex = 0; voiceIndex < DOOM_AUDIO_CHANNELS; ++voiceIndex) {
            DoomVoice *voice = &voices[voiceIndex];
            const DoomSample *sample = voice->sample;
            if (!sample || voice->position >= (double)sample->length) {
                voice->sample = NULL;
                continue;
            }
            unsigned int index = (unsigned int)voice->position;
            unsigned int indexNext = index + 1 < sample->length ? index + 1 : index;
            float fraction = (float)(voice->position - (double)index);
            float a = (float)sample->samples[index] - 128.f;
            float b = (float)sample->samples[indexNext] - 128.f;
            float value = (a + fraction*(b-a)) * 256.f;
            left += value * voice->left;
            right += value * voice->right;
            voice->position += voice->advance;
        }
        // 0.7 gain prevents harsh clipping when several original Doom sounds overlap.
        output[2*frame]   = (int16_t)limited(left  * userVolume * 0.7f, -32768.f, 32767.f);
        output[2*frame+1] = (int16_t)limited(right * userVolume * 0.7f, -32768.f, 32767.f);
    }
}

static void audioCallback(void *userData, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    (void)userData;
    int16_t *dest = (int16_t *)buffer->mAudioData;
    pthread_mutex_lock(&soundLock);
    if (!audioPaused && audioStarted) {
        mixFrames(dest, DOOM_AUDIO_BUFFER_FRAMES);
    } else {
        memset(dest, 0, DOOM_AUDIO_BUFFER_FRAMES * 4);
    }
    callbackCount++;
    pthread_mutex_unlock(&soundLock);
    buffer->mAudioDataByteSize = DOOM_AUDIO_BUFFER_FRAMES * 4;
    AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
}

static boolean iosSoundInit(boolean prefix) {
    useSfxPrefix = prefix;
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = DOOM_AUDIO_RATE;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    format.mBytesPerPacket = 4;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 4;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 16;

    OSStatus error = AudioQueueNewOutput(&format, audioCallback, NULL, NULL, NULL, 0, &audioQueue);
    if (error != noErr || !audioQueue) {
        fprintf(stderr, "DOOM iOS audio: AudioQueueNewOutput failed (%d)\n", (int)error);
        return false;
    }
    pthread_mutex_lock(&soundLock);
    memset(voices, 0, sizeof(voices));
    audioStarted = 1;
    audioPaused = 0;
    pthread_mutex_unlock(&soundLock);
    for (int i=0; i<DOOM_AUDIO_QUEUE_BUFFERS; ++i) {
        error = AudioQueueAllocateBuffer(audioQueue, DOOM_AUDIO_BUFFER_FRAMES*4, &queueBuffers[i]);
        if (error != noErr) break;
        memset(queueBuffers[i]->mAudioData, 0, DOOM_AUDIO_BUFFER_FRAMES*4);
        queueBuffers[i]->mAudioDataByteSize = DOOM_AUDIO_BUFFER_FRAMES*4;
        error = AudioQueueEnqueueBuffer(audioQueue, queueBuffers[i], 0, NULL);
        if (error != noErr) break;
    }
    if (error == noErr) error = AudioQueueStart(audioQueue, NULL);
    if (error != noErr) {
        fprintf(stderr, "DOOM iOS audio: AudioQueueStart failed (%d)\n", (int)error);
        pthread_mutex_lock(&soundLock);
        audioStarted = 0;
        pthread_mutex_unlock(&soundLock);
        AudioQueueDispose(audioQueue, true);
        audioQueue = NULL;
        return false;
    }
    return true;
}

static void iosSoundShutdown(void) {
    pthread_mutex_lock(&soundLock);
    audioStarted = 0;
    memset(voices, 0, sizeof(voices));
    pthread_mutex_unlock(&soundLock);
    if (audioQueue) {
        AudioQueueStop(audioQueue, true);
        AudioQueueDispose(audioQueue, true);
        audioQueue = NULL;
    }
}

static int iosSfxLump(sfxinfo_t *info) {
    if (!info) return -1;
    if (info->link) info = info->link;
    char name[9] = {0};
    if (useSfxPrefix)
        snprintf(name, sizeof(name), "ds%.6s", info->name);
    else
        snprintf(name, sizeof(name), "%.8s", info->name);
    return W_CheckNumForName(name);
}

static DoomSample *loadSample(sfxinfo_t *info) {
    if (!info) return NULL;
    if (info->link) info = info->link;
    if (info->driver_data) return (DoomSample *)info->driver_data;
    int lump = info->lumpnum;
    if (lump < 0) lump = iosSfxLump(info);
    if (lump < 0) return NULL;
    int total = W_LumpLength((unsigned int)lump);
    if (total < 24 || total > 1024*1024) return NULL;
    uint8_t *raw = (uint8_t *)W_CacheLumpNum(lump, PU_STATIC);
    if (!raw || raw[0] != 3 || raw[1] != 0) {
        if (raw) W_ReleaseLumpNum(lump);
        return NULL;
    }
    uint32_t rate = (uint32_t)raw[2] | ((uint32_t)raw[3] << 8);
    uint32_t count = (uint32_t)raw[4] | ((uint32_t)raw[5] << 8)
                   | ((uint32_t)raw[6] << 16) | ((uint32_t)raw[7] << 24);
    if (rate < 4000 || rate > 48000 || count > (uint32_t)(total-8) || count < 8) {
        W_ReleaseLumpNum(lump);
        return NULL;
    }
    DoomSample *copy = calloc(1, sizeof(DoomSample));
    if (copy) {
        copy->samples = malloc(count);
        if (!copy->samples) { free(copy); copy=NULL; }
        else {
            memcpy(copy->samples, raw+8, count);
            copy->length = count;
            copy->sampleRate = rate;
            info->driver_data = copy;
            info->lumpnum = lump;
        }
    }
    W_ReleaseLumpNum(lump);
    return copy;
}

static void iosSoundUpdate(void) {}

static void iosSoundParams(int channel, int volume, int separation) {
    if (channel < 0 || channel >= DOOM_AUDIO_CHANNELS) return;
    float v = limited((float)volume / 127.f, 0.f, 1.f);
    float p = limited((float)separation / 254.f, 0.f, 1.f);
    pthread_mutex_lock(&soundLock);
    voices[channel].left  = v * (1.f-p);
    voices[channel].right = v * p;
    pthread_mutex_unlock(&soundLock);
}

static int iosSoundStart(sfxinfo_t *sfx, int channel, int vol, int sep) {
    if (!audioStarted || channel < 0 || channel >= DOOM_AUDIO_CHANNELS) return -1;
    DoomSample *sample = loadSample(sfx);
    if (!sample) return -1;
    float v = limited((float)vol/127.f,0.f,1.f);
    float p = limited((float)sep/254.f,0.f,1.f);
    pthread_mutex_lock(&soundLock);
    voices[channel] = (DoomVoice){
        .sample = sample,
        .position = 0,
        .advance = (double)sample->sampleRate / DOOM_AUDIO_RATE,
        .left = v*(1.f-p),
        .right = v*p,
    };
    playedSoundCount++;
    pthread_mutex_unlock(&soundLock);
    return channel;
}

static void iosSoundStop(int channel) {
    if (channel < 0 || channel >= DOOM_AUDIO_CHANNELS) return;
    pthread_mutex_lock(&soundLock);
    voices[channel].sample = NULL;
    pthread_mutex_unlock(&soundLock);
}

static boolean iosSoundPlaying(int channel) {
    if (channel < 0 || channel >= DOOM_AUDIO_CHANNELS) return false;
    pthread_mutex_lock(&soundLock);
    boolean result = voices[channel].sample != NULL;
    pthread_mutex_unlock(&soundLock);
    return result;
}

static void iosPrecache(sfxinfo_t *sounds, int count) {
    (void)sounds;
    (void)count;
    // Samples load on the Doom engine thread at first use (never in audio callback).
}
static snddevice_t supportedDevices[] = { SNDDEVICE_SB, SNDDEVICE_PAS, SNDDEVICE_GUS };

sound_module_t DG_sound_module = {
    supportedDevices,
    sizeof(supportedDevices)/sizeof(supportedDevices[0]),
    iosSoundInit,
    iosSoundShutdown,
    iosSfxLump,
    iosSoundUpdate,
    iosSoundParams,
    iosSoundStart,
    iosSoundStop,
    iosSoundPlaying,
    iosPrecache
};
// Doom music stays explicitly disabled via -nomusic until original MUS playback is integrated.
// The module symbol is required by doomgeneric's optional FEATURE_SOUND linkage.
music_module_t DG_music_module = {0};

void doom_audio_set_paused(int value) {
    pthread_mutex_lock(&soundLock);
    audioPaused = value != 0;
    pthread_mutex_unlock(&soundLock);
}
void doom_audio_set_volume(float value) {
    pthread_mutex_lock(&soundLock);
    userVolume = limited(value, 0.f, 1.f);
    pthread_mutex_unlock(&soundLock);
}
int doom_audio_is_active(void) {
    pthread_mutex_lock(&soundLock);
    int active = audioStarted;
    pthread_mutex_unlock(&soundLock);
    return active;
}
unsigned int doom_audio_played_count(void) {
    pthread_mutex_lock(&soundLock);
    unsigned int count = playedSoundCount;
    pthread_mutex_unlock(&soundLock);
    return count;
}
unsigned int doom_audio_callback_count(void) {
    pthread_mutex_lock(&soundLock);
    unsigned int count = callbackCount;
    pthread_mutex_unlock(&soundLock);
    return count;
}
// Deterministic backend test of Doom's genuine 8-bit mono sample path and stereo panning.
int doom_audio_selftest(void) {
    uint8_t pcm[4] = {128, 255, 0, 128};
    DoomSample sample = {pcm,4,11025};
    int16_t out[8] = {0};
    pthread_mutex_lock(&soundLock);
    DoomVoice saved[DOOM_AUDIO_CHANNELS];
    memcpy(saved, voices, sizeof(saved));
    float savedVolume = userVolume;
    for (int i=1; i<DOOM_AUDIO_CHANNELS; ++i) voices[i].sample = NULL;
    voices[0] = (DoomVoice){.sample=&sample,.position=0,.advance=1.0,.left=1.0,.right=0.0};
    userVolume=1.0f;
    mixFrames(out,4);
    memcpy(voices, saved, sizeof(saved));
    userVolume=savedVolume;
    pthread_mutex_unlock(&soundLock);
    return out[0]==0 && out[1]==0 && out[2]>0 && out[3]==0 && out[4]<0 && out[5]==0;
}
