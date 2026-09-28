import Darwin
import Foundation

/// Accès noyau aux mêmes grandeurs que la fenêtre « Forcer à quitter » :
/// empreinte physique (swap et compression compris), processus responsable
/// (l'app à qui macOS impute un processus lancé depuis elle) et pause imposée
/// quand l'espace de pagination s'épuise.
enum ProcessControl {
    /// `phys_footprint` : la colonne « Mémoire » d'Activity Monitor et la valeur
    /// de « Forcer à quitter ». Le RSS ne compte que ce qui reste en RAM.
    nonisolated static func footprint(_ pid: Int32) -> Double? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return status == 0 ? Double(info.ri_phys_footprint) : nil
    }

    /// Un `node` lancé dans Ghostty est imputé à Ghostty, un serveur de dev lancé
    /// dans le terminal de Cursor à Cursor : c'est ce regroupement qui donne les
    /// 16 Go de « Forcer à quitter ». API privée, résolue à l'exécution.
    nonisolated static func responsiblePID(_ pid: Int32) -> Int32 {
        guard let resolve = responsibleSymbol else { return pid }
        let owner = resolve(pid)
        return owner > 0 ? owner : pid
    }

    /// Suspendu par le noyau faute d'espace de pagination — le « (paused) » de
    /// « Forcer à quitter ». `ps` l'affiche pourtant en état `S`, pas `T`.
    nonisolated static func isStarvationPaused(_ pid: Int32) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_flags & UInt32(PROC_FLAG_PA_SUSP) != 0
    }

    nonisolated static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t
    private typealias ClearFunction = @convention(c) (pid_t) -> Int32

    private nonisolated static let responsibleSymbol: ResponsibleFunction? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    // MARK: Reprise

    /// `proc_clear_vmpressure` lève la pause, et le noyau ne l'accepte que de root.
    /// Le bouton « Resume » de « Forcer à quitter » échoue quand la mémoire manque
    /// toujours ou que des auxiliaires restent suspendus : on les reprend tous,
    /// après une invite administrateur.
    static func resumeWithAdministratorPrompt(_ pids: [Int32]) async -> Bool {
        guard !pids.isEmpty, let executable = Bundle.main.executablePath else { return false }
        let arguments = pids.map(String.init).joined(separator: " ")
        let escaped = executable.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script (quoted form of \"\(escaped)\") & \" --resume \(arguments)\" with administrator privileges"

        return await Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            return error == nil
        }.value
    }

    /// Mode `NotchKiller --resume <pid>…`, exécuté en root par l'invite ci-dessus.
    static func runResumeCommand(_ arguments: [String]) -> Never {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "proc_clear_vmpressure") else {
            FileHandle.standardError.write(Data("proc_clear_vmpressure introuvable\n".utf8))
            exit(69)
        }
        let clear = unsafeBitCast(symbol, to: ClearFunction.self)
        var failures = 0
        for pid in arguments.compactMap(Int32.init) {
            let status = clear(pid)
            if status != 0 {
                failures += 1
                FileHandle.standardError.write(Data("\(pid): \(String(cString: strerror(status)))\n".utf8))
            }
        }
        exit(failures == 0 ? 0 : 1)
    }
}
