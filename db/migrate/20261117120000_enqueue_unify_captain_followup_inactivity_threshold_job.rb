class EnqueueUnifyCaptainFollowupInactivityThresholdJob < ActiveRecord::Migration[7.1]
  def up
    Migration::UnifyCaptainFollowupInactivityThresholdJob.perform_later if ChatwootApp.enterprise?
  end

  def down; end
end
