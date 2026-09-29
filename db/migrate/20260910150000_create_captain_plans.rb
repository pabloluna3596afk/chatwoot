class CreateCaptainPlans < ActiveRecord::Migration[7.2]
  def change
    create_table :captain_plans do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :description

      t.integer :monthly_messages, null: false, default: 0
      t.integer :storage_mb, null: false, default: 100
      t.integer :max_bots, null: false, default: 1
      t.integer :max_human_agents, null: false, default: 3

      t.decimal :price_monthly, precision: 10, scale: 2, null: false, default: 0
      t.decimal :price_yearly, precision: 10, scale: 2, null: false, default: 0

      t.integer :trial_days, null: false, default: 0
      t.integer :trial_messages, null: false, default: 0

      t.decimal :addon_agent_price, precision: 10, scale: 2, null: false, default: 0
      t.decimal :addon_bot_price, precision: 10, scale: 2, null: false, default: 0
      t.decimal :credit_unit_price, precision: 10, scale: 4, null: false, default: 0

      t.boolean :is_active, null: false, default: true
      t.boolean :is_public, null: false, default: true
      t.integer :display_order, null: false, default: 0

      t.timestamps
    end

    add_index :captain_plans, :slug, unique: true
  end
end
