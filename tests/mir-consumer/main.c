#include <mir.h>
#include <mir-gen.h>

#include <assert.h>
#include <stdint.h>

typedef int64_t (*add_fn)(int64_t, int64_t);

int main(void) {
    static const char program[] =
        "m: module\n"
        "    export add\n"
        "add: func i64, i64:a, i64:b\n"
        "    local i64:r\n"
        "    add r, a, b\n"
        "    ret r\n"
        "    endfunc\n"
        "    endmodule\n";

    MIR_context_t ctx = MIR_init();
    MIR_item_t item;
    MIR_module_t module;
    add_fn add;

    assert(ctx != NULL);
    MIR_scan_string(ctx, program);

    module = DLIST_HEAD(MIR_module_t, *MIR_get_module_list(ctx));
    assert(module != NULL);
    MIR_load_module(ctx, module);

    item = MIR_get_global_item(ctx, "add");
    assert(item != NULL);

    MIR_gen_init(ctx);
    MIR_gen_set_optimize_level(ctx, 0u);
    MIR_link(ctx, MIR_set_gen_interface, NULL);

    add = (add_fn)MIR_gen(ctx, item);
    assert(add != NULL);
    assert(add(INT64_C(20), INT64_C(22)) == INT64_C(42));

    MIR_gen_finish(ctx);
    MIR_finish(ctx);
    return 0;
}
