//! Pek HTML Preprocessor Language
//!
//! Shortening of Pekingese
//!     https://en.wikipedia.org/wiki/Pekingese
//!
//! Loosely inspired by Pug + Handlebars
//!     https://pugjs.org/
//!     https://handlebarsjs.com/

const std = @import("std");
const string = []const u8;
const range = @import("range").range;
const htmlentities = @import("htmlentities");
const root = @import("root");

const tokenize = @import("./tokenize.zig");
const astgen = @import("./astgen.zig");

pub fn parse(comptime input: string) astgen.Value {
    return astgen.Value{ .element = astgen.do(tokenize.do(input, &.{ '[', '=', ']', '(', ')', '{', '}', '#', '/', '.', '<', '>' })) };
}

pub fn compile(comptime Ctx: type, alloc: std.mem.Allocator, writer: anytype, comptime value: astgen.Value, data: anytype) !void {
    try writer.writeAll("<!DOCTYPE html>\n");
    try do(Ctx, alloc, writer, value, data, data, .{
        .indent = 0,
        .flag1 = false,
    });
    try writer.writeAll("\n");
}

pub const Writer = std.ArrayList(u8).Writer;

inline fn do(comptime Ctx: type, alloc: std.mem.Allocator, writer: anytype, comptime value: astgen.Value, data: anytype, ctx: anytype, opts: DoOptions) anyerror!void {
    switch (comptime value) {
        .element => |v| {
            const hastext = for (v.children) |x| {
                switch (x) {
                    .string, .replacement, .function => break true,
                    .element, .attr, .block, .body => {},
                }
            } else false;

            if (opts.flag1) for (range(opts.indent)) |_| try writer.writeAll("    ");
            try writer.writeAll("<");
            try writer.writeAll(v.name);

            inline for (v.attrs) |it| {
                switch (comptime it.value) {
                    .string => try writer.print(" {s}=\"{}\"", .{ it.key, std.zig.fmtEscapes(it.value.string[1 .. it.value.string.len - 1]) }),
                    .body => {
                        try writer.print(" {s}=\"", .{it.key});
                        try do(Ctx, alloc, writer, astgen.Value{ .body = it.value.body }, data, ctx, opts);
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
                    try do(Ctx, alloc, writer, it, data, ctx, .{
                        .indent = opts.indent + 1,
                        .flag1 = !hastext,
                    });
                }
                if (!hastext) for (range(opts.indent)) |_| try writer.writeAll("    ");
                try writer.print("</{s}>", .{v.name});
                if (opts.flag1) try writer.writeAll("\n");
            }
        },
        .string => |v| {
            try writeEscaped(v[1 .. v.len - 1], writer);
        },
        .replacement => |repl| {
            const v = repl.arms;
            const x = if (comptime std.mem.eql(u8, v[0], "this")) search(v[1..], data) else search(v, ctx);
            const TO = @TypeOf(x);
            const TI = @typeInfo(TO);

            if (comptime std.meta.trait.isZigString(TO)) {
                if (repl.raw) {
                    try writer.writeAll(x);
                    return;
                }
                const s = std.mem.trim(u8, x, "\n");
                try writeEscaped(s, writer);
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
            @compileError(std.fmt.comptimePrint("pek: print {s}: unsupported type: {s}", .{ v, @typeName(TO) }));
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
                    for (x) |item| try do(Ctx, alloc, writer, body, item, ctx, opts);
                },
                .@"if" => {
                    comptime assertEqual(v.args.len, 1);
                    if (comptime std.meta.trait.isIndexable(T)) {
                        try doif(Ctx, alloc, writer, body, bottom, data, ctx, opts, x.len > 0);
                        return;
                    }
                    switch (comptime TI) {
                        .Bool => try doif(Ctx, alloc, writer, body, bottom, data, ctx, opts, x),
                        .Optional => try docap(Ctx, alloc, writer, body, bottom, data, ctx, opts, x),
                        else => @compileError(std.fmt.comptimePrint("pek: unable to use '{s}' in an #if block", .{@typeName(T)})),
                    }
                },
                .ifnot => {
                    comptime assertEqual(v.args.len, 1);
                    switch (comptime TI) {
                        .Bool => try doif(Ctx, alloc, writer, body, bottom, data, ctx, opts, !x),
                        .Optional => try docap(Ctx, alloc, writer, body, bottom, data, ctx, opts, !x),
                        else => @compileError(std.fmt.comptimePrint("pek: unable to use '{s}' in an #ifnot block", .{@typeName(T)})),
                    }
                },
                .ifequal => {
                    comptime assertEqual(v.args.len, 2);
                    const y = if (comptime std.mem.eql(u8, v.args[1][0], "this")) search(v.args[1][1..], data) else search(v.args[1], ctx);
                    if (@typeInfo(@TypeOf(x)) == .Enum and comptime std.meta.trait.isZigString(@TypeOf(y))) {
                        return try doif(Ctx, alloc, writer, body, bottom, data, ctx, opts, std.mem.eql(u8, @tagName(x), y));
                    }
                    try doif(Ctx, alloc, writer, body, bottom, data, ctx, opts, x == y);
                },
                .ifnotequal => {
                    comptime assertEqual(v.args.len, 2);
                    const y = if (comptime std.mem.eql(u8, v.args[1][0], "this")) search(v.args[1][1..], data) else search(v.args[1], ctx);
                    if (@typeInfo(@TypeOf(x)) == .Enum and comptime std.meta.trait.isZigString(@TypeOf(y))) {
                        return try doif(Ctx, alloc, writer, body, bottom, data, ctx, opts, std.mem.eql(u8, @tagName(x), y));
                    }
                    try doif(Ctx, alloc, writer, body, bottom, data, ctx, opts, x != y);
                },
            }
        },
        .body => |v| {
            inline for (v) |val| {
                try do(Ctx, alloc, writer, val, data, ctx, opts);
            }
        },
        .function => |v| {
            var arena = std.heap.ArenaAllocator.init(alloc);
            defer arena.deinit();

            if (!v.raw and @hasDecl(Ctx, "pek_" ++ v.name)) {
                const func = @field(Ctx, "pek_" ++ v.name);
                var list = std.ArrayList(u8).init(arena.allocator());
                errdefer list.deinit();
                var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;
                args.@"0" = alloc;
                args.@"1" = list.writer();
                inline for (v.args, 0..) |arg, i| {
                    const field_name = comptime std.fmt.comptimePrint("{d}", .{i + 2});
                    @field(args, field_name) = if (comptime std.mem.eql(u8, arg[0], "this")) search(arg[1..], data) else search(arg, ctx);
                }
                const repvalue = astgen.Value{ .replacement = .{ .arms = &.{"this"}, .raw = v.raw } };
                try @call(.auto, func, args);
                try do(Ctx, alloc, writer, repvalue, try list.toOwnedSlice(), ctx, opts);
                return;
            }
            if (v.raw and @hasDecl(Ctx, "pek__" ++ v.name)) {
                const func = @field(Ctx, "pek__" ++ v.name);
                var list = std.ArrayList(u8).init(arena.allocator());
                errdefer list.deinit();
                var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;
                args.@"0" = alloc;
                args.@"1" = list.writer();
                inline for (v.args, 0..) |arg, i| {
                    const field_name = comptime std.fmt.comptimePrint("{d}", .{i + 2});
                    @field(args, field_name) = if (comptime std.mem.eql(u8, arg[0], "this")) search(arg[1..], data) else search(arg, ctx);
                }
                const repvalue = astgen.Value{ .replacement = .{ .arms = &.{"this"}, .raw = v.raw } };
                try @call(.auto, func, args);
                try do(Ctx, alloc, writer, repvalue, try list.toOwnedSlice(), ctx, opts);
                return;
            }
            @compileError("pek: unknown custom function: " ++ v.name);
        },
        else => unreachable,
    }
}

