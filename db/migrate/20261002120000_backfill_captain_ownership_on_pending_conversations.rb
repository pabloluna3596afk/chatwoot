# Captain "owns" a pending conversation through upstream's typed AI assignee. Conversations already pending in an
# inbox with a connected assistant were attended implicitly (pending + captain_inboxes), so they get the owner now.
class BackfillCaptainOwnershipOnPendingConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  BATCH_SIZE = 1000

  def up
    loop do
      updated = execute(<<~SQL.squish).cmd_tuples
        UPDATE conversations
        SET ai_assignee_type = 'Captain::Assistant', assignee_agent_bot_id = captain_inboxes.captain_assistant_id
        FROM captain_inboxes
        WHERE conversations.id IN (
          SELECT conversations.id
          FROM conversations
          INNER JOIN captain_inboxes ON captain_inboxes.inbox_id = conversations.inbox_id
          WHERE conversations.status = 2
            AND conversations.assignee_id IS NULL
            AND conversations.assignee_agent_bot_id IS NULL
          LIMIT #{BATCH_SIZE}
        )
        AND captain_inboxes.inbox_id = conversations.inbox_id
      SQL
      break if updated.zero?
    end
  end

  def down
    # The owner can't be told apart from one assigned later, so this stays in place on rollback.
  end
end
