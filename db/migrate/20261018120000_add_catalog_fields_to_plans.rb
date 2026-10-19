class AddCatalogFieldsToPlans < ActiveRecord::Migration[7.2]
  def change
    add_column :plans, :coming_soon, :boolean, default: false, null: false
    add_column :plans, :feature_keys, :jsonb, default: [], null: false
  end
end
