#include "test_harness.h"

#include "ir_debounce.h"

int main(void)
{
    TEST_CHECK(ir_accept_edge(0, 1000, IR_REFRACTORY_US));
    TEST_CHECK(!ir_accept_edge(1000, 1100, IR_REFRACTORY_US)); /* 100 µs */
    TEST_CHECK(!ir_accept_edge(1000, 1499, IR_REFRACTORY_US));
    TEST_CHECK(ir_accept_edge(1000, 1500, IR_REFRACTORY_US));
    TEST_CHECK(ir_accept_edge(1000, 2000, IR_REFRACTORY_US));

    return test_finish("ir_debounce");
}
