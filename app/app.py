import os
import socket
import time
from datetime import datetime, timezone

import psycopg2
from flask import Flask, jsonify, render_template_string

app = Flask(__name__)

DATABASE_URL = os.environ.get("DATABASE_URL")
ENVIRONMENT = os.environ.get("APP_ENV", "unknown")
CLOUD_PROVIDER = os.environ.get("CLOUD_PROVIDER", "AWS")


def get_connection():
    return psycopg2.connect(DATABASE_URL, connect_timeout=5)


def init_db():
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS visits (
            id SERIAL PRIMARY KEY,
            visited_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """
    )
    conn.commit()
    cur.close()
    conn.close()


def record_visit():
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS visits (
            id SERIAL PRIMARY KEY,
            visited_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """
    )
    cur.execute("INSERT INTO visits (visited_at) VALUES (now())")
    conn.commit()
    cur.execute("SELECT count(*) FROM visits")
    total = cur.fetchone()[0]
    cur.close()
    conn.close()
    return total


PAGE = """
<!doctype html>
<html>
<head><title>DevOps Puzzle - {{ env }}</title></head>
<body style="font-family: sans-serif; max-width: 640px; margin: 40px auto;">
  <h1>Deployment Info</h1>
  <ul>
    <li><b>Environment:</b> {{ env }}</li>
    <li><b>Cloud provider:</b> {{ provider }}</li>
    <li><b>Server time (UTC):</b> {{ now }}</li>
    <li><b>Host:</b> {{ host }}</li>
    <li><b>Database writes recorded:</b> {{ visits }}</li>
  </ul>
</body>
</html>
"""


@app.route("/")
def index():
    visits = record_visit()
    return render_template_string(
        PAGE,
        env=ENVIRONMENT,
        provider=CLOUD_PROVIDER,
        now=datetime.now(timezone.utc).isoformat(),
        host=socket.gethostname(),
        visits=visits,
    )


@app.route("/health")
def health():
    try:
        conn = get_connection()
        conn.close()
        return jsonify(status="ok", database="reachable"), 200
    except Exception as exc:
        return jsonify(status="error", database=str(exc)), 503


if __name__ == "__main__":
    for _ in range(10):
        try:
            init_db()
            break
        except Exception:
            time.sleep(3)
    app.run(host="0.0.0.0", port=8080)