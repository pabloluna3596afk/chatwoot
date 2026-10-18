import { shallowMount } from '@vue/test-utils';
import GoogleOAuthButton from './Button.vue';

function getWrapper() {
  return shallowMount(GoogleOAuthButton, {
    global: { mocks: { $t: text => text } },
  });
}

describe('GoogleOAuthButton.vue', () => {
  beforeEach(() => {
    window.chatwootConfig = {
      googleOAuthClientId: 'clientId',
      googleOAuthCallbackUrl: 'http://localhost:3000/test-callback',
    };
  });

  afterEach(() => {
    window.chatwootConfig = {};
  });

  it('generates the correct Google Auth URL', () => {
    const wrapper = getWrapper();
    const googleAuthUrl = new URL(wrapper.get('a').attributes('href'));
    const params = googleAuthUrl.searchParams;
    expect(googleAuthUrl.origin).toBe('https://accounts.google.com');
    expect(googleAuthUrl.pathname).toBe('/o/oauth2/auth');
    expect(params.get('client_id')).toBe('clientId');
    expect(params.get('redirect_uri')).toBe(
      'http://localhost:3000/test-callback'
    );
    expect(params.get('response_type')).toBe('code');
    expect(params.get('scope')).toBe('email profile');
  });

  it('uses the login label by default', () => {
    expect(getWrapper().get('a').text()).toBe('LOGIN.OAUTH.GOOGLE_LOGIN');
  });

  it('accepts signup copy through its default slot', () => {
    const wrapper = shallowMount(GoogleOAuthButton, {
      slots: { default: 'Registrarte con Google' },
    });
    expect(wrapper.get('a').text()).toBe('Registrarte con Google');
  });
});
