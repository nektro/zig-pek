const std = @import("std");
const string = []const u8;

//
//

pub const Token = union(enum) {
    word: string,
    symbol: string,
    string: string,

    pub const skippedChars = &[_]u8{ ' ', '\n', '\t', '\r' };
};

//
//

pub fn do(comptime input: string, comptime symbols: []const u8) []const Token {
    var ret: []const Token = &[_]Token{};

    var line = 1;
    var pos = 1;

    var start = 0;
    var end = 0;
    var mode = 0;

    @setEvalBranchQuota(10001000);

    inline for (input) |c, i| {
        const s = &[_]u8{c};

        var shouldFlush: bool = undefined;

        blk: {
            if (mode == 0) {
                if (c == '#') {
                    mode = 1;
                    shouldFlush = false;
                    break :blk;
                }
                if (c == '"') {
                    mode = 2;
                    shouldFlush = false;
                    break :blk;
                }
            }
            if (mode == 1) {
                if (c == '\n') {
                    // skip comments
                    // f(v.handle(TTCom, in[s:i]))
                    start = i;
                    end = i;
                    mode = 0;
                }
                shouldFlush = c == '\n';
                break :blk;
            }
            if (mode == 2) {
                if (c == input[start]) {
                    ret = ret ++ &[_]Token{.{ .string = input[start .. i + 1] }};
                    start = i + 1;
                    end = i;
                    mode = 0;
                }
                shouldFlush = false;
                break :blk;
            }
            if (std.mem.indexOf(u8, Token.skippedChars, s)) |_| {
                shouldFlush = true;
                break :blk;
            }
            if (std.mem.indexOf(u8, symbols, s)) |_| {
                shouldFlush = true;
                break :blk;
            }
            shouldFlush = false;
            break :blk;
        }

        if (!shouldFlush) {
            end += 1;
        }
        if (shouldFlush) {
            if (mode == 0) {
                if (end - start > 0) {
                    ret = ret ++ &[_]Token{.{ .word = input[start..end] }};
                    start = i;
                    end = i;
                }
                if (std.mem.indexOf(u8, Token.skippedChars, s)) |_| {
                    start += 1;
                    end += 1;
                }
                if (std.mem.indexOf(u8, symbols, s)) |_| {
                    ret = ret ++ &[_]Token{.{ .symbol = s }};
                    start += 1;
                    end += 1;
                }
            }
        }

        pos += 1;
        if (c != '\n') continue;
        line += 1;
        pos = 1;
    }

    return ret;
}
