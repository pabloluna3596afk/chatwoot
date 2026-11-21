class CreateWhatsappTemplateDrafts < ActiveRecord::Migration[7.1]
  def change
    create_drafts
    create_submissions
  end

  private

  def create_drafts
    create_table :whatsapp_template_drafts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :preferred_channel, foreign_key: { to_table: :channel_whatsapp, on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :source_draft, foreign_key: { to_table: :whatsapp_template_drafts }
      draft_content(t)
      t.timestamps
    end
    add_index(
      :whatsapp_template_drafts, [:account_id, :waba_id, :name, :language],
      unique: true,
      where: 'archived_at IS NULL AND waba_id IS NOT NULL AND name IS NOT NULL AND language IS NOT NULL',
      name: 'index_wa_drafts_on_identity'
    )
    add_index :whatsapp_template_drafts, [:account_id, :archived_at, :updated_at], name: 'index_wa_drafts_on_catalog'
  end

  def draft_content(table)
    table.string :source_remote_id
    table.string :title, null: false, default: ''
    [:waba_id, :name, :language, :category, :parameter_format].each { |field| table.string field }
    table.jsonb :definition, null: false, default: {}
    table.jsonb :variable_bindings, null: false, default: {}
    table.integer :lock_version, null: false, default: 0
    table.datetime :archived_at
  end

  def create_submissions
    create_table :whatsapp_template_submissions do |t|
      t.references :whatsapp_template_draft, null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :revision, null: false
      [:waba_id, :name, :language].each { |field| t.string field, null: false }
      t.jsonb :snapshot, null: false
      t.string :payload_digest, null: false
      t.string :status, null: false, default: 'submitting'
      submission_result(t)
      t.timestamps
    end
    submission_indexes
  end

  def submission_result(table)
    [:remote_id, :remote_status, :remote_category].each { |field| table.string field }
    table.text :remote_reason
    table.jsonb :error_details, null: false, default: {}
    table.jsonb :request_payload
    table.boolean :retry_permitted, null: false, default: false
    table.integer :request_count, null: false, default: 0
    table.datetime :next_retry_at
    table.datetime :submitted_at
  end

  def submission_indexes
    add_index :whatsapp_template_submissions, [:whatsapp_template_draft_id, :revision], unique: true, name: 'index_wa_submissions_on_revision'
    add_index(
      :whatsapp_template_submissions, [:account_id, :waba_id, :name, :language],
      unique: true,
      where: "status IN ('submitting', 'reconciling', 'submitted')",
      name: 'index_wa_submissions_on_identity'
    )
  end
end
