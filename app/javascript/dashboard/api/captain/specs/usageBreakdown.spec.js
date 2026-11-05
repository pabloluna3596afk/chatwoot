import usageBreakdown from '../usageBreakdown';

describe('captain usage breakdown API', () => {
  let originalAxios;

  beforeEach(() => {
    originalAxios = window.axios;
    window.axios = { get: vi.fn() };
    window.history.pushState({}, '', '/app/accounts/12/captain/overview');
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('requests the account scoped breakdown endpoint', () => {
    usageBreakdown.getUsageBreakdown();

    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/12/captain/usage_breakdown'
    );
  });
});
