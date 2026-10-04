#!/usr/bin/env python3
"""Rewrite a Proxmox vzdump backup job's guest selection from VM/CT tags.

Proxmox backup jobs cannot select by tag. This script reads cluster-wide guest
tags from GET /cluster/resources and updates GET/PUT /cluster/backup/{id}.

Both endpoints are cluster-scoped: guests on every node are visible from any
member (or a remote API token). You do not need to query each node.
"""

from __future__ import annotations

import argparse
import configparser
import json
import os
import re
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
NC = "\033[0m"
USE_COLOR = sys.stderr.isatty() and sys.stdout.isatty()

MODES = ("snapshot", "suspend", "stop")


def c(code: str, text: str) -> str:
    if not USE_COLOR:
        return text
    return f"{code}{text}{NC}"


def info(msg: str) -> None:
    print(c(BLUE, "[INFO]"), msg)


def success(msg: str) -> None:
    print(c(GREEN, "[SUCCESS]"), msg)


def warning(msg: str) -> None:
    print(c(YELLOW, "[WARNING]"), msg)


def error(msg: str) -> None:
    print(c(RED, "[ERROR]"), msg, file=sys.stderr)


def die(msg: str, code: int = 1) -> None:
    error(msg)
    raise SystemExit(code)


def split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [p.strip() for p in re.split(r"[,;]+", value) if p.strip()]


def split_tags(raw: str | None) -> list[str]:
    return split_csv(raw)


def norm_tag(tag: str, case_insensitive: bool) -> str:
    tag = tag.strip()
    return tag.casefold() if case_insensitive else tag


@dataclass
class Settings:
    host: str = ""
    user: str = "root@pam"
    token_id: str = ""
    token_secret: str = ""
    password: str = ""
    verify_tls: bool = False
    job_id: str = ""
    selection: str = "all-except"
    sync_mode: bool = True
    skip_templates: bool = False
    exclude_tags: list[str] = field(default_factory=lambda: ["no-backup"])
    include_tags: list[str] = field(default_factory=list)
    case_insensitive: bool = True
    snapshot_tags: list[str] = field(default_factory=lambda: ["backup-snapshot"])
    suspend_tags: list[str] = field(default_factory=lambda: ["backup-suspend"])
    stop_tags: list[str] = field(default_factory=lambda: ["backup-stop"])
    default_mode: str = "snapshot"
    conflict: str = "fail"
    mode: str | None = None


@dataclass
class Guest:
    vmid: int
    name: str
    type: str
    node: str
    tags: list[str]
    template: bool
    excluded: bool = False
    include_ok: bool = True
    mode: str = "snapshot"
    mode_reason: str = "default"
    skip_reason: str = ""

    @property
    def backupable(self) -> bool:
        return not self.skip_reason


def load_config(path: str | None) -> Settings:
    s = Settings()
    if not path:
        return s
    if not os.path.isfile(path):
        die(f"Config file not found: {path}")
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(path)

    def get(section: str, key: str, fallback: str = "") -> str:
        if cfg.has_option(section, key):
            return cfg.get(section, key).strip()
        return fallback

    def getb(section: str, key: str, fallback: bool) -> bool:
        if cfg.has_option(section, key):
            return cfg.getboolean(section, key)
        return fallback

    s.host = get("api", "host")
    s.user = get("api", "user", s.user)
    s.token_id = get("api", "token_id")
    s.token_secret = get("api", "token_secret")
    s.password = get("api", "password")
    s.verify_tls = getb("api", "verify_tls", False)
    s.job_id = get("job", "id")
    s.selection = get("job", "selection", s.selection) or s.selection
    s.sync_mode = getb("job", "sync_mode", True)
    s.skip_templates = getb("job", "skip_templates", False)
    ex = get("tags", "exclude", "no-backup")
    s.exclude_tags = split_csv(ex) or ["no-backup"]
    s.include_tags = split_csv(get("tags", "include"))
    s.case_insensitive = getb("tags", "case_insensitive", True)
    s.snapshot_tags = split_csv(get("tags", "snapshot", "backup-snapshot"))
    s.suspend_tags = split_csv(get("tags", "suspend", "backup-suspend"))
    s.stop_tags = split_csv(get("tags", "stop", "backup-stop"))
    s.default_mode = get("tags", "default_mode", "snapshot") or "snapshot"
    s.conflict = get("tags", "conflict", "fail") or "fail"
    return s


