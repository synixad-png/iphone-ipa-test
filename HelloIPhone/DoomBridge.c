// Doom engine platform adapter. The game logic is provided by GPL-2.0 doomgeneric.
#include "DoomBridge.h"
#include "doomgeneric.h"
#include "d_event.h"
#include "d_main.h"
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <zlib.h>
#include <strings.h>

#define KEY_CAPACITY 128
#define FRAME_PIXELS (DOOMGENERIC_RESX * DOOMGENERIC_RESY)
static pthread_mutex_t state_mutex = PTHREAD_MUTEX_INITIALIZER;
static uint32_t frames[FRAME_PIXELS];
static int has_frame = 0, state = 0, paused = 0;
static unsigned short input_queue[KEY_CAPACITY];
static unsigned int read_index = 0, write_index = 0;
static float pending_mouse_horizontal = 0;
static char wad_filename[4096];
static pthread_t engine_thread;


// Extracts ONLY DOOM1.WAD from an original ZIP archive downloaded by the user.
// Checks central directory lengths, validates CRC, and caps decompression size.
static uint16_t zip16(const unsigned char *p) { return (uint16_t)(p[0] | (p[1]<<8)); }
static uint32_t zip32(const unsigned char *p) {
    return (uint32_t)p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24;
}
int doom_bridge_extract_shareware_zip(const char *zip_path, const char *wad_path) {
    if (!zip_path || !wad_path) return -1;
    FILE *file = fopen(zip_path, "rb");
    if (!file) return -2;
    if (fseek(file,0,SEEK_END) || ftell(file) < 50 || ftell(file) > 25000000) {
        fclose(file); return -3;
    }
    long length = ftell(file);
    rewind(file);
    unsigned char *zip = malloc((size_t)length);
    if (!zip || fread(zip,1,(size_t)length,file)!=(size_t)length) {
        free(zip); fclose(file); return -4;
    }
    fclose(file);
    int result = -5;
    // EOCD may have up to 65535 bytes of comments.
    long eocd = -1;
    for (long pos=length-22; pos>=0 && pos>=length-22-65535; pos--) {
        if (zip32(zip+pos) == 0x06054b50) { eocd=pos; break; }
    }
    if (eocd < 0) goto finish;
    uint32_t entries=zip16(zip+eocd+10), directory=zip32(zip+eocd+16);
    if (entries > 2000 || directory >= (uint32_t)length) goto finish;
    uint32_t at=directory;
    for (uint32_t i=0; i<entries && at+46 <= (uint32_t)length; i++) {
        const unsigned char *header=zip+at;
        if (zip32(header) != 0x02014b50) break;
        uint16_t method=zip16(header+10);
        uint32_t crc=zip32(header+16);
        uint32_t compressed=zip32(header+20), unpacked=zip32(header+24);
        uint16_t nameLength=zip16(header+28), extraLength=zip16(header+30),
                 commentLength=zip16(header+32);
        uint32_t local=zip32(header+42);
        uint64_t next=(uint64_t)at+46+nameLength+extraLength+commentLength;
        if (next > (uint64_t)length) break;
        const char *name=(const char *)(header+46);
        // Filename can include a DOS/ZIP directory prefix.
        int isWad=0;
        if (nameLength>=9) {
            const char *suffix=name+nameLength-9;
            if (strncasecmp(suffix,"DOOM1.WAD",9)==0 &&
                (nameLength==9 || suffix[-1]=='/' || suffix[-1]=='\\')) isWad=1;
        }
        if (isWad && unpacked >= 1000000 && unpacked <= 15000000 &&
            compressed <= 15000000 && local+30 < (uint32_t)length &&
            zip32(zip+local)==0x04034b50) {
            uint64_t dataStart=(uint64_t)local+30+zip16(zip+local+26)+zip16(zip+local+28);
            if (dataStart+compressed > (uint64_t)length) break;
            unsigned char *out=malloc(unpacked);
            if (!out) { result=-6; break; }
            int ok=0;
            if (method==0 && compressed==unpacked) {
                memcpy(out,zip+dataStart,unpacked);
                ok=1;
            } else if (method==8) {
                z_stream stream={0};
                stream.next_in=zip+dataStart;
                stream.avail_in=compressed;
                stream.next_out=out;
                stream.avail_out=unpacked;
                if (inflateInit2(&stream,-MAX_WBITS)==Z_OK) {
                    ok=inflate(&stream,Z_FINISH)==Z_STREAM_END &&
                       stream.total_out==unpacked;
                    inflateEnd(&stream);
                }
            }
            if (ok && memcmp(out,"IWAD",4)==0 &&
                crc32(0L,out,unpacked)==crc) {
                FILE *outFile=fopen(wad_path,"wb");
                if (outFile) {
                    ok=fwrite(out,1,unpacked,outFile)==unpacked;
                    ok=fclose(outFile)==0 && ok;
                    result=ok ? 0 : -8;
                } else result=-7;
            } else result=-9;
            free(out);
            break;
        }
        at=(uint32_t)next;
    }
finish:
    free(zip);
    return result;
}

