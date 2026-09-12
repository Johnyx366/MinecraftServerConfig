#!/usr/bin/env python3
"""Small, dependency-free operator CLI for the sibling MinecraftServers checkout."""
import datetime as dt
import hashlib
import json
import os
import platform
import secrets
import signal
import shutil
import socket
import struct
import subprocess
import sys
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SERVERS = Path(os.environ.get("MC_SERVERS_DIR", ROOT.parent / "MinecraftServers")).resolve()
if platform.system() == "Darwin":
    # Chocolate Edition's official launcher refuses paths containing spaces.
    DEFAULT_RUNTIME = Path.home() / "MinecraftServerRuntime"
else:
    DEFAULT_RUNTIME = Path.home() / ".local/share/minecraft-server-runtime"
RUNTIME = Path(os.environ.get("MC_RUNTIME_ROOT", DEFAULT_RUNTIME)).expanduser().resolve()

def die(message):
    print(f"ERROR: {message}", file=sys.stderr); raise SystemExit(1)
def ok(message): print(f"[✓] {message}")
def bad(message, fix=None):
    print(f"[✗] {message}")
    if fix: print(f"    Fix: {fix}")
def load(path):
    try: return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc: die(f"invalid manifest {path}: {exc}")
def inventory(): return load(SERVERS / "inventory.yaml")["servers"]
def manifest(server):
    if server not in inventory(): die(f"unknown server '{server}'; run ./mc list")
    return load(SERVERS / server / "manifest.yaml")
def runtime(server): return RUNTIME / server
def current_platform():
    system = {"Darwin":"darwin", "Linux":"linux"}.get(platform.system(), platform.system().lower())
    machine = platform.machine().lower().replace("aarch64", "arm64").replace("x86_64", "x86_64")
    return f"{system}-{machine}"
def git_commit():
    result = subprocess.run(["git", "-C", str(SERVERS), "rev-parse", "HEAD"], text=True, capture_output=True)
    return result.stdout.strip() if result.returncode == 0 else "uncommitted"
def targets(arg): return inventory() if arg == "--all" else [arg]
def command_exists(name): return shutil.which(name) is not None
def java_info(required=None):
    java = None
    if required and platform.system() == "Darwin":
        candidate = java_home(required)
        if candidate: java = str(Path(candidate) / "bin" / "java")
    java = java or shutil.which("java")
    if not java: return None, None
    result = subprocess.run([java, "-XshowSettings:properties", "-version"], text=True, capture_output=True)
    output = result.stderr
    import re
    match = re.search(r'(?:version|openjdk version) "(\d+)', output)
    architecture = "unknown"
    for line in output.splitlines():
        if "os.arch" in line: architecture = line.split("=", 1)[-1].strip().replace("aarch64", "arm64")
    detail = next((line.strip() for line in output.splitlines()
                   if line.strip().startswith(("openjdk version", "java version"))), java)
    return int(match.group(1)) if match else None, detail, architecture
def java_home(required):
    if platform.system() == "Darwin":
        found = subprocess.run(["/usr/libexec/java_home", "-v", str(required)], text=True, capture_output=True)
        if found.returncode == 0: return found.stdout.strip()
        brew = shutil.which("brew")
        if brew and required == 17:
            prefix = subprocess.run([brew, "--prefix", "openjdk@17"], text=True, capture_output=True)
            candidate = Path(prefix.stdout.strip()) / "libexec/openjdk.jdk/Contents/Home"
            if prefix.returncode == 0 and (candidate / "bin/java").exists(): return str(candidate)
    return os.environ.get("JAVA_HOME", "")
def port_free(port):
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try: s.bind(("127.0.0.1", port)); return True
    except OSError: return False
    finally: s.close()
def pid_running(path):
    try: os.kill(int(path.read_text()), 0); return True
    except (OSError, ValueError): return False
