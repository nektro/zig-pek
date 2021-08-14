//! Pek HTML Preprocessor Language
//!
//! Shortening of Pekingese
//!     https://en.wikipedia.org/wiki/Pekingese
//!
//! Loosely inspired by Pug
//!     https://pugjs.org/api/getting-started.html

const std = @import("std");
const range = @import("range").range;
const htmlentities = @import("htmlentities");

const tokenize = @import("./tokenize.zig");
const astgen = @import("./astgen.zig");

pub fn parse(comptime input: []const u8) astgen.Value {
    return astgen.Value{ .element = astgen.do(tokenize.do(input, &.{ '[', '=', ']', '(', ')', '{', '}', '#', '/', '.', '<', '>' })) };
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
                if (contains(std.meta.fieldNames(HtmlVoidElements), v.name)) {
                    try writer.writeAll(" />\n");
                } else {
                    try writer.print("></{s}>\n", .{v.name});
                }
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
            const x = if (comptime std.mem.eql(u8, v[0], "this")) search(v[1..], data) else search(v, ctx);
            const TO = @TypeOf(x);
            const TI = @typeInfo(TO);

            if (comptime std.meta.trait.isZigString(TO)) {
                const s: []const u8 = x;
                for (s) |c| {
                    if (entityLookupBefore(&[_]u8{c})) |ent| {
                        try writer.writeAll(ent.entity);
                    } else {
                        try writer.writeAll(&[_]u8{c});
                    }
                }
                return;
            }
            if (TI == .Int or TI == .Float or TI == .ComptimeInt or TI == .ComptimeFloat) {
                try writer.print("{d}", .{x});
                return;
            }
            @compileError("pek: print: unsupported type: " ++ @typeName(TO));
        },
        .block => |v| {
            const body = astgen.Value{ .body = v.body };
            const bottom = astgen.Value{ .body = v.bttm };
            const x = if (comptime std.mem.eql(u8, v.args[0][0], "this")) search(v.args[0][1..], data) else search(v.args[0], ctx);
            const T = @TypeOf(x);
            const TI = @typeInfo(T);
            switch (v.name) {
                .each => {
                    comptime assertEqual(v.args.len, 1);
                    for (x) |item| try do(writer, body, item, ctx, indent, flag1);
                },
                .@"if" => {
                    comptime assertEqual(v.args.len, 1);
                    switch (TI) {
                        .Bool => try doif(writer, body, bottom, data, ctx, indent, flag1, x, true),
                        .Optional => try docap(writer, body, bottom, data, ctx, indent, flag1, x, true),
                        else => unreachable,
                    }
                },
                .ifnot => {
                    comptime assertEqual(v.args.len, 1);
                    switch (TI) {
                        .Bool => try doif(writer, body, bottom, data, ctx, indent, flag1, x, false),
                        .Optional => try docap(writer, body, bottom, data, ctx, indent, flag1, x, false),
                        else => unreachable,
                    }
                },
                .ifequal => {
                    comptime assertEqual(v.args.len, 2);
                    const y = search(v.args[1], data);
                    if (x == y) try do(writer, body, data, ctx, indent, flag1);
                },
                .ifnotequal => {
                    comptime assertEqual(v.args.len, 2);
                    const y = if (comptime std.mem.eql(u8, v.args[1][0], "this")) search(v.args[1][1..], data) else search(v.args[1], ctx);
                    if (x != y) try do(writer, body, data, ctx, indent, flag1);
                },
            }
        },
        .body => |v| {
            inline for (v) |val| {
                try do(writer, val, data, ctx, indent, flag1);
            }
        },
        else => unreachable,
    }
}

fn search(comptime args: []const []const u8, ctx: anytype) FieldSearch(@TypeOf(ctx), args) {
    const f = @field(ctx, args[0]);
    if (args.len == 1) return f;
    return search(args[1..], f);
}

fn FieldSearch(comptime T: type, comptime args: []const []const u8) type {
    return if (args.len == 1) Field(T, args[0]) else FieldSearch(Field(T, args[0]), args[1..]);
}

fn Field(comptime T: type, comptime field_name: []const u8) type {
    inline for (std.meta.fields(T)) |fld| {
        if (std.mem.eql(u8, fld.name, field_name)) return fld.field_type;
    }
    if (std.meta.trait.isIndexable(T) and std.mem.eql(u8, field_name, "len")) {
        return usize;
    }
    @compileLog(field_name);
    @compileLog(std.meta.fieldNames(T));
}

fn entityLookupBefore(in: []const u8) ?htmlentities.Entity {
    for (htmlentities.ENTITIES) |e| {
        if (!std.mem.endsWith(u8, e.entity, ";")) {
            continue;
        }
        if (std.mem.eql(u8, e.characters, in)) {
            return e;
        }
    }
    return null;
}

fn assertEqual(comptime a: usize, comptime b: usize) void {
    if (a != b) @compileError(std.fmt.comptimePrint("{d} != {d}", .{ a, b }));
}

const HtmlVoidElements = enum {
    area,
    base,
    br,
    col,
    embed,
    hr,
    img,
    input,
    link,
    meta,
    param,
    source,
    track,
    wbr,
};

fn contains(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |v| {
        if (std.mem.eql(u8, v, needle)) {
            return true;
        }
    }
    return false;
}

fn doif(writer: anytype, comptime top: astgen.Value, comptime bottom: astgen.Value, data: anytype, ctx: anytype, indent: usize, flag1: bool, flag2: bool, flag3: bool) anyerror!void {
    if (flag2 == flag3) {
        try do(writer, top, data, ctx, indent, flag1);
    } else {
        try do(writer, bottom, data, ctx, indent, flag1);
    }
}

fn docap(writer: anytype, comptime top: astgen.Value, comptime bottom: astgen.Value, data: anytype, ctx: anytype, indent: usize, flag1: bool, flag2: bool, flag3: bool) anyerror!void {
    if (flag2 == flag3) {
        try do(writer, top, data, ctx, indent, flag1);
    } else {
        try do(writer, bottom, data, ctx, indent, flag1);
    }
}