void DG_Init(void) { }
void DG_DrawFrame(void) {
    pthread_mutex_lock(&state_mutex);
    if (DG_ScreenBuffer) {
        memcpy(frames, DG_ScreenBuffer, sizeof(frames));
        has_frame = 1;
    }
    pthread_mutex_unlock(&state_mutex);
}
void DG_SleepMs(uint32_t ms) { usleep((useconds_t) ms * 1000); }
uint32_t DG_GetTicksMs(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint32_t)(t.tv_sec * 1000ULL + t.tv_nsec / 1000000ULL);
}
int DG_GetKey(int *pressed, unsigned char *key) {
    pthread_mutex_lock(&state_mutex);
    if (read_index == write_index) {
        pthread_mutex_unlock(&state_mutex);
        return 0;
    }
    unsigned short entry = input_queue[read_index % KEY_CAPACITY];
    read_index++;
    pthread_mutex_unlock(&state_mutex);
    *pressed = (entry >> 8) & 1;
    *key = (unsigned char)(entry & 0xff);
    return 1;
}
void DG_SetWindowTitle(const char *title) { (void)title; }

static void *doom_thread(void *ignored) {
    (void)ignored;
    char *args[] = { "doom", "-iwad", wad_filename, "-nomusic", NULL };
    // Doom writes configuration and save games to the writable app Documents directory.
    char working_directory[4096];
    snprintf(working_directory,sizeof(working_directory),"%s",wad_filename);
    char *last_slash=strrchr(working_directory,'/');
    if (last_slash) { *last_slash='\0'; chdir(working_directory); }
    doomgeneric_Create(4, args);
    pthread_mutex_lock(&state_mutex);
    state = 2;
    pthread_mutex_unlock(&state_mutex);
    while (1) {
        pthread_mutex_lock(&state_mutex);
        int should_pause = paused;
        pthread_mutex_unlock(&state_mutex);
        if (should_pause) { usleep(25000); continue; }
        float motion = 0;
        pthread_mutex_lock(&state_mutex);
        motion = pending_mouse_horizontal;
        if (motion >= 1.0f || motion <= -1.0f)
            pending_mouse_horizontal = 0;
        pthread_mutex_unlock(&state_mutex);
        if (motion >= 1.0f || motion <= -1.0f) {
            // Post on the engine thread, never from the UI thread.
            event_t event = { .type = ev_mouse, .data1 = 0,
                              .data2 = (int)motion, .data3 = 0 };
            D_PostEvent(&event);
        }
        doomgeneric_Tick();
    }
    return NULL;
}

int doom_bridge_start(const char *wad_path) {
    if (!wad_path || strlen(wad_path) >= sizeof(wad_filename)) { return -1; }
    pthread_mutex_lock(&state_mutex);
    if (state != 0) {
        int current = state;
        pthread_mutex_unlock(&state_mutex);
        return current;
    }
    strncpy(wad_filename, wad_path, sizeof(wad_filename)-1);
    state = 1;
    pthread_mutex_unlock(&state_mutex);
    if (pthread_create(&engine_thread, NULL, doom_thread, NULL) != 0) {
        pthread_mutex_lock(&state_mutex);
        state = -1;
        pthread_mutex_unlock(&state_mutex);
        return -1;
    }
    pthread_detach(engine_thread);
    return 1;
}
int doom_bridge_status(void) {
    pthread_mutex_lock(&state_mutex);
    int result = state;
    pthread_mutex_unlock(&state_mutex);
    return result;
}
int doom_bridge_copy(uint32_t *destination, int maximum_pixels) {
    if (!destination || maximum_pixels < FRAME_PIXELS) return 0;
    pthread_mutex_lock(&state_mutex);
    int result = has_frame;
    if (result) memcpy(destination, frames, sizeof(frames));
    pthread_mutex_unlock(&state_mutex);
    return result ? FRAME_PIXELS : 0;
}
void doom_bridge_key(int code, int pressed) {
    if (code < 1 || code > 255) return;
    pthread_mutex_lock(&state_mutex);
    if (write_index - read_index >= KEY_CAPACITY)
        read_index++;
    input_queue[write_index % KEY_CAPACITY] = (unsigned short)(((pressed ? 1 : 0) << 8) | code);
    write_index++;
    pthread_mutex_unlock(&state_mutex);
}
void doom_bridge_look(float horizontal_delta) {
    if (!isfinite(horizontal_delta)) return;
    pthread_mutex_lock(&state_mutex);
    pending_mouse_horizontal += horizontal_delta * 3.0f;
    if (pending_mouse_horizontal > 250.0f) pending_mouse_horizontal = 250.0f;
    if (pending_mouse_horizontal < -250.0f) pending_mouse_horizontal = -250.0f;
    pthread_mutex_unlock(&state_mutex);
}
void doom_bridge_pause(int value) {
    pthread_mutex_lock(&state_mutex);
    paused = value != 0;
    pthread_mutex_unlock(&state_mutex);
    doom_audio_set_paused(value);
}
