class Calendar::TemplateDrafts::AutoLinker
  def initialize(account:, waba_id:)
    @account = account
    @waba_id = waba_id
  end

  def perform
    channel = @account.whatsapp_channels.where(provider: 'whatsapp_cloud')
                      .where("provider_config ->> 'business_account_id' = ?", @waba_id).order(:id).first
    return unless channel

    resources = @account.calendar_template_resources.includes(:whatsapp_template_draft)
                        .where(waba_id: @waba_id).where.not(whatsapp_template_draft_id: nil)
    resources.find_each { |resource| link_if_approved(resource, channel) }
  end

  private

  def link_if_approved(resource, channel)
    return if resource.status_linked?

    draft = resource.whatsapp_template_draft
    return unless draft && draft.archived_at.nil? && draft.waba_id == @waba_id

    submission = draft.submissions.where(waba_id: @waba_id, language: draft.language).order(revision: :desc).first
    return unless approved_submission?(submission)

    Calendar::TemplateDrafts::Linker.new(account: @account, function: resource.function, channel_id: channel.id)
                                    .perform(draft_id: draft.id, preserve_existing: true)
  rescue StandardError => e
    Rails.logger.error("Calendar template auto-link failed (function=#{resource.function}, error=#{e.class})")
  end

  def approved_submission?(submission)
    submission&.status == 'submitted' && submission.remote_status == 'APPROVED' && submission.remote_id.present?
  end
end
