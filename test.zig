const std = @import("std");
const pek = @import("pek");
const expect = @import("expect").expect;
const extras = @import("extras");

test {
    std.testing.refAllDeclsRecursive(pek);
}

test "document" {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\html[lang="en"](
        \\    head(
        \\        title("Pek Example")
        \\        meta[charset="UTF-8"]
        \\        meta[name="viewport" content="width=device-width,initial-scale=1"]
        \\    )
        \\    body(
        \\        h1("Pek Example")
        \\        hr
        \\        p("This is an example HTML document written in "a[href="https://github.com/nektro/zig-pek"]("Pek")".")
        \\    )
        \\)
    );
    try pek.compile(
        @This(),
        alloc,
        builder.writer(),
        doc,
        .{},
    );
    try expect(builder.items).toEqualString(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\    <head>
        \\        <title>Pek Example</title>
        \\        <meta charset="UTF-8" />
        \\        <meta name="viewport" content="width=device-width,initial-scale=1" />
        \\    </head>
        \\    <body>
        \\        <h1>Pek Example</h1>
        \\        <hr />
        \\        <p>This is an example HTML document written in <a href="https://github.com/nektro/zig-pek">Pek</a>.</p>
        \\    </body>
        \\</html>
        \\
    );
}

test "apostrophe attribute string" {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\html[lang="en"](
        \\    head(
        \\        title("Pek Example")
        \\        meta[charset="UTF-8"]
        \\        meta[name="viewport" content="width=device-width,initial-scale=1"]
        \\        meta[name="htmx-config" content='{"includeIndicatorStyles":false}']
        \\    )
        \\)
    );
    try pek.compile(
        @This(),
        alloc,
        builder.writer(),
        doc,
        .{},
    );
    try expect(builder.items).toEqualString(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\    <head>
        \\        <title>Pek Example</title>
        \\        <meta charset="UTF-8" />
        \\        <meta name="viewport" content="width=device-width,initial-scale=1" />
        \\        <meta name="htmx-config" content='{"includeIndicatorStyles":false}' />
        \\    </head>
        \\</html>
        \\
    );
}

test "fragment" {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    h1("Pek Example")
        \\    hr
        \\    p("This is an example HTML document written in "a[href="https://github.com/nektro/zig-pek"]("Pek")".")
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{},
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <h1>Pek Example</h1>
        \\    <hr />
        \\    <p>This is an example HTML document written in <a href="https://github.com/nektro/zig-pek">Pek</a>.</p>
        \\</body>
        \\
    );
}

test "if: basic" {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    h1("Pek Example")
        \\    hr
        \\    {#if foo}
        \\    p("This is an example HTML document written in "a[href="https://github.com/nektro/zig-pek"]("Pek")".")
        \\    /if/
        \\    {#if bar}
        \\    p("This will show up because "code("bar")" is true instead.")
        \\    /if/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .foo = false, .bar = true },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <h1>Pek Example</h1>
        \\    <hr />
        \\    <p>This will show up because <code>bar</code> is true instead.</p>
        \\</body>
        \\
    );
}

test "if: optional" {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const foo: ?u8 = null;
    const bar: ?u8 = 24;
    const doc = comptime pek.parse(
        \\body(
        \\    h1("Pek Example")
        \\    hr
        \\    {#if foo}
        \\    p("This is an example HTML document written in "a[href="https://github.com/nektro/zig-pek"]("Pek")".")
        \\    /if/
        \\    {#if bar}
        \\    p("This will show up because "code("bar")" is non-null instead.")
        \\    /if/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .foo = foo, .bar = bar },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <h1>Pek Example</h1>
        \\    <hr />
        \\    <p>This will show up because <code>bar</code> is non-null instead.</p>
        \\</body>
        \\
    );
}

// if else
test "if else + field access" {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#if bar.qux}
        \\    p("This will show up because "code("bar")" is true.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is false.")
        \\    /if/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = .{ .qux = false } },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is false.</p>
        \\</body>
        \\
    );
}

