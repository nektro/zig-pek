const std = @import("std");
const Token = @import("./tokenize.zig").Token;

//
//

pub const Value = union(enum) {
    element: Element,
    attr: Attr,
    string: []const u8,
};

pub const Element = struct {
    name: []const u8,
    attrs: []const Attr,
    children: []const Value,
};

pub const Attr = struct {
    key: []const u8,
    value: []const u8,
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

    fn tryEatSymbol(comptime self: *Parser, comptime needle: []const u8) bool {
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

    pub fn eatSymbol(comptime self: *Parser, comptime needle: []const u8) void {
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
        return Value{ .element = self.doElement() };
    }

    fn eat(comptime self: *Parser, comptime typ: std.meta.Tag(Token)) []const u8 {
        defer self.index += 1;
        return @field(self.tokens[self.index], @tagName(typ));
    }
};
