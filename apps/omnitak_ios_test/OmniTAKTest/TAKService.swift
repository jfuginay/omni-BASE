import Foundation
import Combine
import CoreLocation

// CoT Event Model
struct CoTEvent {
    let uid: String
    let type: String
    let time: Date
    let point: CoTPoint
    let detail: CoTDetail
}

struct CoTPoint {
    let lat: Double
    let lon: Double
    let hae: Double
    let ce: Double
    let le: Double
}

struct CoTDetail {
    let callsign: String
    let team: String?
}

class TAKService: ObservableObject {
    @Published var connectionStatus = "Disconnected"
    @Published var isConnected = false
    @Published var lastError = ""
    @Published var messagesReceived: Int = 0
    @Published var messagesSent: Int = 0
    @Published var lastMessage = ""
    @Published var cotEvents: [CoTEvent] = []

    private var connectionHandle: UInt64 = 0
    var onCoTReceived: ((CoTEvent) -> Void)?

    init() {
        // Initialize the omnitak library
        let result = omnitak_init()
        if result != 0 {
            print("❌ Failed to initialize omnitak library")
        }
    }

    deinit {
        disconnect()
        omnitak_shutdown()
    }

    func connect(host: String, port: UInt16, protocolType: String, useTLS: Bool) {
        // Convert protocol string to enum
        var protocolCode: Int32
        switch protocolType.lowercased() {
        case "tcp":
            protocolCode = 0 // OMNITAK_PROTOCOL_TCP
        case "udp":
            protocolCode = 1 // OMNITAK_PROTOCOL_UDP
        case "tls":
            protocolCode = 2 // OMNITAK_PROTOCOL_TLS
        case "websocket", "ws":
            protocolCode = 3 // OMNITAK_PROTOCOL_WEBSOCKET
        default:
            protocolCode = 0 // Default to TCP
        }

        // Convert to C strings
        let hostCStr = host.cString(using: .utf8)!

        // Call FFI connect function
        let result = omnitak_connect(
            hostCStr,
            port,
            protocolCode,
            useTLS ? 1 : 0,
            nil,  // cert_pem
            nil,  // key_pem
            nil   // ca_pem
        )

        if result > 0 {
            connectionHandle = result
            isConnected = true
            connectionStatus = "Connected"
            lastError = ""

            // Register callback for receiving messages
            registerCallback()

            print("✅ Connected to TAK server: \(host):\(port) (connection ID: \(result))")
        } else {
            connectionStatus = "Connection Failed"
            lastError = "Failed to connect to \(host):\(port)"
            print("❌ Connection failed")
        }
    }

    func disconnect() {
        guard connectionHandle > 0 else { return }

        // Unregister callback
        omnitak_unregister_callback(connectionHandle)

        // Disconnect
        omnitak_disconnect(connectionHandle)
        connectionHandle = 0
        isConnected = false
        connectionStatus = "Disconnected"

        print("🔌 Disconnected from TAK server")
    }

    func sendCoT(xml: String) -> Bool {
        guard connectionHandle > 0 else {
            print("❌ Not connected")
            return false
        }

        let xmlCStr = xml.cString(using: .utf8)!
        let result = omnitak_send_cot(connectionHandle, xmlCStr)

        if result == 0 {  // OMNITAK_SUCCESS
            messagesSent += 1
            print("📤 Sent CoT message")
            return true
        } else {
            print("❌ Failed to send CoT message (error: \(result))")
            return false
        }
    }

    private func registerCallback() {
        // Create context pointer
        let context = Unmanaged.passUnretained(self).toOpaque()

        // Register callback
        omnitak_register_callback(connectionHandle, cotCallback, context)
    }
}

// Global callback function (must be at file scope, not inside class)
private func cotCallback(
    userData: UnsafeMutableRawPointer?,
    connectionId: UInt64,
    cotXml: UnsafePointer<CChar>?
) {
    guard let userData = userData,
          let cotXml = cotXml else {
        return
    }

    // Convert C string to Swift string
    let message = String(cString: cotXml)

    // Get the TAKService instance
    let service = Unmanaged<TAKService>.fromOpaque(userData).takeUnretainedValue()

    // Parse CoT message
    if let event = parseCoT(xml: message) {
        DispatchQueue.main.async {
            service.messagesReceived += 1
            service.lastMessage = message
            service.cotEvents.append(event)
            service.onCoTReceived?(event)
            print("📥 Received CoT: \(event.detail.callsign) at (\(event.point.lat), \(event.point.lon))")
        }
    }
}

// Simple CoT XML Parser
private func parseCoT(xml: String) -> CoTEvent? {
    // Extract UID
    guard let uidRange = xml.range(of: "uid=\"([^\"]+)\"", options: .regularExpression),
          let uid = xml[uidRange].split(separator: "\"").dropFirst().first else {
        return nil
    }

    // Extract type
    guard let typeRange = xml.range(of: "type=\"([^\"]+)\"", options: .regularExpression),
          let type = xml[typeRange].split(separator: "\"").dropFirst().first else {
        return nil
    }

    // Extract point data
    guard let pointRange = xml.range(of: "<point[^>]+>", options: .regularExpression) else {
        return nil
    }

    let pointTag = String(xml[pointRange])

    guard let latStr = extractAttribute("lat", from: pointTag),
          let lonStr = extractAttribute("lon", from: pointTag),
          let lat = Double(latStr),
          let lon = Double(lonStr) else {
        return nil
    }

    let hae = Double(extractAttribute("hae", from: pointTag) ?? "0") ?? 0
    let ce = Double(extractAttribute("ce", from: pointTag) ?? "10") ?? 10
    let le = Double(extractAttribute("le", from: pointTag) ?? "10") ?? 10

    // Extract callsign
    var callsign = String(uid)
    if let callsignRange = xml.range(of: "callsign=\"([^\"]+)\"", options: .regularExpression),
       let extractedCallsign = xml[callsignRange].split(separator: "\"").dropFirst().first {
        callsign = String(extractedCallsign)
    }

    // Extract team
    var team: String? = nil
    if let teamRange = xml.range(of: "name=\"([^\"]+)\"", options: .regularExpression),
       let extractedTeam = xml[teamRange].split(separator: "\"").dropFirst().first {
        team = String(extractedTeam)
    }

    return CoTEvent(
        uid: String(uid),
        type: String(type),
        time: Date(),
        point: CoTPoint(lat: lat, lon: lon, hae: hae, ce: ce, le: le),
        detail: CoTDetail(callsign: callsign, team: team)
    )
}

private func extractAttribute(_ name: String, from xml: String) -> String? {
    guard let range = xml.range(of: "\(name)=\"([^\"]+)\"", options: .regularExpression) else {
        return nil
    }
    let parts = xml[range].split(separator: "\"")
    return parts.count > 1 ? String(parts[1]) : nil
}
