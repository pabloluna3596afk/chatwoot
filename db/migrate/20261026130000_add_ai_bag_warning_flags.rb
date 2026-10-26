class AddAiBagWarningFlags < ActiveRecord::Migration[7.2]
  def change
    thresholds = [80, 100].freeze
    %i[responses copilot internal].each do |bag|
      thresholds.each do |threshold|
        add_column :account_plan_usages, "warned_at_#{bag}_#{threshold}_percent", :boolean, default: false, null: false
      end
    end

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE account_plan_usages
          SET warned_at_responses_80_percent = warned_at_80_percent,
              warned_at_responses_100_percent = warned_at_100_percent
        SQL
      end
    end
  end
end
