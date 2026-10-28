import Foundation

/// The Windows themes' Terminal profile opens zsh with a Command Prompt prompt: /Users/maik/src
/// reads `C:\Users\maik\src>`. zsh starts with ZDOTDIR pointing at a folder of RetroMac's own whose
/// startup files source the user's (from their usual place, in zsh's usual order, unchanged) and
/// only then set the prompt. Nothing in the user's home is edited.
///
/// After macOS 7 Ultimate SP1's cmd-zsh (github.com/kaganisildak/macOS-7-Ultimate-SP1, GPL-3.0).
enum CmdPrompt {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroMac/cmd-zsh")
    }

    /// The user's login shell, from the user database.
    static var loginShell: String {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return "" }
        return String(cString: shell)
    }

    /// The profile keys that start zsh this way, or nil when the login shell is not zsh or the
    /// folder could not be written: then the profile opens the login shell as usual.
    static func profileKeys() -> [String: Any]? {
        let shell = loginShell
        guard (shell as NSString).lastPathComponent == "zsh", install() else { return nil }
        // RunCommandAsShell false: with "run inside shell" Terminal splits the command at blanks.
        // ZDOTDIR only while the folder is there, so a profile left behind still opens a normal shell.
        let script = "[ -r \"$1/.zshenv\" ] && export ZDOTDIR=\"$1\"; exec \"$2\" -l"
        return [
            "CommandString": "/usr/bin/env /bin/sh -c \(quoted(script)) sh \(quoted(folder.path)) \(quoted(shell))",
            "RunCommandAsShell": false,
            // Started with a command, Terminal would ask before closing a window with a bare shell in it.
            "noWarnProcesses": ["login", "sh", "-sh", "zsh", "-zsh", "bash", "-bash", "screen", "tmux"]
                .map { ["ProcessName": $0] },
        ]
    }

    static func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    @discardableResult
    static func install(into folder: URL = folder) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, text) in files {
                let url = folder.appendingPathComponent(name)
                if (try? String(contentsOf: url, encoding: .utf8)) != text {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                }
            }
            return true
        } catch {
            print("[CmdPrompt] Could not write \(folder.path): \(error)")
            return false
        }
    }

    static let files: [(String, String)] = [
        ("retromac-cmd.zsh", support),
        (".zshenv", """
        # RetroMac Command Prompt: runs the user's own ~/.zshenv.
        source "$ZDOTDIR/retromac-cmd.zsh"
        rm_cmd_enter .zshenv && source "$REPLY"; rm_cmd_leave
        [[ -o interactive || -o login ]] || rm_cmd_finish

        """),
        (".zprofile", """
        # RetroMac Command Prompt: runs the user's own .zprofile.
        rm_cmd_enter .zprofile && source "$REPLY"; rm_cmd_leave

        """),
        (".zshrc", """
        # RetroMac Command Prompt: runs the user's own .zshrc, then sets the prompt. Terminal's
        # "Last login" line goes; whatever the user's .zshrc prints stays.
        [[ -o interactive && -t 1 && -n $TERM_PROGRAM ]] && printf '\\e[H\\e[2J\\e[3J'
        rm_cmd_fix_history
        rm_cmd_enter .zshrc && source "$REPLY"; rm_cmd_leave
        rm_cmd_prompt_setup
        [[ -o login ]] || rm_cmd_finish

        """),
        (".zlogin", """
        # RetroMac Command Prompt: runs the user's own .zlogin.
        rm_cmd_enter .zlogin && source "$REPLY"; rm_cmd_leave
        rm_cmd_finish

        """),
    ]

    private static let support = """
    # RetroMac Command Prompt, sourced by the startup files in this folder. The user's own startup
    # files are sourced at top level, unchanged, from their usual place, in zsh's usual order.

    # This folder, and the user's own startup-file folder ($HOME, or the ZDOTDIR their ~/.zshenv sets).
    typeset -g RM_CMD_ZDOTDIR=${RM_CMD_ZDOTDIR:-$ZDOTDIR}
    typeset -g RM_USER_ZDOTDIR=${RM_USER_ZDOTDIR:-$HOME}

    # rm_cmd_enter <file>: ZDOTDIR becomes the user's, as their files expect; succeeds, with the
    # path in REPLY, when the file is readable.
    rm_cmd_enter() {
        ZDOTDIR=$RM_USER_ZDOTDIR
        REPLY=$RM_USER_ZDOTDIR/$1
        [[ -r $REPLY ]]
    }

    # rm_cmd_leave: remembers where the user's files live now and points ZDOTDIR back here, so zsh
    # reads its next startup file from this folder.
    rm_cmd_leave() {
        RM_USER_ZDOTDIR=${ZDOTDIR:-$HOME}
        ZDOTDIR=$RM_CMD_ZDOTDIR
    }

    # After the last startup file ZDOTDIR is the user's again, for nested shells and ~/.zlogout.
    rm_cmd_finish() {
        if [[ $RM_USER_ZDOTDIR == "$HOME" ]]; then
            unset ZDOTDIR
        else
            export ZDOTDIR=$RM_USER_ZDOTDIR
        fi
    }

    # /etc/zshrc would keep the history in this folder; it goes back to the user's file.
    rm_cmd_fix_history() {
        local ours=$RM_CMD_ZDOTDIR/.zsh_history theirs=$RM_USER_ZDOTDIR/.zsh_history
        [[ $HISTFILE == "$ours" ]] && HISTFILE=$theirs
        [[ $SHELL_SESSION_HISTFILE_SHARED == "$ours" ]] && SHELL_SESSION_HISTFILE_SHARED=$theirs
        return 0
    }

    _rm_cmd_precmd() {
        local dir=${PWD//\\//\\\\}
        PS1="C:${dir//\\%/%%}>"
        RPS1=
    }

    # After the user's .zshrc, so this prompt wins over a prompt theme's own hook. Only %-escapes
    # are expanded, so a folder name is never run.
    rm_cmd_prompt_setup() {
        setopt prompt_percent no_prompt_subst no_prompt_bang
        autoload -Uz add-zsh-hook
        add-zsh-hook -d precmd _rm_cmd_precmd
        add-zsh-hook precmd _rm_cmd_precmd
        _rm_cmd_precmd
    }

    """
}