def state(server): return runtime(server) / "state"
def running(server): return pid_running(state(server) / "server.pid")
def run(args, **kwargs): return subprocess.run(args, check=True, text=True, **kwargs)
def set_properties(path, values):
    lines = path.read_text().splitlines() if path.exists() else []
    remaining, output, replaced = dict(values), [], set()
    for line in lines:
        key = line.split("=", 1)[0] if "=" in line else None
        if key in values:
            if key not in replaced:
                output.append(f"{key}={values[key]}"); replaced.add(key)
            continue
        output.append(line)
    output.extend(f"{key}={value}" for key, value in remaining.items() if key not in replaced)
    path.write_text("\n".join(output) + "\n")
def set_shell_variables(path, values):
    set_properties(path, values)

def cmd_list(_):
    for s in inventory():
        m = manifest(s); print(f"{s}\t{m['name']}\t{m['minecraft_version']} {m['loader']}\t:{m['port']}")

def cmd_bootstrap(args):
    if platform.system() != "Darwin": die("bootstrap automation is currently implemented for macOS; see ARCHITECTURE.md")
    if platform.machine().lower() not in ("arm64", "aarch64"): die("this Mac is not ARM64; refusing a Rosetta-oriented bootstrap")
    if not command_exists("brew"):
        die("Homebrew is required to bootstrap. Install it from https://brew.sh, then rerun ./mc bootstrap")
    packages = [("openjdk@17", False), ("restic", False)]
    for package, is_cask in packages:
        list_cmd = ["brew", "list", "--cask" if is_cask else "--versions", package]
        installed = subprocess.run(list_cmd, capture_output=True).returncode == 0
        if installed: ok(f"{package} installed")
        else:
            print(f"Installing {package}...")
            run(["brew", "install", "--cask", package] if is_cask else ["brew", "install", package])
    print("Restart your shell if Java 17 is not selected; then run ./mc doctor --all.")

def cmd_deploy(server):
    m = manifest(server); rt = runtime(server); serverdir = rt / "server"; world = serverdir / "world"
    if current_platform() not in m["platforms"]: die(f"{server} does not support {current_platform()}")
    RUNTIME.mkdir(parents=True, exist_ok=True); (rt / "downloads").mkdir(parents=True, exist_ok=True); state(server).mkdir(parents=True, exist_ok=True)
    zip_path = rt / "downloads" / m["pack"]["file"]
    if not zip_path.exists():
        die(f"official server pack required: download {m['pack']['file']} from {m['pack']['source_page']} into {zip_path}")
    wanted = m["pack"]["sha256"]
    actual = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    if wanted.startswith("UNSET"):
        die(f"SHA-256 of downloaded pack is {actual}. Review it, set manifest pack.sha256 to this value, commit, then deploy.")
    if actual != wanted: die(f"server pack checksum mismatch: expected {wanted}, got {actual}")
    if not serverdir.exists():
        with zipfile.ZipFile(zip_path) as archive:
            target = serverdir.resolve()
            for member in archive.infolist():
                if not (target / member.filename).resolve().is_relative_to(target):
                    die(f"unsafe path in server-pack ZIP: {member.filename}")
            archive.extractall(serverdir)
        ok("official server pack extracted")
    else: ok("existing extracted runtime preserved")
    source_props = SERVERS / server / "server.properties"; props = serverdir / "server.properties"
    if not props.exists(): shutil.copy2(source_props, props)
    desired_props = {}
    for line in source_props.read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1); desired_props[key] = value
    set_properties(props, desired_props)
    ok("versioned server.properties policy applied")
    jvm_args = serverdir / "user_jvm_args.txt"
    if not jvm_args.exists():
        jvm_args.write_text(f"-Xms{m['memory_min_mib']}M\n-Xmx{m['memory_max_mib']}M\n")
    eula = serverdir / "eula.txt"
    if not eula.exists(): eula.write_text("# Review Minecraft EULA at https://aka.ms/MinecraftEULA\neula=false\n")
    secret = state(server) / "rcon-password"
    if not secret.exists():
        secret.write_text(secrets.token_urlsafe(32)); secret.chmod(0o600)
    set_properties(props, {"rcon.password": secret.read_text().strip()})
    variables = serverdir / "variables.txt"
    if variables.exists(): set_shell_variables(variables, {"WAIT_FOR_USER_INPUT": "false", "RESTART": "false"})
    launchers = [p.name for p in serverdir.glob("run.*") if p.is_file()] + [p.name for p in serverdir.glob("start*.sh")]
    (state(server) / "runtime.json").write_text(json.dumps({"deployed_at":dt.datetime.now(dt.timezone.utc).isoformat(), "pack_sha256":actual, "launchers":launchers}, indent=2)+"\n")
    print(f"Deployed {server}. Set eula=true in {eula} after accepting the EULA; then ./mc start {server}.")