def apply_env(s: Settings) -> None:
    s.host = os.environ.get("PVE_HOST", s.host)
    s.user = os.environ.get("PVE_USER", s.user)
    s.token_id = os.environ.get("PVE_TOKEN_ID", s.token_id)
    s.token_secret = os.environ.get("PVE_TOKEN_SECRET", s.token_secret)
    s.password = os.environ.get("PVE_PASSWORD", s.password)


class PveClient:
    def __init__(self, s: Settings, verbose: bool = False) -> None:
        self.s = s
        self.verbose = verbose
        self.ticket: str | None = None
        self.csrf: str | None = None
        self.use_pvesh = not s.host and self._have_pvesh()
        if not self.use_pvesh and not s.host:
            if s.token_secret or s.password:
                s.host = "127.0.0.1"
            else:
                die(
                    "No API host set and pvesh not found. "
                    "Run on a cluster node, or set [api] host / PVE_HOST."
                )
        if not self.use_pvesh and not (s.token_secret or s.password):
            die("Remote API needs token_id+token_secret or password.")

    @staticmethod
    def _have_pvesh() -> bool:
        from shutil import which

        return which("pvesh") is not None

    def _ssl(self) -> ssl.SSLContext:
        if self.s.verify_tls:
            return ssl.create_default_context()
        ctx = ssl._create_unverified_context()
        return ctx

    def _base(self) -> str:
        host = self.s.host
        if "://" in host:
            return host.rstrip("/")
        return f"https://{host}:8006"

    def _headers(self) -> dict[str, str]:
        headers = {"Accept": "application/json"}
        if self.s.token_secret:
            token_id = self.s.token_id
            user = self.s.user
            if "!" in token_id:
                ident = f"{token_id}={self.s.token_secret}"
            else:
                ident = f"{user}!{token_id}={self.s.token_secret}"
            headers["Authorization"] = f"PVEAPIToken={ident}"
        elif self.ticket:
            headers["Cookie"] = f"PVEAuthCookie={self.ticket}"
            if self.csrf:
                headers["CSRFPreventionToken"] = self.csrf
        return headers

    def login(self) -> None:
        if self.use_pvesh or self.s.token_secret:
            return
        data = urllib.parse.urlencode(
            {"username": self.s.user, "password": self.s.password}
        ).encode()
        raw = self._http("POST", "/api2/json/access/ticket", data=data, form=True)
        payload = raw.get("data") or {}
        self.ticket = payload.get("ticket")
        self.csrf = payload.get("CSRFPreventionToken")
        if not self.ticket:
            die("Login failed: no ticket in response")

    def _http(
        self,
        method: str,
        path: str,
        params: dict[str, Any] | None = None,
        data: bytes | None = None,
        form: bool = False,
    ) -> Any:
        url = self._base() + path
        if params and method == "GET":
            q = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
            url = f"{url}?{q}"
        headers = self._headers()
        body = data
        if params and method != "GET" and body is None:
            body = urllib.parse.urlencode(
                {k: v for k, v in params.items() if v is not None}
            ).encode()
            form = True
        if form:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        if self.verbose:
            info(f"{method} {url}")
        try:
            with urllib.request.urlopen(req, context=self._ssl()) as resp:
                raw = resp.read().decode()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")
            die(f"API {method} {path} failed: HTTP {exc.code}: {detail}")
        except urllib.error.URLError as exc:
            die(f"API {method} {path} failed: {exc.reason}")
        if not raw:
            return None
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            die(f"API {method} {path} returned non-JSON: {raw[:200]}")

    def _pvesh(self, method: str, path: str, params: dict[str, Any] | None = None) -> Any:
        cmd = ["pvesh", method.lower(), path, "--output-format", "json"]
        if params:
            for k, v in params.items():
                if v is None:
                    continue
                cmd.extend([f"--{k}", str(v)])
        if self.verbose:
            info(" ".join(cmd))
        try:
            out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
        except subprocess.CalledProcessError as exc:
            die(f"pvesh failed ({exc.returncode}): {exc.output.strip()}")
        out = out.strip()
        if not out or out == "null":
            return None
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            return out

    def get(self, path: str, params: dict[str, Any] | None = None) -> Any:
        if self.use_pvesh:
            data = self._pvesh("get", path, params)
            return data
        wrapped = self._http("GET", f"/api2/json{path}", params=params)
        return wrapped.get("data") if isinstance(wrapped, dict) else wrapped

    def put(self, path: str, params: dict[str, Any]) -> Any:
        if self.use_pvesh:
            return self._pvesh("set", path, params)
        wrapped = self._http("PUT", f"/api2/json{path}", params=params)
        return wrapped.get("data") if isinstance(wrapped, dict) else wrapped


