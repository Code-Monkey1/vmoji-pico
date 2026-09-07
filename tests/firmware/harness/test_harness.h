#ifndef VMOJI_TEST_HARNESS_H
#define VMOJI_TEST_HARNESS_H

#include <stdio.h>
#include <stdlib.h>

static int g_test_failures;
static int g_test_checks;

#define TEST_CHECK(cond)                                                       \
    do {                                                                       \
        g_test_checks++;                                                       \
        if (!(cond)) {                                                         \
            g_test_failures++;                                                 \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);   \
        }                                                                      \
    } while (0)

#define TEST_CHECK_EQ_U32(a, b)                                                \
    do {                                                                       \
        uint32_t _a = (uint32_t)(a);                                           \
        uint32_t _b = (uint32_t)(b);                                           \
        g_test_checks++;                                                       \
        if (_a != _b) {                                                        \
            g_test_failures++;                                                 \
            fprintf(stderr, "FAIL %s:%d: %s (%u) != %s (%u)\n", __FILE__,     \
                    __LINE__, #a, _a, #b, _b);                                 \
        }                                                                      \
    } while (0)

#define TEST_CHECK_EQ_INT(a, b)                                                \
    do {                                                                       \
        int _a = (int)(a);                                                     \
        int _b = (int)(b);                                                     \
        g_test_checks++;                                                       \
        if (_a != _b) {                                                        \
            g_test_failures++;                                                 \
            fprintf(stderr, "FAIL %s:%d: %s (%d) != %s (%d)\n", __FILE__,     \
                    __LINE__, #a, _a, #b, _b);                                 \
        }                                                                      \
    } while (0)

static inline int test_finish(const char *suite)
{
    if (g_test_failures == 0) {
        printf("OK %s (%d checks)\n", suite, g_test_checks);
        return 0;
    }
    printf("FAILED %s (%d/%d checks failed)\n", suite, g_test_failures,
           g_test_checks);
    return 1;
}

#endif
