import Foundation
import CoreLocation

/// A GPS waypoint captured during recording
struct GPSWaypoint: Codable, Identifiable, Equatable {
    let id: UUID
    /// Time since recording started (seconds)
    let offsetFromStart: TimeInterval
    /// ISO 8601 timestamp of when this waypoint was captured
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    /// Horizontal accuracy in meters
    let accuracy: Double
    
    init(offsetFromStart: TimeInterval, location: CLLocation) {
        self.id = UUID()
        self.offsetFromStart = offsetFromStart
        self.timestamp = Date()
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.accuracy = location.horizontalAccuracy
    }
    
    var coordinateString: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }
    
    var accuracyString: String {
        String(format: "±%.0fm", accuracy)
    }
}

/// Collection of GPS waypoints from a recording session
struct GPSWaypointCollection: Codable {
    var waypoints: [GPSWaypoint]
    
    init() {
        self.waypoints = []
    }
    
    /// Add a waypoint at the given offset from recording start
    mutating func addWaypoint(offset: TimeInterval, location: CLLocation) {
        let waypoint = GPSWaypoint(offsetFromStart: offset, location: location)
        waypoints.append(waypoint)
    }
    
    /// Add final waypoint at recording end
    mutating func addFinalWaypoint(offset: TimeInterval, location: CLLocation?) {
        guard let location = location else { return }
        let waypoint = GPSWaypoint(offsetFromStart: offset, location: location)
        waypoints.append(waypoint)
    }
    
    /// Encode to dictionary for JSON metadata
    func toDictionary() -> [[String: Any]] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(waypoints),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return dict
    }
    
    var count: Int { waypoints.count }
    
    var startWaypoint: GPSWaypoint? { waypoints.first }
    var endWaypoint: GPSWaypoint? { waypoints.last }
}