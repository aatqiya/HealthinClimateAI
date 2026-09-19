import Foundation
import Observation

@Observable @MainActor
final class EnvironmentStore {
    struct Cached { var series:EnvironmentalTimeSeries; var checkedAt:Date }
    var current:Cached?; var errorMessage:String?; var isLoading=false
    private let provider:EnvironmentalDataProviding=OpenMeteoProvider(); private var cache:[String:Cached]=[:]
    func refresh(location:ActivityLocation,force:Bool=false) async { let key=String(format:"%.2f,%.2f",location.latitude,location.longitude); let now=Date(); if !force,let hit=cache[key],now.timeIntervalSince(hit.checkedAt)<300{current=hit;return};isLoading=true;defer{isLoading=false};do{let range=now.addingTimeInterval(-3600)...now.addingTimeInterval(60*60*48);let s=try await provider.fetchConditions(latitude:location.latitude,longitude:location.longitude,range:range);let c=Cached(series:s,checkedAt:now);cache[key]=c;current=c;errorMessage=nil}catch{errorMessage=(error as? LocalizedError)?.errorDescription ?? error.localizedDescription}}
}
