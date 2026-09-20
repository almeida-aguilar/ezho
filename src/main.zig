const std = @import("std");

fn isHexDigit(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

fn isOctalDigit(c: u8) bool {
    return c >= '0' and c <= '7';
}

fn unescape(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;

    while (i < input.len) {
        if (input[i] == '\\' and i + 1 < input.len) {
            switch (input[i + 1]) {
                'n' => {
                    try result.append(allocator, '\n');
                    i += 2;
                },
                't' => {
                    try result.append(allocator, '\t');
                    i += 2;
                },
                'r' => {
                    try result.append(allocator, '\r');
                    i += 2;
                },
                '\\' => {
                    try result.append(allocator, '\\');
                    i += 2;
                },
                'a' => {
                    try result.append(allocator, 0x07);
                    i += 2;
                },
                'b' => {
                    try result.append(allocator, 0x08);
                    i += 2;
                },
                'f' => {
                    try result.append(allocator, 0x0C);
                    i += 2;
                },
                'v' => {
                    try result.append(allocator, 0x0B);
                    i += 2;
                },
                'x' => {
                    var digits: usize = 0;
                    while (digits < 2 and i + 2 + digits < input.len and isHexDigit(input[i + 2 + digits])) {
                        digits += 1;
                    }

                    if (digits == 0) {
                        try result.append(allocator, input[i]);
                        i += 1;
                    } else {
                        const hex_str = input[i + 2 .. i + 2 + digits];
                        const byte = std.fmt.parseInt(u8, hex_str, 16) catch unreachable;
                        try result.append(allocator, byte);
                        i += 2 + digits;
                    }
                },
                '0' => {
                    var digits: usize = 0;
                    while (digits < 3 and i + 2 + digits < input.len and isOctalDigit(input[i + 2 + digits])) {
                        digits += 1;
                    }

                    if (digits == 0) {
                        try result.append(allocator, 0);
                        i += 2;
                    } else {
                        const oct_str = input[i + 2 .. i + 2 + digits];
                        const byte = std.fmt.parseInt(u8, oct_str, 8) catch unreachable;
                        try result.append(allocator, byte);
                        i += 2 + digits;
                    }
                },
                else => {
                    try result.append(allocator, input[i]);
                    i += 1;
                },
            }
        } else {
            try result.append(allocator, input[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init) !void {
    // Allocators
    const arena = init.arena.allocator();

    // Stdout
    const stdout_file = std.Io.File.stdout();
    var stdout_buffer: [std.heap.page_size_min]u8 = undefined;
    var stdout_writer = std.Io.File.writer(stdout_file, init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    // Arguments
    const args_raw = init.minimal.args;
    const args_slice = try args_raw.toSlice(arena);

    // Guard
    if (args_slice.len < 2) {
        try stdout.print("Not enough arguments\n", .{});
        try stdout.flush();
        return;
    }

    // Help
    if (std.mem.eql(u8, args_slice[1], "-h")) {
        try stdout.print("Ezho the STRING(s) to standard output.\n\n", .{});
        try stdout.print("-n\tdo not output the trailing newline\n", .{});
        try stdout.print("-E\tdisable interpretation of backslash escapes\n", .{});
        try stdout.print("-e\tenable interpretation of backslash escapes (default)\n", .{});
        try stdout.flush();
        return;
    }

    // Flags
    var not_new_line = false;
    var not_formated = false;
    var index: usize = 1;
    for (args_slice[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--")) {
            index += 1;
            break;
        }
        if (arg.len < 2 or arg[0] != '-') {
            break;
        }

        for (arg[1..]) |char| {
            switch (char) {
                'n' => not_new_line = true,
                'E' => not_formated = true,
                'e' => not_formated = false, // by default
                else => {
                    try stdout.print("Unknown flag: -{c}\n", .{char});
                    try stdout.flush();
                    return;
                },
            }
        }
        index += 1;
    }

    // Debuging flags [remove later]
    // std.debug.print("no_new_line: {}\n", .{not_new_line});
    // std.debug.print("not_formated: {}\n", .{not_formated});

    // Guard
    if (index >= args_slice.len) {
        try stdout.print("No message provided\n", .{});
        try stdout.flush();
        return;
    }

    // Join
    const message = try std.mem.join(arena, " ", args_slice[index..]);

    // Adding or removing formatting
    const final = if (not_formated) message else try unescape(arena, message);

    // Print or not with new line at the end
    if (not_new_line) {
        try stdout.print("{s}", .{final});
    } else {
        try stdout.print("{s}\n", .{final});
    }

    // Flushing
    try stdout.flush();
}
