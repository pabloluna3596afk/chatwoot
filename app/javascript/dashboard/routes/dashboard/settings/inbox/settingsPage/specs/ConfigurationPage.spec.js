import { flushPromises, shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConfigurationPage from '../ConfigurationPage.vue';
import SmtpSettings from '../../SmtpSettings.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/useWhatsappEmbeddedSignup', () => ({
  useWhatsappEmbeddedSignup: () => ({
    runEmbeddedSignup: vi.fn(),
  }),
}));

const createTestStore = () =>
  createStore({
    getters: {
      'globalConfig/isOnChatwootCloud': () => true,
    },
  });

const mountComponent = (inbox, store = createTestStore()) =>
  shallowMount(ConfigurationPage, {
    props: { inbox },
    global: {
      plugins: [store],
      mocks: {
        $t: key => key,
      },
      stubs: {
        SettingsFieldSection: {
          template: '<section><slot /></section>',
        },
        NextButton: {
          template: '<button><slot /></button>',
        },
        Banner: { template: '<div><slot /></div>' },
        'woot-code': true,
        'woot-input': {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<input :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
        WhatsappBusinessManagementToken: true,
      },
    },
  });

describe('ConfigurationPage', () => {
  it.each([false, true])(
    'shows SMTP settings for email inboxes when IMAP is %s',
    imapEnabled => {
      const inbox = {
        channel_type: 'Channel::Email',
        imap_enabled: imapEnabled,
      };
      const wrapper = mountComponent(inbox);

      expect(wrapper.findComponent(SmtpSettings).exists()).toBe(true);
      expect(wrapper.findComponent(SmtpSettings).props('inbox')).toEqual(inbox);
    }
  );

  it('shows the WhatsApp reconfigure option for embedded signup inboxes without checking account feature flags', () => {
    const wrapper = mountComponent({
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      provider_config: {
        source: 'embedded_signup',
        webhook_verify_token: 'verify-token',
      },
    });

    expect(wrapper.vm.showWhatsAppReconfigure).toBe(true);
    expect(wrapper.text()).toContain(
      'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_RECONFIGURE_BUTTON'
    );
  });

  it('does not show the WhatsApp reconfigure option for manual WhatsApp inboxes', () => {
    const wrapper = mountComponent({
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      provider_config: {
        source: 'manual_setup_v2',
        webhook_verify_token: 'verify-token',
      },
    });

    expect(wrapper.vm.showWhatsAppReconfigure).toBe(false);
  });

  it('lets a legacy manual inbox save the secret without replacing its existing provider settings', async () => {
    const inbox = {
      id: 12,
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      provider_config: {
        api_key: 'existing-token',
        phone_number_id: '12345',
        business_account_id: '67890',
        webhook_verify_token: 'verify-token',
      },
    };
    const store = createTestStore();
    const dispatch = vi.spyOn(store, 'dispatch').mockResolvedValue({ id: 12 });
    const wrapper = mountComponent(inbox, store);
    const section = wrapper
      .findAll('section')
      .find(item =>
        item.attributes('label')?.endsWith('WHATSAPP_APP_SECRET_TITLE')
      );
    const secretInput = section.get('input');
    const save = section.get('button');

    expect(section.text()).toContain('WHATSAPP_APP_SECRET_MISSING');
    expect(secretInput.attributes('type')).toBe('password');
    expect(save.attributes('disabled')).toBeDefined();
    await save.trigger('click');
    expect(dispatch).not.toHaveBeenCalled();

    await secretInput.setValue('app-secret');
    expect(save.attributes('disabled')).toBeUndefined();
    await save.trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: 12,
      formData: false,
      channel: {
        provider_config: { ...inbox.provider_config, app_secret: 'app-secret' },
      },
    });
    expect(secretInput.element.value).toBe('');
    await wrapper.setProps({
      inbox: {
        ...inbox,
        provider_config: { ...inbox.provider_config, app_secret: 'app-secret' },
      },
    });
    expect(wrapper.text()).not.toContain('WHATSAPP_APP_SECRET_MISSING');
    expect(wrapper.text()).not.toContain('app-secret');
    wrapper.unmount();
  });
});
