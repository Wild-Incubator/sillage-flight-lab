class AddVideoSyncToJumps < ActiveRecord::Migration[8.1]
  def change
    add_column :jumps, :video_exit_offset_seconds, :float
    add_column :jumps, :video_duration_seconds, :float
    add_column :jumps, :video_processing_status, :string, null: false, default: "empty"
    add_column :jumps, :video_processing_error, :text

    add_index :jumps, :video_processing_status
  end
end
