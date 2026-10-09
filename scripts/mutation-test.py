#!/usr/bin/env python3
"""뮤테이션 테스트: 사본에 변형 하나를 넣고 빌드·테스트해 테스트가 잡아내는지 본다.

사용법: scripts/mutation-test.py <Shared 아래 파일·폴더>... [--jobs N] [--out 보고서.json]
        [--timeout 초] [--limit N] [--list]
"""
import argparse, json, os, queue, re, signal, subprocess, sys, threading, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / ".build" / "mutation"
EQUIVALENTS = ROOT / "scripts" / "mutation-equivalents.txt"
# 실제 홈 폴더를 읽는 테스트 묶음은 뺀다.
SKIP_ARGS = ["--skip", "GuidanceRealFileTests", "--skip", "RealInstallStateTests"]
BUILD = ["swift", "build", "--build-tests"]
TEST = ["swift", "test", "--skip-build", *SKIP_ARGS]
RSYNC_EXCLUDES = [".git", ".build", "dist", "DerivedData", "Waypoint.xcodeproj", "design"]
BASELINE_TIMEOUT = 1800
BASELINE_TRIES = 3
SKIP_LINE = re.compile(r"\s*(import\b|@available\b|#if\b)")
KILLED, SURVIVED, INVALID, TIMEOUT, EQUIVALENT = "죽음", "생존", "무효", "시간 초과", "동등"
STATUSES = [KILLED, SURVIVED, INVALID, TIMEOUT, EQUIVALENT]

# (연산자 이름, 찾는 꼴, 바꿀 글자)
OPERATORS = [
    ("== → !=", r"(?<![=!<>])==(?!=)", "!="),
    ("!= → ==", r"!=(?!=)", "=="),
    ("<= → <", r"(?<=\s)<=(?=\s)", "<"),
    (">= → >", r"(?<=\s)>=(?=\s)", ">"),
    ("< → <=", r"(?<= )<(?= )", "<="),
    ("> → >=", r"(?<= )>(?= )", ">="),
    ("&& → ||", r"&&", "||"),
    ("|| → &&", r"\|\|", "&&"),
    ("true → false", r"(?<![\w.])true(?!\w)", "false"),
    ("false → true", r"(?<![\w.])false(?!\w)", "true"),
    ("! 제거", r"(?<![\w)\]?!])!(?=[A-Za-z_$(])", ""),
    ("+ → -", r"(?<= )\+(?= )", "-"),
    ("- → +", r"(?<= )-(?= )", "+"),
]


def skip_string(s, i):
    """i에서 시작하는 문자열 리터럴의 끝(다음 글자 위치)을 돌려준다."""
    hashes = 0
    while s[i] == "#":
        hashes += 1
        i += 1
    quote = '"""' if s.startswith('"""', i) else '"'
    i += len(quote)
    close, escape = quote + "#" * hashes, "\\" + "#" * hashes
    while i < len(s):
        if s.startswith(close, i):
            return i + len(close)
        if s.startswith(escape, i):
            i += len(escape)
            if s.startswith("(", i):  # 보간은 괄호 짝이 맞을 때까지 통째로 넘긴다
                depth, i = 1, i + 1
                while i < len(s) and depth:
                    if s[i] == '"' or re.match(r'#+"', s[i:i + 8]):
                        i = skip_string(s, i)
                        continue
                    depth += {"(": 1, ")": -1}.get(s[i], 0)
                    i += 1
            else:
                i += 1
            continue
        if s[i] == "\n" and quote == '"':
            return i
        i += 1
    return i


def mask_code(s):
    """주석과 문자열을 같은 길이의 공백으로 가린 글을 돌려준다."""
    out, i, n = list(s), 0, len(s)

    def blank(a, b):
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        if s.startswith("//", i):
            j = s.find("\n", i)
            j = n if j < 0 else j
        elif s.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:  # 블록 주석은 겹칠 수 있다
                if s.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif s.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
        elif s[i] == '"' or (s[i] == "#" and re.match(r'#+"', s[i:i + 8])):
            j = skip_string(s, i)
        else:
            i += 1
            continue
        blank(i, j)
        i = j
    return "".join(out)


