import os
import re
import sys


OPENSSH = "@openssh@"
TSSH = "@tssh@"

# This profile deliberately accepts only the terminal/installer argv surface.
OPTIONS = {
    "addressfamily", "certificatefile", "clearallforwardings",
    "connecttimeout", "forwardagent", "globalknownhostsfile",
    "hostname", "identitiesonly", "identityagent", "identityfile",
    "kbdinteractiveauthentication", "loglevel", "passwordauthentication", "port",
    "proxycommand", "proxyjump", "pubkeyauthentication",
    "serveralivecountmax", "serveraliveinterval", "stricthostkeychecking", "user",
    "userknownhostsfile",
}


def translate(args):
    translated = []
    debug = False
    flags = set()
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--":
            i += 1
            break
        if not arg.startswith("-") or arg == "-":
            break
        if arg.startswith("--"):
            return None
        j = 1
        while j < len(arg):
            flag = arg[j]
            if flag in "GV":
                return None
            if flag == "v":
                debug = True
            elif flag in "46aATnt":
                flags.add(flag)
                if any(pair <= flags for pair in ({"4", "6"}, {"a", "A"}, {"t", "T"})):
                    return None
                translated.append("-" + flag)
            elif flag in "DFiJlop":
                value = arg[j + 1:]
                if not value:
                    i += 1
                    if i >= len(args):
                        return None
                    value = args[i]
                if not value:
                    return None
                if flag == "F" and value == "-":
                    return None
                if flag in "Dp":
                    port = value.rsplit(":", 1)[-1] if flag == "D" else value
                    if not port.isascii() or not port.isdecimal() or not 1 <= int(port) <= 65535:
                        return None
                if flag == "l" and value == "nix-ssh":
                    return None
                if flag == "o":
                    option = re.fullmatch(r"\s*([^\s=]+)(?:\s*=\s*|\s+)(.+?)\s*", value)
                    if not option:
                        return None
                    key, setting = option.groups()
                    key = key.lower()
                    if key == "user" and setting == "nix-ssh":
                        return None
                    if key in {"clearallforwardings", "forwardagent", "identitiesonly",
                               "kbdinteractiveauthentication", "passwordauthentication",
                               "pubkeyauthentication"} and setting.lower() not in {"yes", "no"}:
                        return None
                    if key == "loglevel" and setting.lower() not in {
                        "quiet", "fatal", "error", "info", "verbose", "debug", "debug1", "debug2", "debug3",
                    }:
                        return None
                    if key == "addressfamily" and setting.lower() not in {"any", "inet", "inet6"}:
                        return None
                    if key == "stricthostkeychecking" and setting.lower() not in {"yes", "no", "ask", "accept-new", "off"}:
                        return None
                    if key in {"connecttimeout", "port", "serveralivecountmax", "serveraliveinterval"}:
                        if not setting.isascii() or not setting.isdecimal():
                            return None
                        number = int(setting)
                        if number > 4294967295 or (key == "port" and not 1 <= number <= 65535):
                            return None
                        if key == "connecttimeout" and number == 0:
                            return None
                    if key in {"controlmaster", "controlpersist", "udpsessionattach"}:
                        if setting.lower() != "no":
                            return None
                    elif key == "controlpath":
                        if setting.lower() != "none":
                            return None
                    elif key not in OPTIONS:
                        return None
                translated.extend(["-" + flag, value])
                break
            else:
                return None
            j += 1
        i += 1

    # No host chooser, subsystem, multiplexing, or background invocation here.
    if i >= len(args) or not args[i] or args[i].startswith("-"):
        return None
    if "://" in args[i] or args[i].startswith("nix-ssh@"):
        return None
    profile = [
        "--auto-transport", "--reliable-io",
        "-oControlMaster=no", "-oControlPath=none", "-oControlPersist=no",
        "-oUdpSessionAttach=no",
    ]
    if debug:
        profile.append("--debug")
    return profile + translated + args[i:]


def main():
    args = sys.argv[1:]
    translated = translate(args)
    executable = OPENSSH if translated is None else TSSH
    # One exec only: unsupported argv and probes are native before authentication.
    os.execv(executable, [executable] + (args if translated is None else translated))


if __name__ == "__main__":
    main()
