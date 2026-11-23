class Calendar::EventVisibility
  OCCUPANCY_KEYS = [:id, :start, :end, :all_day, :connection_id, :calendar_id, :verified, :deleted].freeze

  def initialize(account:, user:)
    @user = user
    @context = { user: user, account: account,
                 account_user: user.is_a?(User) ? account.account_users.find_by!(user_id: user.id) : nil }
  end

  def call(payload, record)
    return payload if readable?(record)

    payload.slice(*OCCUPANCY_KEYS).merge(summary: I18n.t('integration_apps.calendars.busy'))
  end

  private

  def readable?(record)
    return true unless @user.is_a?(User)
    return true if record&.conversation.blank?

    Pundit.policy!(@context, record.conversation).show?
  end
end
