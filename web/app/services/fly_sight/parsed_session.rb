module FlySight
  ParsedSession = Data.define(:format, :metadata, :track_points, :sensor_samples) do
    def started_at
      track_points.first&.fetch(:recorded_at, nil)
    end
  end
end