def memory_mib():
    if platform.system() == "Darwin":
        return int(subprocess.check_output(["sysctl","-n","hw.memsize"])) // 1024 // 1024
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemTotal:"): return int(line.split()[1]) // 1024
    except OSError: pass
    return 0
def cmd_start(server):
    m=manifest(server); sd=runtime(server)/"server"; pid=state(server)/"server.pid"
    if running(server): die(f"{server} is already running")
    if not (sd/"eula.txt").exists() or "eula=true" not in (sd/"eula.txt").read_text(): die("EULA is not accepted; review it and set eula=true")
    total=sum(manifest(x)["memory_max_mib"] for x in inventory() if running(x))+m["memory_max_mib"]
    if memory_mib() and total > memory_mib()*0.75: die(f"configured running Xmx would be {total} MiB (>75% of {memory_mib()} MiB RAM)")
    launcher = next((sd / name for name in ("run.sh", "start.sh") if (sd / name).exists()), None)
    if not launcher: die(f"no supported Unix launcher (run.sh or start.sh) supplied by pack in {sd}")
    log=(runtime(server)/"logs"); log.mkdir(exist_ok=True)
    env=os.environ.copy(); env["JAVA_HOME"]=java_home(m["java_major"])
    if not env["JAVA_HOME"]: die(f"Java {m['java_major']} is unavailable; run ./mc bootstrap java")
    env["PATH"] = str(Path(env["JAVA_HOME"]) / "bin") + os.pathsep + env["PATH"]
    with (log/"console.log").open("ab") as out:
        proc=subprocess.Popen(["bash",str(launcher)],cwd=sd,stdout=out,stderr=subprocess.STDOUT,env=env,start_new_session=True)
    pid.write_text(str(proc.pid)); ok(f"started {server} (pid {proc.pid})")
def cmd_stop(server):
    pid=state(server)/"server.pid"
    if not running(server): print(f"{server} is stopped"); return
    os.killpg(int(pid.read_text()), signal.SIGTERM)
    for _ in range(30):
        if not running(server): pid.unlink(missing_ok=True); ok(f"stopped {server}"); return
        time.sleep(1)
    die(f"{server} did not stop in 30 seconds; inspect logs before escalating")
def cmd_status(server):
    m=manifest(server); print(f"{server}: {'RUNNING' if running(server) else 'STOPPED'} port={m['port']} runtime={runtime(server)}")
