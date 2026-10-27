class AddLimitsToPlans < ActiveRecord::Migration[7.2]
  def change
    add_column :plans, :limits, :jsonb, default: {}, null: false
  end
end
