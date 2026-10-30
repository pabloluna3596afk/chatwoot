class CreateAiUsageReservations < ActiveRecord::Migration[7.0]
  def change
    create_table :ai_usage_reservations do |t|
      t.references :account_plan_usage, null: false, foreign_key: true, index: true
      t.string :reservation_id, null: false
      t.string :bucket, null: false
      t.datetime :released_at

      t.timestamps
    end

    add_index :ai_usage_reservations, :reservation_id, unique: true
  end
end
