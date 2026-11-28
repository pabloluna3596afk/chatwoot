import { describe, it, beforeEach, afterEach, expect, vi } from 'vitest';
import ActionCableConnector from '../actionCable';

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    subscriptions: { create: () => ({}) },
    disconnect: vi.fn(),
  }),
}));

describe('Widget ActionCableConnector', () => {
  let app;
  let mockDispatch;
  let connector;

  beforeEach(() => {
    vi.useFakeTimers();
    mockDispatch = vi.fn();
    app = {
      $store: {
        dispatch: mockDispatch,
        getters: {
          getCurrentAccountId: 1,
          getCurrentUserID: 1,
        },
      },
    };
    connector = new ActionCableConnector(app, 'test-token');
    mockDispatch.mockClear();
  });

  afterEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  it('registers the conversation.status_changed event handler', () => {
    expect(connector.events['conversation.status_changed']).toBe(
      connector.onStatusChange
    );
  });

  it('re-fetches conversation attributes on reconnect so a status change missed while disconnected is reflected', () => {
    connector.onReconnect();

    expect(mockDispatch).toHaveBeenCalledWith(
      'conversation/syncLatestMessages'
    );
    expect(mockDispatch).toHaveBeenCalledWith(
      'conversationAttributes/getAttributes'
    );
  });

  it('updates conversation status from the reduced realtime payload', () => {
    const data = {
      id: 7,
      inbox_id: 2,
      contact_last_seen_at: 123,
      status: 'resolved',
    };
    connector.onStatusChange(data);

    expect(mockDispatch).toHaveBeenCalledWith('campaign/resetCampaign');
    expect(mockDispatch).toHaveBeenCalledWith(
      'conversationAttributes/update',
      data
    );
  });

  it('accepts a contact message whose sender contains only its type', async () => {
    app.$store.getters['conversationAttributes/getConversationParams'] = {
      id: 7,
    };
    mockDispatch.mockResolvedValue();
    const data = {
      id: 10,
      conversation_id: 7,
      content: 'Hello',
      sender: { type: 'contact' },
    };

    connector.onMessageCreated(data);

    expect(mockDispatch).toHaveBeenCalledWith(
      'conversation/addOrUpdateMessage',
      data
    );
  });
});
