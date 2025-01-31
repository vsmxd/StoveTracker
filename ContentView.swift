//
//  ContentView.swift
//  StoveTracker
//
//  Created by Vishnu on 12/26/24.
//

import SwiftUI
import CoreLocation
import UserNotifications
import MapKit

// MARK: - Data Models
struct StoveStatus: Codable {
    var isOn: Bool
    var lastUpdated: Date?
    
    static let defaultStatus = StoveStatus(isOn: false, lastUpdated: nil)
}

struct HomeLocation: Codable {
    var latitude: Double
    var longitude: Double
    var radius: Double // Dynamic radius in meters
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var didLeaveHome = false
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var isMonitoringLocation = false
    private var currentRegion: CLCircularRegion?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
//        locationManager.showsBackgroundLocationIndicator = true
    }
    
    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.first?.coordinate
    }
    
    func setHomeLocation(_ coordinate: CLLocationCoordinate2D, radius: Double) {
        if let existingRegion = currentRegion {
            locationManager.stopMonitoring(for: existingRegion)
        }
        
        let region = CLCircularRegion(center: coordinate,
                                      radius: radius,
                                      identifier: "home")
        region.notifyOnExit = true
        currentRegion = region
        locationManager.startMonitoring(for: region)
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if region.identifier == "home" {
            didLeaveHome = true
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("DidLeaveHome"), object: nil)
            }
        }
    }
}

// MARK: - Notification Manager
class NotificationManager {
    static let shared = NotificationManager()
    
    func requestPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            print("Notification permission granted: \(granted)")
        }
    }
    
    func scheduleStoveCheckNotification(isStoveOn: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Stove Check"
        content.body = isStoveOn ?
            "Warning: Your stove is still ON!" :
            "It's been a while since you checked your stove"
        content.sound = .default
        
        // Trigger notification immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "stoveCheck",
                                            content: content,
                                            trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Location Selection View
struct LocationSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LocationManager()
    @Binding var homeLocation: HomeLocation?
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3348, longitude: -122.0090),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var pin: LocationPin?
    @State private var radius: Double = 10
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Top padding
                Spacer()
                    .frame(height: 8)
                
                // Map View (70% of screen)
                CustomMapView(coordinateRegion: $region, selectedCoordinate: $pin)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .frame(height: UIScreen.main.bounds.height * 0.7)
                
                // Controls Section with more top padding
                VStack(spacing: 12) {
                    Spacer()
                        .frame(height: 16)
                    
                    HStack {
                        Text("\(Int(radius))m")
                            .frame(width: 40)
                            .font(.footnote)
                        Slider(value: $radius, in: 5...30, step: 1)
                        Text("radius")
                            .font(.footnote)
                    }
                    .padding(.horizontal)
                    
                    HStack(spacing: 15) {
                        Button("Use Current Location") {
                            if let currentLocation = locationManager.currentLocation {
                                pin = LocationPin(coordinate: currentLocation)
                                withAnimation {
                                    region.center = currentLocation
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Set Location") {
                            if let pinLocation = pin?.coordinate {
                                homeLocation = HomeLocation(latitude: pinLocation.latitude,
                                                            longitude: pinLocation.longitude,
                                                            radius: radius)
                                locationManager.setHomeLocation(pinLocation, radius: radius)
                                dismiss()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(pin == nil)
                    }
                    
                    // Bottom padding
                    Spacer()
                        .frame(height: 24)
                }
                
                Spacer()
            }
            .navigationTitle("Set Home Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                locationManager.requestPermissions()
                if let location = homeLocation {
                    region.center = location.coordinate
                    pin = LocationPin(coordinate: location.coordinate)
                    radius = location.radius
                }
            }
        }
    }
}

// MARK: - Custom MapView Representable
struct CustomMapView: UIViewRepresentable {
    @Binding var coordinateRegion: MKCoordinateRegion
    @Binding var selectedCoordinate: LocationPin?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.setRegion(coordinateRegion, animated: true)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.handleMapTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        mapView.addGestureRecognizer(tapGesture)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if uiView.region.center.latitude != coordinateRegion.center.latitude ||
            uiView.region.center.longitude != coordinateRegion.center.longitude ||
            uiView.region.span.latitudeDelta != coordinateRegion.span.latitudeDelta ||
            uiView.region.span.longitudeDelta != coordinateRegion.span.longitudeDelta {
            uiView.setRegion(coordinateRegion, animated: true)
        }
        
        // Update annotation
        uiView.removeAnnotations(uiView.annotations)
        if let pin = selectedCoordinate {
            let annotation = MKPointAnnotation()
            annotation.coordinate = pin.coordinate
            uiView.addAnnotation(annotation)
        }
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CustomMapView
        
        init(_ parent: CustomMapView) {
            self.parent = parent
        }
        
        @objc func handleMapTap(_ gestureRecognizer: UITapGestureRecognizer) {
            let mapView = gestureRecognizer.view as! MKMapView
            let locationInView = gestureRecognizer.location(in: mapView)
            let coordinate = mapView.convert(locationInView, toCoordinateFrom: mapView)
            
            // Update the selected coordinate
            parent.selectedCoordinate = LocationPin(coordinate: coordinate)
        }
        
