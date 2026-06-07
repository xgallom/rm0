const std = @import("std");
const assert = std.debug.assert;
const fatal = std.process.fatal;
const log = std.log.scoped(.default);

const Allocator = std.mem.Allocator;

pub const ScramblePass = enum {
    random,
    ff,
    const default: []const ScramblePass = &.{ .random, .ff, .random };
};

pub const Context = struct {
    buf: []u8 = undefined,
    buf_rnd: []u8 = undefined,
    path: std.ArrayList(u8) = .empty,
    path_idx: std.ArrayList(usize) = .empty,

    pub fn init(gpa: Allocator) !Context {
        return .{
            .buf = try gpa.alloc(u8, 4 << 10),
            .buf_rnd = try gpa.alloc(u8, 4 << 10),
        };
    }

    pub fn deinit(self: *Context, gpa: Allocator) void {
        gpa.free(self.buf);
        gpa.free(self.buf_rnd);
        self.path.deinit(gpa);
        self.path_idx.deinit(gpa);
    }

    pub fn reset(self: *Context, gpa: Allocator, path: []const u8) !void {
        self.path.clearRetainingCapacity();
        self.path_idx.clearRetainingCapacity();
        try self.path.appendSlice(gpa, path);
    }

    pub fn getPath(self: *const Context) []const u8 {
        return self.path.items;
    }

    pub fn getRandom(self: *Context, len: usize, comptime pass: ScramblePass) []const u8 {
        assert(len <= self.buf_rnd.len);
        switch (pass) {
            .random => std.crypto.random.bytes(self.buf_rnd[0..len]),
            .ff => @memset(self.buf_rnd[0..len], 0xff),
        }
        return self.buf_rnd[0..len];
    }

    pub fn getBasename(self: *Context) []const u8 {
        const random: *const [16]u8 = @ptrCast(self.getRandom(16, .random));
        const buf = std.fmt.bytesToHex(random.*, .lower);
        @memcpy(self.buf[0..32], &buf);
        return self.buf[0..32];
    }

    pub fn push(self: *Context, gpa: Allocator, path: []const u8) !void {
        try self.path_idx.append(gpa, self.path.items.len);
        try self.path.append(gpa, std.fs.path.sep);
        try self.path.appendSlice(gpa, path);
    }

    pub fn pop(self: *Context) void {
        assert(self.path_idx.items.len > 0);
        self.path.items.len = self.path_idx.pop().?;
    }
};

pub fn erase(gpa: Allocator, dir: std.fs.Dir, sub_path: []const u8, ctx: *Context) !void {
    log.info("Erasing {s}", .{sub_path});
    try ctx.reset(gpa, sub_path);
    const stat = try dir.statFile(sub_path);
    switch (stat.kind) {
        .directory => try eraseDir(gpa, dir, sub_path, ctx),
        .file => try eraseFile(gpa, dir, sub_path, ctx),
        .sym_link,
        .named_pipe,
        .unix_domain_socket,
        .whiteout,
        => |kind| try deleteFile(gpa, dir, sub_path, ctx, kind),
        else => log.warn("Skipping {s} ({})", .{ ctx.getPath(), stat.kind }),
    }
}

pub fn eraseDir(gpa: Allocator, dir: std.fs.Dir, sub_path: []const u8, ctx: *Context) !void {
    {
        var sub_dir = try dir.openDir(sub_path, .{ .access_sub_paths = true, .iterate = true });
        defer sub_dir.close();
        var iter = sub_dir.iterate();
        while (try iter.next()) |entry| {
            try ctx.push(gpa, entry.name);
            defer ctx.pop();
            switch (entry.kind) {
                .directory => try eraseDir(gpa, sub_dir, entry.name, ctx),
                .file => try eraseFile(gpa, sub_dir, entry.name, ctx),
                .sym_link,
                .named_pipe,
                .unix_domain_socket,
                .whiteout,
                => |kind| try deleteFile(gpa, sub_dir, entry.name, ctx, kind),
                else => log.warn("Skipping {s} ({})", .{ ctx.getPath(), entry.kind }),
            }
        }
    }
    const new_sub_path = try rename(gpa, dir, sub_path, ctx);
    defer gpa.free(new_sub_path);
    try dir.deleteDir(new_sub_path);
    log.info("Erased {s} (directory)", .{ctx.getPath()});
}

pub fn eraseFile(gpa: Allocator, dir: std.fs.Dir, sub_path: []const u8, ctx: *Context) !void {
    {
        var file = try dir.openFile(sub_path, .{ .mode = .read_write });
        defer file.close();
        const file_end = try file.getEndPos();
        inline for (ScramblePass.default) |pass| {
            try file.seekTo(0);
            var writer = file.writer(ctx.buf);
            var idx: usize = 0;
            while (idx < file_end) : (idx += ctx.buf_rnd.len) {
                const buf_end = @min(ctx.buf_rnd.len, file_end - idx);
                try writer.interface.writeAll(ctx.getRandom(buf_end, pass));
            }
            try writer.interface.flush();
            try file.sync();
            log.debug("Scrambled {s} ({s})", .{ ctx.getPath(), @tagName(pass) });
        }
        try file.setEndPos(0);
        try file.sync();
        log.debug("Truncated {s}", .{ctx.getPath()});
    }
    try deleteFile(gpa, dir, sub_path, ctx, .file);
}

pub fn deleteFile(gpa: Allocator, dir: std.fs.Dir, sub_path: []const u8, ctx: *Context, kind: std.fs.File.Kind) !void {
    const new_sub_path = try rename(gpa, dir, sub_path, ctx);
    defer gpa.free(new_sub_path);
    try dir.deleteFile(new_sub_path);
    log.info("Erased {s} ({s})", .{ ctx.getPath(), @tagName(kind) });
}

pub fn rename(gpa: Allocator, dir: std.fs.Dir, sub_path: []const u8, ctx: *Context) ![]const u8 {
    const dirname = std.fs.path.dirname(sub_path);
    const basename = ctx.getBasename();
    const new_sub_path = if (dirname) |dn| try std.fs.path.join(gpa, &.{ dn, basename }) else try gpa.dupe(u8, basename);
    try dir.rename(sub_path, new_sub_path);
    log.debug("Renamed {s} -> {s}", .{ ctx.getPath(), basename });
    return new_sub_path;
}
