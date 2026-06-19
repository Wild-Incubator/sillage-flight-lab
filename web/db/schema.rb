# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_22_120000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "flight_imports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "details"
    t.string "device_id"
    t.text "error_message"
    t.string "firmware_version"
    t.datetime "log_started_at"
    t.string "session_id"
    t.string "source_filename"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["log_started_at"], name: "index_flight_imports_on_log_started_at"
    t.index ["session_id"], name: "index_flight_imports_on_session_id"
    t.index ["status"], name: "index_flight_imports_on_status"
  end

  create_table "jumps", force: :cascade do |t|
    t.float "altitude_loss_m"
    t.float "avg_glide_ratio"
    t.datetime "created_at", null: false
    t.float "distance_m"
    t.float "duration_seconds"
    t.datetime "ended_at"
    t.datetime "exit_at"
    t.integer "flight_import_id", null: false
    t.datetime "landing_at"
    t.string "location"
    t.float "max_altitude_m"
    t.float "max_horizontal_speed_mps"
    t.float "max_vertical_speed_mps"
    t.float "min_altitude_m"
    t.string "name"
    t.text "notes"
    t.datetime "opening_at"
    t.integer "sample_count", default: 0, null: false
    t.integer "sensor_sample_count", default: 0, null: false
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.float "video_duration_seconds"
    t.float "video_exit_offset_seconds"
    t.text "video_processing_error"
    t.string "video_processing_status", default: "empty", null: false
    t.index ["exit_at"], name: "index_jumps_on_exit_at"
    t.index ["flight_import_id"], name: "index_jumps_on_flight_import_id"
    t.index ["started_at"], name: "index_jumps_on_started_at"
    t.index ["video_processing_status"], name: "index_jumps_on_video_processing_status"
  end

  create_table "sensor_samples", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "elapsed_seconds"
    t.integer "jump_id", null: false
    t.json "readings"
    t.datetime "recorded_at"
    t.string "sensor_type"
    t.datetime "updated_at", null: false
    t.index ["jump_id", "elapsed_seconds"], name: "index_sensor_samples_on_jump_id_and_elapsed_seconds"
    t.index ["jump_id", "sensor_type"], name: "index_sensor_samples_on_jump_id_and_sensor_type"
    t.index ["jump_id"], name: "index_sensor_samples_on_jump_id"
  end

  create_table "track_points", force: :cascade do |t|
    t.float "altitude_m"
    t.float "course_accuracy_deg"
    t.datetime "created_at", null: false
    t.float "distance_from_start_m"
    t.float "elapsed_seconds"
    t.float "glide_ratio"
    t.integer "gps_fix"
    t.float "heading_deg"
    t.float "horizontal_accuracy_m"
    t.float "horizontal_speed_mps"
    t.integer "jump_id", null: false
    t.float "lat"
    t.float "lon"
    t.datetime "recorded_at"
    t.integer "satellite_count"
    t.float "speed_accuracy_mps"
    t.datetime "updated_at", null: false
    t.float "vel_d_mps"
    t.float "vel_e_mps"
    t.float "vel_n_mps"
    t.float "vertical_accuracy_m"
    t.float "vertical_speed_mps"
    t.index ["jump_id", "elapsed_seconds"], name: "index_track_points_on_jump_id_and_elapsed_seconds"
    t.index ["jump_id", "recorded_at"], name: "index_track_points_on_jump_id_and_recorded_at"
    t.index ["jump_id"], name: "index_track_points_on_jump_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "jumps", "flight_imports"
  add_foreign_key "sensor_samples", "jumps"
  add_foreign_key "track_points", "jumps"
end
