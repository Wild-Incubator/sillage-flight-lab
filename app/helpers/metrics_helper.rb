module MetricsHelper
  def meters(value)
    return "-" if value.blank?

    number_to_human(value, units: { unit: "m", thousand: "km" }, precision: 3)
  end

  def speed_ms(value)
    return "-" if value.blank?

    "#{number_with_precision(value, precision: 1)} m/s"
  end

  def duration(value)
    return "-" if value.blank?

    minutes = value.to_i / 60
    seconds = value.to_i % 60
    format("%02d:%02d", minutes, seconds)
  end

  def glide(value)
    return "-" if value.blank?

    number_with_precision(value, precision: 2)
  end
end
