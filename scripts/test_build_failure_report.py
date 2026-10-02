"""Installer failure-path, build number, and release-argument checks. No Xcode, GUI, or installed app is touched."""
import pathlib
import os
import shutil
import subprocess
import tempfile
import unittest

REPORT = pathlib.Path(__file__).with_name("build-failure-report.sh")


VERSION = REPORT.with_name("build-version.sh")
RELEASE = REPORT.with_name("release-mac.sh")


def make_repo(root, commits):
    git = ["git", "-C", str(root), "-c", "user.name=t", "-c", "user.email=t@example.com"]
    subprocess.run(git[:3] + ["init", "-q"], check=True)
    for i in range(commits):
        subprocess.run(git + ["commit", "-q", "--allow-empty", "-m", f"c{i}"], check=True)


def version_call(function, root):
    return subprocess.run(["/bin/bash", "-c", 'source "$1"; ' + function + ' "$2"', "v", str(VERSION), str(root)],
                          capture_output=True, text=True)


class BuildVersionTests(unittest.TestCase):
    def test_build_number_is_commit_count(self):
        with tempfile.TemporaryDirectory(prefix="waypoint-build-number-") as directory:
            make_repo(pathlib.Path(directory), commits=3)
            result = version_call("waypoint_build_number", directory)
            self.assertEqual((result.returncode, result.stdout), (0, "3\n"))

    def test_build_number_fails_outside_git(self):
        with tempfile.TemporaryDirectory(prefix="waypoint-build-number-") as directory:
            result = version_call("waypoint_build_number", directory)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, "")
            self.assertIn("git 저장소가 아님", result.stderr)

    def test_marketing_version_from_project_yml(self):
        with tempfile.TemporaryDirectory(prefix="waypoint-version-") as directory:
            (pathlib.Path(directory) / "project.yml").write_text(
                'settings:\n  base:\n    MARKETING_VERSION: "1.2.3"\n    CURRENT_PROJECT_VERSION: "1"\n')
            self.assertEqual(version_call("waypoint_marketing_version", directory).stdout, "1.2.3\n")
        real = version_call("waypoint_marketing_version", REPORT.parent.parent)
        self.assertRegex(real.stdout, r"^\d+\.\d+\.\d+\n$")

    def test_version_argument_shape(self):
        for value, ok in [("1.0.0", True), ("10.20.30", True), ("1.0", False), ("1.0.0-beta", False), ("v1.0.0", False)]:
            result = version_call("waypoint_valid_version", value)
            self.assertEqual(result.returncode == 0, ok, value)


class ReleaseArgumentTests(unittest.TestCase):
    """xcodebuild까지 가지 않는 인자 오류만 본다(빌드·서명·공증은 하지 않는다)."""
    def release(self, *args):
        return subprocess.run(["/bin/bash", str(RELEASE), *args], capture_output=True, text=True)

    def test_unknown_argument(self):
        result = self.release("--nope")
        self.assertEqual(result.returncode, 2)
        self.assertIn("모르는 인자", result.stderr)

    def test_version_needs_value(self):
        result = self.release("--version")
        self.assertEqual(result.returncode, 2)

    def test_bad_version_rejected_before_build(self):
        result = self.release("--allow-dirty", "--skip-notarize", "--version", "1.0")
        self.assertEqual(result.returncode, 2)
        self.assertIn("X.Y.Z", result.stderr)

    def test_help(self):
        result = self.release("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("--skip-notarize", result.stdout)


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
            for name in ["install-local.sh", "build-failure-report.sh", "build-version.sh"]:
                shutil.copyfile(REPORT.with_name(name), scripts / name)
            make_repo(root, commits=1)
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
