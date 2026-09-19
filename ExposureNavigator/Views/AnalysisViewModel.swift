import Foundation
import Observation

@Observable
@MainActor
final class AnalysisViewModel {
    enum State {
        case idle
        case loading
        case failed(String)
        case loaded(CounterfactualResult, EnvironmentalTimeSeries)
    }

    var state: State = .idle

    private let provider: EnvironmentalDataProviding

    init(provider: EnvironmentalDataProviding = ForecastRepository.shared) {
        self.provider = provider
    }

    /// One network fetch covers the full candidate window; every counterfactual
    /// is then evaluated locally against that series.
    func analyze(plan: ActivityPlan) async {
        state = .loading

        let range = plan.startTime...plan.endTime

        do {
            let series = try await provider.fetchConditions(
                latitude: plan.location.latitude,
                longitude: plan.location.longitude,
                range: range
            )
            let result = CounterfactualEngine.evaluate(plan: plan, series: series)
            guard !result.original.metrics.isEmpty else {
                state = .failed("There isn't enough published data covering your activity window to model exposure.")
                return
            }
            state = .loaded(result, series)
        } catch let error as EnvironmentalDataError {
            state = .failed(error.errorDescription ?? "Something went wrong fetching environmental data.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
