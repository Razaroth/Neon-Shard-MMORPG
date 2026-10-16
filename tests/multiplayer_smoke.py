"""Real ENet clients, shared world, authoritative movement, disk save and restart."""
import json
import math
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="neon-smoke-") as temp:
        temp = Path(temp)
        env = dict(os.environ)
        for key, name in [("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache"), ("XDG_CONFIG_HOME", "config")]:
            env[key] = str(temp / name)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind(("127.0.0.1", 0))
            port = str(sock.getsockname()[1])
        base = [str(ROOT / "tools/godot.sh"), "--headless", "--", "--port", port]
        world = temp / "world"
        processes = []
        logs = []

        def server():
            log = open(temp / f"server-{len(logs)}.log", "w+")
            logs.append(log)
            proc = subprocess.Popen(base + ["--server", "--save-dir", str(world)], env=env, stdout=log, stderr=subprocess.STDOUT)
            processes.append(proc)
            for _ in range(100):
                log.flush()
                if "SERVER_READY" in Path(log.name).read_text():
                    return proc
                if proc.poll() is not None:
                    raise AssertionError(Path(log.name).read_text())
                time.sleep(0.05)
            raise AssertionError("Server startup timed out")

        def client(identity, peers, mode="--smoke-client", chosen="ronin", expected="ronin", slot=1, extra=None):
            proc = subprocess.Popen(base + [mode, "--identity-file", str(temp / identity), "--expect-peers", str(peers), "--class", chosen, "--expect-class", expected, "--slot", str(slot)] + (extra or []), env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            processes.append(proc)
            return proc

        def result(proc):
            output, _ = proc.communicate(timeout=18)
            assert proc.returncode == 0 and "SMOKE_OK" in output, output
            assert "SCRIPT ERROR" not in output and "ERROR:" not in output, output
            match = re.search(r"INITIAL_POSITION ([\d.-]+) ([\d.-]+)", output)
            assert match, output
            return float(match[1]), float(match[2])

        try:
            running = server()
            first, second = client("a.cfg", 2, chosen="vanguard", expected="vanguard"), client("b.cfg", 2, chosen="cipher", expected="cipher")
            assert result(first) == (0.0, 0.0)
            assert result(second) == (0.0, 0.0)
            saves = json.loads((world / "characters.json").read_text())
            assert len(saves) == 2, saves
            assert all(20 < math.hypot(entry["x"], entry["y"]) < 1100 for entry in saves.values()), saves
            expected_position = next((entry["x"], entry["y"]) for entry in saves.values() if entry["archetype"] == "vanguard")
            assert {entry["archetype"] for entry in saves.values()} == {"vanguard", "cipher"}, saves
            running.terminate()
            running.wait(timeout=5)
            running = server()
            restored = result(client("a.cfg", 1, chosen="ghost", expected="vanguard"))
            assert math.dist(restored, expected_position) < 0.01, (restored, expected_position)
            for log in logs:
                assert "SCRIPT ERROR" not in Path(log.name).read_text(), Path(log.name).read_text()
            fighter = client("fighter.cfg", 1, "--combat-smoke", chosen="machinist", expected="machinist")
            output, _ = fighter.communicate(timeout=45)
            assert fighter.returncode == 0 and "COMBAT_OK" in output, output
            assert "SCRIPT ERROR" not in output and "ERROR:" not in output, output
            running.terminate()
            running.wait(timeout=5)
            running = server()
            restored_client = client("fighter.cfg", 1, "--verify-progress", chosen="cipher", expected="machinist")
            output, _ = restored_client.communicate(timeout=15)
            assert restored_client.returncode == 0 and "PROGRESS_RESTORED" in output, output
            assert "SCRIPT ERROR" not in output and "ERROR:" not in output, output
            result(client("a.cfg", 1, chosen="ghost", expected="ghost", slot=2))
            running.terminate()
            running.wait(timeout=5)
            running = server()
            probes = [client("a.cfg", 1, "--verify-class", chosen="cipher", expected="vanguard", slot=1), client("a.cfg", 1, "--verify-class", chosen="ronin", expected="ghost", slot=2)]
            for probe in probes:
                output, _ = probe.communicate(timeout=15)
                assert probe.returncode == 0 and "CLASS_SLOT_OK" in output, output
                assert "ERROR:" not in output, output
            resident = client("resident.cfg", 1, "--observe-travel", chosen="cipher", expected="cipher")
            traveller = client("traveller.cfg", 1, "--travel-smoke", chosen="vanguard", expected="vanguard")
            travel_output, _ = traveller.communicate(timeout=75)
            assert traveller.returncode == 0 and "ENTERED_MAINTENANCE" in travel_output and "TRAVEL_COMBAT_OK" in travel_output, travel_output
            assert "ERROR:" not in travel_output, travel_output
            observer_output, _ = resident.communicate(timeout=15)
            assert resident.returncode == 0 and "ROOM_ISOLATION_OK" in observer_output, observer_output
            assert "ERROR:" not in observer_output, observer_output
            records = json.loads((world / "characters.json").read_text())
            room_record = next(entry for entry in records.values() if entry.get("zone") == "maintenance")
            assert room_record["scrap"] >= 1 and room_record["archetype"] == "vanguard", room_record
            running.terminate()
            running.wait(timeout=5)
            running = server()
            probe = client("traveller.cfg", 1, "--verify-room", chosen="cipher", expected="vanguard", extra=["--expect-room", "maintenance", "--expect-hp", str(room_record["hp"]), "--expect-scrap", str(room_record["scrap"])])
            probe_output, _ = probe.communicate(timeout=15)
            assert probe.returncode == 0 and "ROOM_RESTORED" in probe_output and "ERROR:" not in probe_output, probe_output
            returning = client("traveller.cfg", 1, "--return-smoke", chosen="cipher", expected="vanguard")
            return_output, _ = returning.communicate(timeout=75)
            assert returning.returncode == 0 and "RETURN_TRAVEL_OK" in return_output and "ERROR:" not in return_output, return_output
            print("PASS: door travel, room isolation, maintenance combat, saved room/health/loot, return travel")
            for log in logs:
                assert "ERROR:" not in Path(log.name).read_text(), Path(log.name).read_text()
            print("PASS: separate character slots retain distinct classes across restart")
            print("PASS: class selection persists and reconnect cannot change class")
            print("PASS: combat defeats drones, awards loot, completes contract, and restores rewards after restart")
            print("PASS: two clients share a world, move through server authority, save separate characters, and restore after server restart")
        finally:
            for proc in processes:
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(timeout=5)
            for log in logs:
                log.close()


if __name__ == "__main__":
    main()
