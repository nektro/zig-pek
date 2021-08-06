const std = @import("std");
const pek = @import("pek");

const example_document =
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
    \\        p("Pek is written by "{author}".")
    \\        p("Her favorite plant is the "{favorite.flower})
    \\        br
    \\        p("The most populous US cities are:")
    \\        ul(
    \\            {#each top_cities}
    \\            li({name})
    \\            /each/
    \\        )
    \\    )
    \\)
;

pub fn main() !void {
    std.log.info("All your codebase are belong to us.", .{});
    std.debug.print("\n", .{});

    const doc = comptime pek.parse(example_document);
    try pek.compile(std.io.getStdErr().writer(), doc, .{
        .author = "Meghan D",
        .favorite = .{
            .flower = "Sunflower",
        },
        .top_cities = .{
            .{ .name = "New York" },
            .{ .name = "Los Angeles" },
            .{ .name = "Chicago" },
            .{ .name = "Houston" },
            .{ .name = "Phoenix" },
        },
    });
    std.debug.print("\n", .{});
}
