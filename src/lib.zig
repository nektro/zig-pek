//! Pek HTML Preprocessor Language
//!
//! Shortening of Pekingese
//!     https://en.wikipedia.org/wiki/Pekingese
//!
//! Loosely inspired by Pug
//!     https://pugjs.org/api/getting-started.html

// // document.corgi
// doctype html
// html[lang="en"](
//     head(
//         title("Corgi Example")
//         meta[charset="UTF-8"]
//         meta[name="viewport",content="width=device-width,initial-scale=1"]
//     )
//     body(
//         h1("Corgi Example")
//         hr
//         p("This is an example HTML document written in "a[href="https://github.com/corgi-lang/corgi"]("Corgi")".")
//         p("Follow Nektro on Twitter @Nektro")
//     )
// )

const std = @import("std");
const range = @import("range").range;

const tokenize = @import("./tokenize.zig");
const astgen = @import("./astgen.zig");

pub fn parse(comptime input: []const u8) astgen.Value {
    return astgen.Value{ .element = astgen.do(tokenize.do(input, &.{ '[', '=', ']', '(', ')', '{', '}', '#', '/', '.' })) };
}

pub fn compile(writer: anytype, comptime value: astgen.Value, data: anytype) !void {
    try writer.writeAll("<!DOCTYPE html>\n");
    try do(writer, value, data, data, 0, false);
    try writer.writeAll("\n");
}

fn do(writer: anytype, comptime value: astgen.Value, data: anytype, ctx: anytype, indent: usize, flag1: bool) anyerror!void {
    switch (value) {
        .element => |v| {
            const hastext = for (v.children) |x| {
                if (x == .string or x == .replacement) break true;
            } else false;

            if (flag1) for (range(indent)) |_| try writer.writeAll("    ");
            try writer.writeAll("<");
            try writer.writeAll(v.name);

            for (v.attrs) |it| {
                try writer.print(" {s}=\"{}\"", .{ it.key, std.zig.fmtEscapes(it.value[1 .. it.value.len - 1]) });
            }

            if (v.children.len == 0) {
                try writer.writeAll(" />\n");
            } else {
                try writer.writeAll(">");

                if (!hastext) try writer.writeAll("\n");
                inline for (v.children) |it| {
                    try do(writer, it, data, ctx, indent + 1, !hastext);
                }
                if (!hastext) for (range(indent)) |_| try writer.writeAll("    ");
                try writer.print("</{s}>", .{v.name});
                if (flag1) try writer.writeAll("\n");
            }
        },
        .string => |v| {
            try writer.writeAll(v[1 .. v.len - 1]);
        },
        .replacement => |v| {
            const x = if (comptime std.mem.eql(u8, v[0], "this")) search(data, v[1..]) else search(ctx, v);
            const TO = @TypeOf(x);

            if (comptime std.meta.trait.isZigString(TO)) {
                try writer.print("{s}", .{x});
                return;
            }
            @compileError("pek: compile: unsupported type: " ++ @typeName(TO));
        },
        .block => |v| {
            const x = comptime search(data, v.args);

            switch (v.name) {
                .each => {
                    inline for (x) |item| {
                        inline for (v.body) |val| {
                            try do(writer, val, item, ctx, indent, flag1);
                        }
                    }
                },
            }
        },
        else => unreachable,
    }
}

fn search(comptime T: anytype, comptime args: []const []const u8) @TypeOf(if (args.len == 1) @field(T, args[0]) else search(@field(T, args[0]), args[1..])) {
    return if (args.len == 1) @field(T, args[0]) else search(@field(T, args[0]), args[1..]);
}
