class CreateAccountFeatureOverrides < ActiveRecord::Migration[7.0]
  def change
    create_table :account_feature_overrides do |t|
      t.references :account, null: false, foreign_key: true
      t.string :feature_key, null: false
      t.boolean :enabled, default: false, null: false
      t.text :reason, null: false
      t.datetime :expires_at
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :account_feature_overrides, %i[account_id feature_key], unique: true
    add_index :account_feature_overrides, :expires_at
  end
end
