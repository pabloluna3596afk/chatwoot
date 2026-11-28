import { isMessageRenderable } from '../messageVisibility';

describe('isMessageRenderable', () => {
  it('is false for a message with nothing to show', () => {
    expect(isMessageRenderable({ content: '', contentAttributes: {} })).toBe(
      false
    );
    expect(isMessageRenderable(null)).toBe(false);
  });

  it.each([
    ['text', { content: 'Hola' }],
    ['attachments', { attachments: [{ id: 1 }] }],
    ['email', { contentType: 'incoming_email' }],
    ['integration', { contentType: 'integrations' }],
    ['failed', { status: 'failed' }],
    ['unsupported', { contentAttributes: { isUnsupported: true } }],
    ['flow response', { contentAttributes: { whatsappFlowResponse: {} } }],
    ['external error', { contentAttributes: { externalError: 'boom' } }],
  ])('is true for %s', (_, message) => {
    expect(isMessageRenderable(message)).toBe(true);
  });

  it('is true when the referral card is shown', () => {
    expect(isMessageRenderable({ content: '' }, true)).toBe(true);
  });
});
