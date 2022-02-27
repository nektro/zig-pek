const std = @import("std");
const pek = @import("pek");

const example_document =
    \\html[lang="en"](
    \\    head(
    \\        meta[charset="utf-8"]
    \\        title("Pek Example")
    \\        meta[name="viewport" content="width=device-width,initial-scale=1"]
    \\        meta[http-equiv="X-UA-Compatible" content="IE=edge"]
    \\    )
    \\    body(
    \\        h1("Pek Example")
    \\        hr
    \\        p("This is an example HTML document written in "a[href="https://github.com/nektro/zig-pek"]("Pek")".")
    \\        p("Pek is written by "{author}".")
    \\        p("Her favorite plant is the "{favorite.flower})
    \\        p("Hello, 世界")
    \\        p("The most populous US cities are:")
    \\        ul(
    \\            {#each top_cities}
    \\            li({this.name}", "{this.state.code})
    \\            /each/
    \\        )
    \\        p("Spooky text: "{spooky})
    \\
    \\        {#if am_i_a_girl}
    \\        p("#1")
    \\        /if/
    \\
    \\        {#ifnot is_it_my_birthday}
    \\        p("#2")
    \\        /ifnot/
    \\
    \\        {#ifequal top_cities.len best_rating}
    \\        p("#3")
    \\        /ifequal/
    \\
    \\        {#ifnotequal favorite.color sky}
    \\        p("#4")
    \\        /ifnotequal/
    \\    )
    \\)
;

const S = struct {
    name: []const u8,
    state: struct {
        code: []const u8,
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var name: []const u8 = "Meghan D";
    const doc = comptime pek.parse(example_document);
    try pek.compile(@This(), alloc, std.io.getStdOut().writer(), doc, .{
        .author = name,
        .favorite = .{
            .flower = "Sunflower",
            .program_lang = "Zig",
            .color = "Pink",
        },
        .top_cities = &[_]S{
            .{ .name = "New York", .state = .{ .code = "NY" } },
            .{ .name = "Los Angeles", .state = .{ .code = "CA" } },
            .{ .name = "Chicago", .state = .{ .code = "IL" } },
            .{ .name = "Houston", .state = .{ .code = "TX" } },
            .{ .name = "Phoenix", .state = .{ .code = "AZ" } },
        },
        .spooky = "<strong>I better not be in bold.</strong>",
        .am_i_a_girl = true,
        .sky = "Blue",
        .best_rating = @as(usize, 5),
        .is_it_my_birthday = false,
    });
}
