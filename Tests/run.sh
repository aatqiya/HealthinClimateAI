#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH=/tmp/resilio-clang-cache
swiftc -module-cache-path /tmp/resilio-swift-cache \
  ExposureNavigator/Models/*.swift \
  ExposureNavigator/Storage/*.swift \
  ExposureNavigator/Engine/*.swift \
  ExposureNavigator/Services/EnvironmentalDataProviding.swift \
  ExposureNavigator/Services/OpenMeteoProvider.swift \
  ExposureNavigator/Services/ForecastRepository.swift \
  ExposureNavigator/Services/IntegrationServices.swift \
  ExposureNavigator/Services/LocalPlanAssistant.swift \
  Tests/RegressionTests.swift -o /tmp/resilio-regression-tests
/tmp/resilio-regression-tests
