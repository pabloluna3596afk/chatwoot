import VariablesAPI from '../variables';

describe('variables catalog API', () => {
  it('pins metadata requests to the requested account and surface', async () => {
    const get = vi.fn().mockResolvedValue({ data: {} });
    vi.stubGlobal('axios', { get });
    await VariablesAPI.catalog(31, 'automation');
    expect(get).toHaveBeenCalledWith('/api/v1/accounts/31/variables', {
      params: { surface: 'automation' },
    });
    vi.unstubAllGlobals();
  });
});
