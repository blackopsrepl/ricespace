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

ActiveRecord::Schema[8.1].define(version: 2026_10_04_000003) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_tokens", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_agent_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_agent_tokens_on_user_id"
  end

  create_table "blocks", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "blocked_user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_user_id"], name: "index_blocks_on_blocked_user_id"
    t.index ["user_id"], name: "index_blocks_on_user_id"
  end

  create_table "blurbs", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title", null: false
    t.text "body", default: "", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "position"], name: "index_blurbs_on_user_id_and_position"
    t.index ["user_id"], name: "index_blurbs_on_user_id"
  end

  create_table "build_photos", force: :cascade do |t|
    t.integer "build_id", null: false
    t.string "caption"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["build_id", "position"], name: "index_build_photos_on_build_id_and_position"
    t.index ["build_id"], name: "index_build_photos_on_build_id"
  end

  create_table "builds", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title", null: false
    t.string "kind"
    t.string "summary"
    t.text "details", default: "", null: false
    t.string "specs"
    t.string "cooling"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_builds_on_user_id"
  end

  create_table "comments", force: :cascade do |t|
    t.integer "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "commentable_type", null: false
    t.integer "commentable_id", null: false
    t.index ["author_id"], name: "index_comments_on_author_id"
    t.index ["commentable_type", "commentable_id", "created_at"], name: "index_comments_on_commentable_and_time"
    t.index ["created_at"], name: "index_comments_on_user_id_and_created_at"
  end

  create_table "demos", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title", null: false
    t.string "group_name"
    t.string "party"
    t.integer "release_year"
    t.string "platform"
    t.string "category"
    t.integer "ranking"
    t.string "url"
    t.string "watch_note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "title"], name: "index_demos_on_user_id_and_title"
    t.index ["user_id"], name: "index_demos_on_user_id"
  end

  create_table "friendships", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "friend_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "position", default: 0, null: false
    t.index ["friend_id"], name: "index_friendships_on_friend_id"
    t.index ["user_id", "friend_id"], name: "index_friendships_on_user_id_and_friend_id", unique: true
    t.index ["user_id", "position"], name: "index_friendships_on_user_id_and_position"
    t.index ["user_id"], name: "index_friendships_on_user_id"
  end

  create_table "peer_records", force: :cascade do |t|
    t.string "author_pubkey", null: false
    t.integer "seq", null: false
    t.string "kind", null: false
    t.text "body_json", default: "{}", null: false
    t.string "signer"
    t.string "signature"
    t.string "record_hash"
    t.string "prev_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_pubkey", "kind"], name: "index_peer_records_on_author_pubkey_and_kind"
    t.index ["author_pubkey", "seq"], name: "index_peer_records_on_author_pubkey_and_seq", unique: true
  end

  create_table "peers", force: :cascade do |t|
    t.string "pubkey", null: false
    t.string "petname"
    t.boolean "followed", default: false, null: false
    t.boolean "self_feed", default: false, null: false
    t.integer "latest_seq", default: 0, null: false
    t.string "latest_hash"
    t.boolean "compromised", default: false, null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pubkey"], name: "index_peers_on_pubkey", unique: true
  end

  create_table "profile_pictures", force: :cascade do |t|
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_profile_pictures_on_user_id", unique: true
  end

  create_table "profiles", force: :cascade do |t|
    t.integer "user_id", null: false
    t.text "document", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 0, null: false
    t.string "song_url"
    t.string "song_title"
    t.json "interests", default: {}
    t.integer "view_count", default: 0
    t.index ["user_id"], name: "index_profiles_on_user_id", unique: true
  end

  create_table "ratings", force: :cascade do |t|
    t.integer "author_id", null: false
    t.integer "score", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "rateable_type", null: false
    t.integer "rateable_id", null: false
    t.index ["author_id", "rateable_type", "rateable_id"], name: "index_ratings_on_author_and_rateable", unique: true
    t.index ["author_id"], name: "index_ratings_on_author_id"
    t.index ["rateable_type", "rateable_id"], name: "index_ratings_on_rateable_type_and_rateable_id"
  end

  create_table "showcase_shots", force: :cascade do |t|
    t.integer "showcase_id", null: false
    t.string "caption"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["showcase_id", "position"], name: "index_showcase_shots_on_showcase_id_and_position"
    t.index ["showcase_id"], name: "index_showcase_shots_on_showcase_id"
  end

  create_table "showcases", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title"
    t.string "summary"
    t.text "details", default: "", null: false
    t.string "hardware"
    t.string "window_manager"
    t.string "bar"
    t.string "terminal"
    t.string "font"
    t.string "theme"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_showcases_on_user_id", unique: true
  end

  create_table "stream_links", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "url", null: false
    t.string "platform", null: false
    t.string "reference", null: false
    t.string "title"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "platform"], name: "index_stream_links_on_user_id_and_platform", unique: true
    t.index ["user_id"], name: "index_stream_links_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "username", null: false
    t.string "name"
    t.string "headline"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "greeting"
    t.string "mood"
    t.boolean "admin", default: false, null: false
    t.datetime "last_seen_at"
    t.string "pubkey"
    t.boolean "feed_link_verified", default: false, null: false
    t.json "feed_snapshot", default: {}, null: false
    t.string "feed_sync_status"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["pubkey"], name: "index_users_on_pubkey", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_tokens", "users"
  add_foreign_key "blocks", "blocked_users"
  add_foreign_key "blocks", "users"
  add_foreign_key "blurbs", "users"
  add_foreign_key "build_photos", "builds"
  add_foreign_key "builds", "users"
  add_foreign_key "comments", "users", column: "author_id"
  add_foreign_key "demos", "users"
  add_foreign_key "friendships", "users"
  add_foreign_key "friendships", "users", column: "friend_id"
  add_foreign_key "profile_pictures", "users"
  add_foreign_key "profiles", "users"
  add_foreign_key "ratings", "users", column: "author_id"
  add_foreign_key "showcase_shots", "showcases"
  add_foreign_key "showcases", "users"
  add_foreign_key "stream_links", "users"
end
