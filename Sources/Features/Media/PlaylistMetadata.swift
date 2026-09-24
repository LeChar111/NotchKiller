import Foundation

/// Nom et pochette d'une playlist à partir de son lien, sans compte ni clé d'API.
///
/// Les balises Open Graph de la page donnent le vrai nom : l'oEmbed de Spotify,
/// lui, renvoie le dernier épisode pour un podcast. YouTube, qui sert une page
/// de consentement en Europe, passe par son oEmbed.
enum PlaylistMetadata {
    struct Result: Sendable {
        var title: String?
        var imageURL: String?
    }

    static func fetch(_ link: String) async -> Result {
        guard let url = webURL(for: link) else { return Result() }

        if url.host?.contains("youtube.com") == true || url.host?.contains("youtu.be") == true {
            return await oEmbed("https://www.youtube.com/oembed?format=json&url=", url)
        }

        var result = await openGraph(url)
        if result.title == nil || result.imageURL == nil, url.host?.contains("spotify.com") == true {
            let fallback = await oEmbed("https://open.spotify.com/oembed?url=", url)
            result.title = result.title ?? fallback.title
            result.imageURL = result.imageURL ?? fallback.imageURL
        }
        return result
    }

    /// `spotify:playlist:ID` n'a pas de page : on passe par son équivalent web.
    static func webURL(for link: String) -> URL? {
        if link.hasPrefix("spotify:") {
            let parts = link.split(separator: ":")
            guard parts.count >= 3 else { return nil }
            return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
        }
        guard let url = URL(string: link), url.scheme == "https" else { return nil }
        return url
    }

    private static func openGraph(_ url: URL) async -> Result {
        var request = URLRequest(url: url, timeoutInterval: 8)
        // Un navigateur reçoit l'application JavaScript sans balises ; un robot
        // d'aperçu de liens reçoit la page prévue pour ça.
        request.setValue("facebookexternalhit/1.1", forHTTPHeaderField: "User-Agent")
        request.setValue("fr-FR,fr;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return Result() }
        // Les balises sont dans l'en-tête : inutile de décoder toute la page.
        let html = String(decoding: data.prefix(400_000), as: UTF8.self)
        return Result(title: meta("og:title", in: html), imageURL: meta("og:image", in: html))
    }

    private static func oEmbed(_ endpoint: String, _ url: URL) async -> Result {
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        guard let api = URL(string: endpoint + encoded),
              let (data, _) = try? await URLSession.shared.data(from: api),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Result() }
        return Result(title: (json["title"] as? String)?.nilIfEmpty, imageURL: json["thumbnail_url"] as? String)
    }

    private static func meta(_ property: String, in html: String) -> String? {
        // L'ordre des attributs varie d'un site à l'autre.
        let patterns = [
            #"<meta[^>]+property="\#(property)"[^>]+content="([^"]*)""#,
            #"<meta[^>]+content="([^"]*)"[^>]+property="\#(property)""#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let value = decodeEntities(String(html[range])).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, char) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "] {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Entités numériques : &#x27; ou &#8217;
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return result }
        for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let whole = Range(match.range, in: result),
                  let digits = Range(match.range(at: 2), in: result) else { continue }
            let hex = match.range(at: 1).length > 0
            if let code = UInt32(result[digits], radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return result
    }
}
