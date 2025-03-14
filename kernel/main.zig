const builtin = @import("builtin");
const limine = @import("limine");
const std = @import("std");
const tty = @import("drivers/tty/tty.zig");
const dbg = @import("drivers/dbg/dbg.zig");
const idt = @import("arch/x64/interrupts/handle.zig");
const pic = @import("drivers/pic/pic.zig");
const pageframe = @import("arch/x64/paging/pageframe_allocator.zig");
const gpt = @import("drivers/storage/gpt.zig");
const sched = @import("proc/sched.zig");
pub export var framebuffer_request: limine.FramebufferRequest = .{};
pub export var base_revision: limine.BaseRevision = .{ .revision = 2 };
pub export fn done() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
const vmm = @import("arch/x64/paging/vmm.zig");
const pf = @import("arch/x64/paging/pageframe.zig");
const pci = @import("drivers/pci.zig");
const alloc = @import("HAL/mem/alloc.zig");
export fn _start() callconv(.C) noreturn {
    if (!base_revision.is_supported()) {
        done();
    }

    // Ensure we got a framebuffer.
    if (framebuffer_request.response) |framebuffer_response| {
        dbg.printf("init framebuffer\n", .{});
        tty.initialise_tty(framebuffer_response);
        dbg.printf("init framebuffer done\n", .{});
    } else {
        dbg.printf("FRAMEBUFFER FAIL\n", .{});
    }
    //vmm.setup();
    switch (builtin.target.cpu.arch) {
        .x86_64 => {
            pageframe.print_mem();
            pageframe.setup();

            tty.printf("pageframe setup\n", .{});
            @import("arch/x64/gdt/gdt.zig").setup_gdt();
            tty.printf("paging setup\n", .{});
        },
        else => std.debug.panic("unsupported arch!!!\n", .{}),
    }

    tty.printf("paging fully set up\n", .{});
    idt.init();
    pic.PIC_remap(0x20, 0x20 + 8);
    //pic.IRQ_clear_mask(1);
    //    pic.clear_mask();
    asm volatile ("sti");

    tty.printf("Interrupts setup\n", .{});
    alloc.init();
    dbg.printf("allocator initialised\n", .{});
    const a: []u8 = alloc.gl_alloc.alloc(u8, 10) catch {
        @panic("allocator tests failed");
    };
    dbg.printf("alloc test: {x}\n", .{@intFromPtr(a.ptr)});
    alloc.gl_alloc.free(a);
    @import("HAL/storage/dtree.zig").init();
    pci.init_devices();
    gpt.load_partitions() orelse @panic("PARTITION TABLE DAMAGED");
    tty.printf("GPT Partitions loaded\n", .{});
    dbg.printf("GPT Partitions loaded\n", .{});
    @import("arch/x64/syscall/init.zig").init();
    dbg.printf("syscalls initialised\n", .{});
    @import("proc/sched.zig").gl_sched.init() catch @panic("Scheduler init failed\n");
    dbg.printf("scheduler initialised\n", .{});
    tty.printf(" _______  _______  _______  _______  _______ \n", .{});
    tty.printf("(  ____ \\(  ___  )/ ___   )(  ___  )(  ____ \\\n", .{});
    tty.printf("| (    \\/| (   ) |\\/   )  || (   ) || (    \\/\n", .{});
    tty.printf("| (__    | |   | |    /   )| |   | || (_____ \n", .{});
    tty.printf("|  __)   | |   | |   /   / | |   | |(_____  )\n", .{});
    tty.printf("| (      | |   | |  /   /  | |   | |      ) |\n", .{});
    tty.printf("| )      | (___) | /   (_/\\| (___) |/\\____) |\n", .{});
    tty.printf("|/       (_______)(_______/(_______)\\_______)\n", .{});
    tty.printf("Boot finished!!!\n", .{});
    dbg.printf("FOZOS init done, going to the userspace!!!\n", .{});
    sched.gl_sched.execve_elf("testapp") catch @panic("EXEC fail");
    @import("drivers/PIT/pit.zig").unmask(); //starts the scheduler
    pic.IRQ_clear_mask(0);
    done();
}
pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    // asm volatile ("cli");
    dbg.printf("FOZOS PANIC: {s}\n", .{message});
    tty.printf("FOZOS PANIC: {s}\n", .{message});

    done();
}
