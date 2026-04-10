#!/usr/bin/env python3

from collections import Counter
import datetime as dt
import json
import pathlib
import subprocess
import sys


SUCCESS_STALE_THRESHOLD_SECONDS = 10 * 60
REPEATED_401_WINDOW_SECONDS = 60 * 60
REPEATED_401_THRESHOLD = 2
REPEATED_429_WINDOW_SECONDS = 30 * 60
REPEATED_429_THRESHOLD = 2
WAKE_REFRESH_WINDOW_SECONDS = 2 * 60
DUPLICATE_WAKE_FETCH_WINDOW_SECONDS = 5
CACHED_DATA_THRESHOLD_SECONDS = 10 * 60
RESET_REFRESH_WINDOW_SECONDS = 2 * 60
LAUNCH_GRACE_SECONDS = 3 * 60
PROCESS_DRIFT_GRACE_SECONDS = 3 * 60
RECOVERY_VALIDATION_WINDOW_SECONDS = 3 * 60
HIDDEN_CLAUDE_COOLDOWN_SECONDS = 20 * 60


def parse_time(value):
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(dt.timezone.utc)
    except ValueError:
        return None


def format_time(value):
    parsed = parse_time(value) if isinstance(value, str) else value
    if not parsed:
        return "n/a"
    return parsed.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def age_string(value, now):
    parsed = parse_time(value) if isinstance(value, str) else value
    if not parsed:
        return "n/a"

    delta = now - parsed
    future = delta.total_seconds() < 0
    total_seconds = int(abs(delta.total_seconds()))
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)

    parts = []
    if hours:
        parts.append(f"{hours}h")
    if minutes or hours:
        parts.append(f"{minutes}m")
    parts.append(f"{seconds}s")

    suffix = "from now" if future else "ago"
    return f"{' '.join(parts)} {suffix}"


def format_time_and_age(value, now):
    parsed = parse_time(value) if isinstance(value, str) else value
    if not parsed:
        return "n/a"
    return f"{format_time(parsed)} ({age_string(parsed, now)})"


def load_status(path):
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return {}


def load_records(log_dir):
    paths = sorted(log_dir.glob("monitor.jsonl*"))
    records = []
    for path in paths:
        try:
            with path.open() as handle:
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        record = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    record["_timestamp"] = parse_time(record.get("timestamp"))
                    record["_source"] = path.name
                    records.append(record)
        except OSError:
            continue

    records.sort(key=lambda item: item.get("_timestamp") or dt.datetime.min.replace(tzinfo=dt.timezone.utc))
    return records


