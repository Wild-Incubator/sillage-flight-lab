class CreateFlightImports < ActiveRecord::Migration[8.1]
  def change
    create_table :flight_imports do |t|
      t.string :source_filename
      t.string :status, null: false, default: "pending"
      t.string :device_id
      t.string :firmware_version
      t.string :session_id
      t.datetime :log_started_at
      t.text :error_message
      t.json :details

      t.timestamps
    end

    add_index :flight_imports, :status
    add_index :flight_imports, :log_started_at
    add_index :flight_imports, :session_id
  end
end
