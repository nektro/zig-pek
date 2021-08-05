# Pek

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
[src/main.zig](src/main.zig)

## Built With
- [Zig](https://github.com/ziglang/zig) master
- [Zigmod](https://github.com/nektro/zigmod) package manager

## Add me
```
$ zigmod aq add 1/nektro/pek
```

## License
AGPL-3.0
