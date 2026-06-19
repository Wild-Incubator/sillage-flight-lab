require "open3"
require "tempfile"

module Videos
  class WebOptimizer
    class Error < StandardError; end

    Result = Struct.new(:io, :filename, :duration_seconds, keyword_init: true) do
      def close
        io&.close!
      end
    end

    def initialize(blob, ffmpeg_path: ENV.fetch("FFMPEG_PATH", "ffmpeg"), ffprobe_path: ENV.fetch("FFPROBE_PATH", "ffprobe"))
      @blob = blob
      @ffmpeg_path = ffmpeg_path
      @ffprobe_path = ffprobe_path
    end

    def call
      input = download_input
      output = Tempfile.new([ "sillage-video-", ".mp4" ], binmode: true)
      output.close

      run_ffmpeg(input.path, output.path)
      output.open
      output.binmode
      output.rewind

      Result.new(
        io: output,
        filename: optimized_filename,
        duration_seconds: probe_duration(output.path)
      )
    ensure
      input&.close!
    end

    private

    attr_reader :blob, :ffmpeg_path, :ffprobe_path

    def download_input
      extension = blob.filename.extension_with_delimiter.presence || ".video"
      Tempfile.new([ "sillage-source-", extension ], binmode: true).tap do |file|
        blob.download { |chunk| file.write(chunk) }
        file.flush
        file.rewind
      end
    end

    def run_ffmpeg(input_path, output_path)
      run!(
        ffmpeg_path,
        "-hide_banner",
        "-y",
        "-i", input_path,
        "-map", "0:v:0",
        "-map", "0:a?",
        "-vf", "scale=w='min(1920,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-crf", "23",
        "-profile:v", "high",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        "-b:a", "128k",
        "-ac", "2",
        "-movflags", "+faststart",
        output_path
      )
    end

    def probe_duration(path)
      stdout = run!(
        ffprobe_path,
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        path
      ).first

      duration = Float(stdout)
      duration.positive? ? duration : nil
    rescue ArgumentError
      nil
    end

    def run!(*command)
      stdout, stderr, status = Open3.capture3(*command)
      raise Error, "#{command.first} failed: #{stderr.presence || stdout}" unless status.success?

      [ stdout, stderr ]
    rescue Errno::ENOENT
      raise Error, "#{command.first} is not installed"
    end

    def optimized_filename
      basename = blob.filename.base.parameterize.presence || "jump-video"
      "#{basename}-web.mp4"
    end
  end
end