// ifnot
test {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifnot bar}
        \\    p("This will show up because "code("bar")" is false.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is true.")
        \\    /ifnot/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = true },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is true.</p>
        \\</body>
        \\
    );
}
test {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifnot bar}
        \\    p("This will show up because "code("bar")" is false.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is true.")
        \\    /ifnot/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = false },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is false.</p>
        \\</body>
        \\
    );
}
// ifnot optional
test {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const foo: ?u8 = null;
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifnot foo}
        \\    p("This will show up because "code("foo")" is null.")
        \\    <else>
        \\    p("This will show up because "code("foo")" is non-null.")
        \\    /ifnot/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .foo = foo },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>foo</code> is null.</p>
        \\</body>
        \\
    );
}

// ifequal
test { // bool
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifequal bar true}
        \\    p("This will show up because "code("bar")" is true.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is false.")
        \\    /ifequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = true },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is true.</p>
        \\</body>
        \\
    );
}
test { // bool false
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifequal bar true}
        \\    p("This will show up because "code("bar")" is true.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is false.")
        \\    /ifequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = false },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is false.</p>
        \\</body>
        \\
    );
}
test { // string
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifequal bar "foo"}
        \\    p("This will show up because "code("bar")" is 'foo'.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is 'qux'.")
        \\    /ifequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = @as([]const u8, "foo") },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is 'foo'.</p>
        \\</body>
        \\
    );
}
test { // string false
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifequal bar "foo"}
        \\    p("This will show up because "code("bar")" is 'foo'.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is 'qux'.")
        \\    /ifequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = @as([]const u8, "qux") },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is 'qux'.</p>
        \\</body>
        \\
    );
}
test { // enum
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifequal bar "foo"}
        \\    p("This will show up because "code("bar")" is .foo.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is .qux.")
        \\    /ifequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = @as(enum { foo, bar, qux }, .foo) },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is .foo.</p>
        \\</body>
        \\
    );
}
test { // enum false
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifequal bar "foo"}
        \\    p("This will show up because "code("bar")" is .foo.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is .qux.")
        \\    /ifequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = @as(enum { foo, bar, qux }, .qux) },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is .qux.</p>
        \\</body>
        \\
    );
}

// ifnotequal
test { // bool
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifnotequal bar true}
        \\    p("This will show up because "code("bar")" is false.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is true.")
        \\    /ifnotequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = false },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is false.</p>
        \\</body>
        \\
    );
}
test { // bool false
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifnotequal bar true}
        \\    p("This will show up because "code("bar")" is false.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is true.")
        \\    /ifnotequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = true },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is true.</p>
        \\</body>
        \\
    );
}
test { // string
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifnotequal bar "foo"}
        \\    p("This will show up because "code("bar")" is 'qux'.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is 'foo'.")
        \\    /ifnotequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = @as([]const u8, "qux") },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is 'qux'.</p>
        \\</body>
        \\
    );
}
test { // string false
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifnotequal bar "foo"}
        \\    p("This will show up because "code("bar")" is 'qux'.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is 'foo'.")
        \\    /ifnotequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = @as([]const u8, "foo") },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is 'foo'.</p>
        \\</body>
        \\
    );
}
test { // enum
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifnotequal bar "foo"}
        \\    p("This will show up because "code("bar")" is .qux.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is .foo.")
        \\    /ifnotequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = @as(enum { foo, bar, qux }, .qux) },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is .qux.</p>
        \\</body>
        \\
    );
}
test { // enum false
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    {#ifnotequal bar "foo"}
        \\    p("This will show up because "code("bar")" is .qux.")
        \\    <else>
        \\    p("This will show up because "code("bar")" is .foo.")
        \\    /ifnotequal/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .bar = @as(enum { foo, bar, qux }, .foo) },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This will show up because <code>bar</code> is .foo.</p>
        \\</body>
        \\
    );
}

