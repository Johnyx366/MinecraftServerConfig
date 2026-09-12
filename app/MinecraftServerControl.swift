import AppKit
import SwiftUI

struct CommandResult {
    let status: Int32
    let output: String
}

@MainActor
final class ServerModel: ObservableObject {
    @Published var running = false
    @Published var busy = false
    @Published var message = "Leyendo estado…"
    @Published var console = ""

    let serverID: String
    private let cli: URL
    private var timer: Timer?

    init() {
        let resourceRoot = Bundle.main.resourceURL!
        let pointer = resourceRoot.appendingPathComponent("mc-config.path")
        let root = (try? String(contentsOf: pointer, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        self.cli = URL(fileURLWithPath: root).appendingPathComponent("mc")
        self.serverID = (try? String(contentsOf: resourceRoot.appendingPathComponent("server-id.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? "chocolate-edition"
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        execute(["status", serverID]) { result in
            self.running = result.output.contains("RUNNING")
            self.message = self.running ? "Servidor listo" : "Servidor apagado"
        }
        let log = NSHomeDirectory() + "/MinecraftServerRuntime/" + serverID + "/logs/console.log"
        executeExternal("/usr/bin/tail", ["-n", "14", log]) { result in
            self.console = result.output.isEmpty ? "Aún no hay salida de consola." : result.output
        }
    }

    func toggle() {
        guard !busy else { return }
        busy = true
        message = running ? "Apagando de forma segura…" : "Iniciando y esperando a Minecraft…"
        execute(["toggle", serverID]) { result in
            self.busy = false
            if result.status == 0 {
                self.running.toggle()
                self.message = self.running ? "Servidor listo" : "Servidor apagado correctamente"
            } else {
                self.message = "La operación no terminó correctamente. Revisa la consola."
            }
            self.refresh()
        }
    }

    private func execute(_ arguments: [String], completion: @escaping (CommandResult) -> Void) {
        executeExternal(cli.path, arguments, completion: completion)
    }

    private func executeExternal(_ executable: String, _ arguments: [String], completion: @escaping (CommandResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(CommandResult(status: process.terminationStatus, output: output)) }
            } catch {
                DispatchQueue.main.async { completion(CommandResult(status: 1, output: error.localizedDescription)) }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var model = ServerModel()

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.055).ignoresSafeArea()
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MINECRAFT SERVER")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                        Text("Chocolate Edition")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Forge 1.19.2 · Java 17 · Puerto 25565")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Label(model.running ? "EN LÍNEA" : "APAGADO", systemImage: model.running ? "checkmark.circle.fill" : "power.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(model.running ? .green : .orange)
                        Text(model.message).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Button(action: model.toggle) {
                    HStack(spacing: 10) {
                        Image(systemName: model.running ? "power" : "play.fill")
                        Text(model.busy ? "ESPERA…" : (model.running ? "APAGAR SERVIDOR" : "ENCENDER SERVIDOR"))
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.running ? .red : .green)
                .disabled(model.busy)

                HStack {
                    Label("El apagado es limpio; no se fuerza Java.", systemImage: "lock.shield.fill")
                    Spacer()
                    Button("Actualizar", action: model.refresh).disabled(model.busy)
                }
                .font(.caption).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("CONSOLA RECIENTE")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                    ScrollView {
                        Text(model.console)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: 0.55, green: 1, blue: 0.68))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(12).frame(height: 175)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(26).frame(minWidth: 650, minHeight: 410)
        }
        .preferredColorScheme(.dark)
    }
}

@main
struct MinecraftServerControlApp: App {
    var body: some Scene {
        WindowGroup("Minecraft Server Control") { ContentView() }
            .windowResizability(.contentSize)
    }
}
