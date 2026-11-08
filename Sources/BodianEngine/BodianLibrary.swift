import BodianCore
import Foundation
import SQLite3

struct BodianLibrary {
    let database: URL

    private struct Song: Decodable {
        let id: Int64?
        let name: String?
        let artist: String?
        let album: String?
        let duration: Double?
    }

    func songID(for track: Track) throws -> String {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw databaseError(db)
        }
        var statement: OpaquePointer?
        let sql = "SELECT json FROM hist_song ORDER BY ord DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw databaseError(db) }
        defer { sqlite3_finalize(statement) }
        let title = Self.key(track.title), artist = Self.key(track.artist), album = Self.key(track.album)
        let decoder = JSONDecoder()
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_DONE: return ""
            case SQLITE_ROW:
                guard let json = sqlite3_column_text(statement, 0) else { continue }
                let data = Data(bytes: json, count: Int(sqlite3_column_bytes(statement, 0)))
                let song = try decoder.decode(Song.self, from: data)
                guard let id = song.id, Self.key(song.name ?? "") == title, Self.key(song.artist ?? "") == artist else { continue }
                let duration = song.duration ?? 0
                let difference = abs(duration - track.duration)
                let hasDuration = duration > 0 && track.duration > 0
                if hasDuration, difference / max(duration, track.duration) > 0.12 { continue }
                if let name = song.album, !name.isEmpty, !track.album.isEmpty,
                   Self.key(name) != album, !hasDuration || difference > 1 { continue }
                return String(id)
            default: throw databaseError(db)
            }
        }
    }

    private func databaseError(_ db: OpaquePointer?) -> NSError {
        NSError(domain: "SQLite", code: Int(sqlite3_errcode(db)),
                userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
    }

    private static func key(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter {
            switch $0.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
                return true
            default:
                return false
            }
        })).lowercased()
    }
}
