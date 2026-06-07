const std = @import("std");
const assert = std.debug.assert;
const fatal = std.process.fatal;
const log = std.log.scoped(.default);

const rm0 = @import("rm0");

pub fn main() !void {
    const stdout_f = std.fs.File.stdout();
    var stdout_buf: [256]u8 = undefined;
    var stdout_w = stdout_f.writer(&stdout_buf);
    const stdout = &stdout_w.interface;
    defer stdout.flush() catch unreachable;
    var allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = allocator.deinit();
    const gpa = allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);
    if (args.len < 2) fatal("Missing arguments\n{s}", .{help});
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(help);
            return;
        }
    }
    const cwd = std.fs.cwd();
    var ctx: rm0.Context = try .init(gpa);
    defer ctx.deinit(gpa);
    for (args[1..]) |path| try rm0.erase(gpa, cwd, std.mem.trimEnd(u8, path, "\\/"), &ctx);
}

const help =
    \\ rm0 [-h | --help] [...{path}]
    \\
    \\ Securely erase files and directories by overwriting contents
    \\ with random data before deletion.
    \\
    \\ Arguments:
    \\   {path}         : one or more files or directories to erase
    \\   -h, --help     : display this help
    \\
    \\ Notes:
    \\   Directories are erased recursively.
    \\   Symlinks are removed without following them.
    \\   On SSDs, overwriting does not guarantee data erasure due to
    \\   wear-leveling. Use full disk encryption for stronger guarantees.
    \\  
;
