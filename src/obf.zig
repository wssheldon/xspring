const std = @import("std");

// Compile-time encryption
fn encryptString(comptime str: []const u8) [str.len]u8 {
    const hash = std.hash.Wyhash.hash(0, str);
    const key = @as(u8, @truncate(hash));

    var result: [str.len]u8 = undefined;
    inline for (str, 0..) |c, i| {
        result[i] = c ^ key;
    }
    return result;
}

// Static encrypted data
const encrypted_data = encryptString("test");

comptime {
    @export(obfuscate_string, .{ .name = "obfuscate_string" });
}

// The decryption function that will be called at runtime
pub fn obfuscate_string(str: [*]const u8, len: usize) callconv(.C) ?[*:0]u8 {
    const hash = std.hash.Wyhash.hash(0, str[0..len]);
    const key = @as(u8, @truncate(hash));

    const result = std.heap.c_allocator.allocSentinel(u8, len, 0) catch return null;

    for (0..len) |i| {
        result[i] = str[i] ^ key;
    }

    return result;
}

// Return pointer to static encrypted data
export fn get_encrypted_string(out_len: *usize) callconv(.C) [*]const u8 {
    out_len.* = encrypted_data.len;
    return &encrypted_data;
}
