//! Pek HTML Preprocessor Language
//!
//! Shortening of Pekingese
//!     https://en.wikipedia.org/wiki/Pekingese
//!
//! Loosely inspired by Pug + Handlebars
//!     https://pugjs.org/
//!     https://handlebarsjs.com/

const std = @import("std");
const range = @import("range").range;
const htmlentities = @import("htmlentities");
const root = @import("root");

const tokenize = @import("./tokenize.zig");
const astgen = @import("./astgen.zig");

pub fn parse(comptime input: []const u8) astgen.Value {
    return astgen.Value{ .element = astgen.do(tokenize.do(input, &.{ '[', '=', ']', '(', ')', '{', '}', '#', '/', '.', '<', '>' })) };
}

pub fn compile(comptime Ctx: type, alloc: std.mem.Allocator, writer: anytype, comptime value: astgen.Value, data: anytype) !void {
    try writer.writeAll("<!DOCTYPE html>\n");
    try do(Ctx, alloc, writer, value, data, data, 0, false);
    try writer.writeAll("\n");
}

fn do(comptime Ctx: type, alloc: std.mem.Allocator, writer: anytype, comptime value: astgen.Value, data: anytype, ctx: anytype, indent: usize, flag1: bool) anyerror!void {
    switch (comptime value) {
        .element => |v| {
            const hastext = for (v.children) |x| {
                switch (x) {
                    .string, .replacement, .function => break true,
                    .element, .attr, .block, .body => {},
                }
            } else false;

            if (flag1) for (range(indent)) |_| try writer.writeAll("    ");
            try writer.writeAll("<");
            try writer.writeAll(v.name);

            inline for (v.attrs) |it| {
                switch (comptime it.value) {
                    .string => try writer.print(" {s}=\"{}\"", .{ it.key, std.zig.fmtEscapes(it.value.string[1 .. it.value.string.len - 1]) }),
                    .body => {
                        try writer.print(" {s}=\"", .{it.key});
                        try do(Ctx, alloc, writer, astgen.Value{ .body = it.value.body }, data, ctx, indent, flag1);
                        try writer.print("\"", .{});
                    },
                }
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
                    try do(Ctx, alloc, writer, it, data, ctx, indent + 1, !hastext);
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
            if (comptime std.meta.trait.hasFn("format")(TO)) {
                return std.fmt.format(writer, "{}", .{x});
            }
            if (comptime std.meta.trait.hasFn("toString")(TO)) {
                try writer.writeAll(try x.toString(alloc));
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
                    for (x) |item| try do(Ctx, alloc, writer, body, item, ctx, indent, flag1);
                },
                .@"if" => {
                    comptime assertEqual(v.args.len, 1);
                    if (comptime std.meta.trait.isIndexable(T)) {
                        try doif(Ctx, alloc, writer, body, bottom, data, ctx, indent, flag1, x.len > 0);
                        return;
                    }
                    switch (comptime TI) {
                        .Bool => try doif(Ctx, alloc, writer, body, bottom, data, ctx, indent, flag1, x),
                        .Optional => try docap(Ctx, alloc, writer, body, bottom, data, ctx, indent, flag1, x),
                        else => @compileError(comptime std.fmt.comptimePrint("pek: unable to use '{s}' in an #if block", .{@typeName(T)})),
                    }
                },
                .ifnot => {
                    comptime assertEqual(v.args.len, 1);
                    switch (comptime TI) {
                        .Bool => try doif(Ctx, alloc, writer, body, bottom, data, ctx, indent, flag1, !x),
                        .Optional => try docap(Ctx, alloc, writer, body, bottom, data, ctx, indent, flag1, !x),
                        else => @compileError(comptime std.fmt.comptimePrint("pek: unable to use '{s}' in an #ifnot block", .{@typeName(T)})),
                    }
                },
                .ifequal => {
                    comptime assertEqual(v.args.len, 2);
                    const y = if (comptime std.mem.eql(u8, v.args[1][0], "this")) search(v.args[1][1..], data) else search(v.args[1], ctx);
                    if (@typeInfo(@TypeOf(x)) == .Enum and comptime std.meta.trait.isZigString(@TypeOf(y))) {
                        return try doif(Ctx, alloc, writer, body, bottom, data, ctx, indent, flag1, std.mem.eql(u8, @tagName(x), y));
                    }
                    try doif(Ctx, alloc, writer, body, bottom, data, ctx, indent, flag1, x == y);
                },
                .ifnotequal => {
                    comptime assertEqual(v.args.len, 2);
                    const y = if (comptime std.mem.eql(u8, v.args[1][0], "this")) search(v.args[1][1..], data) else search(v.args[1], ctx);
                    if (@typeInfo(@TypeOf(x)) == .Enum and comptime std.meta.trait.isZigString(@TypeOf(y))) {
                        return try doif(Ctx, alloc, writer, body, bottom, data, ctx, indent, flag1, std.mem.eql(u8, @tagName(x), y));
                    }
                    try doif(Ctx, alloc, writer, body, bottom, data, ctx, indent, flag1, x != y);
                },
            }
        },
        .body => |v| {
            inline for (v) |val| {
                try do(Ctx, alloc, writer, val, data, ctx, indent, flag1);
            }
        },
        .function => |v| {
            var arena = std.heap.ArenaAllocator.init(alloc);
            defer arena.deinit();

            if (@hasDecl(Ctx, "pek_" ++ v.name)) {
                const func = @field(Ctx, "pek_" ++ v.name);
                var list = std.ArrayList(u8).init(arena.allocator());
                errdefer list.deinit();
                var args: FnArgsTuple(func) = undefined;
                args.@"0" = alloc;
                args.@"1" = list.writer();
                inline for (v.args) |arg, i| {
                    const field_name = comptime std.fmt.comptimePrint("{d}", .{i + 2});
                    @field(args, field_name) = if (comptime std.mem.eql(u8, arg[0], "this")) search(arg[1..], data) else search(arg, ctx);
                }
                const repvalue = astgen.Value{ .replacement = &.{"this"} };
                try @call(.{}, func, args);
                try do(Ctx, alloc, writer, repvalue, list.toOwnedSlice(), ctx, indent, flag1);
                return;
            }
            @compileError("pek: unknown custom function: " ++ v.name);
        },
        else => unreachable,
    }
}