def find_mutants(path):
    text = path.read_text(encoding="utf-8")
    masked, rel = mask_code(text), path.relative_to(ROOT).as_posix()
    found = []
    for name, pattern, repl in OPERATORS:
        for m in re.finditer(pattern, masked):
            start = text.rfind("\n", 0, m.start()) + 1
            end = text.find("\n", m.start())
            end = len(text) if end < 0 else end
            line = text[start:end]
            if SKIP_LINE.match(line):
                continue
            col = m.start() - start
            found.append({
                "file": rel, "line": text.count("\n", 0, start) + 1, "col": col + 1, "op": name,
                "original": line, "mutated": line[:col] + repl + line[col + len(m.group()):],
                "_span": (m.start(), m.end()), "_repl": repl,
            })
    found.sort(key=lambda x: x["_span"])
    return found


def key_of(m):
    return "\t".join([m["file"], str(m["line"]), str(m["col"]), m["op"], m["original"]])


def load_equivalents():
    known = set()
    if EQUIVALENTS.exists():
        for raw in EQUIVALENTS.read_text(encoding="utf-8").splitlines():
            parts = raw.split("\t")
            if raw.strip() and not raw.lstrip().startswith("#") and len(parts) >= 3:
                known.add((parts[0].strip(), parts[1].strip(), parts[2].strip()))
    return known


class Stopped(Exception):
    pass


STOP = threading.Event()
LOCK = threading.Lock()
BASELINE_TEST_LOCK = threading.Lock()
LIVE = set()
FATAL = []


def kill_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def run_cmd(args, cwd, timeout):
    """(종료 코드, 출력, 시간 초과 여부). 자식은 따로 묶어 그룹째 죽일 수 있게 한다."""
    if STOP.is_set():
        raise Stopped()
    proc = subprocess.Popen(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            stdin=subprocess.DEVNULL, text=True, errors="replace", start_new_session=True)
    with LOCK:
        LIVE.add(proc)
    timed_out = False
    try:
        out, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        kill_group(proc)
        out, _ = proc.communicate()
    finally:
        kill_group(proc)  # 부모가 끝나도 남은 도우미 프로세스를 정리한다
        with LOCK:
            LIVE.discard(proc)
    if STOP.is_set():
        raise Stopped()
    return proc.returncode, out, timed_out


def failed_tests(out):
    """실패한 테스트 이름을 나온 순서대로, 겹치지 않게 돌려준다."""
    names = re.findall(r"^✘ Test (?!run with )(.+?) (?:recorded|failed)\b", out, re.M)
    return list(dict.fromkeys(names))


def tail(out, n=25):
    return "\n".join(out.strip().splitlines()[-n:])


class Report:
    def __init__(self, path):
        self.path, self.results, self.extra = path, {}, {}
        if path.exists():
            for r in json.loads(path.read_text(encoding="utf-8")).get("mutants", []):
                self.results[key_of(r)] = r

    def add(self, record):
        with LOCK:
            self.results[key_of(record)] = record
            self.save()

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        body = {"mutants": list(self.results.values()), **self.extra}
        tmp.write_text(json.dumps(body, ensure_ascii=False, indent=1), encoding="utf-8")
        os.replace(tmp, self.path)


