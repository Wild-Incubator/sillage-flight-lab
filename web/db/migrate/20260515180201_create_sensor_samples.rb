class CreateSensorSamples < ActiveRecord::Migration[8.1]
  def change
    create_table :sensor_samples do |t|
      t.references :jump, null: false, foreign_key: true
      t.string :sensor_type
      t.datetime :recorded_at
      t.float :elapsed_seconds
      t.json :readings

      t.timestamps
    end

    add_index :sensor_samples, [ :jump_id, :sensor_type ]
    add_index :sensor_samples, [ :jump_id, :elapsed_seconds ]
  end
end
