class AddUnitsToAiUsageReservations < ActiveRecord::Migration[7.0]
  def change
    add_column :ai_usage_reservations, :units, :integer, default: 1, null: false
  end
end
