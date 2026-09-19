import Foundation
import Observation

@Observable
final class ProfileStore {
    private(set) var profiles:[UserProfile]=[]
    var selectedProfileID:UUID? { didSet { saveSelection() } }
    private let fileURL:URL
    init(filename:String="profiles-v2.json") { let d=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]; try? FileManager.default.createDirectory(at:d,withIntermediateDirectories:true); fileURL=d.appendingPathComponent(filename); load(); selectedProfileID=UUID(uuidString:UserDefaults.standard.string(forKey:"selectedProfileID") ?? "") ?? profiles.first?.id }
    var selectedProfile:UserProfile? { profiles.first{$0.id==selectedProfileID} }
    func select(_ id:UUID){ selectedProfileID=id }
    func add(_ p:UserProfile){ profiles.append(p); selectedProfileID=p.id; save() }
    func update(_ p:UserProfile){ guard let i=profiles.firstIndex(where:{$0.id==p.id}) else{return}; var x=p;x.updatedAt=Date();profiles[i]=x;save() }
    func delete(_ p:UserProfile){ profiles.removeAll{$0.id==p.id}; if selectedProfileID==p.id {selectedProfileID=profiles.first?.id}; save() }
    func addSampleProfiles(){ let p=UserProfile(name:"Maya",relationship:.child,age:12,homeZipCode:"10044",medicalConditions:["Asthma"],source:.synthetic); if !profiles.contains(where:{$0.name==p.name}){profiles.append(p)}; selectedProfileID=p.id;save() }
    private func load(){ guard let d=try? Data(contentsOf:fileURL),let p=try? JSONDecoder.appDecoder.decode([UserProfile].self,from:d) else{return};profiles=p }
    private func save(){ if let d=try? JSONEncoder.appEncoder.encode(profiles){try? d.write(to:fileURL,options:.atomic)} }
    private func saveSelection(){ UserDefaults.standard.set(selectedProfileID?.uuidString,forKey:"selectedProfileID") }
}
extension JSONEncoder { static var appEncoder:JSONEncoder { let e=JSONEncoder();e.dateEncodingStrategy = .iso8601;return e } }
extension JSONDecoder { static var appDecoder:JSONDecoder { let d=JSONDecoder();d.dateDecodingStrategy = .iso8601;return d } }
