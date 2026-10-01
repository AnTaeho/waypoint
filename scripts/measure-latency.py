#!/usr/bin/env python3
"""Waypoint Dev의 훅 수신 → 저장/화면 지연을 잰다(TRK-11, docs/RELIABILITY.md).

실측 픽스처(Tests/Fixtures/hooks/real-*, doc-codex-*) 형식의 훅을 여러 세션·도구로 섞어 실제와 비슷한
속도·버스트로 Dev 앱(기본 127.0.0.1:47822)에 POST하고, 앱이 기록한 지표(/integration/status의 metrics)를 읽어
p50/p95/최대를 출력한다. 요청마다 스크립트 쪽 왕복 시간도 함께 잰다.

- 평소용(47821)에는 보내지 않는다(포트 47821이면 멈춘다).
- 세션 ID·tool_use_id·prompt_id는 매번 새로 만든다(재수신으로 걸러지지 않게). PID 머리는 보내지 않는다
  (가짜 PID는 10초 점검에서 process-gone으로 정리된다).
- 모든 세션은 SessionEnd로 닫는다. 등록된 측정용 프로젝트 폴더(--root) 안의 경로만 쓴다(파일은 만들지 않는다).
- 표준 라이브러리만 쓴다.

사용: python3 scripts/measure-latency.py [--count 500] [--sessions 6] [--root ~/workspace/waypoint-probe] [--json 결과.json]
"""
import argparse
import json
import math
import os
import random
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "..", "Tests", "Fixtures", "hooks")


def load(name):
    with open(os.path.join(FIXTURES, name + ".json"), encoding="utf-8") as f:
        return json.load(f)


def nearest_rank(values, p):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, max(0, math.ceil(p * len(ordered)) - 1))]


def summary(values):
    if not values:
        return None
    return {"count": len(values), "p50": nearest_rank(values, 0.5), "p95": nearest_rank(values, 0.95),
            "max": max(values)}


class Session:
    """한 세션의 훅 순서. 턴마다 요청 → 도구 몇 번(빠른 버스트) → Stop."""

    def __init__(self, root, provider, rng):
        self.root, self.provider, self.rng = root, provider, rng
        self.id = str(uuid.uuid4())
        self.turn = 0

    def base(self, name):
        hook = load(name)
        hook["session_id"] = self.id
        hook["cwd"] = self.root
        hook.pop("transcript_path", None)
        return hook

    def path(self, event):
        return ("/hooks/codex/" if self.provider == "codex" else "/hooks/") + event

    def start(self):
        name = "doc-codex-SessionStart" if self.provider == "codex" else "real-SessionStart"
        return [(self.path("SessionStart"), self.base(name))]

    def end(self):
        name = "doc-codex-SessionEnd" if self.provider == "codex" else "real-SessionEnd"
        return [(self.path("SessionEnd"), self.base(name))]

    def turn_hooks(self):
        """한 턴의 훅 목록(요청, 도구 1~5번, Stop)."""
        self.turn += 1
        hooks = []
        prompt_name = "doc-codex-UserPromptSubmit" if self.provider == "codex" else "real-UserPromptSubmit"
        prompt = self.base(prompt_name)
        prompt["prompt"] = f"측정 요청 {self.turn}"
        prompt["prompt_id" if self.provider == "claude" else "turn_id"] = str(uuid.uuid4())
        hooks.append((self.path("UserPromptSubmit"), prompt))
        for _ in range(self.rng.randint(1, 5)):
            tool_id = "toolu_" + uuid.uuid4().hex[:24]
            if self.provider == "codex":
                pre = self.base("doc-codex-PreToolUse-Agent")
                pre.update({"tool_name": "Bash", "tool_use_id": tool_id, "tool_input": {"command": "ls"}})
                post = self.base("doc-codex-PostToolUse-apply_patch")
                post["tool_use_id"] = tool_id
            else:
                pre = self.base("real-PreToolUse-Agent")
                pre.update({"tool_name": "Edit", "tool_use_id": tool_id,
                            "tool_input": {"file_path": self.root + "/measure.txt"}})
                post = self.base(self.rng.choice(["real-PostToolUse-Edit", "real-PostToolUse-Write", "real-PostToolUse-Bash"]))
                post["tool_use_id"] = tool_id
                if isinstance(post.get("tool_input"), dict) and "file_path" in post["tool_input"]:
                    post["tool_input"]["file_path"] = f"{self.root}/measure-{self.rng.randint(1, 20)}.txt"
            hooks.append((self.path("PreToolUse"), pre))
            hooks.append((self.path("PostToolUse"), post))
        hooks.append((self.path("Stop"), self.base("doc-codex-Stop" if self.provider == "codex" else "real-Stop")))
        return hooks


