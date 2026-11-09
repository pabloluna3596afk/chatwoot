class CreateExtraPacksAndBalances < ActiveRecord::Migration[7.0]
  def change
    create_table :extra_packs do |t|
      t.string :bucket, null: false
      t.integer :units, null: false
      t.decimal :price_usd, precision: 10, scale: 2, null: false
      t.boolean :active, default: true, null: false
      t.integer :display_order, default: 0, null: false
      t.timestamps
    end
    add_index :extra_packs, [:bucket, :units], unique: true

    create_table :account_extra_balances do |t|
      t.references :account, null: false, foreign_key: true
      t.string :bucket, null: false
      t.integer :units_total, null: false
      t.integer :units_remaining, null: false
      t.datetime :expires_at, null: false
      t.string :source, null: false
      t.references :extra_pack, foreign_key: true
      t.string :external_reference
      t.timestamps
    end
    add_index :account_extra_balances, [:account_id, :bucket, :expires_at], name: 'index_extra_balances_on_account_bucket_expiry'
    add_index :account_extra_balances, :external_reference, unique: true
    add_check_constraint :account_extra_balances, 'units_total > 0 AND units_remaining >= 0 AND units_remaining <= units_total',
                         name: 'extra_balance_units_valid'

    add_column :ai_usage_reservations, :plan_units, :integer
    add_column :ai_usage_reservations, :extra_allocations, :jsonb, default: {}, null: false
    add_column :ai_usage_events, :extra_units, :integer, default: 0, null: false
    add_column :plans, :addon_inbox_price, :decimal, precision: 10, scale: 2, default: 12, null: false
    add_column :plans, :addon_storage_100mb_price, :decimal, precision: 10, scale: 2, default: 1, null: false
    add_column :plans, :addon_storage_250mb_price, :decimal, precision: 10, scale: 2, default: 2, null: false
  end
end