def guest_from_resource(item: dict[str, Any], s: Settings) -> Guest | None:
    gtype = item.get("type")
    if gtype not in ("qemu", "lxc"):
        return None
    vmid = item.get("vmid")
    if vmid is None:
        return None
    template = bool(item.get("template"))
    tags = split_tags(item.get("tags") or "")
    return Guest(
        vmid=int(vmid),
        name=str(item.get("name") or ""),
        type=gtype,
        node=str(item.get("node") or ""),
        tags=tags,
        template=template,
    )


def classify(guest: Guest, s: Settings) -> None:
    ci = s.case_insensitive
    have = {norm_tag(t, ci) for t in guest.tags}
    exclude = {norm_tag(t, ci) for t in s.exclude_tags}
    include = {norm_tag(t, ci) for t in s.include_tags}

    if guest.template and s.skip_templates:
        guest.skip_reason = "template"
        return
    if have & exclude:
        guest.excluded = True
        guest.skip_reason = "exclude-tag"
        return
    if include and not (have & include):
        guest.include_ok = False
        guest.skip_reason = "missing-include-tag"
        return

    matched: list[str] = []
    for mode, taglist in (
        ("snapshot", s.snapshot_tags),
        ("suspend", s.suspend_tags),
        ("stop", s.stop_tags),
    ):
        want = {norm_tag(t, ci) for t in taglist}
        if have & want:
            matched.append(mode)

    if len(matched) > 1:
        if s.conflict == "fail":
            die(
                f"VM {guest.vmid} ({guest.name}) has conflicting mode tags "
                f"{matched}. Resolve tags or set tags.conflict=use-default."
            )
        if s.conflict == "prefer-first":
            guest.mode = matched[0]
            guest.mode_reason = f"tags:{','.join(matched)}->first"
        else:
            guest.mode = s.default_mode
            guest.mode_reason = f"tags:{','.join(matched)}->default"
    elif len(matched) == 1:
        guest.mode = matched[0]
        guest.mode_reason = "tag"
    else:
        guest.mode = s.default_mode
        guest.mode_reason = "default"


def format_selection(job: dict[str, Any]) -> str:
    if job.get("pool"):
        return f"pool {job['pool']}"
    if job.get("all") in (1, True, "1"):
        excl = job.get("exclude") or ""
        return f"All except {excl}" if excl else "All"
    vmids = job.get("vmid") or ""
    return vmids if vmids else "(none)"


def vmid_csv(ids: list[int]) -> str:
    return ",".join(str(i) for i in sorted(ids))


def parse_vmid_list(raw: str | None) -> set[int]:
    out: set[int] = set()
    for part in split_csv(raw):
        out.add(int(part))
    return out


def print_guests(title: str, guests: list[Guest], extra: str | None = None) -> None:
    print(f"\n{title} ({len(guests)})")
    if extra:
        print(f"  {extra}")
    if not guests:
        print("  (none)")
        return
    print(f"  {'VMID':>6}  {'TYPE':<5}  {'NODE':<16}  {'MODE':<9}  NAME  [tags]")
    for g in sorted(guests, key=lambda x: x.vmid):
        tags = ";".join(g.tags) if g.tags else "-"
        print(
            f"  {g.vmid:6d}  {g.type:<5}  {g.node:<16}  {g.mode:<9}  "
            f"{g.name}  [{tags}]"
        )


def list_jobs(jobs: list[dict[str, Any]]) -> None:
    print(f"{'ID':<40} {'EN':<3} {'NODE':<12} {'SCHED':<12} {'MODE':<9} STORAGE  COMMENT")
    for job in jobs:
        jid = str(job.get("id") or "")
        en = "yes" if job.get("enabled", 1) not in (0, False, "0") else "no"
        node = job.get("node") or "All"
        sched = str(job.get("schedule") or "")
        mode = str(job.get("mode") or "snapshot")
        storage = str(job.get("storage") or "")
        comment = str(job.get("comment") or "")
        print(f"{jid:<40} {en:<3} {node:<12} {sched:<12} {mode:<9} {storage}  {comment}")
        print(f"    selection: {format_selection(job)}")


