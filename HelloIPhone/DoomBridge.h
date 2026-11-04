#ifndef SHADERLAB_DOOMBRIDGE_H
#define SHADERLAB_DOOMBRIDGE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Native doomgeneric framebuffer and keyboard bridge (GPL-2.0 compatible).
int doom_bridge_extract_shareware_zip(const char *zip_path, const char *wad_path);
int doom_bridge_start(const char *wad_path);
int doom_bridge_status(void);
int doom_bridge_copy(uint32_t *destination, int maximum_pixels);
void doom_bridge_key(int code, int pressed);
void doom_bridge_pause(int paused);
#ifdef __cplusplus
}
#endif
#endif
