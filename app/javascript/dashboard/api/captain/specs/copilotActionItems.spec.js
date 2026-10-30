import copilotActionItems from '../copilotActionItems';

describe('copilotActionItems API', () => {
  let originalAxios;

  beforeEach(() => {
    originalAxios = window.axios;
    window.axios = {
      get: vi.fn(),
      post: vi.fn(),
      patch: vi.fn(),
    };
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('sends the thread id when updating an item', () => {
    copilotActionItems.update(7, { label_name: 'Urgente' }, 15);

    expect(window.axios.patch).toHaveBeenCalledWith(
      expect.stringMatching(/copilot_action_items\/7$/),
      { payload: { label_name: 'Urgente' } },
      { params: { copilot_thread_id: 15 } }
    );
  });

  it('sends the thread id when approving and rejecting', () => {
    copilotActionItems.approve(7, 15);
    copilotActionItems.reject(8, 15);

    expect(window.axios.post).toHaveBeenNthCalledWith(
      1,
      expect.stringMatching(/copilot_action_items\/7\/approve$/),
      null,
      { params: { copilot_thread_id: 15 } }
    );
    expect(window.axios.post).toHaveBeenNthCalledWith(
      2,
      expect.stringMatching(/copilot_action_items\/8\/reject$/),
      null,
      { params: { copilot_thread_id: 15 } }
    );
  });
});
