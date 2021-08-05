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
    \\    )
    \\)
;

pub fn main() !void {
    std.log.info("All your codebase are belong to us.", .{});
    std.debug.print("\n", .{});

    const doc = comptime pek.parse(example_document);
    try pek.compile(std.io.getStdErr().writer(), doc, .{}, 0, false);
    std.debug.print("\n", .{});
}
