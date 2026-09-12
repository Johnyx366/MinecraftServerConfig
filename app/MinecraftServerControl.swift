import AppKit
import SwiftUI

struct CommandResult { let status: Int32; let output: String }
struct PlayerResponse: Decodable { let players: [String]; let count: Int; let maximum: Int; let rcon_latency_ms: Int }
struct BackupSnapshot: Decodable { let id: String; let age_seconds: Int; let world_size_mib: Double }
struct BackupResponse: Decodable { let configured: Bool; let reachable: Bool; let snapshot: BackupSnapshot? }
struct MetricsResponse: Decodable { let running: Bool; let host_ram_mib: Int; let free_disk_gib: Double; let server_cpu_percent: Double?; let server_rss_mib: Double? }

@MainActor
final class ServerModel: ObservableObject {
    @Published var running = false
    @Published var busy = false
    @Published var message = "Leyendo estado…"
    @Published var console = ""
    @Published var players: [String] = []
    @Published var playerLimit = 0
    @Published var rconLatency: Int?
    @Published var commandInput = ""
    @Published var commandOutput = ""
    @Published var backup: BackupResponse?
    @Published var metrics: MetricsResponse?
    let serverID: String
    private let cli: URL
    private var timer: Timer?

    init() {
        let resources = Bundle.main.resourceURL!
        let root = (try? String(contentsOf: resources.appendingPathComponent("mc-config.path"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        cli = URL(fileURLWithPath: root).appendingPathComponent("mc")
        serverID = (try? String(contentsOf: resources.appendingPathComponent("server-id.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "chocolate-edition"
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    deinit { timer?.invalidate() }
    func refresh() {
        execute(["status", serverID]) { result in
            self.running = result.output.contains("RUNNING")
            self.message = self.running ? "Servidor listo" : "Servidor apagado"
            if self.running { self.refreshPlayers() } else { self.players = []; self.rconLatency = nil }
        }
        let log = NSHomeDirectory() + "/MinecraftServerRuntime/" + serverID + "/logs/console.log"
        executeExternal("/usr/bin/tail", ["-n", "16", log]) { result in self.console = result.output.isEmpty ? "Aún no hay salida de consola." : result.output }
        execute(["backup-status", serverID, "--json"]) { result in
            guard let data = result.output.data(using: .utf8) else { return }
            self.backup = try? JSONDecoder().decode(BackupResponse.self, from: data)
        }
        execute(["metrics", serverID, "--json"]) { result in
            guard let data = result.output.data(using: .utf8) else { return }
            self.metrics = try? JSONDecoder().decode(MetricsResponse.self, from: data)
        }
    }
    func refreshPlayers() {
        execute(["players", serverID, "--json"]) { result in
            guard result.status == 0, let data = result.output.data(using: .utf8), let state = try? JSONDecoder().decode(PlayerResponse.self, from: data) else { return }
            self.players = state.players; self.playerLimit = state.maximum; self.rconLatency = state.rcon_latency_ms
        }
    }
    func toggle() {
        guard !busy else { return }; busy = true
        message = running ? "Apagando de forma segura…" : "Iniciando y esperando a Minecraft…"
        execute(["toggle", serverID]) { result in
            self.busy = false; self.message = result.status == 0 ? "Operación terminada correctamente" : "La operación no terminó correctamente. Revisa la consola."
            self.refresh()
        }
    }
    func sendCommand() {
        let command = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard running, !busy, !command.isEmpty else { return }; busy = true; commandOutput = "Enviando: /\(command)"
        execute(["command", serverID, command]) { result in
            self.busy = false; self.commandOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines); self.commandInput = ""; self.refresh()
        }
    }
    func backupNow() {
        guard !busy else { return }; busy = true; message = "Creando backup consistente…"
        execute(["backup", serverID]) { result in
            self.busy = false; self.message = result.status == 0 ? "Backup verificado correctamente" : "Falló el backup; revisa la consola"
            self.commandOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines); self.refresh()
        }
    }
    func openLog() {
        let log = NSHomeDirectory() + "/MinecraftServerRuntime/" + serverID + "/logs/console.log"
        executeExternal("/usr/bin/open", [log]) { _ in }
    }
    private func execute(_ arguments: [String], completion: @escaping (CommandResult) -> Void) { executeExternal(cli.path, arguments, completion: completion) }
    private func executeExternal(_ executable: String, _ arguments: [String], completion: @escaping (CommandResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            do {
                try process.run(); process.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(CommandResult(status: process.terminationStatus, output: output)) }
            } catch { DispatchQueue.main.async { completion(CommandResult(status: 1, output: error.localizedDescription)) } }
        }
    }
}

private func consoleColour(_ line: String) -> Color {
    if line.localizedCaseInsensitiveContains("error") || line.localizedCaseInsensitiveContains("exception") { return .red }
    if line.localizedCaseInsensitiveContains("warn") || line.localizedCaseInsensitiveContains("timeout") { return .yellow }
    if line.localizedCaseInsensitiveContains("info") { return .cyan }
    return Color(red: 0.57, green: 1, blue: 0.68)
}
private func ageText(_ seconds: Int) -> String {
    if seconds < 60 { return "hace \(seconds)s" }
    if seconds < 3600 { return "hace \(seconds / 60)m" }
    if seconds < 86_400 { return "hace \(seconds / 3600)h" }
    return "hace \(seconds / 86_400)d"
}
private func requiresCommandConfirmation(_ command: String) -> Bool {
    let value = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let dangerous = ["stop", "op ", "deop ", "ban ", "ban-ip ", "pardon ", "kick ",
                     "whitelist", "difficulty", "gamerule", "worldborder", "forceload", "save-off", "save-on", "reload"]
    return dangerous.contains { value == $0 || value.hasPrefix($0) }
}

struct PlayerCard: View {
    let name: String
    private var headURL: URL? { URL(string: "https://mc-heads.net/avatar/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)/96") }
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: headURL) { $0.resizable().interpolation(.none) } placeholder: { Image(systemName: "person.crop.square").resizable().padding(7).foregroundStyle(.purple) }
                .frame(width: 45, height: 45).background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
            Text(name).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Spacer(); Image(systemName: "wifi").foregroundStyle(.green)
        }.padding(11).background(Color(red: 0.08, green: 0.12, blue: 0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ContentView: View {
    @StateObject private var model = ServerModel()
    @State private var showCommandConfirmation = false
    private func submitCommand() {
        if requiresCommandConfirmation(model.commandInput) { showCommandConfirmation = true }
        else { model.sendCommand() }
    }
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.025, green: 0.045, blue: 0.06), Color(red: 0.045, green: 0.075, blue: 0.055)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 25) {
                    HStack(spacing: 18) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 19))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("MINECRAFT SERVER").font(.system(size: 19, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                            Text("Chocolate Edition").font(.system(size: 39, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("Forge 1.19.2 · Java 17 · Puerto 25565").font(.system(size: 18, design: .monospaced)).foregroundStyle(.mint)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Label(model.running ? "EN LÍNEA" : "APAGADO", systemImage: model.running ? "checkmark.circle.fill" : "power.circle.fill").font(.system(size: 19, weight: .bold)).foregroundStyle(model.running ? .green : .orange)
                            Text(model.message).font(.system(size: 15)).foregroundStyle(.secondary)
                        }
                    }
                    Button(action: model.toggle) {
                        HStack(spacing: 12) { Image(systemName: model.running ? "power" : "play.fill"); Text(model.busy ? "ESPERA…" : (model.running ? "APAGAR SERVIDOR" : "ENCENDER SERVIDOR")) }
                            .font(.system(size: 24, weight: .bold, design: .rounded)).frame(maxWidth: .infinity).padding(.vertical, 19)
                    }.buttonStyle(.borderedProminent).tint(model.running ? .red : .green).disabled(model.busy)
                    HStack { Label("Apagado limpio: nunca se fuerza Java.", systemImage: "lock.shield.fill"); Spacer(); Button("↻ Actualizar", action: model.refresh).disabled(model.busy) }
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(.yellow)

                    HStack(alignment: .top, spacing: 15) {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("BACKUP", systemImage: "externaldrive.fill.badge.checkmark").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.mint)
                            if let backup = model.backup, backup.reachable, let snapshot = backup.snapshot {
                                Text("\(snapshot.id) · \(ageText(snapshot.age_seconds)) · mundo \(snapshot.world_size_mib, specifier: "%.1f") MiB").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                            } else if model.backup?.configured == true { Text("Repositorio no alcanzable o sin snapshot.").font(.system(size: 16)).foregroundStyle(.red) }
                            else { Text("Backup aún no configurado.").font(.system(size: 16)).foregroundStyle(.orange) }
                        }
                        Spacer()
                        Button("BACKUP AHORA", action: model.backupNow).font(.system(size: 17, weight: .bold)).buttonStyle(.borderedProminent).tint(.blue).disabled(model.busy)
                    }.padding(17).background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))

