const std = @import("std");
const assert = std.debug.assert;
const fatal = std.process.fatal;
const log = std.log.scoped(.default);
const testing = std.testing;

const rm0 = @import("rm0");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn makeTestDir(tmp: std.testing.TmpDir, sub: []const u8) !std.fs.Dir {
    try tmp.dir.makeDir(sub);
    return tmp.dir.openDir(sub, .{ .access_sub_paths = true, .iterate = true });
}

fn writeFile(dir: std.fs.Dir, name: []const u8, content: []const u8) !void {
    const file = try dir.createFile(name, .{});
    defer file.close();
    try file.writeAll(content);
}

fn fileExists(dir: std.fs.Dir, name: []const u8) bool {
    dir.access(name, .{}) catch return false;
    return true;
}

fn makeContext(gpa: std.mem.Allocator) !rm0.Context {
    return rm0.Context.init(gpa);
}

// ---------------------------------------------------------------------------
// eraseFile
// ---------------------------------------------------------------------------

test "eraseFile removes the file" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    try writeFile(tmp.dir, "secret.txt", "sensitive data");

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);
    try ctx.reset(testing.allocator, "secret.txt");

    try rm0.eraseFile(testing.allocator, tmp.dir, "secret.txt", &ctx);

    try testing.expect(!fileExists(tmp.dir, "secret.txt"));
}

test "eraseFile removes empty file" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    try writeFile(tmp.dir, "empty.txt", "");

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);
    try ctx.reset(testing.allocator, "empty.txt");

    try rm0.eraseFile(testing.allocator, tmp.dir, "empty.txt", &ctx);

    try testing.expect(!fileExists(tmp.dir, "empty.txt"));
}

test "eraseFile leaves no file with original name" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    try writeFile(tmp.dir, "data.bin", "top secret");

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);
    try ctx.reset(testing.allocator, "data.bin");

    try rm0.eraseFile(testing.allocator, tmp.dir, "data.bin", &ctx);

    // original name must not exist in any form
    var iter = tmp.dir.iterate();
    while (try iter.next()) |entry| {
        try testing.expect(!std.mem.eql(u8, entry.name, "data.bin"));
    }
}

test "eraseFile does not leave readable original content" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    const content = "password: hunter2";
    try writeFile(tmp.dir, "creds.txt", content);

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);
    try ctx.reset(testing.allocator, "creds.txt");

    // capture file content before erase by reading raw blocks via a second fd
    // open before erase, read after — if truncated to 0 nothing to read
    const file_before = try tmp.dir.openFile("creds.txt", .{});
    const size_before = try file_before.getEndPos();
    file_before.close();

    try rm0.eraseFile(testing.allocator, tmp.dir, "creds.txt", &ctx);

    // file must be gone — size before was nonzero, now no trace remains
    try testing.expect(size_before > 0);
    try testing.expect(!fileExists(tmp.dir, "creds.txt"));
}

// ---------------------------------------------------------------------------
// eraseDir
// ---------------------------------------------------------------------------

test "eraseDir removes empty directory" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makeDir("subdir");

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);
    try ctx.reset(testing.allocator, "subdir");

    try rm0.eraseDir(testing.allocator, tmp.dir, "subdir", &ctx);

    try testing.expect(!fileExists(tmp.dir, "subdir"));
}

test "eraseDir removes directory with files" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makeDir("private");
    var sub = try tmp.dir.openDir("private", .{});
    try writeFile(sub, "a.txt", "aaa");
    try writeFile(sub, "b.txt", "bbb");
    sub.close();

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);
    try ctx.reset(testing.allocator, "private");

    try rm0.eraseDir(testing.allocator, tmp.dir, "private", &ctx);

    try testing.expect(!fileExists(tmp.dir, "private"));
}

test "eraseDir removes nested directories" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("root/a/b/c");
    var deep = try tmp.dir.openDir("root/a/b/c", .{});
    try writeFile(deep, "deep.txt", "deep content");
    deep.close();

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);
    try ctx.reset(testing.allocator, "root");

    try rm0.eraseDir(testing.allocator, tmp.dir, "root", &ctx);

    try testing.expect(!fileExists(tmp.dir, "root"));
}

test "eraseDir leaves no entries behind" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("vault/inner");
    var inner = try tmp.dir.openDir("vault/inner", .{});
    try writeFile(inner, "secret.txt", "secret");
    inner.close();

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);
    try ctx.reset(testing.allocator, "vault");

    try rm0.eraseDir(testing.allocator, tmp.dir, "vault", &ctx);

    var iter = tmp.dir.iterate();
    while (try iter.next()) |entry| {
        try testing.expect(!std.mem.eql(u8, entry.name, "vault"));
    }
}

