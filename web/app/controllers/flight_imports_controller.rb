class FlightImportsController < ApplicationController
  def new
  end

  def create
    flight_import = FlySight::ImportService.new(source_files).call
    jump = flight_import.jumps.recent.first

    redirect_to(jump || flight_import, notice: t(".success", count: flight_import.jumps.count))
  rescue FlySight::Error, Zip::Error, ActiveRecord::RecordInvalid => error
    redirect_back fallback_location: root_path, alert: error.message
  end

  def show
    @flight_import = FlightImport.find(params[:id])
    @jumps = @flight_import.jumps.recent
  end

  private

  def source_files
    params.dig(:flight_import, :source_files) || []
  end
end
