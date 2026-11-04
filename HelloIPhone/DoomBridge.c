// Doom engine platform adapter. The game logic is provided by GPL-2.0 doomgeneric.
#include "DoomBridge.h"
#include "doomgeneric.h"
#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define KEY_CAPACITY 128
#define FRAME_PIXELS (DOOMGENERIC_RESX * DOOMGENERIC_RESY)
static pthread_mutex_t state_mutex = PTHREAD_MUTEX_INITIALIZER;
static uint32_t frames[FRAME_PIXELS];
static int has_frame = 0, state = 0, paused = 0;
static unsigned short input_queue[KEY_CAPACITY];
static unsigned int read_index = 0, write_index = 0;
static char wad_filename[4096];
static pthread_t engine_thread;

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
    char *args[] = { "doom", "-iwad", wad_filename, "-nomusic", "-nosfx", NULL };
    doomgeneric_Create(5, args);
    pthread_mutex_lock(&state_mutex);
    state = 2;
    pthread_mutex_unlock(&state_mutex);
    while (1) {
        pthread_mutex_lock(&state_mutex);
        int should_pause = paused;
        pthread_mutex_unlock(&state_mutex);
        if (should_pause) { usleep(25000); continue; }
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
void doom_bridge_pause(int value) {
    pthread_mutex_lock(&state_mutex);
    paused = value != 0;
    pthread_mutex_unlock(&state_mutex);
}
