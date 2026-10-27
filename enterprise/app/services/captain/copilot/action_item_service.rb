class Captain::Copilot::ActionItemService
  EXPIRATION = 24.hours
  MAX_PENDING_PER_THREAD = 5
  MAX_PROPOSALS_PER_TURN = 3

  class ExpiredError < StandardError; end

  def initialize(thread:, user:)
    @thread = thread
    @user = user
    @account = thread.account
  end

  def propose(action_name:, target_type:, target_id:, payload:, turn_count:)
    raise ArgumentError, 'At most three proposals are allowed per turn' if turn_count > MAX_PROPOSALS_PER_TURN

    @thread.with_lock do
      raise ArgumentError, 'At most five proposals may be pending in this thread' if pending_limit_reached?

      action_class = Captain::Copilot::ActionRegistry.fetch(action_name)
      action = action_class.new(account: @account, user: @user, target_type: target_type, target_id: target_id, payload: payload)
      action.validate
      item = @thread.copilot_action_items.create!(
        copilot_message: @thread.copilot_messages.user.order(id: :desc).first,
        action: action_name,
        target_type: target_type,
        target_id: target_id,
        payload: payload,
        payload_hash: payload_hash(payload),
        idempotency_key: SecureRandom.uuid,
        expires_at: EXPIRATION.from_now
      )
      item.record_event!('proposed')
      item
    end
  end

  def update(item:, payload:)
    item.with_lock do
      raise ArgumentError, 'Only pending proposals can be edited' unless item.pending?

      if item.expires_at <= Time.current
        item.update!(status: 'expired', decided_at: Time.current)
        item.record_event!('expired')
        next
      end

      action = action_for(item, payload)
      action.validate
      item.update!(payload: payload, payload_hash: payload_hash(payload))
      item.record_event!('edited')
    end
    item
  end

  def decide(item:, decision:)
    item.with_lock do
      return item if %w[executed rejected expired].include?(item.status)

      if item.expires_at <= Time.current
        item.update!(status: 'expired', decided_at: Time.current)
        item.record_event!('expired')
        return item
      end
      raise ArgumentError, 'Only pending proposals can be decided' unless item.pending?

      if decision == 'reject'
        record_decision!(item, 'rejected')
        return item
      end

      execute_approved_action!(item)
    end
    item
  end

  private

  def pending_limit_reached?
    @thread.copilot_action_items.where(status: 'pending').count >= MAX_PENDING_PER_THREAD
  end

  def record_decision!(item, status)
    item.update!(status: status, decided_at: Time.current)
    item.record_event!(status)
  end

  def execute_approved_action!(item)
    action = action_for(item, item.payload)
    action.validate
    record_decision!(item, 'approved')
    result = ActiveRecord::Base.transaction(requires_new: true) { action.execute }
    item.update!(status: 'executed', result: result, executed_at: Time.current)
    item.record_event!('executed')
  rescue StandardError
    item.update!(status: 'failed', error: 'execution_failed', decided_at: Time.current)
    item.record_event!('failed', metadata: { code: 'execution_failed' })
  end

  def action_for(item, payload)
    Captain::Copilot::ActionRegistry.fetch(item.action).new(
      account: @account, user: @user, target_type: item.target_type, target_id: item.target_id, payload: payload
    )
  end

  def payload_hash(payload)
    canonical_payload = payload.deep_stringify_keys.sort.to_h
    Digest::SHA256.hexdigest(canonical_payload.to_json)
  end
end
