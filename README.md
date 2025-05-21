# Pek

![loc](https://sloc.xyz/github/nektro/zig-pek)
[![license](https://img.shields.io/github/license/nektro/zig-pek.svg)](https://github.com/nektro/zig-pek/blob/master/LICENSE)
[![nektro @ github sponsors](https://img.shields.io/badge/sponsors-nektro-purple?logo=github)](https://github.com/sponsors/nektro)
[![Zig](https://img.shields.io/badge/Zig-0.14-f7a41d)](https://ziglang.org/)
[![Zigmod](https://img.shields.io/badge/Zigmod-latest-f7a41d)](https://github.com/nektro/zigmod)

A comptime HTML preprocessor with a builtin template engine for Zig.

## Example Document

```fsharp
html[lang="en"](
    head(
        title("Pek Example")
        meta[charset="UTF-8"]
        meta[name="viewport" content="width=device-width,initial-scale=1"]
    )
    body(
        h1("Pek Example")
        hr
        p("This is an example HTML document written in "a[href="https://github.com/nektro/zig-pek"]("Pek")".")
    )
)
```

## Example Usage

See [test.zig](test.zig).
