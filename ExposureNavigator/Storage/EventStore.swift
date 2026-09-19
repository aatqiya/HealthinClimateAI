import Foundation
import Observation

@Observable
final class EventStore {
    private(set) var events:[ActivityEvent]=[]
    private let fileURL:URL
    init(){let d=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0];try? FileManager.default.createDirectory(at:d,withIntermediateDirectories:true);fileURL=d.appendingPathComponent("events.json");load()}
    var upcoming:[ActivityEvent]{events.filter{$0.endTime>Date()}.sorted{$0.selectedStart<$1.selectedStart}}
    func save(_ event:ActivityEvent){if let i=events.firstIndex(where:{$0.id==event.id}){events[i]=event}else{events.append(event)};persist()}
    func delete(_ event:ActivityEvent){events.removeAll{$0.id==event.id};persist()}
    private func load(){guard let d=try? Data(contentsOf:fileURL),let v=try? JSONDecoder.appDecoder.decode([ActivityEvent].self,from:d) else{return};events=v}
    private func persist(){if let d=try? JSONEncoder.appEncoder.encode(events){try? d.write(to:fileURL,options:.atomic)}}
}