fn search(comptime args: []const []const u8, ctx: anytype) FieldSearch(@TypeOf(ctx), args) {
    if (args.len == 0) return ctx;
    if (args[0][0] == '"') return std.mem.trim(u8, args[0], "\"");
    const f = @field(ctx, args[0]);
    if (args.len == 1) return f;
    return search(args[1..], f);
}

fn FieldSearch(comptime T: type, comptime args: []const []const u8) type {
    if (args.len > 0 and args[0][0] == '"') return []const u8;
    return if (args.len == 0) T else if (args.len == 1) Field(T, args[0]) else FieldSearch(Field(T, args[0]), args[1..]);
}

fn Field(comptime T: type, comptime field_name: []const u8) type {
    inline for (std.meta.fields(T)) |fld| {
        if (std.mem.eql(u8, fld.name, field_name)) return fld.field_type;
    }
    if (std.meta.trait.isIndexable(T) and std.mem.eql(u8, field_name, "len")) {
        return usize;
    }
    @compileError(std.fmt.comptimePrint("pek: unknown field {s} on type {s}", .{ field_name, @typeName(T) }));
}

fn entityLookupBefore(in: []const u8) ?htmlentities.Entity {
    for (htmlentities.ENTITIES) |e| {
        if (!std.mem.endsWith(u8, e.entity, ";")) {
            continue;
        }
        if (in.len == 1) {
            switch (in[0]) {
                '\n',
                '.',
                ':',
                '(',
                ')',
                '%',
                '+',
                => return null,
                else => break,
            }
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

fn doif(comptime Ctx: type, alloc: std.mem.Allocator, writer: anytype, comptime top: astgen.Value, comptime bottom: astgen.Value, data: anytype, ctx: anytype, indent: usize, flag1: bool, flag2: bool) anyerror!void {
    if (flag2) {
        try do(Ctx, alloc, writer, top, data, ctx, indent, flag1);
    } else {
        try do(Ctx, alloc, writer, bottom, data, ctx, indent, flag1);
    }
}

fn docap(comptime Ctx: type, alloc: std.mem.Allocator, writer: anytype, comptime top: astgen.Value, comptime bottom: astgen.Value, data: anytype, ctx: anytype, indent: usize, flag1: bool, flag2: anytype) anyerror!void {
    if (flag2) |_| {
        try do(Ctx, alloc, writer, top, data, ctx, indent, flag1);
    } else {
        try do(Ctx, alloc, writer, bottom, data, ctx, indent, flag1);
    }
}

fn FnArgsTuple(func: anytype) type {
    var types: []const type = &.{};
    inline for (@typeInfo(@TypeOf(func)).Fn.args) |arg| {
        types = types ++ &[_]type{arg.arg_type.?};
    }
    return std.meta.Tuple(types);
}
