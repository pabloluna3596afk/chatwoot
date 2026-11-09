class IncludeCustomerDataExportInPaidPlans < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL.squish
      UPDATE plans
      SET feature_keys = feature_keys || '["customer_data_export"]'::jsonb, updated_at = CURRENT_TIMESTAMP
      WHERE price_monthly > 0 AND is_default_trial = FALSE
        AND NOT feature_keys @> '["customer_data_export"]'::jsonb
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE plans
      SET feature_keys = feature_keys - 'customer_data_export', updated_at = CURRENT_TIMESTAMP
      WHERE price_monthly > 0 AND is_default_trial = FALSE
        AND feature_keys @> '["customer_data_export"]'::jsonb
    SQL
  end
end