                    HStack(spacing: 18) {
                        Label(model.metrics?.server_cpu_percent.map { String(format: "Java CPU %.1f%%", $0) } ?? "Java detenido", systemImage: "cpu.fill").foregroundStyle(.pink)
                        Label(model.metrics?.server_rss_mib.map { String(format: "RAM %.0f MiB", $0) } ?? "RAM —", systemImage: "memorychip.fill").foregroundStyle(.cyan)
                        Label(model.metrics.map { String(format: "Disco libre %.1f GiB", $0.free_disk_gib) } ?? "Disco —", systemImage: "internaldrive.fill").foregroundStyle(.orange)
                        Spacer()
                        Button("Abrir log completo", action: model.openLog).foregroundStyle(.purple)
                    }.font(.system(size: 16, weight: .medium)).padding(.horizontal, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("JUGADORES", systemImage: "person.2.fill").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.purple)
                            Text("\(model.players.count)/\(model.playerLimit)").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            Spacer()
                            Label(model.rconLatency.map { "RCON local \($0) ms" } ?? "RCON sin datos", systemImage: "bolt.horizontal.circle.fill").font(.system(size: 16, weight: .medium)).foregroundStyle(.orange)
                        }
                        if model.players.isEmpty { Text(model.running ? "No hay jugadores conectados." : "El servidor está apagado.").font(.system(size: 17)).foregroundStyle(.secondary).padding(.vertical, 10) }
                        else { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) { ForEach(model.players, id: \.self) { PlayerCard(name: $0) } } }
                    }.padding(17).background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 12) {
                        Label("COMANDO DE CONSOLA", systemImage: "terminal.fill").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.yellow)
                        HStack {
                            Text("/").font(.system(size: 23, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                            TextField("say Hola desde el panel", text: $model.commandInput).font(.system(size: 19, design: .monospaced)).textFieldStyle(.plain).onSubmit(submitCommand).disabled(!model.running || model.busy)
                            Button("EJECUTAR", action: submitCommand).font(.system(size: 17, weight: .bold)).buttonStyle(.borderedProminent).tint(.purple).disabled(!model.running || model.busy || model.commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.padding(13).background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                        if !model.commandOutput.isEmpty { Text(model.commandOutput).font(.system(size: 16, design: .monospaced)).foregroundStyle(.mint).textSelection(.enabled) }
                    }.padding(17).background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Label("CONSOLA RECIENTE", systemImage: "text.alignleft").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                        ScrollView { VStack(alignment: .leading, spacing: 5) { ForEach(model.console.split(separator: "\n", omittingEmptySubsequences: false).map(String.init), id: \.self) { line in Text(line).font(.system(size: 16.5, design: .monospaced)).foregroundStyle(consoleColour(line)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) } } }
                            .padding(14).frame(height: 335).background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 13))
                    }
                }.padding(32).frame(minWidth: 880, minHeight: 920)
            }
        }.preferredColorScheme(.dark)
        .alert("¿Ejecutar comando peligroso?", isPresented: $showCommandConfirmation) {
            Button("Cancelar", role: .cancel) { }
            Button("Ejecutar", role: .destructive) { model.sendCommand() }
        } message: {
            Text("/\(model.commandInput) puede cambiar el estado del servidor o de los jugadores.")
        }
    }
}

@main
struct MinecraftServerControlApp: App {
    var body: some Scene { WindowGroup("Minecraft Server Control") { ContentView() }.windowResizability(.contentSize) }
}
