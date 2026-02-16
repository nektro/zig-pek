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
const tracer = @import("tracer");
const extras = @import("extras");
const builtin = @import("builtin");

const tokenize = @import("./tokenize.zig");
const astgen = @import("./astgen.zig");

const callconv_inline: std.builtin.CallingConvention = if (builtin.mode == .Debug) .auto else .@"inline";

pub fn parse(comptime input: string) astgen.Value {
    return astgen.Value{ .element = astgen.do(tokenize.do(input, &.{ '[', '=', ']', '(', ')', '{', '}', '#', '/', '.', '<', '>' })) };
}

pub fn compile(comptime Ctx: type, alloc: std.mem.Allocator, writer: anytype, comptime value: astgen.Value, data: anytype) !void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try writer.writeAll("<!DOCTYPE html>\n");
    try do(alloc, writer, value, data, data, .{
        .Ctx = Ctx,
        .indent = 0,
        .doindent = builtin.mode == .Debug,
        .doindent2 = builtin.mode == .Debug,
    });
}

pub fn compileInner(alloc: std.mem.Allocator, writer: anytype, comptime value: astgen.Value, comptime opts: DoOptions, data: anytype) !void {
    try do(alloc, writer, value, data, data, opts);
}

pub const Writer = std.ArrayList(u8).Writer;