        // Customize annotation view
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            
            let identifier = "HomePin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
                (annotationView as? MKMarkerAnnotationView)?.markerTintColor = .red
            } else {
                annotationView?.annotation = annotation
            }
            
            return annotationView
        }
    }
}

// MARK: - LocationPin Struct
struct LocationPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var stoveStatus: StoveStatus = StoveStatus.defaultStatus
    @State private var showingLocationPicker = false
    
    @AppStorage("stoveStatus") private var stoveStatusData: Data = {
        if let data = UserDefaults.standard.data(forKey: "stoveStatus"),
           let status = try? JSONDecoder().decode(StoveStatus.self, from: data) {
            return data
        }
        return try! JSONEncoder().encode(StoveStatus.defaultStatus)
    }()
    
    @AppStorage("homeLocation") private var homeLocationData: Data?
    
    @State private var homeLocation: HomeLocation? {
        didSet {
            if let location = homeLocation {
                if let encodedData = try? JSONEncoder().encode(location) {
                    homeLocationData = encodedData
                }
                locationManager.setHomeLocation(location.coordinate, radius: location.radius)
            } else {
                homeLocationData = nil
            }
        }
    }
    
    private var shouldNotify: Bool {
        if stoveStatus.isOn { return true }
        guard let lastUpdated = stoveStatus.lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 4 * 3600
    }
    
    private var notificationMessage: String {
        if stoveStatus.isOn {
            return "You will be notified when leaving this area because your stove is ON"
        } else if stoveStatus.lastUpdated == nil {
            return "You will be notified when leaving this area because you haven't updated stove status since forever"
        } else {
            return "You will be notified when leaving this area because you haven't updated stove status since \(stoveStatus.lastUpdated?.formatted(date: .abbreviated, time: .shortened) ?? "N/A")"
        }
    }
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                StoveStatusCard(status: stoveStatus)
                
                VStack(spacing: 10) {
                    if let location = homeLocation {
                        Text("Home Location Set")
                            .foregroundColor(.green)
                        Text("Lat: \(String(format: "%.4f", location.latitude)), Long: \(String(format: "%.4f", location.longitude))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Monitoring Radius: \(Int(location.radius)) meters")
                            .foregroundColor(.blue)
                            .font(.subheadline)
                        
                        if locationManager.isMonitoringLocation && shouldNotify {
                            Text(notificationMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    } else {
                        Text("Home Location Not Set")
                            .foregroundColor(.red)
                    }
                    
                    Button("Set Home Location") {
                        showingLocationPicker = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                
                VStack(spacing: 20) {
                    Button(action: markStoveOff) {
                        Text("Mark Stove as OFF")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    Button(action: markStoveOn) {
                        Text("Mark Stove as ON")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Stove Status")
            .sheet(isPresented: $showingLocationPicker) {
                LocationSelectionView(homeLocation: $homeLocation)
            }
            .onAppear {
                locationManager.requestPermissions()
                NotificationManager.shared.requestPermissions()
                loadStoveStatus()
                loadHomeLocation()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DidLeaveHome"))) { _ in
                if shouldNotify {
                    NotificationManager.shared.scheduleStoveCheckNotification(isStoveOn: stoveStatus.isOn)
                }
            }
            .onChange(of: scenePhase) { newPhase, _ in
                if newPhase == .background || newPhase == .inactive {
                    saveStoveStatus()
                    saveHomeLocation()
                }
            }
        }
    }
    
    private func loadStoveStatus() {
        if let decodedStatus = try? JSONDecoder().decode(StoveStatus.self, from: stoveStatusData) {
            stoveStatus = decodedStatus
        } else {
            stoveStatus = StoveStatus.defaultStatus
        }
    }
    
    private func loadHomeLocation() {
        if let data = homeLocationData,
           let location = try? JSONDecoder().decode(HomeLocation.self, from: data) {
            homeLocation = location
            locationManager.setHomeLocation(location.coordinate, radius: location.radius)
        } else {
            homeLocation = nil
        }
    }
    
    private func markStoveOff() {
        stoveStatus = StoveStatus(isOn: false, lastUpdated: Date())
        saveStoveStatus()
    }
    
    private func markStoveOn() {
        stoveStatus = StoveStatus(isOn: true, lastUpdated: Date())
        saveStoveStatus()
    }
    
    private func saveStoveStatus() {
        if let encodedData = try? JSONEncoder().encode(stoveStatus) {
            stoveStatusData = encodedData
        }
    }
    
    private func saveHomeLocation() {
        if let location = homeLocation,
           let encodedData = try? JSONEncoder().encode(location) {
            homeLocationData = encodedData
        } else {
            homeLocationData = nil
        }
    }
}

// MARK: - Stove Status Card View
struct StoveStatusCard: View {
    let status: StoveStatus
    
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: status.isOn ? "flame.fill" : "poweroff")
                .font(.system(size: 60))
                .foregroundColor(status.isOn ? .orange : .green)
            
            Text(status.isOn ? "Stove is ON" : "Stove is OFF")
                .font(.title)
                .bold()
            
            Text("Last updated: \(status.lastUpdated?.formatted(date: .abbreviated, time: .shortened) ?? "N/A")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(radius: 5)
    }
}

// MARK: - Entry Point

@main
struct StoveTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#Preview {
    ContentView()
}
