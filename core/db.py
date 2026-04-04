"""
core/db.py — SQLite storage para histórico e sessões
"""
import sqlite3
import os
from pathlib import Path

DB_PATH = Path(os.environ.get("ENVCTL_DATA", Path.home() / ".envctl")) / "manager.db"


def get_connection() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_connection()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS sessions (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            profile     TEXT NOT NULL,
            wsl_user    TEXT NOT NULL,
            started_at  TEXT NOT NULL,
            ended_at    TEXT,
            duration_s  INTEGER
        );

        CREATE TABLE IF NOT EXISTS history (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            profile     TEXT NOT NULL,
            operation   TEXT NOT NULL,
            detail      TEXT,
            status      TEXT NOT NULL DEFAULT 'ok',
            ran_at      TEXT NOT NULL
        );
    """)
    conn.commit()
    conn.close()


def log_session_start(profile: str, wsl_user: str) -> int:
    from datetime import datetime, timezone
    conn = get_connection()
    cur = conn.execute(
        "INSERT INTO sessions (profile, wsl_user, started_at) VALUES (?,?,?)",
        (profile, wsl_user, datetime.now(timezone.utc).isoformat())
    )
    conn.commit()
    session_id = cur.lastrowid
    conn.close()
    return session_id


def log_session_end(session_id: int):
    from datetime import datetime, timezone
    conn = get_connection()
    row = conn.execute("SELECT started_at FROM sessions WHERE id=?", (session_id,)).fetchone()
    if row:
        from datetime import datetime
        started = datetime.fromisoformat(row["started_at"])
        ended = datetime.now(timezone.utc)
        duration = int((ended - started).total_seconds())
        conn.execute(
            "UPDATE sessions SET ended_at=?, duration_s=? WHERE id=?",
            (ended.isoformat(), duration, session_id)
        )
        conn.commit()
    conn.close()


def log_operation(profile: str, operation: str, detail: str = "", status: str = "ok"):
    from datetime import datetime, timezone
    conn = get_connection()
    conn.execute(
        "INSERT INTO history (profile, operation, detail, status, ran_at) VALUES (?,?,?,?,?)",
        (profile, operation, detail, status, datetime.now(timezone.utc).isoformat())
    )
    conn.commit()
    conn.close()


def get_history(profile: str = None, limit: int = 50) -> list:
    conn = get_connection()
    if profile:
        rows = conn.execute(
            "SELECT * FROM history WHERE profile=? ORDER BY ran_at DESC LIMIT ?",
            (profile, limit)
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM history ORDER BY ran_at DESC LIMIT ?",
            (limit,)
        ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_last_operation(profile: str) -> dict | None:
    conn = get_connection()
    row = conn.execute(
        "SELECT * FROM history WHERE profile=? ORDER BY ran_at DESC LIMIT 1",
        (profile,)
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def get_sessions(profile: str = None, limit: int = 20) -> list:
    conn = get_connection()
    if profile:
        rows = conn.execute(
            "SELECT * FROM sessions WHERE profile=? ORDER BY started_at DESC LIMIT ?",
            (profile, limit)
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM sessions ORDER BY started_at DESC LIMIT ?",
            (limit,)
        ).fetchall()
    conn.close()
    return [dict(r) for r in rows]