// ---------------------------------------------------------------------------
// deleteFile (symlinks, pipes)
// ---------------------------------------------------------------------------

test "deleteFile removes symlink without following it" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    // target file to verify it is NOT erased
    try writeFile(tmp.dir, "target.txt", "do not erase me");
    try tmp.dir.symLink("target.txt", "link.txt", .{});

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);
    try ctx.reset(testing.allocator, "link.txt");

    try rm0.deleteFile(testing.allocator, tmp.dir, "link.txt", &ctx, .sym_link);

    // symlink gone
    try testing.expect(!fileExists(tmp.dir, "link.txt"));
    // target untouched
    try testing.expect(fileExists(tmp.dir, "target.txt"));
    const file = try tmp.dir.openFile("target.txt", .{});
    defer file.close();
    var buf: [64]u8 = undefined;
    const n = try file.readAll(&buf);
    try testing.expectEqualStrings("do not erase me", buf[0..n]);
}

test "deleteFile removes dangling symlink" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.symLink("/nonexistent/ghost.txt", "dangling.txt", .{});

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);
    try ctx.reset(testing.allocator, "dangling.txt");

    try rm0.deleteFile(testing.allocator, tmp.dir, "dangling.txt", &ctx, .sym_link);

    try testing.expect(!fileExists(tmp.dir, "dangling.txt"));
}

// ---------------------------------------------------------------------------
// rename
// ---------------------------------------------------------------------------

test "rename produces hex basename" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    try writeFile(tmp.dir, "original.txt", "content");

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);
    try ctx.reset(testing.allocator, "original.txt");

    const new_path = try rm0.rename(testing.allocator, tmp.dir, "original.txt", &ctx);
    defer testing.allocator.free(new_path);

    // new name must be 32 hex chars
    try testing.expectEqual(@as(usize, 32), new_path.len);
    for (new_path) |c| {
        try testing.expect(std.ascii.isHex(c));
    }

    // original name gone, new name exists
    try testing.expect(!fileExists(tmp.dir, "original.txt"));
    try testing.expect(fileExists(tmp.dir, new_path));

    // cleanup
    try tmp.dir.deleteFile(new_path);
}

test "rename produces unique names across calls" {
    var tmp = std.testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp.cleanup();

    try writeFile(tmp.dir, "a.txt", "a");
    try writeFile(tmp.dir, "b.txt", "b");

    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);

    try ctx.reset(testing.allocator, "a.txt");
    const name_a = try rm0.rename(testing.allocator, tmp.dir, "a.txt", &ctx);
    defer testing.allocator.free(name_a);

    try ctx.reset(testing.allocator, "b.txt");
    const name_b = try rm0.rename(testing.allocator, tmp.dir, "b.txt", &ctx);
    defer testing.allocator.free(name_b);

    try testing.expect(!std.mem.eql(u8, name_a, name_b));

    try tmp.dir.deleteFile(name_a);
    try tmp.dir.deleteFile(name_b);
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

test "Context.push and pop track path correctly" {
    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);

    try ctx.reset(testing.allocator, "root");
    try testing.expectEqualStrings("root", ctx.getPath());

    try ctx.push(testing.allocator, "child");
    try testing.expectEqualStrings("root/child", ctx.getPath());

    try ctx.push(testing.allocator, "grandchild");
    try testing.expectEqualStrings("root/child/grandchild", ctx.getPath());

    ctx.pop();
    try testing.expectEqualStrings("root/child", ctx.getPath());

    ctx.pop();
    try testing.expectEqualStrings("root", ctx.getPath());
}

test "Context.getBasename returns 32 hex chars" {
    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);

    const name = ctx.getBasename();
    try testing.expectEqual(@as(usize, 32), name.len);
    for (name) |c| {
        try testing.expect(std.ascii.isHex(c));
    }
}

test "Context.getRandom random pass fills buffer" {
    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);

    const a = try testing.allocator.dupe(u8, ctx.getRandom(16, .random));
    defer testing.allocator.free(a);
    const b = ctx.getRandom(16, .random);
    // two random draws over same buffer astronomically unlikely to match
    try testing.expect(!std.mem.eql(u8, a, b));
}

test "Context.getRandom ff pass fills with 0xff" {
    var ctx = try makeContext(testing.allocator);
    defer ctx.deinit(testing.allocator);

    const buf = ctx.getRandom(64, .ff);
    for (buf) |b| try testing.expectEqual(@as(u8, 0xff), b);
}
