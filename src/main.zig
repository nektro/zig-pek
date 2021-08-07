const std = @import("std");
const pek = @import("pek");

const example_document =
    \\html[lang="en"](
    \\    head(
    \\        meta[charset="utf-8"]
    \\        title("Pek Example")
    \\        meta[name="viewport" content="width=device-width,initial-scale=1"]
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
    \\    )
    \\)
;

pub fn main() !void {
    const doc = comptime pek.parse(example_document);
    try pek.compile(std.io.getStdOut().writer(), doc, .{
        .author = "Meghan D",
        .favorite = .{
            .flower = "Sunflower",
        },
        .top_cities = .{
            .{ .name = "New York", .state = .{ .code = "NY" } },
            .{ .name = "Los Angeles", .state = .{ .code = "CA" } },
            .{ .name = "Chicago", .state = .{ .code = "IL" } },
            .{ .name = "Houston", .state = .{ .code = "TX" } },
            .{ .name = "Phoenix", .state = .{ .code = "AZ" } },
        },
        .spooky = "<strong>I better not be in bold.</strong>",
    });
}
