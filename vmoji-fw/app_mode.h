#ifndef VMOJI_APP_MODE_H
#define VMOJI_APP_MODE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    APP_MODE_STATIC = 0,
    APP_MODE_POV = 1,
    APP_MODE_SIM = 2,
} AppMode;

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_APP_MODE_H
