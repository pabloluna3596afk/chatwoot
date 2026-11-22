class CreateCalendarTemplateResources < ActiveRecord::Migration[7.1]
  def change
    create_table :calendar_template_resources do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :whatsapp_template_draft, foreign_key: { on_delete: :nullify }, index: { name: 'index_calendar_resources_on_draft' }
      t.string :function, null: false
      t.string :language, null: false
      t.string :waba_id
      t.string :template_name, null: false
      t.string :remote_template_id
      t.datetime :linked_at
      t.string :status, null: false, default: 'pending'
      t.string :incompatibility_reason
      t.jsonb :contract_snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :calendar_template_resources, [:account_id, :function, :language, :waba_id], unique: true,
              where: 'waba_id IS NOT NULL',
              name: 'index_calendar_resources_on_waba_identity'
    add_index :calendar_template_resources, [:account_id, :function, :language], unique: true,
              where: 'waba_id IS NULL',
              name: 'index_calendar_resources_on_local_identity'
  end
end
