import Foundation
import VitaEpochCore

public enum MovementPlanningError: Error { case invalidWindow, unsupportedDay }

/// Research collection planning only: no stage labels, BLE writes or production sleep behavior.
public enum MovementPagePlanner {
    public static func selectors(start: Date, end: Date, capturedAt: Date, calendar: Calendar) throws -> [MovementSelector] {
        guard start < end else { throw MovementPlanningError.invalidWindow }
        let captureDay = calendar.startOfDay(for: capturedAt)
        guard let earliest = calendar.date(byAdding: .day, value: -1, to: captureDay),
              let latest = calendar.date(byAdding: .day, value: 1, to: captureDay),
              start >= earliest, end <= latest else { throw MovementPlanningError.unsupportedDay }
        guard var cursor = calendar.dateInterval(of: .minute, for: start)?.start else { throw MovementPlanningError.invalidWindow }
        var selected: [MovementSelector] = []
        while cursor < end {
            let represented = calendar.startOfDay(for: cursor)
            guard let offset = calendar.dateComponents([.day], from: represented, to: captureDay).day,
                  (0...1).contains(offset) else { throw MovementPlanningError.unsupportedDay }
            let selector = try MovementSelector(dayOffset: UInt8(offset), page: UInt8(calendar.component(.hour, from: cursor) / 3))
            if !selected.contains(selector) { selected.append(selector) }
            cursor = cursor.addingTimeInterval(60)
        }
        return selected
    }
}
