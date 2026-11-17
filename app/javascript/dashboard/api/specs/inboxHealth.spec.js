import inboxHealthAPI from '../inboxHealth';

describe('InboxHealthAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = { get: vi.fn(() => Promise.resolve()) };

  beforeEach(() => {
    window.axios = axiosMock;
  });

  afterEach(() => {
    window.axios = originalAxios;
    vi.clearAllMocks();
  });

  it('requests message pricing for the inbox and month count', () => {
    inboxHealthAPI.getMessagePricing(17, { months: 3 });

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/inboxes/17/message_pricing',
      { params: { months: 3 } }
    );
  });
});
