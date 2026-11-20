import { createStore } from 'vuex';
import module from '../decisions';
import API from 'dashboard/api/captain/decisions';

vi.mock('dashboard/api/captain/decisions', () => ({
  default: { getForMessage: vi.fn() },
}));
const lookup = { accountId: 1, conversationId: 42, messageId: 7 };

describe('Captain decisions store', () => {
  let store;
  beforeEach(() => {
    store = createStore({
      modules: { captainDecisions: { ...module, state: { entries: {} } } },
    });
  });
  const entry = () => store.getters['captainDecisions/getEntry'](lookup);

  it.each([401, 403, 500, undefined])(
    'retains request errors for status %s and clears them on retry',
    async status => {
      API.getForMessage.mockRejectedValue({ response: { status } });
      await store.dispatch('captainDecisions/fetch', lookup);
      expect(entry()).toEqual({
        loading: false,
        error: [401, 403].includes(status) ? 'forbidden' : 'network',
      });
      API.getForMessage.mockResolvedValue({ data: [] });
      await store.dispatch('captainDecisions/fetch', lookup);
      expect(entry()).toEqual({ loading: false, error: null, decisions: [] });
    }
  );

  it('deduplicates requests in flight and refreshes afterwards on reopening', async () => {
    let resolve;
    API.getForMessage.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const pending = store.dispatch('captainDecisions/fetch', lookup);
    expect(entry().loading).toBe(true);
    await store.dispatch('captainDecisions/fetch', lookup);
    expect(API.getForMessage).toHaveBeenCalledTimes(1);
    resolve({ data: [{ reason_text: 'Reason' }] });
    await pending;
    expect(entry().decisions[0].reasonText).toBe('Reason');
    API.getForMessage.mockResolvedValue({ data: [] });
    await store.dispatch('captainDecisions/fetch', lookup);
    expect(API.getForMessage).toHaveBeenCalledTimes(2);
    expect(
      store.getters['captainDecisions/getEntry']({ ...lookup, accountId: 2 })
    ).toBeUndefined();
  });
});
