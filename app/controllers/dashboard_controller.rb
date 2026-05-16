class DashboardController < ApplicationController
  def index
    @jumps = Jump.recent.includes(:flight_import).limit(6)
    @flight_imports = FlightImport.recent.limit(5)
    @stats = {
      jumps_count: Jump.count,
      imports_count: FlightImport.count,
      total_distance_m: Jump.sum(:distance_m),
      total_duration_seconds: Jump.sum(:duration_seconds)
    }
  end
end
