"""Installer failure-path checks. No Xcode, GUI, or installed app is touched."""
import pathlib
import os
import shutil
import subprocess
import tempfile
import unittest

REPORT = pathlib.Path(__file__).with_name("build-failure-report.sh")


class BuildFailureReportTests(unittest.TestCase):
    def report(self, content):
        with tempfile.TemporaryDirectory(prefix="waypoint-build-report-") as directory:
            log = pathlib.Path(directory) / "build log.txt"
            log.write_text(content)
            result = subprocess.run(
                ["/bin/bash", "-c", 'source "$1"; report_build_failure "$2"', "report", str(REPORT), str(log)],
                capture_output=True, text=True, check=True,
            )
            self.assertEqual(log.read_text(), content)
            self.assertEqual(result.stdout, "")
            return result.stderr

    def test_permission_failure_survives_simulator_noise(self):
        noise = "[-[SimServiceContext sendRequest:reply:error:]:1982] ERROR: unavailable\n" * 20
        result = self.report(noise + "<unknown>:0: error: ModuleCache: Operation not permitted\n")
        self.assertIn("ModuleCache: Operation not permitted", result)
        self.assertIn("권한 승인을 받은 뒤", result)
        self.assertNotIn("SimServiceContext", result)

    def test_compiler_error_does_not_suggest_permission_change(self):
        result = self.report("File.swift:12:3: error: type mismatch\n** BUILD FAILED **\n")
        self.assertIn("type mismatch", result)
        self.assertNotIn("권한 승인을 받은 뒤", result)

    def test_last_errors_and_generic_failure_are_bounded(self):
        result = self.report("".join(f"file: error: error-{i}\n" for i in range(30)))
        self.assertNotIn("error-0\n", result)
        self.assertIn("error-29\n", result)
        self.assertEqual(result.count("file: error:"), 12)
        result = self.report("starting\n" * 20 + "Signing identity missing\n")
        self.assertIn("Signing identity missing", result)
        self.assertEqual(len(result.splitlines()), 13)

    def test_installer_stops_before_replacing_app(self):
        with tempfile.TemporaryDirectory(prefix="waypoint-install-failure-") as directory:
            root = pathlib.Path(directory)
            scripts = root / "scripts"; scripts.mkdir()
            for name in ["install-local.sh", "build-failure-report.sh"]:
                shutil.copyfile(REPORT.with_name(name), scripts / name)
            binary = root / "bin"; binary.mkdir()
            fake = binary / "xcodebuild"
            fake.write_text('#!/bin/bash\necho "file: error: ModuleCache: Operation not permitted"\nexit 1\n')
            fake.chmod(0o700)
            environment = dict(os.environ, PATH=str(binary) + ":/usr/bin:/bin")
            environment.pop("WAYPOINT_SKIP_BUILD", None)
            result = subprocess.run(["/bin/bash", str(scripts / "install-local.sh")],
                                    env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("ModuleCache: Operation not permitted", result.stderr)
            self.assertIn("전체 로그:", result.stderr)
            self.assertNotIn("평소용 종료", result.stdout)
            self.assertNotIn("교체", result.stdout)


if __name__ == "__main__":
    unittest.main()
