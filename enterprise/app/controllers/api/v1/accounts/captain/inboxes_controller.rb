class Api::V1::Accounts::Captain::InboxesController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(Captain::Assistant) }

  before_action :set_assistant
  def index
    @captain_inboxes = @assistant.captain_inboxes.includes(:inbox)
  end

  def create
    inbox = Current.account.inboxes.find(assistant_params[:inbox_id])
    @captain_inbox = @assistant.captain_inboxes.build(inbox: inbox)
    @captain_inbox.assign_attributes(audience_params)
    @captain_inbox.save!
  end

  def update
    @captain_inbox = @assistant.captain_inboxes.find_by!(inbox_id: permitted_params[:inbox_id])
    attributes = update_params
    if attributes.key?(:appointments_enabled)
      attributes[:appointments_enabled] = ActiveModel::Type::Boolean.new.cast(attributes[:appointments_enabled])
    end
    @captain_inbox.update!(attributes)
  end

  def destroy
    @captain_inbox = @assistant.captain_inboxes.find_by!(inbox_id: permitted_params[:inbox_id])
    @captain_inbox.destroy!
    head :no_content
  end

  private

  def set_assistant
    @assistant = account_assistants.find(permitted_params[:assistant_id])
  end

  def account_assistants
    @account_assistants ||= Current.account.captain_assistants
  end

  def permitted_params
    params.permit(:assistant_id, :id, :account_id, :inbox_id)
  end

  def assistant_params
    params.require(:inbox).permit(:inbox_id)
  end

  def update_params
    params.require(:inbox).permit(:appointments_enabled).merge(audience_params)
  end

  def audience_params
    input = params.require(:inbox)
    validate_audience_input(input)
    input.permit(:audience_mode, audience_rules: [
                   :contact_scope, { tree: audience_tree_params,
                                     phones: [:mode, { list: [] }], channel_ids: [:mode, { list: [] }],
                                     emails: [:mode, { list: [] }] }
                 ])
  end

  # Validate before strong params filters unknown keys or malformed shapes out of the request.
  def validate_audience_input(input)
    attributes = input.slice(:audience_mode, :audience_rules).to_unsafe_h
    candidate = CaptainInbox.new(captain_assistant: @assistant, **attributes.symbolize_keys)
    Captain::InboxAudienceValidator.new.validate(candidate)
    raise ActiveRecord::RecordInvalid, candidate if candidate.errors.any?
  end

  def audience_tree_params(depth = 1)
    attributes = [:attribute_key, :filter_operator, { values: [] }]
    return attributes if depth == Captain::AudienceMatcher::MAX_DEPTH

    attributes + [:operator, { conditions: audience_tree_params(depth + 1) }]
  end
end