def cmd_doctor(server):
    m=manifest(server); healthy=True
    if current_platform() in m["platforms"]: ok(f"platform {current_platform()}")
    else: bad(f"platform {current_platform()} unsupported"); healthy=False
    version, detail, java_arch=java_info(m["java_major"])
    expected_arch = "arm64" if current_platform().endswith("arm64") else "x86_64"
    if version == m["java_major"] and java_arch == expected_arch: ok(f"Java {version} {java_arch} detected ({detail})")
    else:
        bad(f"Java {m['java_major']} {expected_arch} required; detected {detail or 'none'} ({java_arch})", "./mc bootstrap java")
        healthy=False
    if (SERVERS/server/"manifest.yaml").exists(): ok("server manifest valid")
    rt=runtime(server); sd=rt/"server"
    if sd.exists(): ok("runtime exists")
    else: bad("runtime missing", f"./mc deploy {server}"); healthy=False
    if sd.exists() and (sd/"world").exists(): ok("world available")
    else: bad("world not yet created (normal before first successful start)")
    if port_free(m["port"]) or running(server): ok(f"TCP port {m['port']} available/owned by server")
    else: bad(f"TCP port {m['port']} unavailable"); healthy=False
    if sd.exists() and "eula=true" in (sd/"eula.txt").read_text() if (sd/"eula.txt").exists() else False: ok("EULA accepted")
    else: bad("EULA not accepted", f"edit {sd}/eula.txt after reviewing it")
    if command_exists("restic") and os.environ.get("MC_RESTIC_REPOSITORY"): ok("restic repository configured")
    else: bad("restic repository unavailable", "set MC_RESTIC_REPOSITORY and RESTIC_PASSWORD_FILE")
    print("SYSTEM HEALTHY" if healthy else "SYSTEM NEEDS ATTENTION")
    if not healthy: raise SystemExit(1)
def restic(server, extra, cwd=None):
    if not os.environ.get("MC_RESTIC_REPOSITORY"): die("MC_RESTIC_REPOSITORY is not set")
    if not command_exists("restic"): die("restic not installed; run ./mc bootstrap")
    run(["restic", *extra], cwd=cwd)
def rcon_command(server, command):
    """Issue one authenticated RCON command over loopback only."""
    m = manifest(server); password = (state(server) / "rcon-password").read_text().strip()
    def packet(request_id, kind, body):
        data = struct.pack("<ii", request_id, kind) + body.encode() + b"\0\0"
        return struct.pack("<i", len(data)) + data
    with socket.create_connection(("127.0.0.1", m["rcon_port"]), timeout=10) as conn:
        conn.sendall(packet(1, 3, password))
        length = struct.unpack("<i", conn.recv(4))[0]
        reply = conn.recv(length)
        request_id = struct.unpack("<i", reply[:4])[0]
        if request_id == -1: die("local RCON authentication failed; inspect runtime secret and server.properties")
        conn.sendall(packet(2, 2, command))
def cmd_backup(server):
    sd=runtime(server)/"server"; world=sd/"world"
    if not world.exists(): die(f"world missing: {world}")
    paused=False
    try:
        if running(server):
            rcon_command(server, "save-off")
            rcon_command(server, "save-all flush"); paused=True
        restic(server,["backup","world","--tag",f"server:{server}","--tag",f"config:{git_commit()}"] , cwd=sd)
        restic(server,["check","--read-data-subset=1/20"])
    finally:
        if paused:
            try: rcon_command(server, "save-on")
            except Exception as exc: print(f"WARNING: could not re-enable saving: {exc}", file=sys.stderr)
def cmd_whitelist(action, server, player):
    if not running(server): die("server must be running to modify the whitelist")
    if action not in ("add", "remove"): die("usage: ./mc whitelist {add|remove} ID PLAYER")
    rcon_command(server, f"whitelist {action} {player}")
    ok(f"whitelist {action}: {player}")
def cmd_op(server, player):
    if not running(server): die("server must be running to grant OP")
    rcon_command(server, f"op {player}")
    ok(f"OP granted: {player}")
def cmd_restore(server, snapshot):
    if running(server): die("stop server before restore")
    sd=runtime(server)/"server"; world=sd/"world"
    if world.exists(): world.rename(sd/f"world.before-restore-{dt.datetime.now().strftime('%Y%m%d%H%M%S')}")
    restore_root=runtime(server)/f"restore-{dt.datetime.now().strftime('%Y%m%d%H%M%S')}"
    restic(server,["restore",snapshot,"--target",str(restore_root)])
    restored = restore_root / str(world).lstrip("/")
    if not restored.exists(): die(f"snapshot did not contain expected world path {world}; old world remains preserved")
    restored.rename(world)
    shutil.rmtree(restore_root)
    ok("restore complete; previous world was retained beside it")