def worker(index, jobs, report, timeout, progress):
    copy = WORK / f"w{index}"
    try:
        copy.mkdir(parents=True, exist_ok=True)
        excludes = [f"--exclude=/{name}" for name in RSYNC_EXCLUDES]
        rc, out, _ = run_cmd(["rsync", "-a", "--delete", *excludes, f"{ROOT}/", f"{copy}/"], ROOT, BASELINE_TIMEOUT)
        if rc != 0:
            raise RuntimeError(f"w{index} 사본 만들기 실패\n{tail(out)}")
        # 변형 없이 먼저 통과하는지 본다. 테스트는 포트가 겹치지 않게 하나씩 돌린다.
        rc, out, late = run_cmd(BUILD, copy, BASELINE_TIMEOUT)
        if rc != 0 or late:
            raise RuntimeError(f"w{index} 변형 없는 빌드 실패\n{tail(out)}")
        for attempt in range(1, BASELINE_TRIES + 1):  # 흔들리는 테스트에 대비해 다시 돌린다
            with BASELINE_TEST_LOCK:
                rc, out, late = run_cmd(TEST, copy, max(timeout, 600))
            if rc == 0 and not late:
                break
            lines = [l for l in out.splitlines() if l.startswith("✘ Test")]
            detail = "\n".join(lines) or ("시간 초과" if late else tail(out, 20))
            print(f"w{index} 변형 없는 테스트 실패 {attempt}/{BASELINE_TRIES}\n{detail}", flush=True)
            if attempt == BASELINE_TRIES:
                raise RuntimeError(f"w{index} 변형 없는 테스트가 {BASELINE_TRIES}번 모두 실패\n{detail}")
        print(f"w{index} 준비됨 — {tail(out, 1).strip()}", flush=True)
        while True:
            try:
                m = jobs.get_nowait()
            except queue.Empty:
                return
            target = copy / m["file"]
            original = target.read_text(encoding="utf-8")
            (a, b), started, extra = m["_span"], time.time(), {}
            try:
                target.write_text(original[:a] + m["_repl"] + original[b:], encoding="utf-8")
                rc, out, late = run_cmd(BUILD, copy, timeout)
                if late:
                    status, note = TIMEOUT, "빌드"
                elif rc != 0:
                    errors = [l for l in out.splitlines() if "error:" in l]
                    status, note = INVALID, (errors[0].strip()[-300:] if errors else tail(out, 3))
                else:
                    rc, out, late = run_cmd(TEST, copy, timeout)
                    status = TIMEOUT if late else SURVIVED if rc == 0 else KILLED
                    note = "테스트" if late else ""
                    if status == KILLED:  # 한 번 더 돌려 두 번 다 실패할 때만 죽음으로 센다
                        extra["failed"] = failed_tests(out)[:5]
                        rc, out, late = run_cmd(TEST, copy, timeout)
                        if late:
                            status, note = TIMEOUT, "테스트"
                        elif rc == 0:
                            status, extra["flaky"] = SURVIVED, True
            finally:
                target.write_text(original, encoding="utf-8")
            record = {k: v for k, v in m.items() if not k.startswith("_")}
            record.update(status=status, duration=round(time.time() - started, 1), note=note, **extra)
            report.add(record)
            with LOCK:
                progress[0] += 1
                mark = " (흔들림)" if extra.get("flaky") else ""
                print(f"[{progress[0]}/{progress[1]}] {status}{mark} {m['file']}:{m['line']} {m['op']}", flush=True)
    except Stopped:
        pass
    except Exception as error:  # 예상 밖 실패는 전체를 멈춘다
        FATAL.append(str(error))
        stop_all()


def stop_all(*_):
    STOP.set()
    with LOCK:
        for proc in list(LIVE):
            kill_group(proc)


def summarize(mutants, report, equivalents):
    per_file, survivors, flaky = {}, [], 0
    for m in mutants:
        counts = per_file.setdefault(m["file"], dict.fromkeys(STATUSES + ["미실행"], 0))
        done = report.results.get(key_of(m))
        if (m["file"], m["op"], m["original"].strip()) in equivalents:
            status = EQUIVALENT
        else:
            status = done["status"] if done else "미실행"
        counts[status] += 1
        flaky += bool(done and done.get("flaky") and status == SURVIVED)
        if status == SURVIVED:
            survivors.append({k: m[k] for k in ("file", "line", "col", "op", "original", "mutated")})

    def with_score(c):
        dead = c[KILLED] + c[TIMEOUT]
        total = dead + c[SURVIVED]
        return {**c, "점수": round(dead / total, 3) if total else None}

    total = dict.fromkeys(STATUSES + ["미실행"], 0)
    for counts in per_file.values():
        for k, v in counts.items():
            total[k] += v
    files = {f: with_score(c) for f, c in per_file.items()}
    return {"files": files, "total": with_score(total), "flaky": flaky}, survivors