fn do(alloc: std.mem.Allocator, writer: anytype, comptime value: astgen.Value, data: anytype, ctx: anytype, comptime opts: DoOptions) callconv(callconv_inline) anyerror!void {
    comptime var skipindent = false;
    if (value == .element and comptime std.mem.eql(u8, value.element.name, "pre")) skipindent = true;
    return doInner(alloc, writer, value, data, ctx, .{
        .Ctx = opts.Ctx,
        .indent = opts.indent,
        .doindent = opts.doindent and !skipindent,
        .doindent2 = opts.doindent,
        .escaped = opts.escaped,
    });
}
fn doInner(alloc: std.mem.Allocator, writer: anytype, comptime value: astgen.Value, data: anytype, ctx: anytype, comptime opts: DoOptions) callconv(callconv_inline) anyerror!void {
    switch (comptime value) {
        .element => |v| {
            const hastext = comptime for (v.children) |x| {
                switch (x) {
                    .string, .replacement, .function => break true,
                    .element, .attr, .block, .body => {},
                }
            } else false;
            _ = hastext;

            if (opts.doindent2) for (0..opts.indent) |_| try writer.writeAll("    ");
            try writer.writeAll("<");
            try writer.writeAll(v.name);

            inline for (v.attrs) |it| {
                switch (comptime it.value) {
                    .string => try writer.print(" {s}={s}", .{ it.key, it.value.string }),
                    .body => {
                        try writer.print(" {s}=\"", .{it.key});
                        inline for (it.value.body) |bval| try do(alloc, writer, bval, data, ctx, opts);
                        try writer.print("\"", .{});
                    },
                }
            }

            if (v.children.len == 0) {
                if (contains(std.meta.fieldNames(HtmlVoidElements), v.name)) {
                    try writer.writeAll(" />");
                    if (opts.doindent2) try writer.writeAll("\n");
                } else {
                    try writer.print("></{s}>", .{v.name});
                    if (opts.doindent2) try writer.writeAll("\n");
                }
            } else {
                const shouldindent = opts.doindent and v.children[0] != .string and v.children[0] != .replacement;
                try writer.writeAll(">");
                if (shouldindent) try writer.writeAll("\n");
                inline for (v.children) |it| {
                    try do(alloc, writer, it, data, ctx, .{
                        .Ctx = opts.Ctx,
                        .indent = opts.indent + 1,
                        .doindent = shouldindent,
                        .doindent2 = opts.doindent2,
                    });
                }
                if (shouldindent) for (0..opts.indent) |_| try writer.writeAll("    ");
                try writer.print("</{s}>", .{v.name});
                if (opts.doindent2) try writer.writeAll("\n");
            }
        },
        .string => |v| {
            if (opts.escaped) try writeEscaped(v[1 .. v.len - 1], writer);
            if (!opts.escaped) try writer.writeAll(v[1 .. v.len - 1]);
        },
        .replacement => |repl| {
            const v = repl.arms;
            const x = search(v, ctx);
            const TO = @TypeOf(x);
            const TI = @typeInfo(TO);

            if (comptime extras.isZigString(TO)) {
                return writeReplacementString(writer, repl.raw, opts.escaped, x);
            }
            if (TI == .int or TI == .float or TI == .comptime_int or TI == .comptime_float) {
                try writer.print("{d}", .{x});
                return;
            }
            if (comptime extras.hasFn("format")(TO)) {
                return std.fmt.format(writer, "{}", .{x});
            }
            if (comptime extras.hasFn("toString")(TO)) {
                try writer.writeAll(try x.toString(alloc));
                return;
            }
            if (comptime isArrayOf(u8)(TO)) {
                if (repl.raw) {
                    try writer.writeAll(&x);
                    return;
                }
                const s = std.mem.trim(u8, &x, "\n");
                if (opts.escaped) try writeEscaped(s, writer);
                if (!opts.escaped) try writer.writeAll(s);
                return;
            }
            if (TI == .@"enum") {
                const s = @tagName(x);
                if (opts.escaped) try writeEscaped(s, writer);
                if (!opts.escaped) try writer.writeAll(s);
                return;
            }
            @compileError(std.fmt.comptimePrint("pek: print {s}: unsupported type: {s}", .{ v, @typeName(TO) }));
        },
        .block => |v| {
            const body = astgen.Value{ .body = v.body };
            const bottom = astgen.Value{ .body = v.bttm };
            const x = try resolveArg(v.args[0], alloc, data, ctx, opts);
            const T = @TypeOf(x);
            const TI = @typeInfo(T);
            switch (v.name) {
                .each => {
                    switch (v.args.len) {
                        1 => {
                            for (x) |item| {
                                if (@hasField(@TypeOf(ctx), "this")) {
                                    // handle nested loops, should be temporary
                                    try do(alloc, writer, body, null, extras.join(.{ extras.omit(ctx, "this"), .{ .this = item } }), opts);
                                } else {
                                    try do(alloc, writer, body, null, extras.join(.{ ctx, .{ .this = item } }), opts);
                                }
                            }
                        },
                        2 => {
                            const y = try resolveArg(v.args[1], alloc, data, ctx, opts);
                            for (x, y) |item, jtem| {
                                try do(alloc, writer, body, null, extras.join(.{ ctx, .{ .this = item, .that = jtem } }), opts);
                            }
                        },
                        else => @compileError(std.fmt.comptimePrint("#each block cannot have {d} iterators", .{v.args.len})),
                    }
                },
                .@"if" => {
                    if (v.func) |n| {
                        const f = @field(opts.Ctx, "pek_" ++ n);
                        const x2 = try switch (@typeInfo(@TypeOf(f)).@"fn".params.len) {
                            2 => f(alloc, x),
                            3 => blk: {
                                const y = try resolveArg(v.args[1], alloc, data, ctx, opts);
                                break :blk f(alloc, x, y);
                            },
                            4 => blk: {
                                const y = try resolveArg(v.args[1], alloc, data, ctx, opts);
                                const z = try resolveArg(v.args[2], alloc, data, ctx, opts);
                                break :blk f(alloc, x, y, z);
                            },
                            else => unreachable, // TODO
                        };
                        try doif(alloc, writer, body, bottom, data, ctx, opts, x2);
                        return;
                    }
                    comptime assertEqual(v.args.len, 1);
                    if (comptime extras.isIndexable(T)) {
                        try doif(alloc, writer, body, bottom, data, ctx, opts, x.len > 0);
                        return;
                    }
                    switch (comptime TI) {
                        .bool => try doif(alloc, writer, body, bottom, data, ctx, opts, x),
                        .optional => try doif(alloc, writer, body, bottom, data, ctx, opts, x != null),
                        .int => try doif(alloc, writer, body, bottom, data, ctx, opts, x != 0),
                        else => @compileError(std.fmt.comptimePrint("pek: unable to use '{s}' in an #if block", .{@typeName(T)})),
                    }
                },
                .ifnot => {
                    if (v.func) |n| {
                        const f = @field(opts.Ctx, "pek_" ++ n);
                        const x2 = try switch (@typeInfo(@TypeOf(f)).@"fn".params.len) {
                            2 => f(alloc, x),
                            3 => blk: {
                                const y = try resolveArg(v.args[1], alloc, data, ctx, opts);
                                break :blk f(alloc, x, y);
                            },
                            4 => blk: {
                                const y = try resolveArg(v.args[1], alloc, data, ctx, opts);
                                const z = try resolveArg(v.args[2], alloc, data, ctx, opts);
                                break :blk f(alloc, x, y, z);
                            },
                            else => unreachable, // TODO
                        };
                        try doif(alloc, writer, body, bottom, data, ctx, opts, !x2);
                        return;
                    }
                    comptime assertEqual(v.args.len, 1);
                    if (comptime extras.isIndexable(T)) {
                        try doif(alloc, writer, body, bottom, data, ctx, opts, x.len == 0);
                        return;
                    }
                    switch (comptime TI) {
                        .bool => try doif(alloc, writer, body, bottom, data, ctx, opts, !x),
                        .optional => try doif(alloc, writer, body, bottom, data, ctx, opts, x == null),
                        .int => try doif(alloc, writer, body, bottom, data, ctx, opts, x == 0),
                        else => @compileError(std.fmt.comptimePrint("pek: unable to use '{s}' in an #ifnot block", .{@typeName(T)})),
                    }
                },
                .ifequal => {
                    comptime assertEqual(v.args.len, 2);
                    const y = try resolveArg(v.args[1], alloc, data, ctx, opts);
                    if (@typeInfo(@TypeOf(x)) == .@"enum" and comptime extras.isZigString(@TypeOf(y))) {
                        return try doif(alloc, writer, body, bottom, data, ctx, opts, std.mem.eql(u8, @tagName(x), y));
                    }
                    if (comptime extras.isSlice(@TypeOf(x, y))) {
                        return try doif(alloc, writer, body, bottom, data, ctx, opts, std.mem.eql(u8, x, y));
                    }
                    try doif(alloc, writer, body, bottom, data, ctx, opts, x == y);
                },
                .ifnotequal => {
                    comptime assertEqual(v.args.len, 2);
                    const y = try resolveArg(v.args[1], alloc, data, ctx, opts);
                    if (@typeInfo(@TypeOf(x)) == .@"enum" and comptime extras.isZigString(@TypeOf(y))) {
                        return try doif(alloc, writer, body, bottom, data, ctx, opts, !std.mem.eql(u8, @tagName(x), y));
                    }
                    if (comptime extras.isSlice(@TypeOf(x, y))) {
                        return try doif(alloc, writer, body, bottom, data, ctx, opts, !std.mem.eql(u8, x, y));
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
            if (!v.raw and @hasDecl(opts.Ctx, "pek_" ++ v.name)) {
                const func = @field(opts.Ctx, "pek_" ++ v.name);
                var list = std.ArrayList(u8).init(alloc);
                defer list.deinit();
                var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;
                comptime std.debug.assert(args.len - 2 == v.args.len);
                args.@"0" = alloc;
                args.@"1" = list.writer();
                inline for (v.args, 0..) |arg, i| {
                    const field_name = comptime std.fmt.comptimePrint("{d}", .{i + 2});
                    @field(args, field_name) = try resolveArg(arg, alloc, data, ctx, opts);
                }
                try @call(.auto, func, args);
                try writeReplacementString(writer, v.raw, opts.escaped, try list.toOwnedSlice());
                return;
            }
            if (v.raw and @hasDecl(opts.Ctx, "pek__" ++ v.name)) {
                const func = @field(opts.Ctx, "pek__" ++ v.name);
                var list = std.ArrayList(u8).init(alloc);
                defer list.deinit();
                const AT = std.meta.ArgsTuple(@TypeOf(func));
                const ATT = std.meta.fieldInfo(AT, .@"3").type;
                if (v.args.len != std.meta.fields(ATT).len) @compileError(std.fmt.comptimePrint("expected:{d} - actual:{d}", .{ std.meta.fields(ATT).len, v.args.len }));
                var tupargs = @as(ATT, undefined);
                _ = &tupargs;
                var args = .{
                    alloc,
                    list.writer(),
                    opts,
                    tupargs,
                };
                inline for (v.args, 0..) |arg, i| {
                    const field_name = comptime std.fmt.comptimePrint("{d}", .{i});
                    @field(args[3], field_name) = try resolveArg(arg, alloc, data, ctx, opts);
                }
                try @call(.auto, func, args);
                try writeReplacementString(writer, v.raw, opts.escaped, list.items);
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
    doindent: bool,
    doindent2: bool,
    escaped: bool = true,
};

fn resolveArg(comptime arg: astgen.Arg, alloc: std.mem.Allocator, data: anytype, ctx: anytype, comptime opts: DoOptions) !ResolveArg(arg, @TypeOf(data), @TypeOf(ctx)) {
    return switch (arg) {
        .plain => |av| av[1 .. av.len - 1],
        .lookup => |av| search(av, ctx),
        .int => |av| av,
        .value => |av| {
            var list = std.ArrayList(u8).init(alloc);
            comptime var newopts = opts;
            newopts.escaped = false;
            try do(alloc, list.writer(), astgen.Value{ .body = av }, data, ctx, newopts);
            return list.items;
        },
    };
}

fn ResolveArg(comptime arg: astgen.Arg, comptime This: type, comptime Ctx: type) type {
    _ = This;
    return switch (arg) {
        .plain => string,
        .lookup => |av| FieldSearch(Ctx, av),
        .int => u64,
        .value => string,
    };
}

fn search(comptime args: []const string, ctx: anytype) FieldSearch(@TypeOf(ctx), args) {
    if (args.len == 0) return ctx;
    if (args[0][0] == '"') return std.mem.trim(u8, args[0], "\"");
    if (comptime std.mem.eql(u8, args[0], "true")) return true;
    if (comptime std.mem.eql(u8, args[0], "false")) return false;
    if (@typeInfo(@TypeOf(ctx)) == .optional) return search(args, ctx.?);
    const f = @field(ctx, args[0]);
    if (args.len == 1) return f;
    return search(args[1..], f);
}

fn FieldSearch(comptime T: type, comptime args: []const string) type {
    if (args.len > 0 and args[0][0] == '"') return string;
    if (args.len > 0 and std.mem.eql(u8, args[0], "true")) return bool;
    if (args.len > 0 and std.mem.eql(u8, args[0], "false")) return bool;
    return if (args.len == 0) T else if (args.len == 1) Field(T, args[0]) else FieldSearch(Field(T, args[0]), args[1..]);
}

fn Field(comptime T: type, comptime field_name: string) type {
    if (extras.isIndexable(T) and std.mem.eql(u8, field_name, "len")) {
        return usize;
    }
    switch (@typeInfo(T)) {
        .optional => |info| return Field(info.child, field_name),
        else => {},
    }
    for (std.meta.fields(T)) |fld| {
        if (std.mem.eql(u8, fld.name, field_name)) {
            return fld.type;
        }
    }
    @compileLog(std.meta.fieldNames(T));
    _ = @field(@as(T, undefined), field_name);
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

fn writeReplacementString(writer: anytype, raw: bool, escaped: bool, bytes: []const u8) !void {
    if (raw) {
        try writer.writeAll(bytes);
        return;
    }
    const s = std.mem.trim(u8, bytes, "\n");
    if (escaped) try writeEscaped(s, writer);
    if (!escaped) try writer.writeAll(s);
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
        // '<', MUST NOT skip
        // '<', MUST NOT skip
        // '"', MUST NOT skip
        // '&', MUST NOT skip
        // ';', MUST NOT skip
        '\n',
        '.',
        ':',
        '(',
        ')',
        '%',
        '+',
        '/',
        '@',
        ' ',
        'a'...'z',
        'A'...'Z',
        '0'...'9',
        '_',
        '=',
        '-',
        '#',
        '{',
        '}',
        ',',
        '*',
        '!',
        '\'',
        '[',
        ']',
        '|',
        '?',
        '`',
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

fn isArrayOf(comptime T: type) fn (type) bool {
    const Closure = struct {
        pub fn trait(comptime C: type) bool {
            return switch (@typeInfo(C)) {
                .array => |ti| ti.child == T,
                else => false,
            };
        }
    };
    return Closure.trait;
}
