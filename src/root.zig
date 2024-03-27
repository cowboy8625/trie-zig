const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Self = @This();
branch: std.ArrayList(*Node),
alloc: Allocator,

const Node = struct {
    alloc: Allocator,
    children: std.ArrayList(*Node),
    char: ?u8 = null,
    is_end: bool = false,

    fn init(alloc: Allocator) !*Node {
        const self = try alloc.create(Node);
        self.* = .{
            .alloc = alloc,
            .children = std.ArrayList(*Node).init(alloc),
        };
        return self;
    }

    fn deinit(self: *Node) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit();
        self.alloc.destroy(self);
    }

    fn insert(self: *Node, word: []const u8) !void {
        if (word.len == 0) {
            return;
        }
        if (self.char == null) {
            self.char = word[0];
        }
        if (word.len == 1) {
            self.is_end = true;
            return;
        }
        for (self.children.items) |child| {
            if (child.char == word[1]) {
                try child.insert(word[1..]);
                return;
            }
        }
        const child = try Node.init(self.alloc);
        errdefer child.deinit();
        try child.*.insert(word[1..]);
        try self.children.append(child);
    }

    fn contains(self: *const Node, word: []const u8) bool {
        if (self.char == null) {
            return false;
        }
        if (self.char) |c| if (c != word[0]) {
            return false;
        };
        if (self.char) |c| if (c == word[0] and self.is_end) {
            return true;
        };
        if (word.len == 1) {
            return false;
        }
        for (self.children.items) |child| {
            if (child.char == word[1]) {
                return child.contains(word[1..]);
            }
        }
        return false;
    }

    /// Up to user to free the returned list
    fn getMatches(
        self: *const Node,
        prefix: []const u8,
        list: *std.ArrayList([]const u8),
        word_builder: *[]u8,
        index: usize,
    ) !void {
        if (self.char) |c| if (prefix.len > index and c != prefix[index]) {
            return;
        };
        word_builder.*[index] = self.char.?;
        if (self.is_end) {
            // HACK: Pretty confedent I can unwrap this optional value
            word_builder.*[index] = self.char.?;
            const word = try self.alloc.dupe(u8, word_builder.*[0 .. index + 1]);
            try list.append(word);
        }

        for (self.children.items) |child| {
            try child.getMatches(prefix, list, word_builder, index + 1);
        }
    }
};

pub fn init(alloc: Allocator) Self {
    return .{
        .branch = std.ArrayList(*Self.Node).init(alloc),
        .alloc = alloc,
    };
}

pub fn deinit(self: Self) void {
    for (self.branch.items) |branch| {
        branch.deinit();
    }
    self.branch.deinit();
}

pub fn initFrom(alloc: Allocator, words: []const []const u8) !Self {
    var self = Self.init(alloc);
    errdefer self.deinit();
    for (words) |word| {
        try self.insert(word);
    }
    return self;
}

pub fn insert(self: *Self, word: []const u8) !void {
    if (word.len == 0) {
        return;
    }

    for (self.branch.items) |branch| {
        if (branch.char == word[0]) {
            try branch.insert(word);
            return;
        }
    }
    const branch = try Self.Node.init(self.alloc);
    errdefer branch.deinit();
    try branch.*.insert(word);
    try self.branch.append(branch);
}

pub fn contains(self: *const Self, word: []const u8) bool {
    for (self.branch.items) |branch| {
        if (branch.contains(word)) {
            return true;
        }
    }
    return false;
}

pub fn getMatches(
    self: *const Self,
    prefix: []const u8,
    list: *std.ArrayList([]const u8),
) !void {
    const length = 1024; // self.longestWord();
    var word = try self.alloc.alloc(u8, length);
    defer self.alloc.free(word);
    for (self.branch.items) |branch| {
        @memset(word, 0);
        try branch.getMatches(prefix, list, &word, 0);
    }
}

test "insert into node" {
    const alloc = std.testing.allocator;
    var trie = try Self.Node.init(alloc);
    defer trie.deinit();
    try trie.insert("hello");
    try trie.insert("hey");
    try testing.expect(trie.contains("hello"));
    try testing.expect(trie.contains("hey"));
}

test "initFrom into trie" {
    const alloc = std.testing.allocator;
    const myWords = [_][]const u8{ "hello", "hey", "hi", "howdy", "height" };
    const trie = try Self.initFrom(alloc, &myWords);
    defer trie.deinit();
    try testing.expect(trie.contains("hello"));
    try testing.expect(trie.contains("hey"));
    try testing.expect(trie.contains("hi"));
    try testing.expect(trie.contains("howdy"));
    try testing.expect(trie.contains("height"));
}

test "getMatches" {
    const alloc = std.testing.allocator;
    const myWords = [_][]const u8{ "hello", "hey", "hi", "howdy", "height" };
    const trie = try Self.initFrom(alloc, &myWords);
    defer trie.deinit();

    var list = std.ArrayList([]const u8).init(alloc);
    defer for (list.items) |w| {
        alloc.free(w);
    };
    defer list.deinit();

    try trie.getMatches("h", &list);
    try testing.expectEqual(@as(usize, 5), list.items.len);

    try testing.expectEqual("hi", list.items[0]);
    try testing.expectEqual("hey", list.items[1]);
    try testing.expectEqual("hello", list.items[2]);
    try testing.expectEqual("height", list.items[3]);
    try testing.expectEqual("howdy", list.items[4]);
}
