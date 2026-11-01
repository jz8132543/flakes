import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


source = Path(__file__).parents[1] / "home-manager/modules/desktop/vscode-ssh-adapter.py"
spec = importlib.util.spec_from_file_location("ssh_adapter", source)
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class AdapterTests(unittest.TestCase):
    def test_pre_destination_verbose_only(self):
        translated = adapter.translate(["-vvv", "-T", "-D", "5000", "host", "sh", "-v"])
        self.assertEqual(translated.count("--debug"), 1)
        self.assertEqual(translated[-3:], ["host", "sh", "-v"])
        self.assertIn("--reliable-io", translated)
        self.assertIn("-oControlPath=none", translated)

    def test_native_probes_and_unsupported_invocations(self):
        for args in [
            ["-G", "host"], ["-V"], ["-vG", "host"], ["-s", "host", "sftp"],
            ["-f", "host"], ["-N", "host"], ["-W", "host:22", "jump"],
            ["-L", "8080:host:80", "host"], ["-M", "host"],
            ["-oControlMaster=yes", "host"], ["-oBatchMode=yes", "host"],
            ["-oLogLevel=bogus", "host"], ["-oServerAliveInterval=oops", "host"],
            ["-4", "-6", "host"], ["-t", "-T", "host"], ["-D", "0", "host"],
            ["-p", "70000", "host"], ["-F", "-", "host"], ["-J"],
            ["ssh://root@host:22"], ["nix-ssh@host"], ["-l", "nix-ssh", "host"],
            ["-oUser=nix-ssh", "host"], [],
        ]:
            with self.subTest(args=args):
                self.assertIsNone(adapter.translate(args))

    def test_supported_values_remain_distinct_arguments(self):
        args = ["-Tp2222", "-i", "/key with space", "-oProxyCommand=/native/ssh -W %h:%p jump", "host", "printf", "%s"]
        result = adapter.translate(args)
        self.assertIn("/key with space", result)
        self.assertIn("ProxyCommand=/native/ssh -W %h:%p jump", result)
        self.assertEqual(result[-3:], ["host", "printf", "%s"])

    def test_one_exec_preserves_native_argv(self):
        for args in [["-G", "host"], ["-V"], ["-s", "host", "sftp"], ["host", "true"]]:
            with self.subTest(args=args), patch.object(adapter.os, "execv") as execute, patch.object(adapter.sys, "argv", ["adapter"] + args):
                adapter.main()
                execute.assert_called_once()
                executable, argv = execute.call_args.args
                if adapter.translate(args) is None:
                    self.assertEqual(executable, adapter.OPENSSH)
                    self.assertEqual(argv, [adapter.OPENSSH] + args)
                else:
                    self.assertEqual(executable, adapter.TSSH)


if __name__ == "__main__":
    unittest.main()