def build_update(
    s: Settings, job: dict[str, Any], guests: list[Guest]
) -> tuple[dict[str, Any], list[Guest], list[Guest], list[Guest]]:
    backupable = [g for g in guests if g.backupable]
    skipped = [g for g in guests if not g.backupable]
    target_mode = s.mode or s.default_mode
    if target_mode not in MODES:
        die(f"Invalid mode '{target_mode}'. Use {', '.join(MODES)}.")

    if s.selection == "all-except":
        included = backupable
        excluded_ids = [g.vmid for g in skipped]
        params: dict[str, Any] = {"all": 1}
        delete: list[str] = ["vmid", "pool"]
        if excluded_ids:
            params["exclude"] = vmid_csv(excluded_ids)
        else:
            delete.append("exclude")
        params["delete"] = ",".join(delete)
        mismatches = [g for g in included if g.mode != target_mode]
    elif s.selection == "include-mode":
        included = [g for g in backupable if g.mode == target_mode]
        skipped = skipped + [g for g in backupable if g.mode != target_mode]
        if not included:
            die(
                f"No guests resolve to mode '{target_mode}'. "
                "Refusing to empty the job (pass a different --mode or "
                "use --selection all-except)."
            )
        params = {"vmid": vmid_csv([g.vmid for g in included])}
        params["delete"] = "all,exclude,pool"
        mismatches = []
    else:
        die(f"Unknown selection '{s.selection}'. Use all-except or include-mode.")

    if s.sync_mode:
        params["mode"] = target_mode

    return params, included, skipped, mismatches


def current_sets(job: dict[str, Any]) -> tuple[str, set[int], str]:
    mode = str(job.get("mode") or "snapshot")
    if job.get("all") in (1, True, "1"):
        return "all-except", parse_vmid_list(job.get("exclude")), mode
    return "include", parse_vmid_list(job.get("vmid")), mode


def proposed_sets(
    s: Settings, params: dict[str, Any]
) -> tuple[str, set[int], str | None]:
    mode = params.get("mode")
    if params.get("all") in (1, True, "1"):
        return "all-except", parse_vmid_list(params.get("exclude")), mode
    return "include", parse_vmid_list(params.get("vmid")), mode


def needs_update(job: dict[str, Any], s: Settings, params: dict[str, Any]) -> bool:
    cur_sel, cur_ids, cur_mode = current_sets(job)
    new_sel, new_ids, new_mode = proposed_sets(s, params)
    if cur_sel != new_sel or cur_ids != new_ids:
        return True
    if s.sync_mode and new_mode and new_mode != cur_mode:
        return True
    return False


