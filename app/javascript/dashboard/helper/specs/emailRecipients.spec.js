import { getRecipients } from '@chatwoot/utils';

describe('email reply recipients', () => {
  it('keeps incoming To recipients in CC without the inbox, forwarder or sender', () => {
    const recipients = getRecipients(
      {
        message_type: 0,
        content_attributes: {
          email: {
            from: ['sender@example.com'],
            to: [
              'inbox@example.com',
              'forward@example.com',
              'peer@example.com',
              'to-only@example.com',
            ],
            cc: ['peer@example.com', 'cc@example.com'],
          },
        },
      },
      'sender@example.com',
      'inbox@example.com',
      'forward@example.com'
    );
    expect(recipients.to).toEqual(['sender@example.com']);
    expect(recipients.cc).toEqual([
      'peer@example.com',
      'cc@example.com',
      'to-only@example.com',
    ]);
  });

  it('keeps outgoing recipients in To instead of moving them to CC', () => {
    const recipients = getRecipients(
      {
        message_type: 1,
        content_attributes: {
          to_emails: ['sender@example.com', 'peer@example.com'],
          cc_emails: ['cc@example.com'],
        },
      },
      'sender@example.com',
      'inbox@example.com'
    );
    expect(recipients.to).toEqual(['sender@example.com', 'peer@example.com']);
    expect(recipients.cc).toEqual(['cc@example.com']);
  });
});
