# The forms ("flows") built in ChatHub: one neutral definition per form (see Whatsapp::Flows::Spec), saved as a draft
# while it is being built. Not to be confused with the conversation automations in the `flows` table.
class CreateWhatsappFlows < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_flows do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.jsonb :categories, null: false, default: []
      t.jsonb :definition, null: false, default: {}
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    add_index :whatsapp_flows, [:account_id, :name]
  end
end
