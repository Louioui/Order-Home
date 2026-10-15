#!/usr/bin/env python3
"""Run database checks in a fresh, disposable, loopback-only PostgreSQL cluster.

Requires initdb, pg_ctl and psql on PATH. Never connects to a hosted database.
Supabase Auth is replaced only inside this disposable cluster by a small fixture;
these tests do not validate JWTs, Apple sign-in, Realtime transport or APNs.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import shutil
import socket
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
USERS = [f"20000000-0000-0000-0000-{n:012d}" for n in range(1, 5)]


def command(args, *, input=None):
    result = subprocess.run(args, input=input, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr[-4000:] or result.stdout[-4000:])
    return result.stdout


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def concurrency_checks(psql):
    def sql(query):
        return command(psql, input=query).strip()

    def identity(user, query):
        return f"set role authenticated; select set_config('request.jwt.claim.sub',{quote(user)},false); {query}"

    def value(query):
        return sql(query).splitlines()[-1]

    def as_value(user, query):
        return value(identity(user, query))

    def parallel(calls):
        barrier = threading.Barrier(len(calls))

        def run(call):
            barrier.wait(timeout=10)
            try:
                return (True, sql(call))
            except RuntimeError as error:
                return (False, str(error))

        with ThreadPoolExecutor(max_workers=len(calls)) as pool:
            return list(pool.map(run, calls))

    sql("insert into auth.users(id) values " + ",".join(f"({quote(u)})" for u in USERS))

    def kitchen(mode):
        return as_value(USERS[0], f"select public.create_kitchen('Concurrency table',{quote(mode)},'Owner')")

    def invite(kitchen_id):
        return json.loads(as_value(USERS[0], f"select public.create_kitchen_invite({quote(kitchen_id)})"))["token"]

    # Two distinct invitations race for the last couple seat.
    two = kitchen("couple")
    tokens = [invite(two), invite(two)]
    results = parallel([
        identity(USERS[n + 1], f"select public.join_kitchen({quote(tokens[n])},'Guest')")
        for n in range(2)
    ])
    assert sum(success for success, _ in results) == 1, "Both concurrent couple joins succeeded"
    assert any("already has two people" in output for success, output in results if not success)
    assert value(f"select count(*) from public.household_members where household_id={quote(two)}") == "2"

    # The same single-use invitation cannot admit two different people.
    family = kitchen("family")
    token = invite(family)
    results = parallel([
        identity(user, f"select public.join_kitchen({quote(token)},'Guest')") for user in USERS[1:3]
    ])
    assert sum(success for success, _ in results) == 1, "Single-use invite admitted two concurrent users"
    assert any("Invitation is unavailable or expired" in output for success, output in results if not success)
    guest = value(f"select user_id from public.household_members where household_id={quote(family)} and user_id<>{quote(USERS[0])}")

    session = as_value(USERS[0], f"select public.open_dinner({quote(family)},now()+interval '1 hour')")
    first = as_value(USERS[0], f"select public.add_pitch({quote(session)},'pasta')")
    second = as_value(guest, f"select public.add_pitch({quote(session)},'soup')")
    sql(identity(USERS[0], f"select public.start_voting({quote(session)})"))

    def ballot(a, b):
        return quote(json.dumps([{"pitch_id": first, "weight": a}, {"pitch_id": second, "weight": b}])) + "::jsonb"

    # The final simultaneous submissions resolve once under the session lock.
    results = parallel([
        identity(USERS[0], f"select public.submit_order({quote(session)},{ballot(2, 0)})"),
        identity(guest, f"select public.submit_order({quote(session)},{ballot(1, 2)})"),
    ])
    assert all(success for success, _ in results), "Concurrent valid ballots failed"
    snapshots = [json.loads(as_value(user, f"select public.kitchen_snapshot({quote(family)})")) for user in (USERS[0], guest)]
    assert snapshots[0] == snapshots[1], "Members disagree after concurrent submissions"
    assert snapshots[0]["session"]["status"] == "ticket_locked"
    assert snapshots[0]["session"]["winning_pitch_id"] == first
    assert len(snapshots[0]["votes"]) == 4
    assert all(order["submitted_at"] for order in snapshots[0]["orders"])

    # Joining and opening voting must produce an exact membership snapshot,
    # regardless of which request wins the household lock.
    boundary = kitchen("family")
    token = invite(boundary)
    session = as_value(USERS[0], f"select public.open_dinner({quote(boundary)},now()+interval '1 hour')")
    sql(identity(USERS[0], f"select public.add_pitch({quote(session)},'pasta'); select public.add_pitch({quote(session)},'soup')"))
    results = parallel([
        identity(USERS[0], f"select public.start_voting({quote(session)})"),
        identity(USERS[1], f"select public.join_kitchen({quote(token)},'Guest')"),
    ])
    assert results[0][0], "Opening voting failed during concurrent join"
    if not results[1][0]:
        assert "Join after the current dinner" in results[1][1]
    snap = json.loads(as_value(USERS[0], f"select public.kitchen_snapshot({quote(boundary)})"))
    assert {member["id"] for member in snap["members"]} == {order["member_id"] for order in snap["orders"]}, "Concurrent join escaped the voter snapshot"
    print("Passed four concurrent invitation, ballot and voter-snapshot checks.")


def main():
    for program in ("initdb", "pg_ctl", "psql"):
        if not shutil.which(program):
            raise SystemExit(f"Required local PostgreSQL program is missing: {program}")
    with tempfile.TemporaryDirectory(prefix="order-home-db-tests-") as temporary:
        directory = Path(temporary)
        data = directory / "data"
        with socket.socket() as available:
            available.bind(("127.0.0.1", 0))
            port = available.getsockname()[1]
        command(["initdb", "-D", str(data), "-U", "postgres", "-A", "trust", "--no-locale", "-E", "UTF8"])
        command(["pg_ctl", "-D", str(data), "-l", str(directory / "postgres.log"), "-o", f"-h 127.0.0.1 -p {port} -c wal_level=logical", "-w", "start"])
        try:
            psql = ["psql", "-X", "-qAt", "-h", "127.0.0.1", "-p", str(port), "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"]
            command(psql, input="""
                create role anon; create role authenticated; create role service_role;
                create schema auth; create table auth.users(id uuid primary key);
                create function auth.uid() returns uuid language sql stable set search_path = '' as $$
                  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
                $$;
                grant usage on schema auth to authenticated;
                grant execute on function auth.uid() to authenticated;
                create publication supabase_realtime;
            """)
            for migration in sorted((ROOT / "supabase/migrations").glob("*.sql")):
                command(psql + ["-f", str(migration)])
                print(f"Applied {migration.name}")
            for test in ("security_and_workflow.sql", "shared_kitchens.sql"):
                command(psql + ["-f", str(ROOT / "supabase/tests" / test)])
                print(f"Passed {test}")
            concurrency_checks(psql)
            print("All local database checks passed. Hosted Supabase/Apple services were not exercised.")
        finally:
            command(["pg_ctl", "-D", str(data), "-m", "fast", "-w", "stop"])


if __name__ == "__main__":
    main()
