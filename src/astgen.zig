const std = @import("std");
const Token = @import("./tokenize.zig").Token;
const extras = @import("extras");

const string = []const u8;

//
//

pub const Value = union(enum) {
    element: Element,
    attr: Attr,
    string: string,
    replacement: Replacement,
    block: Block,
    body: Body,
    function: Fn,
};

pub const Element = struct {
    name: string,
    attrs: []const Attr,
    children: Body,
};

pub const Attr = struct {
    key: string,
    value: union(enum) { string: string, body: Body },
};

pub const Replacement = struct {
    arms: []const string,
    raw: bool = false,
};

pub const Block = struct {
    name: Type,
    func: ?string,
    args: []const Arg,
    body: Body,
    bttm: Body,

    pub const Type = enum {
        each,
        @"if",
        ifnot,
        ifequal,
        ifnotequal,
    };
};

pub const Body = []const Value;

pub const Fn = struct {
    name: string,
    raw: bool,
    args: []const Arg,
};

pub const Arg = union(enum) {
    lookup: []const string,
    plain: string,
    int: u64,
    value: []const Value,
};

//
//

pub fn do(comptime tokens: []const Token) Element {
    var parser = Parser{ .tokens = tokens, .index = 0 };
    return parser.doElement();
}

//
//

const Parser = struct {
    tokens: []const Token,
    index: usize,

    pub fn doElement(comptime self: *Parser) Element {
        return Element{
            .name = self.eat(.word),
            .attrs = self.doAttrs(),
            .children = self.doChildren(),
        };
    }

    pub fn doAttrs(comptime self: *Parser) []const Attr {
        var ret: []const Attr = &[_]Attr{};

        if (self.tryEatSymbol("[")) {
            inline while (true) {
                if (self.tryEatSymbol("]")) break;
                ret = ret ++ &[_]Attr{self.doAttr()};
            }
        }

        return ret;
    }

    fn tryEatSymbol(comptime self: *Parser, comptime needle: string) bool {
        if (self.index >= self.tokens.len) return false;
        switch (self.tokens[self.index].data) {
            .symbol => |sym| {
                if (std.mem.eql(u8, sym, needle)) {
                    self.index += 1;
                    return true;
                }
                return false;
            },
            else => {
                return false;
            },
        }
    }

    pub fn doAttr(comptime self: *Parser) Attr {
        const k = self.eat(.word);
        self.eatSymbol("=");
        const body = self.doChildren();
        if (body.len > 0) {
            return Attr{
                .key = k,
                .value = .{ .body = body },
            };
        }
        const v = self.eat(.string);
        return Attr{
            .key = k,
            .value = .{ .string = v },
        };
    }

    pub fn eatSymbol(comptime self: *Parser, comptime needle: string) void {
        std.debug.assert(std.mem.eql(u8, self.eat(.symbol), needle));
    }

    pub fn doChildren(comptime self: *Parser) []const Value {
        var ret: []const Value = &[_]Value{};

        if (self.tryEatSymbol("(")) {
            inline while (true) {
                if (self.tryEatSymbol(")")) break;
                ret = ret ++ &[_]Value{self.doValue()};
            }
        }

        return ret;
    }

    pub fn doValue(comptime self: *Parser) Value {
        if (self.tokens[self.index].data == .string) {
            return Value{ .string = self.eat(.string) };
        }
        if (self.tryEatSymbol("{")) {
            if (self.tryEatSymbol("#")) {
                const fraw = self.tryEatSymbol("#");
                const w = self.eat(.word);
                std.debug.assert(w.len > 0);
                std.debug.assert(w[0] != '_');
                if (std.meta.stringToEnum(Block.Type, w)) |name| {
                    const func = if (self.tryEatSymbol("#")) self.eat(.word) else null;
                    const args = self.doArgs();
                    var children: []const Value = &.{};
                    var bottom: []const Value = &.{};
                    var top = true;
                    while (!self.tryEatSymbol("/")) {
                        if (self.tryEatSymbol("<")) {
                            std.debug.assert(std.mem.eql(u8, "else", self.eat(.word)));
                            self.eatSymbol(">");
                            top = false;
                        }
                        if (top) {
                            children = children ++ &[_]Value{self.doValue()};
                        } else {
                            bottom = bottom ++ &[_]Value{self.doValue()};
                        }
                    }
                    std.debug.assert(std.mem.eql(u8, @tagName(name), self.eat(.word)));
                    self.eatSymbol("/");
                    return Value{ .block = Block{
                        .name = name,
                        .func = func,
                        .args = args,
                        .body = children,
                        .bttm = bottom,
                    } };
                }
                return Value{ .function = .{
                    .name = w,
                    .raw = fraw,
                    .args = self.doArgs(),
                } };
            }
            if (self.tryEatSymbol("{")) {
                defer self.eatSymbol("}");
                return Value{ .replacement = .{ .arms = self.doReplacement(), .raw = true } };
            }
            return Value{ .replacement = .{ .arms = self.doReplacement() } };
        }
        return Value{ .element = self.doElement() };
    }

    pub fn doArgs(comptime self: *Parser) []const Arg {
        var ret: []const Arg = &.{};
        var temp: []const string = &.{};
        while (!self.tryEatSymbol("}")) {
            if (self.nextIs(.string)) {
                if (temp.len > 0) {
                    ret = ret ++ &[_]Arg{.{ .lookup = temp }};
                    temp = &.{};
                }
                ret = ret ++ &[_]Arg{.{ .plain = self.eat(.string) }};
                continue;
            }
            if (self.tryEatSymbol("(")) {
                self.index -= 1;
                ret = ret ++ &[_]Arg{.{ .value = self.doChildren() }};
                continue;
            }
            if (temp.len == 0 and self.nextIs(.word)) {
                const next_word = self.eat(.word);
                if (extras.matchesAll(u8, next_word, std.ascii.isDigit)) {
                    ret = ret ++ &[_]Arg{.{ .int = std.fmt.parseUnsigned(u64, next_word, 10) catch unreachable }};
                    continue;
                }
                temp = temp ++ &[_]string{next_word};
            }
            if (self.tryEatSymbol(".")) {
                temp = temp ++ &[_]string{self.eat(.word)};
            } else {
                ret = ret ++ &[_]Arg{.{ .lookup = temp }};
                temp = &.{};
            }
        }
        if (temp.len > 0) ret = ret ++ &[_]Arg{.{ .lookup = temp }};
        return ret;
    }

    pub fn doReplacement(comptime self: *Parser) []const string {
        var ret: []const string = &.{};
        ret = ret ++ &[_]string{self.eat(.word)};
        while (!self.tryEatSymbol("}")) {
            self.eatSymbol(".");
            ret = ret ++ &[_]string{self.eat(.word)};
        }
        return ret;
    }

    fn eat(comptime self: *Parser, comptime typ: std.meta.Tag(Token.Data)) string {
        defer self.index += 1;
        const tok = self.tokens[self.index];
        const tag = std.meta.activeTag(tok.data);
        if (tag != typ) {
            @compileError(std.fmt.comptimePrint("pek: file:{d}:{d}: expected {s}, found {s}", .{ tok.line, tok.pos, @tagName(typ), @tagName(tag) }));
        }
        return @field(tok.data, @tagName(typ));
    }

    fn nextIs(comptime self: *Parser, comptime typ: std.meta.Tag(Token.Data)) bool {
        return self.tokens[self.index].data == typ;
    }
};
