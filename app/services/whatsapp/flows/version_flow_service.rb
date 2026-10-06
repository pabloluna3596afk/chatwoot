# A flow already published in Meta cannot be edited. Changing it creates a NEW Meta flow that starts as a clone of the
# published one (Meta's clone_flow_id), gets the new Flow JSON, is published, and then the old one is deprecated (it stays
# usable by messages already sent, but no new ones can use it). The same publication row now points at the new Meta flow
# and remembers the old one in old_meta_flow_id.
#
# If anything fails before the new flow is live, the half-made draft is deleted in Meta and the publication keeps
# pointing at the flow that is still published, with the errors attached.
class Whatsapp::Flows::VersionFlowService
  def initialize(flow, channel, publication)
    @flow = flow
    @publication = publication
    @client = Whatsapp::Flows::MetaClient.new(channel)
  end

  def perform
    return failure('The flow is not published in Meta') unless @publication.published_in_meta?

    old_id = @publication.meta_flow_id
    @new_id = @publication.draft_meta_flow_id.presence || create_clone(old_id)
    errors = @client.upload_flow_json(@new_id, @flow.flow_json)
    return abandon_new_flow(errors) if errors.any?

    @client.publish(@new_id)
    live = @client.fetch_flow(@new_id)
    deprecate(old_id)
    record(old_id, live)
  rescue Whatsapp::Flows::MetaClient::Error => e
    discard_new_flow
    @publication.update!(validation_errors: e.to_publication_errors)
    failure(e.message, retryable: e.retryable?)
  end

  private

  # A draft clone left by "Probar" is reused (and is kept, with its errors, if this publish fails); otherwise a new one
  # is made, and only that one is deleted when this run fails.
  def create_clone(old_id)
    @created = true
    @client.create_flow(name: @flow.name, categories: @flow.categories.presence || ['OTHER'], clone_flow_id: old_id)
  end

  def deprecate(old_id)
    @client.deprecate(old_id)
  rescue Whatsapp::Flows::MetaClient::Error => e
    Rails.logger.warn("[WHATSAPP FLOWS] could not deprecate the old flow #{old_id}: #{e.message}")
  end

  def record(old_id, live)
    status = live['status'].to_s.downcase
    @publication.update!(meta_flow_id: @new_id, old_meta_flow_id: old_id, draft_meta_flow_id: nil,
                         validation_errors: Array(live['validation_errors']),
                         status: WhatsappFlowPublication::VALID_STATUSES.include?(status) ? status : 'published',
                         published_version: @publication.published_version.to_i + 1, published_at: Time.current)
    { success: true, status: @publication.status, meta_flow_id: @new_id, old_meta_flow_id: old_id, publication: @publication,
      error: nil, retryable: false }
  end

  def abandon_new_flow(errors)
    discard_new_flow
    @publication.update!(validation_errors: errors)
    failure('Meta found errors in the new version', retryable: false)
  end

  def discard_new_flow
    @client.delete_flow(@new_id) if @created && @new_id.present?
  rescue Whatsapp::Flows::MetaClient::Error => e
    Rails.logger.warn("[WHATSAPP FLOWS] could not delete the unfinished flow #{@new_id}: #{e.message}")
  end

  def failure(message, retryable: false)
    { success: false, status: @publication.status, meta_flow_id: @publication.meta_flow_id, publication: @publication,
      error: message, retryable: retryable }
  end
end