// replacement
test {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    p("This text for this link is "a[href="https://github.com/nektro/zig-pek"]({text})".")
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .text = @as([]const u8, "dynamic") },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This text for this link is <a href="https://github.com/nektro/zig-pek">dynamic</a>.</p>
        \\</body>
        \\
    );
}
test {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    p("This url for this link is "a[href=({url})]("dynamic")".")
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .url = @as([]const u8, "https://github.com/nektro/zig-pek") },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This url for this link is <a href="https://github.com/nektro/zig-pek">dynamic</a>.</p>
        \\</body>
        \\
    );
}
test {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    p("This host for this link is "a[href=("https://"{host}"/nektro/zig-pek")]("dynamic")".")
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .host = @as([]const u8, "github.com") },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This host for this link is <a href="https://github.com/nektro/zig-pek">dynamic</a>.</p>
        \\</body>
        \\
    );
}
test {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    p("This host for this link is "a[href=("https://"{host}"/nektro/zig-pek")]("dynamic")".")
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .host = "github.com".* },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This host for this link is <a href="https://github.com/nektro/zig-pek">dynamic</a>.</p>
        \\</body>
        \\
    );
}

// replacement with custom serializer
test {
    const S = struct {
        name: []const u8,

        pub fn format(s: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.writeAll(s.name);
            try writer.writeAll(".com");
        }
    };
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    p("This host for this link is "a[href=("https://"{host}"/nektro/zig-pek")]("dynamic")".")
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .host = S{ .name = "github" } },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This host for this link is <a href="https://github.com/nektro/zig-pek">dynamic</a>.</p>
        \\</body>
        \\
    );
}
test {
    const S = struct {
        name: []const u8,

        pub fn toString(s: @This(), alloc: std.mem.Allocator) ![]const u8 {
            return std.fmt.allocPrint(alloc, "{s}.com", .{s.name});
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    p("This host for this link is "a[href=("https://"{host}"/nektro/zig-pek")]("dynamic")".")
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .host = S{ .name = "github" } },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This host for this link is <a href="https://github.com/nektro/zig-pek">dynamic</a>.</p>
        \\</body>
        \\
    );
}

// raw replacement
test {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    p("This url for this link is "a[href=({{url}})]("dynamic but not escaped")".")
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .url = "https://github.com/nektro/zig-pek".* },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>This url for this link is <a href="https://github.com/nektro/zig-pek">dynamic but not escaped</a>.</p>
        \\</body>
        \\
    );
}
test {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const doc = comptime pek.parse(
        \\body(
        \\    p("Raw replacements can also "{{foo}}".")
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .foo = "contain HTML such as <button>this</button> as an escape hatch when you know content is safe".* },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>Raw replacements can also contain HTML such as <button>this</button> as an escape hatch when you know content is safe.</p>
        \\</body>
        \\
    );
}

