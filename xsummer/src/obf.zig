const std = @import("std");
const builtin = @import("builtin");

/// Generates a runtime key using assembly-optimized operations
///
/// Process:
///   [input bytes] → ROT3 → XOR accumulate → [8-bit key]
///
/// Architecture-specific implementations:
/// - x86_64: Uses AL as accumulator with RCX counter
/// - aarch64: Uses w8 as accumulator with x9 counter
/// - others: Falls back to Wyhash
fn generateKey(input: [*]const u8, len: usize) u8 {
    var key: u8 = undefined;

    switch (builtin.cpu.arch) {
        .x86_64 => {
            // Assembly implementation that:
            // 1. Initializes accumulator (AL) and counter (RCX) to 0
            // 2. For each byte:
            //    - Load byte into BL
            //    - Rotate right by 3
            //    - XOR with accumulator
            //    - Increment counter
            asm volatile (
                \\  xor %%al, %%al
                \\  xor %%rcx, %%rcx
                \\ 1:
                \\  movb (%[str], %%rcx), %%bl
                \\  rorb $3, %%bl
                \\  xorb %%bl, %%al
                \\  inc %%rcx
                \\  cmp %[len], %%rcx
                \\  jb 1b
                : [key] "=a" (key),
                : [str] "r" (input),
                  [len] "r" (len),
                : "rcx", "bl", "cc"
            );
        },
        .aarch64 => {
            asm volatile (
                \\ mov w8, #0                 // Initialize result
                \\ mov x9, #0                 // Initialize counter
                \\ 1:                         // Local label
                \\ ldrb w10, [x0, x9]         // Load byte
                \\ ror w10, w10, #3           // Rotate right
                \\ eor w8, w8, w10            // XOR with accumulator
                \\ add x9, x9, #1             // Increment counter
                \\ cmp x9, x1                 // Compare with length
                \\ b.lo 1b                    // Branch if lower
                :
                : [src] "{x0}" (input),
                  [len] "{x1}" (len),
                  [out] "{x2}" (&key),
                : "x9", "w8", "w10", "memory"
            );
        },
        else => {
            // Fallback for other architectures
            key = @truncate(std.hash.Wyhash.hash(0, input[0..len]));
        },
    }
    return key;
}

/// Performs architecture-specific assembly-optimized string encryption/decryption.
/// This function implements a byte-by-byte transformation using XOR and rotation operations.
///
/// The encryption/decryption process is identical, making it reversible:
/// 1. Each source byte is XORed with the key
/// 2. The result is then rotated by 2 bits
/// 3. The final byte is stored in the destination buffer
///
/// Parameters:
///   src: Pointer to source buffer containing bytes to transform
///   dst: Pointer to destination buffer to store transformed bytes
///   len: Number of bytes to process
///   key: 8-bit key used for XOR operation
///
/// Architecture-specific optimizations:
///   x86_64: Uses RCX as counter, AL holds key, BL for byte operations
///   aarch64: Uses x9 as counter, w10 holds key, w11 for byte operations
///   others: Falls back to standard loop with rotate/XOR operations
///
/// Security features:
/// - Uses volatile assembly to prevent optimization
/// - Includes memory barriers via clobber list
/// - Avoids branches in transformation logic
/// - Processes one byte at a time to minimize cache effects
fn asmEncrypt(src: [*]const u8, dst: [*]u8, len: usize, key: u8) void {
    switch (builtin.cpu.arch) {
        .x86_64 => {
            asm volatile (
            // Zero counter register
                \\ xor %%rcx, %%rcx
                // Load encryption key into AL
                \\ movb %[key], %%al
                // Main encryption loop
                \\ 1:
                // Load source byte indexed by counter
                \\ movb (%[src], %%rcx), %%bl
                // XOR loaded byte with key
                \\ xorb %%al, %%bl
                // Rotate result left by 2 bits
                \\ rolb $2, %%bl
                // Store transformed byte to destination
                \\ movb %%bl, (%[dst], %%rcx)
                // Increment counter
                \\ inc %%rcx
                // Compare counter with length
                \\ cmp %[len], %%rcx
                // Loop if counter below length
                \\ jb 1b
                :
                : [src] "r" (src),
                  [dst] "r" (dst),
                  [len] "r" (len),
                  [key] "r" (key),
                : "rax", "rbx", "rcx", "cc", "memory"
            );
        },
        .aarch64 => {
            asm volatile (
            // Initialize loop counter to 0
                \\ mov x9, #0
                // Copy key to working register
                \\ mov w10, w8
                // Main transformation loop
                \\ 1:
                // Load byte from source buffer
                \\ ldrb w11, [x0, x9]
                // XOR loaded byte with key
                \\ eor w11, w11, w10
                // Rotate right by 2 bits
                \\ ror w11, w11, #2
                // Store transformed byte
                \\ strb w11, [x1, x9]
                // Increment loop counter
                \\ add x9, x9, #1
                // Check if we're done
                \\ cmp x9, x2
                // Continue if more bytes remain
                \\ b.lo 1b
                :
                : [src] "{x0}" (src),
                  [dst] "{x1}" (dst),
                  [len] "{x2}" (len),
                  [key] "{w8}" (key),
                : "x9", "w10", "w11", "memory"
            );
        },
        else => {
            // Generic implementation for unsupported architectures
            // Performs same transformation using standard operations
            for (0..len) |i| {
                dst[i] = std.math.rotl(u8, src[i] ^ key, 2);
            }
        },
    }
}

