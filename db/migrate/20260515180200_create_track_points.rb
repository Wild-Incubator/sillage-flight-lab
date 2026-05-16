class CreateTrackPoints < ActiveRecord::Migration[8.1]
  def change
    create_table :track_points do |t|
      t.references :jump, null: false, foreign_key: true
      t.datetime :recorded_at
      t.float :elapsed_seconds
      t.float :lat
      t.float :lon
      t.float :altitude_m
      t.float :vel_n_mps
      t.float :vel_e_mps
      t.float :vel_d_mps
      t.float :horizontal_accuracy_m
      t.float :vertical_accuracy_m
      t.float :speed_accuracy_mps
      t.float :heading_deg
      t.float :course_accuracy_deg
      t.integer :gps_fix
      t.integer :satellite_count
      t.float :horizontal_speed_mps
      t.float :vertical_speed_mps
      t.float :glide_ratio
      t.float :distance_from_start_m

      t.timestamps
    end

    add_index :track_points, [ :jump_id, :recorded_at ]
    add_index :track_points, [ :jump_id, :elapsed_seconds ]
  end
end