def cmd_checkpoint(_):
    mapping={"created_at":dt.datetime.now(dt.timezone.utc).isoformat(),"config_commit":git_commit(),"servers":{}}
    for s in inventory():
        cmd_backup(s)
        result=subprocess.run(["restic","snapshots","--tag",f"server:{s}","--latest","1","--json"],text=True,capture_output=True,check=True)
        mapping["servers"][s]=json.loads(result.stdout)[0]["short_id"]
    path=ROOT/"checkpoints"; path.mkdir(exist_ok=True); out=path/(dt.datetime.now().strftime("%Y-%m-%dT%H%M%SZ")+".json"); out.write_text(json.dumps(mapping,indent=2)+"\n"); print(out)
def cmd_service(action, server):
    if platform.system() != "Darwin": die("launchd service is macOS-only")
    m=manifest(server); label=f"local.minecraft.{server}"; plist=Path.home()/"Library/LaunchAgents"/f"{label}.plist"
    if action=="status": subprocess.run(["launchctl","print",f"gui/{os.getuid()}/{label}"]); return
    if action=="remove": subprocess.run(["launchctl","bootout",f"gui/{os.getuid()}",str(plist)]); plist.unlink(missing_ok=True); return
    if not m["autostart"]: die("set autostart: true in manifest, review/commit it, then install service")
    plist.parent.mkdir(parents=True,exist_ok=True)
    plist.write_text(f'''<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>Label</key><string>{label}</string><key>ProgramArguments</key><array><string>{ROOT/'mc'}</string><string>start</string><string>{server}</string></array><key>RunAtLoad</key><true/></dict></plist>''')
    run(["launchctl","bootstrap",f"gui/{os.getuid()}",str(plist)]); ok(f"installed {plist}")
def usage(): print("usage: ./mc {bootstrap|list|status|doctor|deploy|install|start|stop|restart|backup|restore|checkpoint|service|whitelist|op} [ID|--all]")
def main():
    args=sys.argv[1:]
    if not args or args[0] in ("help","--help","-h"): usage(); return
    cmd=args.pop(0)
    if cmd=="list": cmd_list(args); return
    if cmd=="bootstrap": cmd_bootstrap(args); return
    if cmd=="checkpoint": cmd_checkpoint(args); return
    if cmd=="service":
        if len(args)!=2: die("usage: ./mc service {install|remove|status} ID")
        cmd_service(*args); return
    if cmd=="restore":
        if len(args)!=2: die("usage: ./mc restore ID SNAPSHOT")
        cmd_restore(*args); return
    if cmd=="whitelist":
        if len(args)!=3: die("usage: ./mc whitelist {add|remove} ID PLAYER")
        cmd_whitelist(*args); return
    if cmd=="op":
        if len(args)!=2: die("usage: ./mc op ID PLAYER")
        cmd_op(*args); return
    if not args: die(f"usage: ./mc {cmd} ID|--all")
    for server in targets(args[0]):
        if cmd in ("deploy","install"): cmd_deploy(server)
        elif cmd=="start": cmd_start(server)
        elif cmd=="stop": cmd_stop(server)
        elif cmd=="restart": cmd_stop(server); cmd_start(server)
        elif cmd=="status": cmd_status(server)
        elif cmd=="doctor": cmd_doctor(server)
        elif cmd=="backup": cmd_backup(server)
        else: die(f"unknown command: {cmd}")
if __name__ == "__main__":
    try:
        main()
    except PermissionError as exc:
        die(f"cannot access {exc.filename}; choose a writable MC_RUNTIME_ROOT or fix its ownership")