pub const DoOptions = struct {
    indent: usize,
    flag1: bool,
};

fn search(comptime args: []const string, ctx: anytype) FieldSearch(@TypeOf(ctx), args) {
    if (args.len == 0) return ctx;
    if (args[0][0] == '"') return std.mem.trim(u8, args[0], "\"");
    const f = @field(ctx, args[0]);
    if (args.len == 1) return f;
    return search(args[1..], f);
}

fn FieldSearch(comptime T: type, comptime args: []const string) type {
    if (args.len > 0 and args[0][0] == '"') return string;
    return if (args.len == 0) T else if (args.len == 1) Field(T, args[0]) else FieldSearch(Field(T, args[0]), args[1..]);
}

fn Field(comptime T: type, comptime field_name: string) type {
    if (std.meta.trait.isIndexable(T) and std.mem.eql(u8, field_name, "len")) {
        return usize;
    }
    for (std.meta.fields(T)) |fld| {
        if (std.mem.eql(u8, fld.name, field_name)) {
            return fld.type;
        }
    }
    @compileError(std.fmt.comptimePrint("pek: unknown field {s} on type {s}", .{ field_name, @typeName(T) }));
}

pub fn writeEscaped(s: string, writer: anytype) !void {
    const view = std.unicode.Utf8View.initUnchecked(s);
    var iter = view.iterator();
    while (nextCodepointSliceLossy(&iter)) |sl| {
        const cp = std.unicode.utf8Decode(sl) catch unreachable;
        if (isCodepointAnEntity(cp)) |ent| {
            try writer.writeAll(ent.entity);
        } else {
            try writer.writeAll(sl);
        }
    }
}

