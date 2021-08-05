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
    return astgen.Value{ .element = astgen.do(tokenize.do(input, &.{ '[', '=', ']', '(', ')', '{', '}' })) };
}

pub fn compile(writer: anytype, comptime value: astgen.Value, data: anytype, indent: usize, flag1: bool) anyerror!void {
    switch (value) {
        .element => |v| {
            const hastext = for (v.children) |x| {
                if (x == .string) break true;
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
                    try compile(writer, it, data, indent + 1, !hastext);
                }
                if (!hastext) for (range(indent)) |_| try writer.writeAll("    ");
                try writer.print("</{s}>", .{v.name});
                if (flag1) try writer.writeAll("\n");
            }
        },
        .string => |v| {
            try writer.writeAll(v[1 .. v.len - 1]);
        },
        else => unreachable,
    }
}
