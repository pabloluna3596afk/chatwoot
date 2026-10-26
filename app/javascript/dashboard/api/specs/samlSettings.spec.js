import SamlSettingsAPI from '../samlSettings';
import ApiClient from '../ApiClient';

describe('#SamlSettingsAPI', () => {
  it('exposes the metadata refresh action', () => {
    expect(SamlSettingsAPI).toBeInstanceOf(ApiClient);
    expect(SamlSettingsAPI).toHaveProperty('refresh');
  });

  it('posts to the account scoped metadata refresh endpoint', () => {
    const originalAxios = window.axios;
    window.axios = { post: vi.fn() };
    SamlSettingsAPI.refresh();
    expect(window.axios.post).toHaveBeenCalledWith(
      `${SamlSettingsAPI.url}/refresh_metadata`
    );
    window.axios = originalAxios;
  });
});