// custom function
test {
    const C = struct {
        pub fn pek__input_text(alloc: std.mem.Allocator, writer: pek.Writer, comptime opts: pek.DoOptions, args: struct { []const u8, []const u8, []const u8, []const u8 }) !void {
            const tmpl = comptime pek.parse(
                \\label(
                \\    div({label})
                \\    textarea[type="text" required="" name=({name}) placeholder=({placeholder})]({value})
                \\)
            );
            try pek.compileInner(alloc, writer, tmpl, opts, .{
                .name = args[0],
                .label = args[1],
                .value = args[2],
                .placeholder = args[3],
            });
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    var person: struct { name: []const u8 } = .{ .name = "meghan" };
    _ = &person;
    const doc = comptime pek.parse(
        \\body(
        \\    form(
        \\        {##input_text "name" "Name" prev.name ""}
        \\        button("Submit ▶")
        \\    )
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = C, .indent = 0, .doindent = true, .doindent2 = true },
        .{ .prev = person },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <form>
        \\        <label>
        \\            <div>Name</div>
        \\            <textarea type="text" required="" name="name" placeholder="">meghan</textarea>
        \\        </label>
        \\        <button>Submit ▶</button>
        \\    </form>
        \\</body>
        \\
    );
}

// custom bool function
test {
    const S = struct {
        id: u64,
    };
    const C = struct {
        pub fn pek_is_admin(alloc: std.mem.Allocator, user: S) !bool {
            _ = alloc;
            return user.id < 10;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    var person: S = .{ .id = 0 };
    _ = &person;
    const doc = comptime pek.parse(
        \\body(
        \\    {#if#is_admin user}
        \\    p("only an admin user can see this")
        \\    <else>
        \\    p("unauthorized users will see this")
        \\    /if/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = C, .indent = 0, .doindent = true, .doindent2 = true },
        .{ .user = person },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>only an admin user can see this</p>
        \\</body>
        \\
    );
}
test {
    const S = struct {
        id: u64,
    };
    const C = struct {
        pub fn pek_is_admin(alloc: std.mem.Allocator, user: S) !bool {
            _ = alloc;
            return user.id < 10;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    var person: S = .{ .id = 25 };
    _ = &person;
    const doc = comptime pek.parse(
        \\body(
        \\    {#if#is_admin user}
        \\    p("only an admin user can see this")
        \\    <else>
        \\    p("unauthorized users will see this")
        \\    /if/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = C, .indent = 0, .doindent = true, .doindent2 = true },
        .{ .user = person },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>unauthorized users will see this</p>
        \\</body>
        \\
    );
}

// each
test {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const S = struct {
        abbr: []const u8,
        name: []const u8,
        index: u8,
    };
    const states = [_]S{
        .{ .abbr = "MA", .name = "Massachusetts", .index = 0 },
        .{ .abbr = "OR", .name = "Oregon", .index = 0 },
        .{ .abbr = "CA", .name = "California", .index = 0 },
    };
    const doc = comptime pek.parse(
        \\body(
        \\    {#each states}
        \\    p("The US state '"{this.name}"' can be shortened to '"{this.abbr}"'.")
        \\    /each/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .states = &states },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>The US state 'Massachusetts' can be shortened to 'MA'.</p>
        \\    <p>The US state 'Oregon' can be shortened to 'OR'.</p>
        \\    <p>The US state 'California' can be shortened to 'CA'.</p>
        \\</body>
        \\
    );
}

// multi-each
test {
    const alloc = std.testing.allocator;
    var builder = std.ArrayList(u8).init(alloc);
    defer builder.deinit();
    const S = struct {
        abbr: []const u8,
        name: []const u8,
        index: u8,
    };
    const states = extras.StaticMultiList(S).initComptime(&[_]S{
        .{ .abbr = "MA", .name = "Massachusetts", .index = 0 },
        .{ .abbr = "OR", .name = "Oregon", .index = 0 },
        .{ .abbr = "CA", .name = "California", .index = 0 },
    });
    const doc = comptime pek.parse(
        \\body(
        \\    {#each abbrs names}
        \\    p("The US state '"{that}"' can be shortened to '"{this}"'.")
        \\    /each/
        \\)
    );
    try pek.compileInner(
        alloc,
        builder.writer(),
        doc,
        .{ .Ctx = @This(), .indent = 0, .doindent = true, .doindent2 = true },
        .{ .abbrs = states.items.abbr, .names = states.items.name },
    );
    try expect(builder.items).toEqualString(
        \\<body>
        \\    <p>The US state 'Massachusetts' can be shortened to 'MA'.</p>
        \\    <p>The US state 'Oregon' can be shortened to 'OR'.</p>
        \\    <p>The US state 'California' can be shortened to 'CA'.</p>
        \\</body>
        \\
    );
}
