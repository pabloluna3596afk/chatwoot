class AddIsRecommendedToPlans < ActiveRecord::Migration[7.0]
  def change
    add_column :plans, :is_recommended, :boolean, default: false, null: false
    add_index :plans, :is_recommended, unique: true, where: 'is_recommended', name: 'index_plans_on_is_recommended'
  end
end
