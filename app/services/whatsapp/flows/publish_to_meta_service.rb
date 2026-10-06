# Sends a flow to Meta for ONE WhatsApp Cloud channel (its WABA): creates the Meta flow (or reuses the one already
# recorded), uploads the Flow JSON, and publishes it when Meta found nothing wrong. The result is kept in the
# flow's WhatsappFlowPublication for that WABA, which is what the dashboard shows.
#
# Idempotent: the publication row is unique per (flow, WABA) and locked while we work, and the Meta flow id is saved as
# soon as it exists, so a retry or a double click reuses the Meta flow instead of creating another one. A flow that is
# already published in Meta is never edited in place: a changed one goes through VersionFlowService.
#
# Never raises for Meta/definition problems: they are stored in the publication (validation_errors) and returned.
class Whatsapp::Flows::PublishToMetaService
  def initialize(flow, channel)
    @flow = flow
    @channel = channel
    @client = Whatsapp::Flows::MetaClient.new(channel)
  end

  def perform
    publication = find_publication
    publication.with_lock do
      return result(publication) if published_and_current?(publication)
      return Whatsapp::Flows::VersionFlowService.new(@flow, @channel, publication).perform if publication.published_in_meta?

      publish(publication)
    end
  end

  # What "Probar" sends, without publishing: returns [publication, meta_flow_id, mode].
  #  - a flow that is still a draft in Meta: that draft with the current Flow JSON, mode 'draft';
  #  - a published flow that has not changed: the published flow, mode 'published';
  #  - a published flow changed since: a DRAFT clone of it (kept in draft_meta_flow_id and reused until the next publish,
  #    which publishes that draft) with the current Flow JSON, mode 'draft'.
  # Meta's complaints are left in publication.validation_errors.
  def prepare_for_test
    publication = find_publication
    publication.with_lock do
      return [publication, publication.meta_flow_id, 'published'] if published_and_current?(publication)
      return [publication, upload_test_draft(publication), 'draft'] if publication.published_in_meta?

      upload_draft(publication)
      return [publication, publication.meta_flow_id, 'draft']
    end
  rescue Whatsapp::Flows::MetaClient::Error => e
    publication.update!(validation_errors: e.to_publication_errors)
    [publication, nil, 'draft']
  end

  private

  def find_publication
    attributes = { whatsapp_flow_id: @flow.id, waba_id: @client.waba_id }
    WhatsappFlowPublication.find_by(attributes) ||
      WhatsappFlowPublication.create!(attributes.merge(account_id: @flow.account_id, status: 'draft'))
  rescue ActiveRecord::RecordNotUnique
    WhatsappFlowPublication.find_by!(attributes)
  end

  def published_and_current?(publication)
    publication.published_in_meta? && publication.published_at.present? && @flow.updated_at <= publication.published_at
  end

  def publish(publication)
    upload_draft(publication)
    return result(publication) if publication.validation_errors?

    @client.publish(publication.meta_flow_id)
    live = @client.fetch_flow(publication.meta_flow_id)
    publication.update!(status: known_status(live['status']), validation_errors: Array(live['validation_errors']),
                        published_version: [publication.published_version, 1].max, published_at: Time.current)
    result(publication)
  rescue Whatsapp::Flows::MetaClient::Error => e
    publication.update!(validation_errors: e.to_publication_errors)
    result(publication, error: e)
  end

  # The definition must be valid before Meta sees it; then Meta's own checks run on the uploaded JSON.
  def upload_draft(publication)
    check = @flow.definition_check
    return publication.update!(validation_errors: definition_errors(check)) unless check.valid?

    publication.update!(meta_flow_id: @client.create_flow(name: @flow.name, categories: categories)) if publication.meta_flow_id.blank?
    publication.update!(validation_errors: @client.upload_flow_json(publication.meta_flow_id, @flow.flow_json))
  end

  def upload_test_draft(publication)
    check = @flow.definition_check
    unless check.valid?
      publication.update!(validation_errors: definition_errors(check))
      return nil
    end

    if publication.draft_meta_flow_id.blank?
      publication.update!(draft_meta_flow_id: @client.create_flow(name: @flow.name, categories: categories, clone_flow_id: publication.meta_flow_id))
    end
    errors = @client.upload_flow_json(publication.draft_meta_flow_id, @flow.flow_json)
    publication.update!(validation_errors: errors)
    errors.empty? ? publication.draft_meta_flow_id : nil
  end

  def definition_errors(check)
    check.errors.map { |error| { 'error' => error[:code], 'path' => error[:path], 'message' => error[:code].to_s.humanize } }
  end

  def categories
    @flow.categories.presence || ['OTHER']
  end

  def known_status(status)
    value = status.to_s.downcase
    WhatsappFlowPublication::VALID_STATUSES.include?(value) ? value : 'draft'
  end

  def result(publication, error: nil)
    { success: error.nil? && !publication.validation_errors?, status: publication.status, meta_flow_id: publication.meta_flow_id,
      publication: publication, error: error&.message, retryable: error&.retryable? || false }
  end
end
