import Foundation

// NotchKillerAudioHelper — lancé en root par le LaunchDaemon de déport des plug-ins audio.
//
// macOS (TCC) refuse l'écriture sur un disque externe à un processus root lancé par
// launchd quand son exécutable est un binaire système comme /bin/zsh : il ne peut pas
// recevoir d'autorisation. Ce petit exécutable, lui, peut recevoir l'« Accès complet
// au disque » ; le moteur qu'il lance en hérite. Il ne fait rien d'autre que lancer ce
// moteur — et refuse s'il n'appartient pas à root ou s'il est modifiable par un autre.

let engine = "/Library/Application Support/NotchKiller/audio-plugins-offload.sh"

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("NotchKillerAudioHelper : \(message)\n".utf8))
    exit(code)
}

var info = stat()
guard stat(engine, &info) == 0 else { fail("moteur introuvable (\(engine))", 72) }
guard info.st_uid == 0, info.st_mode & 0o022 == 0 else {
    fail("moteur refusé : il doit appartenir à root et n'être modifiable que par lui", 77)
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/bin/zsh")
task.arguments = ["-f", engine] + CommandLine.arguments.dropFirst()
do { try task.run() } catch { fail("lancement impossible : \(error.localizedDescription)", 71) }
task.waitUntilExit()
exit(task.terminationStatus)