def post(port, path, body, timeout=5):
    data = json.dumps(body, ensure_ascii=False).encode()
    request = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=data, method="POST",
                                     headers={"Content-Type": "application/json"})
    began = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response.read()
            status = response.status
    except urllib.error.HTTPError as error:
        status = error.code
    except Exception:
        status = 0
    return status, (time.perf_counter() - began) * 1000


def status(port):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/integration/status", timeout=5) as response:
        return json.loads(response.read())


def run(args):
    if args.port == 47821:
        sys.exit("평소용 포트(47821)에는 보내지 않는다")
    rng = random.Random(args.seed)
    before = status(args.port).get("metrics", {})
    base_count = len(before.get("displayMs", []))

    providers = ["claude" if i % 3 else "codex" for i in range(args.sessions)]
    sessions = [Session(args.root, p, random.Random(rng.random())) for p in providers]
    # 세션마다 받을 몫을 나눈다(시작·끝 포함). 턴을 다 만든 뒤 몫에 맞게 자른다.
    share = [args.count // args.sessions + (1 if i < args.count % args.sessions else 0) for i in range(args.sessions)]
    plans = []
    for session, quota in zip(sessions, share):
        hooks = session.start()
        while len(hooks) < quota - 1:
            hooks += session.turn_hooks()
        plans.append(hooks[: quota - 1] + session.end())

    results, lock = [], threading.Lock()

    def worker(session, hooks):
        local = random.Random(rng.random())
        for index, (path, body) in enumerate(hooks):
            code, rtt = post(args.port, path, body)
            with lock:
                results.append((code, rtt))
            event = path.rsplit("/", 1)[-1]
            # 실제와 비슷한 간격: 도구 앞뒤는 수~수십 ms, 턴 사이는 수백 ms, 가끔 몰림(0 ms)
            if event == "Stop":
                time.sleep(local.uniform(0.2, 0.8) * args.pace)
            elif local.random() < 0.3:
                continue
            else:
                time.sleep(local.uniform(0.003, 0.06) * args.pace)

    began = time.time()
    threads = [threading.Thread(target=worker, args=(s, plan)) for s, plan in zip(sessions, plans)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    elapsed = time.time() - began
    time.sleep(1.5)  # 화면 반영 표본은 메인 큐 다음 차례에 적힌다

    after = status(args.port).get("metrics", {})
    sent = len(results)
    ok = sum(1 for code, _ in results if code in (200, 204))
    new = len(after.get("displayMs", [])) - base_count
    take = min(ok, len(after.get("displayMs", [])))
    report = {
        "sent": sent, "ok": ok, "sessions": args.sessions, "claudeSessions": providers.count("claude"),
        "codexSessions": providers.count("codex"), "seconds": round(elapsed, 2),
        "appSamplesAdded": new,
        "receiveToSaveMs": summary(after.get("saveMs", [])[-take:] if take else []),
        "receiveToDisplayMs": summary(after.get("displayMs", [])[-take:] if take else []),
        "clientRoundTripMs": summary([rtt for code, rtt in results if code in (200, 204)]),
        "failures": after.get("failures"),
    }
    display = report["receiveToDisplayMs"]
    rtt = report["clientRoundTripMs"]
    report["meetsTarget2s"] = bool(display and rtt and display["p95"] < 2000 and rtt["p95"] < 2000)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=int(os.environ.get("WAYPOINT_PORT", 47822)))
    parser.add_argument("--count", type=int, default=500)
    parser.add_argument("--sessions", type=int, default=6)
    parser.add_argument("--root", default=os.path.expanduser("~/workspace/waypoint-probe"))
    parser.add_argument("--pace", type=float, default=1.0, help="간격 배율(0이면 쉬지 않고 몰아 보낸다)")
    parser.add_argument("--seed", type=int, default=11)
    parser.add_argument("--json", help="결과를 이 파일에도 쓴다")
    args = parser.parse_args()
    report = run(args)

    def line(title, s):
        if not s:
            return f"{title}: 표본 없음"
        return f"{title}: {s['count']}건 · p50 {s['p50']:.1f} ms · p95 {s['p95']:.1f} ms · 최대 {s['max']:.1f} ms"

    print(f"보냄 {report['sent']}건(성공 {report['ok']}) · 세션 {report['sessions']}"
          f"(Claude {report['claudeSessions']}, Codex {report['codexSessions']}) · {report['seconds']}초")
    print(line("앱 수신→저장", report["receiveToSaveMs"]))
    print(line("앱 수신→화면", report["receiveToDisplayMs"]))
    print(line("스크립트 왕복", report["clientRoundTripMs"]))
    print(f"앱 실패 횟수: {report['failures']}")
    print("p95 2초 목표: " + ("통과" if report["meetsTarget2s"] else "미달"))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
    return 0 if report["ok"] == report["sent"] else 1


if __name__ == "__main__":
    sys.exit(main())
