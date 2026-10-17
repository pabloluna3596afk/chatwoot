class Onboarding::InboxMemberAssignmentService
  def initialize(account, account_user)
    @account_user = account_user
    @account = account
  end

  def perform
    return unless @account.custom_attributes['onboarding_version'] == 2
    return unless %w[inbox_setup assistant].include?(@account.custom_attributes['onboarding_step'])
    return unless @account_user&.administrator?

    @account.inboxes.find_each do |inbox|
      inbox.with_lock do
        inbox.add_members([@account_user.user_id]) unless inbox.inbox_members.exists?
      end
    end
  end
end