def confirm(prompt: str) -> bool:
    try:
        ans = input(f"{prompt} [y/N] ").strip().lower()
    except EOFError:
        return False
    return ans in ("y", "yes")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=(
            "Update a Proxmox cluster backup job from guest tags. "
            "Default policy: back up every VM/CT unless it has an exclude tag "
            "(no-backup). Mode tags optionally set snapshot/suspend/stop "
            "(default snapshot)."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --list-jobs
  %(prog)s --report
  %(prog)s --job-id <id>                 # plan only
  %(prog)s --job-id <id> --apply
  %(prog)s --config examples/tag-backup.conf --apply --yes

  # Split modes across two jobs (job mode is cluster-wide / one value):
  %(prog)s --job-id nightly-snap --selection include-mode --mode snapshot --apply
  %(prog)s --job-id nightly-stop --selection include-mode --mode stop --apply

Cluster API:
  GET /cluster/resources?type=vm  — every QEMU VM and LXC, with tags + node
  GET /cluster/backup             — jobs (stored in pmxcfs, not per-node)
  PUT /cluster/backup/{id}        — rewrite all/exclude or vmid + mode
""",
    )
    p.add_argument("-c", "--config", help="INI config (see examples/tag-backup.conf)")
    p.add_argument("--list-jobs", action="store_true", help="List backup jobs and exit")
    p.add_argument("--report", action="store_true", help="Classify all guests and exit")
    p.add_argument("--job-id", help="Backup job id (from --list-jobs)")
    p.add_argument(
        "--selection",
        choices=("all-except", "include-mode"),
        help="How to write the job (default: all-except)",
    )
    p.add_argument(
        "--mode",
        choices=MODES,
        help="Job/filter mode (default: tags.default_mode / snapshot)",
    )
    p.add_argument(
        "--sync-mode",
        dest="sync_mode",
        action="store_true",
        default=None,
        help="Also set the job's vzdump mode",
    )
    p.add_argument(
        "--no-sync-mode",
        dest="sync_mode",
        action="store_false",
        help="Do not change the job's vzdump mode",
    )
    p.add_argument(
        "--exclude-tags",
        help="Comma-separated opt-out tags (default: no-backup)",
    )
    p.add_argument("--include-tags", help="If set, guest must have one of these tags")
    p.add_argument("-d", "--dry-run", action="store_true", help="Plan only (default)")
    p.add_argument("--apply", action="store_true", help="Write the job via the API")
    p.add_argument("-y", "--yes", action="store_true", help="Do not prompt on --apply")
    p.add_argument("--verbose", action="store_true")
    return p.parse_args()


def overlay_args(s: Settings, args: argparse.Namespace) -> None:
    if args.job_id:
        s.job_id = args.job_id
    if args.selection:
        s.selection = args.selection
    if args.mode:
        s.mode = args.mode
    if args.sync_mode is not None:
        s.sync_mode = args.sync_mode
    if args.exclude_tags:
        s.exclude_tags = split_csv(args.exclude_tags)
    if args.include_tags is not None:
        s.include_tags = split_csv(args.include_tags)
    if s.default_mode not in MODES:
        die(f"Invalid default_mode '{s.default_mode}'")
    if s.conflict not in ("fail", "use-default", "prefer-first"):
        die("tags.conflict must be fail, use-default, or prefer-first")
    if s.selection not in ("all-except", "include-mode"):
        die("selection must be all-except or include-mode")


def main() -> None:
    args = parse_args()
    s = load_config(args.config)
    apply_env(s)
    overlay_args(s, args)

    if not args.list_jobs and not args.report and not s.job_id:
        die("Provide --job-id, --list-jobs, or --report (see --help).")

    client = PveClient(s, verbose=args.verbose)
    client.login()
    if client.use_pvesh:
        info("Using pvesh (cluster filesystem; all nodes' guests are visible)")
    else:
        info(f"Using API at {client._base()} (cluster-wide resources + backup jobs)")

    if args.list_jobs:
        jobs = client.get("/cluster/backup") or []
        if not jobs:
            warning("No backup jobs found")
            return
        list_jobs(jobs)
        return

    resources = client.get("/cluster/resources", {"type": "vm"}) or []
    guests: list[Guest] = []
    for item in resources:
        g = guest_from_resource(item, s)
        if g is None:
            continue
        classify(g, s)
        guests.append(g)

    if args.report or not s.job_id:
        print_guests("Backup", [g for g in guests if g.backupable])
        print_guests("Skipped", [g for g in guests if not g.backupable])
        by_mode: dict[str, list[Guest]] = {m: [] for m in MODES}
        for g in guests:
            if g.backupable:
                by_mode.setdefault(g.mode, []).append(g)
        print("\nResolved modes for guests that will be backed up:")
        for mode in MODES:
            print(f"  {mode}: {len(by_mode.get(mode, []))}")
        return

    jobs = client.get("/cluster/backup") or []
    job = next((j for j in jobs if str(j.get("id")) == s.job_id), None)
    if job is None:
        # Some versions only list summaries; try a direct GET.
        try:
            job = client.get(f"/cluster/backup/{s.job_id}")
        except SystemExit:
            job = None
    if not job:
        die(f"Backup job not found: {s.job_id} (try --list-jobs)")

    info(
        f"Job {s.job_id}: node={job.get('node') or 'All'} "
        f"schedule={job.get('schedule')} storage={job.get('storage')} "
        f"mode={job.get('mode') or 'snapshot'}"
    )
    info(f"Current selection: {format_selection(job)}")

    params, included, skipped, mismatches = build_update(s, job, guests)
    target_mode = params.get("mode") or s.mode or s.default_mode

    print_guests("Will back up (this job)", included)
    print_guests("Will not back up (this job)", skipped)
    if mismatches:
        warning(
            "These guests have a mode tag that differs from this job's mode "
            f"'{target_mode}'. Proxmox can only set one mode per job; they "
            "will still be included. Use --selection include-mode and a "
            "second job if you need mixed snapshot/stop/suspend."
        )
        print_guests("Mode mismatches (still included)", mismatches)

    if "vmid" in params:
        info(f"Proposed selection: {params['vmid']}")
    elif params.get("all"):
        excl = params.get("exclude")
        info(f"Proposed selection: All except {excl}" if excl else "Proposed selection: All")
    if s.sync_mode:
        info(f"Proposed vzdump mode: {target_mode}")

    changed = needs_update(job, s, params)
    if not changed:
        success("Job already matches tags; nothing to do")
        return

    if not args.apply or args.dry_run:
        info("Plan only. Re-run with --apply to write the job.")
        return

    if not args.yes and not confirm(f"Update backup job {s.job_id}?"):
        warning("Aborted")
        return

    client.put(f"/cluster/backup/{s.job_id}", params)
    success(f"Updated job {s.job_id}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        warning("Interrupted")
        raise SystemExit(130)
