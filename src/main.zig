const std = @import("std");

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

const color = struct {
    const red = "\x1B[31m";
    const green = "\x1B[32m";
    const yellow = "\x1B[33m";
    const blue = "\x1B[34m";
    const purple = "\x1B[35m";
    const cyan = "\x1B[36m";
    const reset = "\x1B[m";
};

var input: Input = undefined;
var persistent_strings: StrBuf = undefined;
var temp_strings: StrBuf = undefined;

const indentation_source = "                ";
var indentation_level: usize = 0;
fn indent() void {
    indentation_level += 1;
}
fn dedent() void {
    indentation_level -= 1;
}
fn indentation() []const u8 {
    return indentation_source[0..(indentation_level * 2)];
}

fn print_bytes(bytes: []const u8) !void {
    for (bytes) |byte| {
        try stdout.writeByte(byte);
        if (byte == '\n') {
            std.time.sleep(100 * std.time.ns_per_ms);
        } else {
            std.time.sleep(10 * std.time.ns_per_ms);
        }
    }
}

const StrBuilder = struct {
    const Self = @This();

    str_buf: *StrBuf,
    start: usize,

    fn init(str_buf: *StrBuf) StrBuilder {
        return StrBuilder{
            .str_buf = str_buf,
            .start = str_buf.at,
        };
    }

    fn append(self: *Self, str: []const u8) void {
        _ = self.str_buf.copy_from(str);
    }

    fn append_fmt(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        _ = try self.str_buf.fmt(fmt, args);
    }

    fn consume(self: Self) []const u8 {
        return self.str_buf.slice(self.start, self.str_buf.at);
    }
};

fn plf(comptime fmt: []const u8, args: anytype) !void {
    var sb = temp_strings.builder();
    sb.append(indentation());
    try sb.append_fmt(fmt, args);
    sb.append("\n");
    try print_bytes(sb.consume());
}

fn prf(comptime fmt: []const u8, args: anytype) !void {
    var sb = temp_strings.builder();
    sb.append(indentation());
    try sb.append_fmt(fmt, args);
    try print_bytes(sb.consume());
}

fn pl(msg: []const u8) !void {
    var sb = temp_strings.builder();
    sb.append(indentation());
    sb.append(msg);
    sb.append("\n");
    try print_bytes(sb.consume());
}

fn pr(msg: []const u8) !void {
    var sb = temp_strings.builder();
    sb.append(indentation());
    sb.append(msg);
    try print_bytes(sb.consume());
}

const Input = struct {
    const Self = @This();

    buf: []u8 = undefined,

    fn init() !Self {
        return Self{
            .buf = try std.heap.page_allocator.alignedAlloc(
                u8,
                std.mem.page_size,
                std.mem.page_size,
            ),
        };
    }

    fn read(self: *Self) ![]const u8 {
        const len = try stdin.read(self.buf);
        return self.buf[0..len];
    }
};

const EntityId = struct {
    v: u16,
};

const Player = struct {
    id: EntityId,
    name: []const u8,
    hp: i16,
    damage: i16,
    armor: i16,
    mana: i16,
    command: Command,

    fn hp_str() []const u8 {}
};

const Game = struct {
    turn: u64,
    entities: [2]Player,
};

const HealCommand = struct {
    amount: u8,
};

const HitCommand = struct {
    target: EntityId,
};

const Command = union(enum) {
    exit: void,
    hit: HitCommand,
    heal: HealCommand,
};

const StrBuf = struct {
    buf: []u8,
    at: usize,

    fn builder(self: *StrBuf) StrBuilder {
        return StrBuilder.init(self);
    }

    fn read_stdin(self: *StrBuf) ![]const u8 {
        const raw = try input.read();
        const no_newline = raw[0..(raw.len - "\n".len)];
        return self.copy_from(no_newline);
    }

    /// returns the owned string
    fn fmt(self: *StrBuf, comptime fmt_str: []const u8, args: anytype) ![]const u8 {
        var buf = std.io.fixedBufferStream(self.buf[self.at..]);
        const w = buf.writer();
        try std.fmt.format(w, fmt_str, args);
        const len = w.context.pos;
        const next = self.at + len;
        std.debug.assert(next < self.buf.len);
        const result = self.buf[self.at..next];
        self.at = next;
        return result;
    }

    /// returns the owned string
    fn copy_from(self: *StrBuf, src: []const u8) []const u8 {
        const next = self.at + src.len;
        std.debug.assert(next <= self.buf.len);
        const result = self.buf[self.at..next];
        @memcpy(result, src);
        self.at = next;
        return result;
    }

    fn slice(self: *const StrBuf, start: usize, end: usize) []const u8 {
        return self.buf[start..end];
    }

    fn reset(self: *StrBuf) void {
        self.at = 0;
    }
};

fn streq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn parse_entity_id(game: *const Game, token: []const u8) ?EntityId {
    for (game.entities) |p| {
        if (streq(p.name, token)) {
            return p.id;
        }
    }

    const id_v = std.fmt.parseInt(u16, token, 10) catch return null;

    for (game.entities) |p| {
        if (p.id.v == id_v) {
            return p.id;
        }
    }

    return null;
}

