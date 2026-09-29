module Internal
  class CloseExpiredUsagePeriodsJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      # Find all open periods that have expired (period_end < now)
      expired_periods = AccountPlanUsage.where(closed_at: nil)
                                        .where('period_end < ?', Time.current)

      # Close each expired period by setting closed_at to now
      # We use update_all for efficiency, but we need to be careful about
      # potential race conditions with the lazy creation mechanism.
      # However, since we're only setting closed_at (not changing period_start/end),
      # and the lazy creation uses a unique index on (account_id, period_start),
      # this should be safe.
      closed_count = expired_periods.update_all(closed_at: Time.current)

      # Optional: Log how many periods were closed for monitoring
      Rails.logger.info("[CloseExpiredUsagePeriodsJob] Closed #{closed_count} expired usage periods") if closed_count.positive?
    end
  end
end