class CreateWhatsappFlowPublications < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_flow_publications, id: :bigint do |t|
      t.references :whatsapp_flow, null: false, foreign_key: { to_table: :whatsapp_flows }
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.string :waba_id, null: false, index: true
      t.string :meta_flow_id, index: true
      t.string :status, default: 'draft', null: false, index: true
      t.jsonb :validation_errors, null: false, default: []
      t.integer :published_version, default: 0
      t.string :old_meta_flow_id
      t.string :draft_meta_flow_id
      t.datetime :published_at
      t.timestamps
    end

    add_index :whatsapp_flow_publications, [:whatsapp_flow_id, :waba_id], unique: true, name: 'idx_flow_pub_flow_waba_unique'
    add_index :whatsapp_flow_publications, [:account_id, :status], name: 'idx_flow_pub_account_status'
  end
end
