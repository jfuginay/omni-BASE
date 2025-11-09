import SwiftUI
import MapKit
import CoreLocation

// ATAK-style Map View with tactical interface
struct ATAKMapView: View {
    @StateObject private var takService = TAKService()
    @StateObject private var locationManager = LocationManager()
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 38.8977, longitude: -77.0365), // Default: DC
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var showServerConfig = false
    @State private var showLayersPanel = false
    @State private var mapType: MKMapType = .satellite
    @State private var showTraffic = false
    @State private var trackingMode: MapUserTrackingMode = .follow
    @State private var orientation = UIDeviceOrientation.unknown

    // Detect device orientation
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var isLandscape: Bool {
        horizontalSizeClass == .regular || verticalSizeClass == .compact
    }

    // Computed CoT markers from TAK service
    private var cotMarkers: [CoTMarker] {
        takService.cotEvents.map { event in
            CoTMarker(
                uid: event.uid,
                coordinate: CLLocationCoordinate2D(
                    latitude: event.point.lat,
                    longitude: event.point.lon
                ),
                type: event.type,
                callsign: event.detail.callsign,
                team: event.detail.team ?? "Unknown"
            )
        }
    }

    var body: some View {
        ZStack {
            // Main Map View
            Map(coordinateRegion: $mapRegion,
                showsUserLocation: true,
                userTrackingMode: $trackingMode,
                annotationItems: cotMarkers) { marker in
                MapAnnotation(coordinate: marker.coordinate) {
                    CoTMarkerView(marker: marker)
                }
            }
            .ignoresSafeArea()

            // Top Status Bar (ATAK-style)
            VStack(spacing: 0) {
                ATAKStatusBar(
                    connectionStatus: takService.connectionStatus,
                    isConnected: takService.isConnected,
                    messagesReceived: takService.messagesReceived,
                    messagesSent: takService.messagesSent,
                    gpsAccuracy: locationManager.accuracy,
                    onServerTap: { showServerConfig = true }
                )
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Spacer()

                // Bottom Toolbar (ATAK-style)
                ATAKBottomToolbar(
                    mapType: $mapType,
                    showLayersPanel: $showLayersPanel,
                    onCenterUser: centerOnUser,
                    onSendCoT: sendSelfPosition,
                    onZoomIn: zoomIn,
                    onZoomOut: zoomOut
                )
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
                .padding(.horizontal, 8)
                .padding(.bottom, 20)
            }

            // Left Side Panel (ATAK-style tools) - Responsive positioning
            if showLayersPanel {
                HStack {
                    ATAKSidePanel(
                        isExpanded: $showLayersPanel,
                        onLayerToggle: { layer in
                            toggleLayer(layer)
                        }
                    )
                    .background(Color.black.opacity(0.9))
                    .cornerRadius(12)
                    .padding(.leading, 8)
                    .padding(.vertical, isLandscape ? 80 : 120)
                    .transition(.move(edge: .leading))

                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showServerConfig) {
            ServerConfigView(takService: takService)
        }
        .onAppear {
            setupTAKConnection()
            startLocationUpdates()
        }
    }

    // MARK: - Actions

    private func setupTAKConnection() {
        // Auto-connect to default server
        takService.connect(
            host: "204.48.30.216",
            port: 8087,
            protocolType: "tcp",
            useTLS: false
        )

    }

    private func startLocationUpdates() {
        locationManager.startUpdating()
    }

    private func centerOnUser() {
        if let location = locationManager.location {
            withAnimation {
                mapRegion.center = location.coordinate
                mapRegion.span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            }
            trackingMode = .follow
            print("🎯 Centered on user: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        } else {
            print("❌ No location available")
        }
    }

    private func sendSelfPosition() {
        guard let location = locationManager.location else {
            print("❌ Cannot send position - no location")
            return
        }

        let cotXml = generateSelfCoT(location: location)
        let success = takService.sendCoT(xml: cotXml)
        if success {
            print("📤 Broadcast position: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }

    private func zoomIn() {
        withAnimation {
            mapRegion.span.latitudeDelta = max(mapRegion.span.latitudeDelta / 2, 0.001)
            mapRegion.span.longitudeDelta = max(mapRegion.span.longitudeDelta / 2, 0.001)
        }
        print("🔍 Zoom in: \(mapRegion.span.latitudeDelta)")
    }

    private func zoomOut() {
        withAnimation {
            mapRegion.span.latitudeDelta = min(mapRegion.span.latitudeDelta * 2, 180)
            mapRegion.span.longitudeDelta = min(mapRegion.span.longitudeDelta * 2, 180)
        }
        print("🔍 Zoom out: \(mapRegion.span.latitudeDelta)")
    }

    private func toggleLayer(_ layer: String) {
        // Toggle map layers
        switch layer {
        case "satellite":
            mapType = .satellite
            print("🗺️ Map type: Satellite")
        case "hybrid":
            mapType = .hybrid
            print("🗺️ Map type: Hybrid")
        case "standard":
            mapType = .standard
            print("🗺️ Map type: Standard")
        default:
            break
        }
    }

    private func generateSelfCoT(location: CLLocation) -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        let stale = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <event version="2.0" uid="SELF-\(UUID().uuidString)" type="a-f-G-E-S" how="m-g" time="\(now)" start="\(now)" stale="\(stale)">
            <point lat="\(location.coordinate.latitude)" lon="\(location.coordinate.longitude)" hae="\(location.altitude)" ce="\(location.horizontalAccuracy)" le="\(location.verticalAccuracy)"/>
            <detail>
                <contact callsign="OmniTAK-iOS" endpoint="*:-1:stcp"/>
                <__group name="Cyan" role="Team Member"/>
                <status battery="100"/>
                <takv device="iPhone" platform="OmniTAK" os="iOS" version="1.0.0"/>
                <track speed="\(location.speed)" course="\(location.course)"/>
            </detail>
        </event>
        """
    }
}

// MARK: - ATAK Status Bar

struct ATAKStatusBar: View {
    let connectionStatus: String
    let isConnected: Bool
    let messagesReceived: Int
    let messagesSent: Int
    let gpsAccuracy: Double
    let onServerTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Connection Status
            Button(action: onServerTap) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "TAK" : "DISC")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isConnected ? .green : .red)
                }
            }

            // Messages
            HStack(spacing: 2) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10))
                Text("\(messagesReceived)")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.cyan)

            HStack(spacing: 2) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 10))
                Text("\(messagesSent)")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.orange)

            Spacer()

            // GPS Status
            HStack(spacing: 4) {
                Image(systemName: gpsAccuracy < 10 ? "location.fill" : "location.slash.fill")
                    .font(.system(size: 10))
                Text(String(format: "±%.0fm", gpsAccuracy))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(gpsAccuracy < 10 ? .green : .yellow)

            // Time
            Text(Date().formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - ATAK Bottom Toolbar

struct ATAKBottomToolbar: View {
    @Binding var mapType: MKMapType
    @Binding var showLayersPanel: Bool
    let onCenterUser: () -> Void
    let onSendCoT: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            // Layers
            ToolButton(icon: "square.stack.3d.up.fill", label: "Layers") {
                showLayersPanel.toggle()
            }

            Spacer()

            // Center on User
            ToolButton(icon: "location.fill", label: "GPS") {
                onCenterUser()
            }

            // Send Position
            ToolButton(icon: "paperplane.fill", label: "Broadcast") {
                onSendCoT()
            }

            // Zoom Controls
            VStack(spacing: 8) {
                ToolButton(icon: "plus", label: "", compact: true) {
                    onZoomIn()
                }
                ToolButton(icon: "minus", label: "", compact: true) {
                    onZoomOut()
                }
            }

            Spacer()

            // Measure Tool
            ToolButton(icon: "ruler", label: "Measure") {
                // TODO: Implement measure tool
            }

            // Route Tool
            ToolButton(icon: "arrow.triangle.turn.up.right.diamond.fill", label: "Route") {
                // TODO: Implement route tool
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// Tool Button Component
struct ToolButton: View {
    let icon: String
    let label: String
    var compact: Bool = false
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 16 : 20, weight: .semibold))
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                }
            }
            .foregroundColor(.white)
            .frame(width: compact ? 36 : 56, height: compact ? 36 : 56)
            .background(isPressed ? Color.cyan.opacity(0.5) : Color.black.opacity(0.3))
            .cornerRadius(8)
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - ATAK Side Panel

struct ATAKSidePanel: View {
    @Binding var isExpanded: Bool
    let onLayerToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                // Compact header with close button
                HStack {
                    Text("LAYERS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { isExpanded = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 16))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

                LayerButton(icon: "map", title: "Satellite", isActive: true, compact: true) {
                    onLayerToggle("satellite")
                }
                LayerButton(icon: "map.fill", title: "Hybrid", isActive: false, compact: true) {
                    onLayerToggle("hybrid")
                }
                LayerButton(icon: "map.circle", title: "Standard", isActive: false, compact: true) {
                    onLayerToggle("standard")
                }

                Divider()
                    .background(Color.white.opacity(0.3))
                    .padding(.vertical, 4)

                Text("UNITS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)

                LayerButton(icon: "shield.fill", title: "Friendly", isActive: true, compact: true) {
                    // Toggle friendly units
                }
                LayerButton(icon: "exclamationmark.triangle.fill", title: "Hostile", isActive: true, compact: true) {
                    // Toggle hostile units
                }
                LayerButton(icon: "questionmark.circle.fill", title: "Unknown", isActive: false, compact: true) {
                    // Toggle unknown units
                }
            }
            .frame(width: 160)
            .padding(.vertical, 8)
            .padding(.bottom, 8)
        }
        .animation(.spring(), value: isExpanded)
    }
}

struct LayerButton: View {
    let icon: String
    let title: String
    let isActive: Bool
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 6 : 8) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 12 : 14))
                    .frame(width: compact ? 16 : 20)
                Text(title)
                    .font(.system(size: compact ? 11 : 13))
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: compact ? 12 : 14))
                        .foregroundColor(.green)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(isActive ? Color.green.opacity(0.2) : Color.clear)
            .cornerRadius(6)
        }
    }
}

// MARK: - CoT Marker

struct CoTMarker: Identifiable {
    let id = UUID()
    let uid: String
    let coordinate: CLLocationCoordinate2D
    let type: String
    let callsign: String
    let team: String
}

struct CoTMarkerView: View {
    let marker: CoTMarker

    var body: some View {
        VStack(spacing: 2) {
            // Icon based on type
            Image(systemName: markerIcon)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(markerColor)
                .shadow(color: .black, radius: 2)

            // Callsign
            Text(marker.callsign)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(markerColor.opacity(0.8))
                .cornerRadius(4)
                .shadow(color: .black, radius: 1)
        }
    }

    private var markerIcon: String {
        if marker.type.contains("a-f") {
            return "shield.fill"  // Friendly
        } else if marker.type.contains("a-h") {
            return "exclamationmark.triangle.fill"  // Hostile
        } else {
            return "questionmark.circle.fill"  // Unknown
        }
    }

    private var markerColor: Color {
        if marker.type.contains("a-f") {
            return .cyan  // Friendly = cyan (ATAK standard)
        } else if marker.type.contains("a-h") {
            return .red  // Hostile = red
        } else {
            return .yellow  // Unknown = yellow
        }
    }
}

// MARK: - Server Config View

struct ServerConfigView: View {
    @ObservedObject var takService: TAKService
    @State private var serverHost = "204.48.30.216"
    @State private var serverPort = "8087"
    @State private var useTLS = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Server Configuration") {
                    TextField("Host", text: $serverHost)
                        .autocapitalization(.none)
                    TextField("Port", text: $serverPort)
                        .keyboardType(.numberPad)
                    Toggle("Use TLS", isOn: $useTLS)
                }

                Section("Status") {
                    HStack {
                        Text("Connection")
                        Spacer()
                        Text(takService.connectionStatus)
                            .foregroundColor(takService.isConnected ? .green : .red)
                    }
                    HStack {
                        Text("Messages RX")
                        Spacer()
                        Text("\(takService.messagesReceived)")
                    }
                    HStack {
                        Text("Messages TX")
                        Spacer()
                        Text("\(takService.messagesSent)")
                    }
                }

                Section {
                    Button(action: connectToServer) {
                        HStack {
                            Spacer()
                            Text(takService.isConnected ? "Disconnect" : "Connect")
                                .foregroundColor(takService.isConnected ? .red : .blue)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("TAK Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func connectToServer() {
        if takService.isConnected {
            takService.disconnect()
        } else {
            guard let port = UInt16(serverPort) else { return }
            takService.connect(
                host: serverHost,
                port: port,
                protocolType: "tcp",
                useTLS: useTLS
            )
        }
    }
}

// MARK: - Location Manager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var accuracy: Double = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        accuracy = locations.last?.horizontalAccuracy ?? 0
    }
}
