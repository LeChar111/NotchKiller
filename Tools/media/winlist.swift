// Liste les fenêtres de NotchKiller : id, niveau, x, y, largeur, hauteur.
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "NotchKiller" {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    print(w[kCGWindowNumber as String]!, w[kCGWindowLayer as String]!, b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!, w[kCGWindowName as String] ?? "")
}