fn nextCodepointSliceLossy(it: *std.unicode.Utf8Iterator) ?[]const u8 {
    if (it.i >= it.bytes.len) return null;
    const cp_len = std.unicode.utf8ByteSequenceLength(it.bytes[it.i]) catch {
        it.i += 1;
        return "�";
    };
    if (it.i + cp_len > it.bytes.len) return null;
    const maybe = it.bytes[it.i..][0..cp_len];
    _ = std.unicode.utf8Decode(maybe) catch {
        it.i += 1;
        return "�";
    };
    it.i += cp_len;
    return maybe;
}

fn isCodepointAnEntity(cp: u21) ?htmlentities.Entity {
    switch (cp) {
        '\n',
        '.',
        ':',
        '(',
        ')',
        '%',
        '+',
        => return null,
        else => {},
    }
    for (htmlentities.ENTITIES) |e| {
        if (e.entity.len == 0) continue;
        if (e.entity[e.entity.len - 1] != ';') continue;

        if (e.codepoints == .Single and e.codepoints.Single == cp) {
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

fn contains(haystack: []const string, needle: string) bool {
    for (haystack) |v| {
        if (std.mem.eql(u8, v, needle)) {
            return true;
        }
    }
    return false;
}

fn doif(comptime Ctx: type, alloc: std.mem.Allocator, writer: anytype, comptime top: astgen.Value, comptime bottom: astgen.Value, data: anytype, ctx: anytype, opts: DoOptions, flag2: bool) anyerror!void {
    if (flag2) {
        try do(Ctx, alloc, writer, top, data, ctx, opts);
    } else {
        try do(Ctx, alloc, writer, bottom, data, ctx, opts);
    }
}

fn docap(comptime Ctx: type, alloc: std.mem.Allocator, writer: anytype, comptime top: astgen.Value, comptime bottom: astgen.Value, data: anytype, ctx: anytype, opts: DoOptions, flag2: anytype) anyerror!void {
    if (flag2) |_| {
        try do(Ctx, alloc, writer, top, data, ctx, opts);
    } else {
        try do(Ctx, alloc, writer, bottom, data, ctx, opts);
    }
}