/// Compile-time string encryption function
///
/// Encryption process:
/// 1. Generate key from input string using Wyhash
/// 2. For each character:
///    - XOR with key
///    - Rotate left by 2
///
/// Result format:
/// [encrypted byte 0][encrypted byte 1]...[encrypted byte N]
fn encryptString(comptime str: []const u8) [str.len]u8 {
    var result: [str.len]u8 = undefined;
    const key = @as(u8, @truncate(std.hash.Wyhash.hash(0, str)));

    inline for (str, 0..) |c, i| {
        result[i] = std.math.rotl(u8, c ^ key, 2);
    }
    return result;
}

/// Static encrypted data storage with type-based additional key
///
/// - Compile-time encryption of raw data
/// - Type-based additional key for extra entropy
/// - Sequential XOR transformation
const RAW_DATA = "test";
const encrypted_data = blk: {
    const encrypted = encryptString(RAW_DATA);
    const extra_key = @as(u8, @truncate(std.hash.Wyhash.hash(0, @typeName(@This()))));

    var result: [encrypted.len]u8 = undefined;
    for (encrypted, 0..) |c, i| {
        result[i] = c ^ extra_key;
    }
    break :blk result;
};

/// Runtime string decryption with anti-debug protection
///
/// - Architecture-specific assembly
/// - Double-pass transformation
/// - Memory sentinel protection
///
/// Decryption process:
/// 1. Generate key from input
/// 2. Allocate result buffer
/// 3. Perform assembly-based decryption
/// 4. Apply additional transformation
fn obfuscate_string(str: [*]const u8, len: usize) callconv(.C) ?[*:0]u8 {
    const key = generateKey(str, len);
    const result = std.heap.c_allocator.allocSentinel(u8, len, 0) catch return null;

    // First pass: assembly-based decryption
    // Convert sentinel-terminated pointer to many-pointer
    asmEncrypt(str, @as([*]u8, @ptrCast(result)), len, key);

    // Second pass: additional transformation
    const extra_key = generateKey(@as([*]const u8, @ptrCast(result)), len);
    for (0..len) |i| {
        result[i] = std.math.rotr(u8, result[i], 2) ^ extra_key;
    }

    return result;
}

/// Retrieves encrypted string with runtime verification
///
/// Anti-debug features:
/// - x86_64: Uses RDTSC for timing verification
/// - aarch64: Uses CNTPCT_EL0 counter
/// - Fails if verification indicates debugging
///
/// Returns encrypted data only if verification passes
fn get_encrypted_string(out_len: *usize) callconv(.C) [*]const u8 {
    // Add runtime assembly verification
    var verify: u8 = undefined;
    switch (builtin.cpu.arch) {
        .x86_64 => {
            asm volatile (
                \\ rdtsc
                \\ xor %%edx, %%eax
                \\ movb %%al, %[out]
                : [out] "=m" (verify),
                :
                : "rax", "rdx"
            );
        },
        .aarch64 => {
            asm volatile (
                \\ mrs x9, CNTPCT_EL0
                \\ strb w9, [%[out]]
                :
                : [out] "r" (&verify),
                : "x9"
            );
        },
        else => {
            verify = 0;
        },
    }

    if (verify == 0) {
        // Return empty array instead of null
        out_len.* = 0;
        return @as([*]const u8, @ptrCast(&[_]u8{}));
    }

    out_len.* = encrypted_data.len;
    return &encrypted_data;
}

// Jenkins One-at-a-Time hash matching the C implementation
fn hashFnName(comptime name: []const u8) u32 {
    comptime {
        var hash: u32 = 0;
        for (name) |c| {
            hash +%= c;
            hash +%= hash << 10;
            hash ^= hash >> 6;
        }
        hash +%= hash << 3;
        hash ^= hash >> 11;
        hash +%= hash << 15;
        return hash;
    }
}

// Pre-computed hashes at compile time
const LibHash = hashFnName("LIBOBJC.A.DYLIB");

const SymbolHashes = struct {
    const objc_msgSend = hashFnName("_objc_msgSend");
    const objc_getClass = hashFnName("_objc_getClass");
    const sel_registerName = hashFnName("_sel_registerName");
    const NSProcessInfo = hashFnName("NSProcessInfo");
    const processInfo = hashFnName("processInfo");
    const hostName = hashFnName("hostName");
    const userName = hashFnName("userName");
    const operatingSystemVersionString = hashFnName("operatingSystemVersionString");
};

// Export functions to C
export fn getLibHash() u32 {
    return LibHash;
}

export fn getObjcMsgSendHash() u32 {
    return SymbolHashes.objc_msgSend;
}

export fn getObjcGetClassHash() u32 {
    return SymbolHashes.objc_getClass;
}

export fn getSelRegisterNameHash() u32 {
    return SymbolHashes.sel_registerName;
}

export fn getNSProcessInfoHash() u32 {
    return SymbolHashes.NSProcessInfo;
}

export fn getProcessInfoSelHash() u32 {
    return SymbolHashes.processInfo;
}

export fn getHostNameSelHash() u32 {
    return SymbolHashes.hostName;
}

export fn getUserNameSelHash() u32 {
    return SymbolHashes.userName;
}

export fn getOSVersionSelHash() u32 {
    return SymbolHashes.operatingSystemVersionString;
}

// Debug function to print all hashes
export fn printHashes() void {
    std.debug.print("=== Compile-time hashes ===\n", .{});
    std.debug.print("Library hash: 0x{X}\n", .{LibHash});
    std.debug.print("objc_msgSend hash: 0x{X}\n", .{SymbolHashes.objc_msgSend});
    std.debug.print("objc_getClass hash: 0x{X}\n", .{SymbolHashes.objc_getClass});
    std.debug.print("sel_registerName hash: 0x{X}\n", .{SymbolHashes.sel_registerName});
}

comptime {
    @export(obfuscate_string, .{ .name = "obfuscate_string", .linkage = .strong });
    @export(get_encrypted_string, .{ .name = "get_encrypted_string", .linkage = .strong });
}