def print_summary(summary, survivors):
    def row(name, c):
        score = "-" if c["점수"] is None else f"{c['점수'] * 100:.1f}%"
        rest = f" 미실행 {c['미실행']}" if c["미실행"] else ""
        print(f"  {name}: " + " ".join(f"{s} {c[s]}" for s in STATUSES) + rest + f" · 점수 {score}")

    print("\n== 요약 ==")
    for name, counts in summary["files"].items():
        row(name, counts)
    row("전체", summary["total"])
    print(f"\n== 생존 {len(survivors)}개 ==")
    for s in survivors:
        print(f"  {s['file']}:{s['line']} [{s['op']}] {s['original'].strip()}  →  {s['mutated'].strip()}")
    print(f"\n흔들림으로 생존이 된 변형 {summary['flaky']}개")


def main():
    parser = argparse.ArgumentParser(description="뮤테이션 테스트")
    parser.add_argument("targets", nargs="+")
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--out", default=str(WORK / "report.json"))
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()

    files = []
    for raw in args.targets:
        path = Path(raw).resolve() if Path(raw).exists() else (ROOT / raw).resolve()
        if not path.exists() or ROOT / "Shared" not in [path, *path.parents]:
            sys.exit(f"Shared 아래 파일·폴더가 아니다: {raw}")
        files += sorted(path.rglob("*.swift")) if path.is_dir() else [path]
    mutants = [m for f in dict.fromkeys(files) for m in find_mutants(f)]

    if args.list:
        for m in mutants:
            print(f"{m['file']}:{m['line']}:{m['col']} [{m['op']}] {m['original'].strip()}  →  {m['mutated'].strip()}")
        print(f"변형 {len(mutants)}개")
        return

    out = Path(args.out)
    report = Report(out if out.is_absolute() else Path.cwd() / out)
    equivalents = load_equivalents()
    runnable = [m for m in mutants if (m["file"], m["op"], m["original"].strip()) not in equivalents]
    pending = [m for m in runnable if key_of(m) not in report.results]
    print(f"변형 {len(mutants)}개 · 동등 {len(mutants) - len(runnable)}개 · 이미 끝남 {len(runnable) - len(pending)}개 건너뜀", flush=True)
    pending = pending[:args.limit] if args.limit is not None else pending
    print(f"이번에 돌릴 것 {len(pending)}개", flush=True)

    if pending:
        signal.signal(signal.SIGINT, stop_all)
        signal.signal(signal.SIGTERM, stop_all)
        jobs, progress = queue.Queue(), [0, len(pending)]
        for m in pending:
            jobs.put(m)
        count = max(1, min(args.jobs, len(pending)))
        threads = [threading.Thread(target=worker, args=(i, jobs, report, args.timeout, progress)) for i in range(count)]
        for t in threads:
            t.start()
        while any(t.is_alive() for t in threads):  # 신호를 받을 수 있게 짧게 끊어 기다린다
            for t in threads:
                t.join(0.2)

    summary, survivors = summarize(mutants, report, equivalents)
    report.extra = {"summary": summary, "survivors": survivors}
    report.save()
    print_summary(summary, survivors)
    print(f"\n보고서: {report.path}")
    if FATAL:
        sys.exit("중단: " + "\n".join(FATAL))
    if STOP.is_set():
        sys.exit(130)


if __name__ == "__main__":
    main()
