#include "test_harness.h"

#include "core1_cmd.h"

int main(void)
{
    TEST_CHECK(!core1_should_abort(false, false));
    TEST_CHECK(core1_should_abort(true, false));
    TEST_CHECK(core1_should_abort(false, true));
    TEST_CHECK(core1_should_abort(true, true));

    TEST_CHECK_EQ_U32(CORE1_CMD_START, 1u);
    TEST_CHECK_EQ_U32(CORE1_CMD_STOP, 2u);
    TEST_CHECK(CORE1_CMD_START != CORE1_CMD_STOP);

    return test_finish("core1_cmd");
}
