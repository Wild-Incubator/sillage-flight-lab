class JumpVideoProcessingJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(jump)
    return unless jump.video_upload.attached?

    result = Videos::WebOptimizer.new(jump.video_upload.blob).call
    jump.video.attach(
      io: result.io,
      filename: result.filename,
      content_type: "video/mp4"
    )
    jump.update!(
      video_processing_status: "ready",
      video_processing_error: nil,
      video_duration_seconds: result.duration_seconds
    )
    jump.video_upload.purge_later
  rescue Videos::WebOptimizer::Error => error
    jump.update!(
      video_processing_status: "failed",
      video_processing_error: error.message.truncate(500)
    )
    raise
  ensure
    result&.close
  end
end
