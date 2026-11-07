#include "ir_debounce.h"

bool ir_accept_edge(uint64_t last_accepted_us, uint64_t now_us,
                    uint32_t refractory_us)
{
    if (last_accepted_us == 0) {
        return true;
    }
    if (now_us < last_accepted_us) {
        return true;  /* clock wrap: accept */
    }
    return (now_us - last_accepted_us) >= (uint64_t)refractory_us;
}
