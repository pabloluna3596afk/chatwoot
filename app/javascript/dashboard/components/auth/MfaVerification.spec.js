import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import axios from 'axios';
import { setAuthCredentials } from 'dashboard/store/utils/api';
import en from 'dashboard/i18n/locale/en/mfa.json';
import es from 'dashboard/i18n/locale/es/mfa.json';
import MfaVerification from './MfaVerification.vue';

vi.mock('axios', () => ({ default: { post: vi.fn() } }));
vi.mock('dashboard/store/utils/api', () => ({
  parseAPIErrorResponse: vi.fn(),
  setAuthCredentials: vi.fn(),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isOnChatwootCloud: { value: false } }),
}));

const mountChallenge = (locale = 'en') => {
  const i18n = createI18n({ legacy: false, locale, messages: { en, es } });
  config.global.plugins = [i18n];

  return mount(MfaVerification, {
    props: { mfaToken: 'device-token', verificationChannel: 'email' },
    global: {
      stubs: {
        Dialog: true,
        Icon: true,
        NextButton: {
          props: ['disabled', 'label'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
      },
    },
  });
};

const enterCode = inputs =>
  inputs.reduce(
    (previous, input, index) =>
      previous.then(() => input.setValue(String(index + 1))),
    Promise.resolve()
  );

const originalPlugins = config.global.plugins;

afterEach(() => {
  config.global.plugins = originalPlugins;
});

beforeEach(() => {
  vi.clearAllMocks();
  axios.post.mockResolvedValue({ status: 200, data: { data: { id: 1 } } });
});

describe('MfaVerification email challenge', () => {
  it.each(['en', 'es'])('renders the email challenge in %s', locale => {
    const wrapper = mountChallenge(locale);
    const messages = { en, es }[locale].MFA_VERIFICATION;

    expect(wrapper.get('h2').text()).toBe(messages.DEVICE_TITLE);
    expect(wrapper.text()).toContain(messages.DEVICE_DESCRIPTION);
    expect(wrapper.findAll('input[type="text"]')).toHaveLength(6);
    expect(wrapper.find('[data-testid="remember_device"]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain(messages.TRY_ANOTHER_METHOD);
    expect(wrapper.text()).not.toContain(messages.BACKUP_CODE);
    wrapper.unmount();
  });

  it('submits the email code and trust preference', async () => {
    const wrapper = mountChallenge();
    const digits = wrapper.findAll('input[type="text"]');

    await enterCode(digits);
    await flushPromises();

    expect(axios.post).toHaveBeenCalledWith('/auth/sign_in', {
      mfa_token: 'device-token',
      otp_code: '123456',
      remember_device: true,
    });
    expect(setAuthCredentials).toHaveBeenCalled();
    expect(wrapper.emitted('verified')).toBeTruthy();
    wrapper.unmount();
  });

  it('lets the user decline to trust the device', async () => {
    const wrapper = mountChallenge();
    await wrapper.get('[data-testid="remember_device"]').setValue(false);
    const digits = wrapper.findAll('input[type="text"]');

    await enterCode(digits);
    await flushPromises();

    expect(axios.post).toHaveBeenCalledWith('/auth/sign_in', {
      mfa_token: 'device-token',
      otp_code: '123456',
      remember_device: false,
    });
    wrapper.unmount();
  });

  it('transitions to enforced MFA enrollment when the server returns another 206', async () => {
    axios.post.mockResolvedValue({
      status: 206,
      data: { mfa_setup_required: true, mfa_setup_token: 'setup-token' },
    });
    const wrapper = mountChallenge();

    await enterCode(wrapper.findAll('input[type="text"]'));
    await flushPromises();

    expect(wrapper.emitted('setupRequired')).toEqual([
      [{ mfa_setup_required: true, mfa_setup_token: 'setup-token' }],
    ]);
    expect(setAuthCredentials).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
