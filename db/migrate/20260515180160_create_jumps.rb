class CreateJumps < ActiveRecord::Migration[8.1]
  def change
    create_table :jumps do |t|
      t.references :flight_import, null: false, foreign_key: true
      t.string :name
      t.string :location
      t.text :notes
      t.datetime :started_at
      t.datetime :ended_at
      t.datetime :exit_at
      t.datetime :opening_at
      t.datetime :landing_at
      t.float :duration_seconds
      t.float :min_altitude_m
      t.float :max_altitude_m
      t.float :altitude_loss_m
      t.float :distance_m
      t.float :max_horizontal_speed_mps
      t.float :max_vertical_speed_mps
      t.float :avg_glide_ratio
      t.integer :sample_count, null: false, default: 0
      t.integer :sensor_sample_count, null: false, default: 0

      t.timestamps
    end

    add_index :jumps, :started_at
    add_index :jumps, :exit_at
  end
end
