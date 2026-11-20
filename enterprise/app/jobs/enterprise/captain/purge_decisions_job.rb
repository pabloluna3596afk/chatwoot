module Enterprise::Captain::PurgeDecisionsJob
  RETENTION = 90.days
  BATCH_SIZE = 1_000

  def perform
    Captain::Decision.where('occurred_at < ?', RETENTION.ago).in_batches(of: BATCH_SIZE, &:delete_all)
  end
end