def live_pids():
    result = subprocess.run(
        ["pgrep", "-x", "ClaudeBat"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []

    pids = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.isdigit():
            pids.append(int(line))
    return sorted(set(pids))


def file_mtime(path):
    try:
        return dt.datetime.fromtimestamp(path.stat().st_mtime, tz=dt.timezone.utc)
    except OSError:
        return None


def newest_log_mtime(log_dir):
    newest = None
    for path in sorted(log_dir.glob("monitor.jsonl*")):
        mtime = file_mtime(path)
        if not mtime:
            continue
        if newest is None or mtime > newest:
            newest = mtime
    return newest


def is_recent(value, now, threshold_seconds):
    parsed = parse_time(value) if isinstance(value, str) else value
    if not parsed:
        return False
    return now - parsed <= dt.timedelta(seconds=threshold_seconds)


def records_within(records, seconds, now, *, outcome=None, action=None, category=None, trigger=None):
    filtered = []
    for record in records:
        timestamp = record.get("_timestamp")
        if not timestamp or now - timestamp > dt.timedelta(seconds=seconds):
            continue
        if outcome and record.get("outcome") != outcome:
            continue
        if action and record.get("action") != action:
            continue
        if category and record.get("event_category") != category:
            continue
        if trigger and record.get("trigger") != trigger:
            continue
        filtered.append(record)
    return filtered


def filter_current_session(records, status):
    current_build_flavor = status.get("build_flavor")
    current_git_commit = status.get("git_commit")
    current_launch = parse_time(status.get("last_launch_at"))

    if not current_launch:
        return records

    return [
        record
        for record in records
        if record.get("_timestamp")
        and record["_timestamp"] >= current_launch
        and (not current_build_flavor or record.get("build_flavor") == current_build_flavor)
        and (not current_git_commit or record.get("git_commit") == current_git_commit)
    ]


def latest_record(records, *, outcome=None, action=None, category=None, trigger=None):
    for record in reversed(records):
        if outcome and record.get("outcome") != outcome:
            continue
        if action and record.get("action") != action:
            continue
        if category and record.get("event_category") != category:
            continue
        if trigger and record.get("trigger") != trigger:
            continue
        return record
    return None


def format_record(record, now):
    trigger = record.get("trigger") or "-"
    outcome = record.get("outcome") or "-"
    action = record.get("action") or "-"
    message = record.get("message") or "-"
    source = record.get("_source") or "-"
    return (
        f"{format_time(record.get('timestamp'))} | {age_string(record.get('_timestamp'), now)} | "
        f"{record.get('event_category')} | {action} | {trigger} | {outcome} | {message} | {source}"
    )


def summarize_counts(records):
    outcomes = Counter(record.get("outcome") for record in records if record.get("outcome"))
    triggers = Counter(record.get("trigger") for record in records if record.get("trigger"))
    actions = Counter(
        f"{record.get('event_category')}:{record.get('action')}"
        for record in records
        if record.get("event_category") and record.get("action")
    )
    return outcomes, triggers, actions


def analyze_rate_limit_sequences(records):
    sequences = []
    for index, record in enumerate(records):
        if record.get("event_category") != "fetch" or record.get("outcome") != "rate_limited":
            continue

        blocked_followup = []
        recovery = None

        for later in records[index + 1:]:
            if later.get("event_category") != "fetch":
                continue

            later_action = later.get("action")
            later_outcome = later.get("outcome")

            if later_action == "blocked" and later_outcome in {"budget_blocked", "server_cooldown_blocked"}:
                blocked_followup.append(later)
                continue

            if later_action == "started":
                continue

            recovery = later
            break

        sequences.append(
            {
                "rate_limit": record,
                "blocked_followup": blocked_followup,
                "recovery": recovery,
            }
        )

    return sequences


def add_rule(results, name, state, observed, details):
    results.append(
        {
            "name": name,
            "state": state,
            "observed": observed,
            "details": details,
        }
    )


def main():
    home = pathlib.Path.home()
    status_path = home / "Library" / "Application Support" / "ClaudeBat" / "monitor-status.json"
    logs_dir = home / "Library" / "Logs" / "ClaudeBat"

    status = load_status(status_path)
    all_records = load_records(logs_dir)
    pids = live_pids()
    running = bool(pids)
    now = dt.datetime.now(dt.timezone.utc)
    anomalies = []
    warnings = []
    rule_results = []

    status_pid = status.get("pid")
    app_running = bool(status.get("app_running"))
    display_sleeping = bool(status.get("display_sleeping"))
    current_launch = parse_time(status.get("last_launch_at"))
    last_attempt = parse_time(status.get("last_attempt_at"))
    last_success = parse_time(status.get("last_success_at"))
    last_failure = parse_time(status.get("last_failure_at"))
    last_wake = parse_time(status.get("last_wake_at"))
    session_reset = parse_time(status.get("session_resets_at"))
    cached_session_reset = parse_time(status.get("cached_session_reset_at"))
    last_successful_usage_session_reset = parse_time(status.get("last_successful_usage_session_reset_at"))
    last_successful_auth_refresh = parse_time(status.get("last_successful_auth_refresh_at"))
    last_token_fingerprint_changed = parse_time(status.get("last_token_fingerprint_changed_at"))
    last_recovery_attempt = parse_time(status.get("last_recovery_attempt_at"))
    last_hidden_claude_activation = parse_time(status.get("last_hidden_claude_activation_at"))
    cache_age = status.get("cache_age_seconds")
    auth_recovery_phase = status.get("auth_recovery_phase")
    auth_recovery_result = status.get("auth_recovery_result")
    last_successful_auth_refresh_method = status.get("last_successful_auth_refresh_method")
    last_token_fingerprint = status.get("last_token_fingerprint")
    launch_age_seconds = (now - current_launch).total_seconds() if current_launch else None
    status_mtime = file_mtime(status_path)
    log_mtime = newest_log_mtime(logs_dir)

    records = filter_current_session(all_records, status)
    outcome_counts, trigger_counts, action_counts = summarize_counts(records)
    rate_limit_sequences = analyze_rate_limit_sequences(records)
    recent_rate_limit_sequences = [
        sequence
        for sequence in rate_limit_sequences
        if sequence["rate_limit"].get("_timestamp")
        and now - sequence["rate_limit"]["_timestamp"] <= dt.timedelta(seconds=REPEATED_429_WINDOW_SECONDS)
    ]
    recent_budget_streaks = [len(sequence["blocked_followup"]) for sequence in recent_rate_limit_sequences]
    max_recent_budget_streak = max(recent_budget_streaks, default=0)
    previous_session_records = [
        record
        for record in records
        if record.get("event_category") == "auth" and record.get("action") == "previous_session_detected"
    ]
    latest_previous_session = previous_session_records[-1] if previous_session_records else None
    recovery_attempt_actions = {
        "auth_recovery_started",
        "native_refresh_started",
        "manual_reconnect_required",
    }
    hidden_claude_records = [
        record
        for record in records
        if record.get("event_category") == "auth" and record.get("action") == "claude_cli_recovery_started"
    ]
    recent_hidden_claude = records_within(
        hidden_claude_records,
        HIDDEN_CLAUDE_COOLDOWN_SECONDS,
        now,
    )
    recovery_success_record = latest_record(records, action="auth_recovery_succeeded", category="auth")
    latest_validation_success = latest_record(records, action="usage_validation_after_refresh_succeeded", category="auth")
    latest_validation_failure = latest_record(records, action="usage_validation_after_refresh_failed", category="auth")
    latest_manual_reconnect = latest_record(records, action="manual_reconnect_required", category="auth")

    if not status:
        anomalies.append("Monitor status snapshot is missing or unreadable.")
        add_rule(
            rule_results,
            "status_snapshot_available",
            "ALERT",
            "missing",
            f"Expected status snapshot at {status_path}",
        )
    else:
        add_rule(
            rule_results,
            "status_snapshot_available",
            "OK",
            "present",
            f"Loaded {status_path}",
        )

    if not all_records:
        anomalies.append("Monitor event log is missing or unreadable.")
        add_rule(
            rule_results,
            "event_log_available",
            "ALERT",
            "missing",
            f"Expected monitor logs under {logs_dir}",
        )
    else:
        add_rule(
            rule_results,
            "event_log_available",
            "OK",
            f"{len(all_records)} total events",
            f"{len(records)} events match the current launch/build session",
        )

    recent_runtime_activity = any(
        is_recent(candidate, now, PROCESS_DRIFT_GRACE_SECONDS)
        for candidate in [status_mtime, log_mtime, last_attempt, last_success, last_failure]
    )

    if app_running and not running:
        observed = (
            f"snapshot_pid={status_pid or 'n/a'} live_pids=[] "
            f"status_write={format_time_and_age(status_mtime, now)} "
            f"log_write={format_time_and_age(log_mtime, now)}"
        )
        if recent_runtime_activity:
            warnings.append(
                "Snapshot says ClaudeBat is running but no live process was visible. "
                "Treating this as transient because monitor state updated recently."
            )
            add_rule(
                rule_results,
                "process_consistency",
                "WARN",
                observed,
                f"No live process was visible, but status/log activity is newer than {PROCESS_DRIFT_GRACE_SECONDS}s.",
            )
        else:
            anomalies.append("ClaudeBat status says app_running=true but no live process was visible and monitor state is stale.")
            add_rule(
                rule_results,
                "process_consistency",
                "ALERT",
                observed,
                f"No live process was visible and monitor state has not moved for at least {PROCESS_DRIFT_GRACE_SECONDS}s.",
            )
    elif app_running and running and status_pid and status_pid not in pids:
        warnings.append(
            "A ClaudeBat process is running, but the snapshot PID does not match the live PID list yet."
        )
        add_rule(
            rule_results,
            "process_consistency",
            "WARN",
            f"snapshot_pid={status_pid} live_pids={pids}",
            "Another ClaudeBat PID is live; snapshot PID appears stale or the app restarted.",
        )
    elif not app_running and running:
        warnings.append("A live ClaudeBat process exists, but the snapshot says app_running=false.")
        add_rule(
            rule_results,
            "process_consistency",
            "WARN",
            f"snapshot_pid={status_pid or 'n/a'} live_pids={pids}",
            "Live process exists but snapshot state has not caught up.",
        )
    else:
        add_rule(
            rule_results,
            "process_consistency",
            "OK",
            f"snapshot_pid={status_pid or 'n/a'} live_pids={pids}",
            "Snapshot PID and live process state agree.",
        )

    if app_running and not display_sleeping:
        if launch_age_seconds is not None and launch_age_seconds < LAUNCH_GRACE_SECONDS:
            add_rule(
                rule_results,
                "recent_success_while_awake",
                "SKIP",
                f"launch_age={int(launch_age_seconds)}s",
                f"In launch grace window ({LAUNCH_GRACE_SECONDS}s).",
            )
        elif not last_success or now - last_success > dt.timedelta(seconds=SUCCESS_STALE_THRESHOLD_SECONDS):
            anomalies.append("No successful fetch has been recorded in more than 10 minutes while the app reports it is awake.")
            add_rule(
                rule_results,
                "recent_success_while_awake",
                "ALERT",
                format_time_and_age(last_success, now),
                f"Expected a successful fetch within {SUCCESS_STALE_THRESHOLD_SECONDS}s while awake.",
            )
        else:
            add_rule(
                rule_results,
                "recent_success_while_awake",
                "OK",
                format_time_and_age(last_success, now),
                f"Successful fetch is within {SUCCESS_STALE_THRESHOLD_SECONDS}s.",
            )
    else:
        add_rule(
            rule_results,
            "recent_success_while_awake",
            "SKIP",
            f"app_running={app_running} display_sleeping={display_sleeping}",
            "Rule only applies while the app reports it is awake.",
        )

    recent_401 = records_within(records, REPEATED_401_WINDOW_SECONDS, now, outcome="http_401")
    if len(recent_401) >= REPEATED_401_THRESHOLD:
        latest_401 = recent_401[-1]
        resolved_after_401 = (
            (recovery_success_record and recovery_success_record.get("_timestamp") and recovery_success_record["_timestamp"] >= latest_401["_timestamp"])
            or (last_success and last_success >= latest_401["_timestamp"])
        )
        if resolved_after_401:
            warnings.append(
                f"Detected {len(recent_401)} HTTP 401 outcomes in the last 60 minutes, but a later recovery/success was recorded."
            )
            add_rule(
                rule_results,
                "repeated_http_401",
                "WARN",
                f"{len(recent_401)} events",
                f"Threshold is {REPEATED_401_THRESHOLD} within {REPEATED_401_WINDOW_SECONDS}s, but recovery completed after the latest 401.",
            )
        else:
            anomalies.append(f"Detected {len(recent_401)} HTTP 401 outcomes in the last 60 minutes.")
            add_rule(
                rule_results,
                "repeated_http_401",
                "ALERT",
                f"{len(recent_401)} events",
                f"Threshold is {REPEATED_401_THRESHOLD} within {REPEATED_401_WINDOW_SECONDS}s.",
            )
    else:
        add_rule(
            rule_results,
            "repeated_http_401",
            "OK",
            f"{len(recent_401)} events",
            f"Threshold is {REPEATED_401_THRESHOLD} within {REPEATED_401_WINDOW_SECONDS}s.",
        )

    recent_429 = records_within(records, REPEATED_429_WINDOW_SECONDS, now, outcome="rate_limited")
    if len(recent_429) >= REPEATED_429_THRESHOLD:
        anomalies.append(
            f"Detected {len(recent_429)} rate-limited outcomes in the last 30 minutes "
            f"with a max following blocked streak of {max_recent_budget_streak}."
        )
        add_rule(
            rule_results,
            "repeated_rate_limit",
            "ALERT",
            f"{len(recent_429)} events; blocked_followup_streaks={recent_budget_streaks}",
            f"Threshold is {REPEATED_429_THRESHOLD} within {REPEATED_429_WINDOW_SECONDS}s. "
            f"Max following blocked streak was {max_recent_budget_streak}.",
        )
    else:
        add_rule(
            rule_results,
            "repeated_rate_limit",
            "OK",
            f"{len(recent_429)} events; blocked_followup_streaks={recent_budget_streaks}",
            f"Threshold is {REPEATED_429_THRESHOLD} within {REPEATED_429_WINDOW_SECONDS}s. "
            f"Max following blocked streak was {max_recent_budget_streak}.",
        )

    last_wake_record = latest_record(records, action="wake_observed", category="lifecycle")
    if last_wake and now - last_wake > dt.timedelta(seconds=WAKE_REFRESH_WINDOW_SECONDS):
        wake_success = [
            record
            for record in records
            if record.get("outcome") == "success"
            and record.get("_timestamp")
            and last_wake <= record["_timestamp"] <= last_wake + dt.timedelta(seconds=WAKE_REFRESH_WINDOW_SECONDS)
        ]
        if not wake_success:
            if last_success and last_success > last_wake + dt.timedelta(seconds=WAKE_REFRESH_WINDOW_SECONDS):
                warnings.append(
                    "A wake event missed the 2-minute refresh target, but the app recovered later in the same wake cycle."
                )
                add_rule(
                    rule_results,
                    "wake_refresh_completion",
                    "WARN",
                    format_time_and_age(last_wake, now),
                    f"No success within {WAKE_REFRESH_WINDOW_SECONDS}s after wake, but a later success arrived at {format_time(last_success)}.",
                )
            else:
                anomalies.append("A wake event was observed but no successful refresh completed within 2 minutes.")
                add_rule(
                    rule_results,
                    "wake_refresh_completion",
                    "ALERT",
                    format_time_and_age(last_wake, now),
                    f"No success within {WAKE_REFRESH_WINDOW_SECONDS}s after wake.",
                )
        else:
            add_rule(
                rule_results,
                "wake_refresh_completion",
                "OK",
                format_time_and_age(last_wake, now),
                f"{len(wake_success)} success event(s) occurred within {WAKE_REFRESH_WINDOW_SECONDS}s after wake.",
            )
    else:
        observed = format_time_and_age(last_wake_record.get("_timestamp"), now) if last_wake_record else "n/a"
        details = "No wake has been observed yet."
        if last_wake and now - last_wake <= dt.timedelta(seconds=WAKE_REFRESH_WINDOW_SECONDS):
            details = f"Wake is still within the {WAKE_REFRESH_WINDOW_SECONDS}s analysis window."
        add_rule(rule_results, "wake_refresh_completion", "SKIP", observed, details)

    wake_fetch_starts = [
        record
        for record in records
        if record.get("action") == "started"
        and record.get("trigger") in {"screen_wake", "machine_wake"}
        and record.get("_timestamp")
        and now - record["_timestamp"] <= dt.timedelta(hours=1)
    ]
    duplicate_wake_pair = None
    for earlier, later in zip(wake_fetch_starts, wake_fetch_starts[1:]):
        if later["_timestamp"] - earlier["_timestamp"] <= dt.timedelta(seconds=DUPLICATE_WAKE_FETCH_WINDOW_SECONDS):
            duplicate_wake_pair = (earlier, later)
            break

    if duplicate_wake_pair:
        anomalies.append("Duplicate wake-triggered fetch starts occurred within 5 seconds.")
        add_rule(
            rule_results,
            "duplicate_wake_fetch_starts",
            "ALERT",
            f"{format_time(duplicate_wake_pair[0]['_timestamp'])} and {format_time(duplicate_wake_pair[1]['_timestamp'])}",
            f"Two wake-triggered fetch starts occurred within {DUPLICATE_WAKE_FETCH_WINDOW_SECONDS}s.",
        )
    else:
        add_rule(
            rule_results,
            "duplicate_wake_fetch_starts",
            "OK",
            f"{len(wake_fetch_starts)} wake-triggered start(s) in 1h",
            f"No pair was closer than {DUPLICATE_WAKE_FETCH_WINDOW_SECONDS}s.",
        )

    if status.get("using_cached_data") and isinstance(cache_age, int) and cache_age > CACHED_DATA_THRESHOLD_SECONDS:
        anomalies.append("ClaudeBat is still rendering cached data that is older than 10 minutes.")
        add_rule(
            rule_results,
            "aged_cached_data_rendering",
            "ALERT",
            f"cache_age={cache_age}s stale_reason={status.get('stale_reason') or 'n/a'}",
            f"Threshold is {CACHED_DATA_THRESHOLD_SECONDS}s.",
        )
    else:
        add_rule(
            rule_results,
            "aged_cached_data_rendering",
            "OK",
            f"using_cached_data={status.get('using_cached_data')} cache_age={cache_age}",
            f"Threshold is {CACHED_DATA_THRESHOLD_SECONDS}s.",
        )

    if app_running and not display_sleeping and session_reset and now - session_reset > dt.timedelta(seconds=RESET_REFRESH_WINDOW_SECONDS):
        if not last_success or last_success < session_reset:
            anomalies.append("The session reset boundary has passed but no successful post-reset refresh was recorded within 2 minutes.")
            add_rule(
                rule_results,
                "post_reset_refresh",
                "ALERT",
                f"reset={format_time(session_reset)} last_success={format_time(last_success)}",
                f"Expected a success within {RESET_REFRESH_WINDOW_SECONDS}s after the reset boundary.",
            )
        else:
            add_rule(
                rule_results,
                "post_reset_refresh",
                "OK",
                f"reset={format_time(session_reset)} last_success={format_time(last_success)}",
                "At least one success occurred after the reset boundary.",
            )
    else:
        details = "Reset boundary has not passed or app is not awake."
        if session_reset:
            details = f"Reset is {age_string(session_reset, now)} and the rule waits until {RESET_REFRESH_WINDOW_SECONDS}s after reset."
        add_rule(
            rule_results,
            "post_reset_refresh",
            "SKIP",
            format_time_and_age(session_reset, now),
            details,
        )

    if latest_previous_session:
        previous_detected_at = latest_previous_session.get("_timestamp")
        followup = next(
            (
                record for record in records
                if record.get("_timestamp")
                and previous_detected_at
                and record["_timestamp"] >= previous_detected_at
                and record.get("event_category") == "auth"
                and record.get("action") in recovery_attempt_actions
            ),
            None,
        )
        if followup:
            add_rule(
                rule_results,
                "previous_session_recovery_attempted",
                "OK",
                format_time_and_age(previous_detected_at, now),
                f"Followed by auth action {followup.get('action')} at {format_time(followup.get('_timestamp'))}.",
            )
        else:
            anomalies.append("A previous-session cache was detected but no auth recovery or reconnect path was started.")
            add_rule(
                rule_results,
                "previous_session_recovery_attempted",
                "ALERT",
                format_time_and_age(previous_detected_at, now),
                "Expected auth recovery or reconnect handling immediately after previous_session_detected.",
            )
    else:
        add_rule(
            rule_results,
            "previous_session_recovery_attempted",
            "SKIP",
            "n/a",
            "No previous-session detection event was recorded in the current launch/build session.",
        )

    recovery_in_progress = auth_recovery_phase in {
        "native_refresh_in_flight",
        "claude_cli_recovery_in_flight",
        "awaiting_usage_validation",
    }
    if recovery_in_progress and last_recovery_attempt:
        if (
            now - last_recovery_attempt > dt.timedelta(seconds=RECOVERY_VALIDATION_WINDOW_SECONDS)
            and (not last_success or last_success < last_recovery_attempt)
            and (not latest_manual_reconnect or latest_manual_reconnect.get("_timestamp", dt.datetime.min.replace(tzinfo=dt.timezone.utc)) < last_recovery_attempt)
        ):
            anomalies.append("Auth recovery has been in progress too long without a successful usage validation or reconnect fallback.")
            add_rule(
                rule_results,
                "auth_recovery_completion",
                "ALERT",
                f"phase={auth_recovery_phase} started={format_time_and_age(last_recovery_attempt, now)}",
                f"Expected recovery success or reconnect within {RECOVERY_VALIDATION_WINDOW_SECONDS}s.",
            )
        else:
            add_rule(
                rule_results,
                "auth_recovery_completion",
                "OK",
                f"phase={auth_recovery_phase} started={format_time_and_age(last_recovery_attempt, now)}",
                f"Recovery is active and still within the {RECOVERY_VALIDATION_WINDOW_SECONDS}s validation window.",
            )
    else:
        add_rule(
            rule_results,
            "auth_recovery_completion",
            "SKIP",
            f"phase={auth_recovery_phase or 'n/a'} result={auth_recovery_result or 'n/a'}",
            "Auth recovery is not currently in flight.",
        )

    if len(recent_hidden_claude) > 1:
        anomalies.append("Hidden Claude fallback was invoked more than once inside the cooldown window.")
        add_rule(
            rule_results,
            "hidden_claude_fallback_frequency",
            "ALERT",
            f"{len(recent_hidden_claude)} launches",
            f"Expected at most one hidden Claude launch within {HIDDEN_CLAUDE_COOLDOWN_SECONDS}s.",
        )
    else:
        add_rule(
            rule_results,
            "hidden_claude_fallback_frequency",
            "OK",
            f"{len(recent_hidden_claude)} launches",
            f"Expected at most one hidden Claude launch within {HIDDEN_CLAUDE_COOLDOWN_SECONDS}s.",
        )

    previous_session_stale_render = (
        bool(status.get("using_cached_data"))
        and cached_session_reset
        and now > cached_session_reset
        and (not last_success or last_success < cached_session_reset)
    )
    if previous_session_stale_render:
        anomalies.append("ClaudeBat is rendering cached data from a previous session instead of hiding usage and recovering.")
        add_rule(
            rule_results,
            "previous_session_cached_rendering",
            "ALERT",
            f"cached_reset={format_time(cached_session_reset)} last_success={format_time(last_success)}",
            "Previous-session cached usage should be hidden until recovery succeeds.",
        )
    else:
        add_rule(
            rule_results,
            "previous_session_cached_rendering",
            "OK",
            f"using_cached_data={status.get('using_cached_data')} cached_reset={format_time(cached_session_reset)}",
            "No previous-session cached usage is currently being rendered.",
        )

    status_label = "ALERT" if anomalies else "OK"
    print(f"STATUS: {status_label}")
    print("")

    print("Snapshot:")
    print(f"- App running: {running} (snapshot says {app_running})")
    print(f"- Snapshot PID: {status_pid if status_pid is not None else 'n/a'}")
    print(f"- Live PIDs: {pids or []}")
    print(f"- Display sleeping: {display_sleeping}")
    print(f"- Build flavor: {status.get('build_flavor') or 'n/a'}")
    print(f"- Git commit: {status.get('git_commit') or 'n/a'}")
    print(f"- Launch time: {format_time_and_age(current_launch, now)}")
    print(f"- Status file modified: {format_time_and_age(status_mtime, now)}")
    print(f"- Newest log modified: {format_time_and_age(log_mtime, now)}")
    print(f"- Last attempt: {format_time_and_age(last_attempt, now)}")
    print(f"- Last success: {format_time_and_age(last_success, now)}")
    print(f"- Last failure: {format_time_and_age(last_failure, now)}")
    print(f"- Last failure reason: {status.get('last_failure_reason') or 'n/a'}")
    print(f"- Last HTTP status: {status.get('last_http_status') if status else 'n/a'}")
    print(f"- Current poll interval: {status.get('current_poll_interval_seconds') if status else 'n/a'}s")
    print(f"- Consecutive failures: {status.get('consecutive_failures') if status else 'n/a'}")
    print(f"- Using cached data: {status.get('using_cached_data') if status else False}")
    print(f"- Cached-data reason: {status.get('stale_reason') or 'n/a'}")
    print(f"- Cache age: {status.get('cache_age_seconds') if status else 'n/a'}s")
    print(f"- Session remaining: {status.get('session_remaining') if status else 'n/a'}")
    print(f"- Session resets at: {format_time_and_age(session_reset, now)}")
    print(f"- Cached session reset at: {format_time_and_age(cached_session_reset, now)}")
    print(f"- Last successful usage session reset at: {format_time_and_age(last_successful_usage_session_reset, now)}")
    print(f"- Last successful auth refresh at: {format_time_and_age(last_successful_auth_refresh, now)}")
    print(f"- Last successful auth refresh method: {last_successful_auth_refresh_method or 'n/a'}")
    print(f"- Last token fingerprint changed at: {format_time_and_age(last_token_fingerprint_changed, now)}")
    print(f"- Last recovery attempt at: {format_time_and_age(last_recovery_attempt, now)}")
    print(f"- Last hidden Claude activation at: {format_time_and_age(last_hidden_claude_activation, now)}")
    print(f"- Auth recovery phase: {auth_recovery_phase or 'n/a'}")
    print(f"- Auth recovery result: {auth_recovery_result or 'n/a'}")
    print(f"- Last wake: {format_time_and_age(last_wake, now)}")
    print(f"- Status file: {status_path}")
    print(f"- Log directory: {logs_dir}")
    print("")

    print("Session Metrics:")
    print(f"- Session events loaded: {len(records)}")
    print(f"- Outcomes: {dict(sorted(outcome_counts.items())) or {}}")
    print(f"- Triggers: {dict(sorted(trigger_counts.items())) or {}}")
    print(f"- Actions: {dict(sorted(action_counts.items())) or {}}")
    print(
        "- Window counts: "
        f"15m success={len(records_within(records, 15 * 60, now, outcome='success'))}, "
        f"15m 401={len(records_within(records, 15 * 60, now, outcome='http_401'))}, "
        f"15m 429={len(records_within(records, 15 * 60, now, outcome='rate_limited'))}, "
        f"15m blocked={len(records_within(records, 15 * 60, now, action='blocked', category='fetch'))}, "
        f"60m wake_starts={len(wake_fetch_starts)}, "
        f"20m hidden_claude={len(recent_hidden_claude)}"
    )
    print(f"- Rate-limit blocked-budget streaks in 30m: {recent_budget_streaks or []} (max={max_recent_budget_streak})")
    print("")

    print("Rule Checks:")
    for result in rule_results:
        print(f"- [{result['state']}] {result['name']}: {result['observed']}")
        print(f"  {result['details']}")

    if anomalies:
        print("")
        print("Anomalies:")
        for item in anomalies:
            print(f"- {item}")

    if warnings:
        print("")
        print("Warnings:")
        for item in warnings:
            print(f"- {item}")

    print("")

    last_401 = latest_record(records, outcome="http_401")
    last_429 = latest_record(records, outcome="rate_limited")
    last_network = latest_record(records, outcome="network_error")
    last_blocked = latest_record(records, action="blocked", category="fetch")
    last_stale_entered = latest_record(records, action="entered", category="stale_state")
    last_previous_session = latest_record(records, action="previous_session_detected", category="auth")
    last_recovery_started = latest_record(records, action="auth_recovery_started", category="auth")
    last_native_refresh = latest_record(records, action="native_refresh_succeeded", category="auth")
    last_claude_cli = latest_record(records, action="claude_cli_recovery_succeeded", category="auth")
    last_manual_reconnect = latest_record(records, action="manual_reconnect_required", category="auth")

    print("Recent Markers:")
    print(f"- Last 401: {format_time_and_age(last_401.get('_timestamp'), now) if last_401 else 'n/a'}")
    print(f"- Last 429: {format_time_and_age(last_429.get('_timestamp'), now) if last_429 else 'n/a'}")
    print(f"- Last network error: {format_time_and_age(last_network.get('_timestamp'), now) if last_network else 'n/a'}")
    print(f"- Last blocked fetch: {format_time_and_age(last_blocked.get('_timestamp'), now) if last_blocked else 'n/a'}")
    print(f"- Last stale-state enter: {format_time_and_age(last_stale_entered.get('_timestamp'), now) if last_stale_entered else 'n/a'}")
    print(f"- Last previous-session detect: {format_time_and_age(last_previous_session.get('_timestamp'), now) if last_previous_session else 'n/a'}")
    print(f"- Last auth recovery start: {format_time_and_age(last_recovery_started.get('_timestamp'), now) if last_recovery_started else 'n/a'}")
    print(f"- Last native refresh success: {format_time_and_age(last_native_refresh.get('_timestamp'), now) if last_native_refresh else 'n/a'}")
    print(f"- Last hidden Claude success: {format_time_and_age(last_claude_cli.get('_timestamp'), now) if last_claude_cli else 'n/a'}")
    print(f"- Last manual reconnect required: {format_time_and_age(last_manual_reconnect.get('_timestamp'), now) if last_manual_reconnect else 'n/a'}")
    print("")

    if recent_rate_limit_sequences:
        print("Rate Limit Analysis:")
        for sequence in recent_rate_limit_sequences:
            rate_limit = sequence["rate_limit"]
            blocked_followup = sequence["blocked_followup"]
            recovery = sequence["recovery"]
            print(
                f"- Rate limit at {format_time_and_age(rate_limit.get('_timestamp'), now)} "
                f"followed by {len(blocked_followup)} blocked follow-up fetch(es); "
                f"recovery={format_time_and_age(recovery.get('_timestamp'), now) if recovery else 'n/a'}"
            )
            for blocked in blocked_followup[:5]:
                print(f"  - blocked: {format_record(blocked, now)}")
            if len(blocked_followup) > 5:
                print(f"  - ... {len(blocked_followup) - 5} more blocked fetches in this streak")
        print("")

    if last_wake_record:
        wake_window_records = [
            record
            for record in records
            if record.get("_timestamp")
            and last_wake_record["_timestamp"] <= record["_timestamp"] <= last_wake_record["_timestamp"] + dt.timedelta(seconds=WAKE_REFRESH_WINDOW_SECONDS)
        ]
        print("Last Wake Window:")
        print(f"- Wake source: {last_wake_record.get('wake_source') or 'n/a'}")
        print(f"- Wake time: {format_time_and_age(last_wake_record.get('_timestamp'), now)}")
        if wake_window_records:
            for record in wake_window_records[:10]:
                print(f"  - {format_record(record, now)}")
        else:
            print("  - No events captured in the wake analysis window.")
        print("")

    if session_reset:
        post_reset_records = [
            record
            for record in records
            if record.get("_timestamp") and record["_timestamp"] >= session_reset
        ]
        print("Reset Boundary Analysis:")
        print(f"- Reset time: {format_time_and_age(session_reset, now)}")
        print(f"- Events since reset: {len(post_reset_records)}")
        if post_reset_records:
            for record in post_reset_records[:10]:
                print(f"  - {format_record(record, now)}")
        else:
            print("  - No current-session events after the reset boundary.")
        print("")

    print("Recent Relevant Events:")
    relevant = [
        record
        for record in records
        if record.get("event_category") in {"fetch", "lifecycle", "auth", "stale_state", "timer"}
    ]
    for record in relevant[-20:]:
        print(f"- {format_record(record, now)}")

    return 1 if anomalies else 0


if __name__ == "__main__":
    sys.exit(main())
