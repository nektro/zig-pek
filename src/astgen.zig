const std = @import("std");
const Token = @import("./tokenize.zig").Token;

const string = []const u8;

//
//

pub const Value = union(enum) {
    element: Element,
    attr: Attr,
    string: string,
    replacement: []const string,
    block: Block,
    function: Fn,
};

pub const Element = struct {
    name: string,
    attrs: []const Attr,
    children: []const Value,
};

pub const Attr = struct {
    key: string,
    value: string,
};

pub const Block = struct {
    name: Type,
    args: []const string,
    body: []const Value,

    pub const Type = enum {
        each,
        @"if",
        ifnot,
        ifequal,
        ifnotequal,
    };
};

pub const Fn = struct {
    name: string,
    args: []const string,
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
        switch (self.tokens[self.index]) {
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
        const v = self.eat(.string);
        return Attr{
            .key = k,
            .value = v,
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
        if (self.tokens[self.index] == .string) {
            return Value{ .string = self.eat(.string) };
        }
        if (self.tryEatSymbol("{")) {
            if (self.tryEatSymbol("#")) {
                const w = self.eat(.word);
                if (std.meta.stringToEnum(Block.Type, w)) |name| {
                    const args = self.doReplacement();
                    var children: []const Value = &.{};
                    while (!self.tryEatSymbol("/")) {
                        children = children ++ &[_]Value{self.doValue()};
                    }
                    std.debug.assert(std.mem.eql(u8, @tagName(name), self.eat(.word)));
                    self.eatSymbol("/");
                    return Value{ .block = Block{
                        .name = name,
                        .args = args,
                        .body = children,
                    } };
                }
                return Value{ .function = .{
                    .name = w,
                    .args = self.doReplacement(),
                } };
            }
            return Value{ .replacement = self.doReplacement() };
        }
        return Value{ .element = self.doElement() };
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

    fn eat(comptime self: *Parser, comptime typ: std.meta.Tag(Token)) string {
        defer self.index += 1;
        return @field(self.tokens[self.index], @tagName(typ));
    }
};