fn read_command_retry(game: *const Game) !Command {
    while (true) {
        const raw = try input.read();
        var tokens = std.mem.zeroes([4][]const u8);

        // parse
        {
            var token_index: usize = 0;

            var token_start: usize = 0;

            var char_index: usize = 0;
            while (char_index < raw.len and token_index < tokens.len) {
                const c = raw[char_index];
                if (c == ' ' or c == '\n') {
                    if (token_start != char_index) {
                        tokens[token_index] = raw[token_start..char_index];
                        token_index += 1;
                    } else {
                        // skip over repeated whitespace
                    }
                    token_start = char_index + 1;
                }
                char_index += 1;
            }
        }

        if (streq(tokens[0], "exit")) {
            return Command.exit;
        }

        if (streq(tokens[0], "hit")) {
            if (parse_entity_id(game, tokens[1])) |id| {
                return Command{
                    .hit = HitCommand{
                        .target = id,
                    },
                };
            }
        }

        if (streq(tokens[0], "heal")) {
            const heal_amount = try std.fmt.parseInt(u8, tokens[1], 10);
            return Command{
                .heal = HealCommand{
                    .amount = heal_amount,
                },
            };
        }

        try pr("Invalid command, try again: ");
    }
}

fn print_status(game: *Game) !void {
    try pl("Status");
    {
        indent();
        defer dedent();

        try pl("name      entity  health  damage   armor    mana");
        for (game.entities) |p| {
            const name = try temp_strings.fmt("{s}{s:<8}{s}", .{ color.purple, p.name, color.reset });
            const entity = try temp_strings.fmt("{s}{:>8}{s}", .{ color.cyan, p.id.v, color.reset });
            const hp = try temp_strings.fmt("{s}{:>8}{s}", .{ color.red, p.hp, color.reset });
            const damage = try temp_strings.fmt("{s}{:>8}{s}", .{ color.yellow, p.damage, color.reset });
            const armor = try temp_strings.fmt("{s}{:>8}{s}", .{ color.green, p.armor, color.reset });
            const mana = try temp_strings.fmt("{s}{:>8}{s}", .{ color.blue, p.mana, color.reset });
            try plf("{s}{s}{s}{s}{s}{s}", .{
                name,
                entity,
                hp,
                damage,
                armor,
                mana,
            });
        }
    }
}

fn game_step(game: *Game) !bool {
    try pl("");
    try plf("Turn {}", .{game.turn});
    defer game.turn += 1;
    defer temp_strings.reset();

    {
        indent();
        defer dedent();

        try print_status(game);

        try pl("Input");
        for (&game.entities) |*p| {
            indent();
            defer dedent();
            try prf("{s}: ", .{p.name});
            p.command = try read_command_retry(game);
            if (p.command == Command.exit) {
                try pl("Exiting...");
                return false;
            }
        }

        try pl("Battle phase");
        std.time.sleep(1000 * std.time.ns_per_ms);
        {
            indent();
            defer dedent();
            for (&game.entities) |*p| {
                try pl(p.name);
                indent();
                defer dedent();
                switch (p.command) {
                    Command.exit => {
                        return false;
                    },
                    Command.hit => |cmd| {
                        const target = &game.entities[cmd.target.v - 1];
                        const dmg = @max(p.damage - target.armor, 0);
                        target.hp -= dmg;
                        try plf("Hit {s} with {s}{}{s} dmg.", .{
                            target.name,
                            color.yellow,
                            dmg,
                            color.reset,
                        });
                    },
                    Command.heal => |cmd| {
                        const max_hp = 10;
                        const max_heal = max_hp - p.hp;
                        const amount = @min(p.mana, cmd.amount, max_heal);
                        p.hp += amount;
                        p.mana -= amount;
                        try plf("Healed {s}{}{s} hp.", .{
                            color.red,
                            amount,
                            color.reset,
                        });
                    },
                }
            }
        }

        // events
        for (game.entities) |p| {
            if (p.hp <= 0) {
                try plf("{s} died.", .{p.name});
                return false;
            }
        }

        try pl("Recovery phase");
        std.time.sleep(1000 * std.time.ns_per_ms);
        {
            indent();
            defer dedent();
            for (&game.entities) |*p| {
                try pl(p.name);
                indent();
                defer dedent();
                const mana_recovery = @min(1, 10 - p.mana);
                p.mana += mana_recovery;
                if (mana_recovery < 0) {
                    try plf("Lost {s}{}{s} mana.", .{
                        color.blue,
                        -mana_recovery,
                        color.reset,
                    });
                } else if (mana_recovery > 0) {
                    try plf("Recovered {s}{}{s} mana.", .{
                        color.blue,
                        mana_recovery,
                        color.reset,
                    });
                }
            }
        }
    }

    return true;
}

pub fn main() !void {
    input = try Input.init();
    temp_strings = StrBuf{
        .buf = try std.heap.page_allocator.alignedAlloc(
            u8,
            std.mem.page_size,
            std.mem.page_size,
        ),
        .at = 0,
    };
    persistent_strings = StrBuf{
        .buf = try std.heap.page_allocator.alignedAlloc(
            u8,
            std.mem.page_size,
            128,
        ),
        .at = 0,
    };

    try pr("Player 1, enter your name: ");
    const p1_name = try persistent_strings.read_stdin();
    try pr("Player 2, enter your name: ");
    const p2_name = try persistent_strings.read_stdin();

    var game = Game{
        .turn = 1,
        .entities = .{
            Player{
                .id = EntityId{ .v = 1 },
                .name = p1_name,
                .hp = 10,
                .damage = 2,
                .armor = 1,
                .mana = 5,
                .command = undefined,
            },
            Player{
                .id = EntityId{ .v = 2 },
                .name = p2_name,
                .hp = 1,
                .damage = 3,
                .armor = 1,
                .mana = 2,
                .command = undefined,
            },
        },
    };

    while (try game_step(&game)) {}

    try pl("Game over.");
}
