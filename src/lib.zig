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
const htmlentities = @import("htmlentities");
const root = @import("root");

const tokenize = @import("./tokenize.zig");
const astgen = @import("./astgen.zig");

pub fn parse(comptime input: string) astgen.Value {
    return astgen.Value{ .element = astgen.do(tokenize.do(input, &.{ '[', '=', ']', '(', ')', '{', '}', '#', '/', '.', '<', '>' })) };
}

pub fn compile(comptime Ctx: type, alloc: std.mem.Allocator, writer: anytype, comptime value: astgen.Value, data: anytype) !void {
    try writer.writeAll("<!DOCTYPE html>\n");
    try do(alloc, writer, value, data, data, .{
        .Ctx = Ctx,
        .indent = 0,
        .flag1 = false,
    });
    try writer.writeAll("\n");
}

pub fn compileInner(alloc: std.mem.Allocator, writer: anytype, comptime value: astgen.Value, comptime opts: DoOptions, data: anytype) !void {
    try do(alloc, writer, value, data, data, opts);
    try writer.writeAll("\n");
}

pub const Writer = std.ArrayList(u8).Writer;

inline fn do(alloc: std.mem.Allocator, writer: anytype, comptime value: astgen.Value, data: anytype, ctx: anytype, comptime opts: DoOptions) anyerror!void {
    switch (comptime value) {
        .element => |v| {
            const hastext = comptime for (v.children) |x| {
                switch (x) {
                    .string, .replacement, .function => break true,
                    .element, .attr, .block, .body => {},
                }
            } else false;

            if (opts.flag1) for (0..opts.indent) |_| try writer.writeAll("    ");
            try writer.writeAll("<");
            try writer.writeAll(v.name);

            inline for (v.attrs) |it| {
                switch (comptime it.value) {
                    .string => try writer.print(" {s}=\"{}\"", .{ it.key, std.zig.fmtEscapes(it.value.string[1 .. it.value.string.len - 1]) }),
                    .body => {
                        try writer.print(" {s}=\"", .{it.key});
                        try do(alloc, writer, astgen.Value{ .body = it.value.body }, data, ctx, opts);
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
                    try do(alloc, writer, it, data, ctx, .{
                        .Ctx = opts.Ctx,
                        .indent = opts.indent + 1,
                        .flag1 = !hastext,
                    });
                }
                if (!hastext) for (0..opts.indent) |_| try writer.writeAll("    ");
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
            if (comptime isArrayOf(u8)(TO)) {
                if (repl.raw) {
                    try writer.writeAll(&x);
                    return;
                }
                const s = std.mem.trim(u8, &x, "\n");
                try writeEscaped(s, writer);
                return;
            }
            @compileError(std.fmt.comptimePrint("pek: print {s}: unsupported type: {s}", .{ v, @typeName(TO) }));
        },
        .block => |v| {
            const body = astgen.Value{ .body = v.body };
            const bottom = astgen.Value{ .body = v.bttm };
            const x = resolveArg(v.args[0], data, ctx);
            const T = @TypeOf(x);
            const TI = @typeInfo(T);
            switch (v.name) {
                .each => {
                    comptime assertEqual(v.args.len, 1);
                    for (x) |item| try do(alloc, writer, body, item, ctx, opts);
                },
                .@"if" => {
                    comptime assertEqual(v.args.len, 1);
                    if (v.func) |n| {
                        const x2 = try @field(opts.Ctx, "pek_" ++ n)(alloc, x);
                        try doif(alloc, writer, body, bottom, data, ctx, opts, x2);
                        return;
                    }
                    if (comptime std.meta.trait.isIndexable(T)) {
                        try doif(alloc, writer, body, bottom, data, ctx, opts, x.len > 0);
                        return;
                    }
                    switch (comptime TI) {
                        .Bool => try doif(alloc, writer, body, bottom, data, ctx, opts, x),
                        .Optional => try docap(alloc, writer, body, bottom, data, ctx, opts, x),
                        else => @compileError(std.fmt.comptimePrint("pek: unable to use '{s}' in an #if block", .{@typeName(T)})),
                    }
                },
                .ifnot => {
                    comptime assertEqual(v.args.len, 1);
                    if (v.func) |n| {
                        const x2 = try @field(opts.Ctx, "pek_" ++ n)(alloc, x);
                        try doif(alloc, writer, body, bottom, data, ctx, opts, !x2);
                        return;
                    }
                    switch (comptime TI) {
                        .Bool => try doif(alloc, writer, body, bottom, data, ctx, opts, !x),
                        .Optional => try docap(alloc, writer, body, bottom, data, ctx, opts, !x),
                        else => @compileError(std.fmt.comptimePrint("pek: unable to use '{s}' in an #ifnot block", .{@typeName(T)})),
                    }
                },
                .ifequal => {
                    comptime assertEqual(v.args.len, 2);
                    const y = resolveArg(v.args[1], data, ctx);
                    if (@typeInfo(@TypeOf(x)) == .Enum and comptime std.meta.trait.isZigString(@TypeOf(y))) {
                        return try doif(alloc, writer, body, bottom, data, ctx, opts, std.mem.eql(u8, @tagName(x), y));
                    }
                    try doif(alloc, writer, body, bottom, data, ctx, opts, x == y);
                },
                .ifnotequal => {
                    comptime assertEqual(v.args.len, 2);
                    const y = resolveArg(v.args[1], data, ctx);
                    if (@typeInfo(@TypeOf(x)) == .Enum and comptime std.meta.trait.isZigString(@TypeOf(y))) {
                        return try doif(alloc, writer, body, bottom, data, ctx, opts, std.mem.eql(u8, @tagName(x), y));
                    }
                    try doif(alloc, writer, body, bottom, data, ctx, opts, x != y);
                },
            }
        },
        .body => |v| {
            inline for (v) |val| {
                try do(alloc, writer, val, data, ctx, opts);
            }
        },
        .function => |v| {
            var arena = std.heap.ArenaAllocator.init(alloc);
            defer arena.deinit();

            if (!v.raw and @hasDecl(opts.Ctx, "pek_" ++ v.name)) {
                const func = @field(opts.Ctx, "pek_" ++ v.name);
                var list = std.ArrayList(u8).init(arena.allocator());
                errdefer list.deinit();
                var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;
                args.@"0" = alloc;
                args.@"1" = list.writer();
                inline for (v.args, 0..) |arg, i| {
                    const field_name = comptime std.fmt.comptimePrint("{d}", .{i + 2});
                    @field(args, field_name) = resolveArg(arg, data, ctx);
                }
                const repvalue = astgen.Value{ .replacement = .{ .arms = &.{"this"}, .raw = v.raw } };
                try @call(.auto, func, args);
                try do(alloc, writer, repvalue, try list.toOwnedSlice(), ctx, opts);
                return;
            }
            if (v.raw and @hasDecl(opts.Ctx, "pek__" ++ v.name)) {
                const func = @field(opts.Ctx, "pek__" ++ v.name);
                var list = std.ArrayList(u8).init(arena.allocator());
                errdefer list.deinit();
                const AT = std.meta.ArgsTuple(@TypeOf(func));
                const ATT = std.meta.fieldInfo(AT, .@"3").type;
                var tupargs = @as(ATT, undefined);
                var args = .{
                    alloc,
                    list.writer(),
                    opts,
                    tupargs,
                };
                inline for (v.args, 0..) |arg, i| {
                    const field_name = comptime std.fmt.comptimePrint("{d}", .{i});
                    @field(args[3], field_name) = resolveArg(arg, data, ctx);
                }
                const repvalue = astgen.Value{ .replacement = .{ .arms = &.{"this"}, .raw = v.raw } };
                try @call(.auto, func, args);
                try do(alloc, writer, repvalue, try list.toOwnedSlice(), ctx, opts);
                return;
            }
            if (v.raw and @hasDecl(opts.Ctx, "pek_" ++ v.name)) {
                @compileError("pek: attempted to call safe custom function: '" ++ v.name ++ "' but did not use '{" ++ v.name ++ "}'");
            }
            if (!v.raw and @hasDecl(opts.Ctx, "pek__" ++ v.name)) {
                @compileError("pek: attempted to call raw custom function: '_" ++ v.name ++ "' but did not use '{#" ++ v.name ++ "}'");
            }
            @compileError("pek: unknown custom function: " ++ v.name);
        },
        else => unreachable,
    }
}

pub const DoOptions = struct {
    Ctx: type,
    indent: usize,
    flag1: bool,
};

fn resolveArg(comptime arg: astgen.Arg, data: anytype, ctx: anytype) ResolveArg(arg, @TypeOf(data), @TypeOf(ctx)) {
    return switch (arg) {
        .plain => |av| av[1 .. av.len - 1],
        .lookup => |av| if (comptime std.mem.eql(u8, av[0], "this")) search(av[1..], data) else search(av, ctx),
    };
}

fn ResolveArg(comptime arg: astgen.Arg, comptime This: type, comptime Ctx: type) type {
    return switch (arg) {
        .plain => string,
        .lookup => |av| if (comptime std.mem.eql(u8, av[0], "this")) FieldSearch(This, av[1..]) else FieldSearch(Ctx, av),
    };
}

fn search(comptime args: []const string, ctx: anytype) FieldSearch(@TypeOf(ctx), args) {
    if (args.len == 0) return ctx;
    if (args[0][0] == '"') return std.mem.trim(u8, args[0], "\"");
    if (@typeInfo(@TypeOf(ctx)) == .Optional) return search(args, ctx.?);
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
    switch (@typeInfo(T)) {
        .Optional => |info| return Field(info.child, field_name),
        else => {},
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

fn doif(alloc: std.mem.Allocator, writer: anytype, comptime top: astgen.Value, comptime bottom: astgen.Value, data: anytype, ctx: anytype, comptime opts: DoOptions, flag2: bool) anyerror!void {
    if (flag2) {
        try do(alloc, writer, top, data, ctx, opts);
    } else {
        try do(alloc, writer, bottom, data, ctx, opts);
    }
}

fn docap(alloc: std.mem.Allocator, writer: anytype, comptime top: astgen.Value, comptime bottom: astgen.Value, data: anytype, ctx: anytype, comptime opts: DoOptions, flag2: anytype) anyerror!void {
    if (flag2) |_| {
        try do(alloc, writer, top, data, ctx, opts);
    } else {
        try do(alloc, writer, bottom, data, ctx, opts);
    }
}

fn isArrayOf(comptime T: type) std.meta.trait.TraitFn {
    const Closure = struct {
        pub fn trait(comptime C: type) bool {
            return switch (@typeInfo(C)) {
                .Array => |ti| ti.child == T,
                else => false,
            };
        }
    };
    return Closure.trait;
}
