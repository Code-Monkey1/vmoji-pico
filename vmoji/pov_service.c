#include "pov_service.h"

#include "volumes_builtin.h"

#include <string.h>

/* Off-stack bake scratch: VolumeScanlist is ~3KB; Pico default stack is often 2KB. */
static VolumeScanlist g_bake_scratch;

static void bake_active_content(PovService *svc)
{
    VolumeFrame *frame = volume_inactive(&svc->volume);
    volumes_builtin_draw(svc->volume_id, frame);
    volume_codec_bake(frame, &g_bake_scratch);

    /* Never overwrite the slot core1 may still be scanning. */
    uint8_t slot;
    if (svc->scan_busy) {
        slot = (uint8_t)(svc->busy_slot ^ 1u);
    } else {
        slot = (uint8_t)(svc->display_list ^ 1u);
    }

    svc->plat->copy(&svc->lists[slot], &g_bake_scratch, sizeof(g_bake_scratch));
    volume_flip(&svc->volume);
    svc->display_list = slot;
    svc->rebake_needed = false;
}

static void stop_display(PovService *svc)
{
    svc->core_stop = true;
    svc->plat->signal_stop();
    svc->plat->blank();
    svc->display_active = false;
}

void pov_service_init(PovService *svc, const PovPlatform *plat)
{
    memset(svc, 0, sizeof(*svc));
    svc->plat = plat;
    volume_init(&svc->volume);
    svc->display_list = 0;
    svc->busy_slot = 0;
    svc->scan_busy = false;
    svc->rebake_needed = true;
    svc->display_active = false;
    svc->core_stop = true;
    svc->mode = APP_MODE_STATIC;
    svc->volume_id = 1;
    bake_active_content(svc);
}

void pov_service_set_mode(PovService *svc, AppMode mode)
{
    if (mode == svc->mode) {
        return;
    }
    svc->mode = mode;
    svc->plat->sync_reset();

    if (mode == APP_MODE_STATIC) {
        stop_display(svc);
        svc->plat->sync_set_sim(false);
    } else if (mode == APP_MODE_SIM) {
        svc->core_stop = false;
        svc->plat->sync_set_sim(true);
    } else {
        svc->core_stop = false;
        svc->plat->sync_set_sim(false);
    }
    svc->rebake_needed = true;
}

AppMode pov_service_mode(const PovService *svc)
{
    return svc->mode;
}

void pov_service_set_volume(PovService *svc, int volume_id)
{
    if (volume_id < 0 || volume_id >= BUILTIN_VOLUME_COUNT) {
        return;
    }
    svc->volume_id = volume_id;
    svc->rebake_needed = true;
}

int pov_service_volume_id(const PovService *svc)
{
    return svc->volume_id;
}

void pov_service_request_rebake(PovService *svc)
{
    svc->rebake_needed = true;
}

void pov_service_release_scan(PovService *svc)
{
    svc->scan_busy = false;
}

void pov_service_service(PovService *svc)
{
    if (svc->mode == APP_MODE_STATIC) {
        return;
    }

    if (svc->mode == APP_MODE_SIM) {
        svc->plat->sync_service();
    }

    if (svc->rebake_needed) {
        bake_active_content(svc);
    }

    /* IR timeout: must blank even when no new edge arrives. */
    if (svc->mode == APP_MODE_POV && svc->plat->sync_take_lost &&
        svc->plat->sync_take_lost()) {
        stop_display(svc);
        return;
    }

    RotationSnapshot snap;
    if (!svc->plat->sync_take_rev(&snap)) {
        return;
    }
    svc->last_rot = snap;

    svc->core_stop = false;
    svc->display_active = true;
    svc->busy_slot = svc->display_list;
    svc->scan_busy = true;
    svc->plat->signal_start(snap.period_us, &svc->lists[svc->display_list]);
    svc->plat->note_scan();
}

RotationSnapshot pov_service_rotation(const PovService *svc)
{
    if (svc->last_rot.rev_count) {
        return svc->last_rot;
    }
    return svc->plat->sync_snapshot();
}

bool pov_service_display_active(const PovService *svc)
{
    return svc->display_active;
}

uint8_t pov_service_display_list(const PovService *svc)
{
    return svc->display_list;
}

uint8_t pov_service_busy_slot(const PovService *svc)
{
    return svc->busy_slot;
}

bool pov_service_scan_busy(const PovService *svc)
{
    return svc->scan_busy;
}

const VolumeScanlist *pov_service_list(const PovService *svc, uint8_t index)
{
    if (index > 1u) {
        return NULL;
    }
    return &svc->lists[index];
}
