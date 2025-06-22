id: gllspcgd4fa2jblyp17dspjm6cww2s6eaelmr7dme5gyv3fn
name: pek
main: src/lib.zig
license: MPL-2.0
description: An HTML preprocessor with a builtin template engine.
dependencies:
  - src: git https://github.com/kivikakk/htmlentities.zig commit-bd5d569a245c7c8e83812eadcb5761b7ba76ef04
  - src: git https://github.com/nektro/zig-extras
  - src: git https://github.com/nektro/zig-tracer

root_dependencies:
  - src: git https://github.com/nektro/zig-expect
  - src: git https://github.com/nektro/zig-extras
