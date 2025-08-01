const std = @import("std");
const Allocator = std.mem.Allocator;
const help_strings = @import("help_strings");
const actionpkg = @import("action.zig");
const SpecialCase = actionpkg.SpecialCase;

const list_fonts = @import("list_fonts.zig");
const help = @import("help.zig");
const version = @import("version.zig");
const list_keybinds = @import("list_keybinds.zig");
const list_themes = @import("list_themes.zig");
const list_colors = @import("list_colors.zig");
const list_actions = @import("list_actions.zig");
const ssh_cache = @import("ssh_cache.zig");
const edit_config = @import("edit_config.zig");
const show_config = @import("show_config.zig");
const validate_config = @import("validate_config.zig");
const crash_report = @import("crash_report.zig");
const show_face = @import("show_face.zig");
const boo = @import("boo.zig");
const new_window = @import("new_window.zig");

/// Special commands that can be invoked via CLI flags. These are all
/// invoked by using `+<action>` as a CLI flag. The only exception is
/// "version" which can be invoked additionally with `--version`.
pub const Action = enum {
    /// Output the version and exit
    version,

    /// Output help information for the CLI or configuration
    help,

    /// List available fonts
    @"list-fonts",

    /// List available keybinds
    @"list-keybinds",

    /// List available themes
    @"list-themes",

    /// List named RGB colors
    @"list-colors",

    /// List keybind actions
    @"list-actions",

    /// Manage SSH terminfo cache for automatic remote host setup
    @"ssh-cache",

    /// Edit the config file in the configured terminal editor.
    @"edit-config",

    /// Dump the config to stdout
    @"show-config",

    // Validate passed config file
    @"validate-config",

    // Show which font face Ghostty loads a codepoint from.
    @"show-face",

    // List, (eventually) view, and (eventually) send crash reports.
    @"crash-report",

    // Boo!
    boo,

    // Use IPC to tell the running Ghostty to open a new window.
    @"new-window",

    pub fn detectSpecialCase(arg: []const u8) ?SpecialCase(Action) {
        // If we see a "-e" and we haven't seen a command yet, then
        // we are done looking for commands. This special case enables
        // `ghostty -e ghostty +command`. If we've seen a command we
        // still want to keep looking because
        // `ghostty +command -e +command` is invalid.
        if (std.mem.eql(u8, arg, "-e")) return .abort_if_no_action;

        // Special case, --version always outputs the version no
        // matter what, no matter what other args exist.
        if (std.mem.eql(u8, arg, "--version")) {
            return .{ .action = .version };
        }

        // --help matches "help" but if a subcommand is specified
        // then we match the subcommand.
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return .{ .fallback = .help };
        }

        return null;
    }

    /// This should be returned by actions that want to print the help text.
    pub const help_error = error.ActionHelpRequested;

    /// Run the action. This returns the exit code to exit with.
    pub fn run(self: Action, alloc: Allocator) !u8 {
        return self.runMain(alloc) catch |err| switch (err) {
            // If help is requested, then we use some comptime trickery
            // to find this action in the help strings and output that.
            help_error => err: {
                inline for (@typeInfo(Action).@"enum".fields) |field| {
                    // Future note: for now we just output the help text directly
                    // to stdout. In the future we can style this much prettier
                    // for all commands by just changing this one place.

                    if (std.mem.eql(u8, field.name, @tagName(self))) {
                        const stdout = std.io.getStdOut().writer();
                        const text = @field(help_strings.Action, field.name) ++ "\n";
                        stdout.writeAll(text) catch |write_err| {
                            std.log.warn("failed to write help text: {}\n", .{write_err});
                            break :err 1;
                        };

                        break :err 0;
                    }
                }

                break :err err;
            },
            else => err,
        };
    }

    fn runMain(self: Action, alloc: Allocator) !u8 {
        return switch (self) {
            .version => try version.run(alloc),
            .help => try help.run(alloc),
            .@"list-fonts" => try list_fonts.run(alloc),
            .@"list-keybinds" => try list_keybinds.run(alloc),
            .@"list-themes" => try list_themes.run(alloc),
            .@"list-colors" => try list_colors.run(alloc),
            .@"list-actions" => try list_actions.run(alloc),
            .@"ssh-cache" => try ssh_cache.run(alloc),
            .@"edit-config" => try edit_config.run(alloc),
            .@"show-config" => try show_config.run(alloc),
            .@"validate-config" => try validate_config.run(alloc),
            .@"crash-report" => try crash_report.run(alloc),
            .@"show-face" => try show_face.run(alloc),
            .boo => try boo.run(alloc),
            .@"new-window" => try new_window.run(alloc),
        };
    }

    /// Returns the filename associated with an action. This is a relative
    /// path from the root src/ directory.
    pub fn file(comptime self: Action) []const u8 {
        comptime {
            const filename = filename: {
                const tag = @tagName(self);
                var filename: [tag.len]u8 = undefined;
                _ = std.mem.replace(u8, tag, "-", "_", &filename);
                break :filename &filename;
            };

            return "cli/" ++ filename ++ ".zig";
        }
    }

    /// Returns the options of action. Supports generating shell completions
    /// without duplicating the mapping from Action to relevant Option
    /// @import(..) declaration.
    pub fn options(comptime self: Action) type {
        comptime {
            return switch (self) {
                .version => version.Options,
                .help => help.Options,
                .@"list-fonts" => list_fonts.Options,
                .@"list-keybinds" => list_keybinds.Options,
                .@"list-themes" => list_themes.Options,
                .@"list-colors" => list_colors.Options,
                .@"list-actions" => list_actions.Options,
                .@"ssh-cache" => ssh_cache.Options,
                .@"edit-config" => edit_config.Options,
                .@"show-config" => show_config.Options,
                .@"validate-config" => validate_config.Options,
                .@"crash-report" => crash_report.Options,
                .@"show-face" => show_face.Options,
                .boo => boo.Options,
                .@"new-window" => new_window.Options,
            };
        }
    }
};

test "parse action none" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var iter = try std.process.ArgIteratorGeneral(.{}).init(
        alloc,
        "--a=42 --b --b-f=false",
    );
    defer iter.deinit();
    const action = try actionpkg.detectIter(Action, &iter);
    try testing.expect(action == null);
}

test "parse action version" {
    const testing = std.testing;
    const alloc = testing.allocator;

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--a=42 --b --b-f=false --version",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--version --a=42 --b --b-f=false",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--c=84 --d --version --a=42 --b --b-f=false",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }
}

test "parse action plus" {
    const testing = std.testing;
    const alloc = testing.allocator;

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--a=42 --b --b-f=false +version",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "+version --a=42 --b --b-f=false",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--c=84 --d +version --a=42 --b --b-f=false",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }
}

test "parse action plus ignores -e" {
    const testing = std.testing;
    const alloc = testing.allocator;

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--a=42 -e +version",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action == null);
    }

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "+list-fonts --a=42 -e +version",
        );
        defer iter.deinit();
        try testing.expectError(
            actionpkg.DetectError.MultipleActions,
            actionpkg.detectIter(Action, &iter),
        );
    }
}
