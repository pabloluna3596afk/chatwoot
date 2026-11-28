import { flushPromises, shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import WhatsappChannelAPI from 'dashboard/api/channel/whatsappChannel';
import CloudWhatsapp from '../CloudWhatsapp.vue';
import WhatsappManualSetup from '../WhatsappManualSetup.vue';
import WhatsappManualMigrationDialog from '../../components/WhatsappManualMigrationDialog.vue';

vi.mock('dashboard/routes/index', () => ({
  default: { replace: vi.fn() },
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'new_inbox', params: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/channel/whatsappChannel', () => ({
  default: {
    previewManualSetup: vi.fn(),
    connectManualSetup: vi.fn(),
  },
}));

const button = (wrapper, key) =>
  wrapper.findAll('button').find(item => item.text().endsWith(key));
const input = (wrapper, key) =>
  wrapper
    .findAll('input')
    .find(item => item.attributes('placeholder')?.endsWith(key));

describe('WhatsApp app secret setup', () => {
  let wrapper;
  let store;
  let dispatch;

  beforeEach(() => {
    store = createStore({
      getters: {
        'inboxes/getUIFlags': () => ({ isCreating: false }),
        'globalConfig/get': () => ({}),
      },
    });
    dispatch = vi.spyOn(store, 'dispatch').mockResolvedValue({ id: 12 });
    HTMLElement.prototype.scrollIntoView = vi.fn();
  });

  afterEach(() => wrapper?.unmount());

  const mountComponent = (component, props = {}) =>
    shallowMount(component, {
      props,
      global: {
        plugins: [store],
        stubs: {
          Input: false,
          TextArea: false,
          Button: false,
          NextButton: false,
          Banner: { template: '<div><slot /></div>' },
          Dialog: {
            template: '<div><slot /><slot name="footer" /></div>',
          },
        },
      },
    });

  it('blocks Cloud creation without an app secret and submits it from a password field', async () => {
    wrapper = mountComponent(CloudWhatsapp);
    await input(wrapper, 'INBOX_NAME.PLACEHOLDER').setValue('Support');
    await input(wrapper, 'PHONE_NUMBER.PLACEHOLDER').setValue('+593999999999');
    await input(wrapper, 'PHONE_NUMBER_ID.PLACEHOLDER').setValue('12345');
    await input(wrapper, 'BUSINESS_ACCOUNT_ID.PLACEHOLDER').setValue('67890');
    await input(wrapper, 'API_KEY.PLACEHOLDER').setValue('access-token');

    await wrapper.get('form').trigger('submit');
    expect(dispatch).not.toHaveBeenCalled();

    const secretInput = input(wrapper, 'APP_SECRET.PLACEHOLDER');
    expect(secretInput.attributes('type')).toBe('password');
    await secretInput.setValue('app-secret');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/createChannel',
      expect.objectContaining({
        channel: expect.objectContaining({
          provider_config: expect.objectContaining({
            app_secret: 'app-secret',
          }),
        }),
      })
    );
    expect(wrapper.text()).not.toContain('app-secret');
  });

  it('requires the secret before verification and sends it when connecting manual setup', async () => {
    WhatsappChannelAPI.previewManualSetup.mockResolvedValue({
      data: {
        suggested_inbox_name: 'Support',
        display_phone_number: '+593999999999',
        phone_number_id: '12345',
        waba_id: '67890',
      },
    });
    WhatsappChannelAPI.connectManualSetup.mockResolvedValue({
      data: { id: 12 },
    });
    wrapper = mountComponent(WhatsappManualSetup);
    await button(wrapper, 'ACTIONS.APP_READY').trigger('click');
    await input(wrapper, 'DETAILS.PHONE_ID_PLACEHOLDER').setValue('12345');
    await input(wrapper, 'DETAILS.WABA_PLACEHOLDER').setValue('67890');
    await button(wrapper, 'ACTIONS.NEXT').trigger('click');
    await input(wrapper, 'DETAILS.TOKEN_PLACEHOLDER').setValue('access-token');

    await button(wrapper, 'ACTIONS.VERIFY_DETAILS').trigger('click');
    expect(WhatsappChannelAPI.previewManualSetup).not.toHaveBeenCalled();
    expect(WhatsappChannelAPI.connectManualSetup).not.toHaveBeenCalled();

    const secretInput = input(wrapper, 'DETAILS.APP_SECRET_PLACEHOLDER');
    expect(secretInput.attributes('type')).toBe('password');
    await secretInput.setValue(' app-secret ');
    await button(wrapper, 'ACTIONS.VERIFY_DETAILS').trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('app-secret');
    await button(wrapper, 'ACTIONS.CONNECT').trigger('click');
    await flushPromises();

    expect(WhatsappChannelAPI.connectManualSetup).toHaveBeenCalledWith({
      waba_id: '67890',
      phone_number_id: '12345',
      access_token: 'access-token',
      app_secret: 'app-secret',
      inbox_name: 'Support',
    });
  });

  it('requires the secret for migration and emits it without displaying it in review', async () => {
    wrapper = mountComponent(WhatsappManualMigrationDialog, {
      inbox: {
        name: 'Support',
        phone_number: '+593999999999',
        provider_config: {
          business_account_id: '67890',
          phone_number_id: '12345',
        },
      },
    });
    await button(wrapper, 'DIALOG.CONTINUE').trigger('click');
    await button(wrapper, 'DIALOG.CONTINUE').trigger('click');
    await wrapper.get('textarea').setValue('access-token');
    expect(
      button(wrapper, 'DIALOG.REVIEW_MIGRATION').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.emitted('reconnect')).toBeUndefined();

    const secretInput = input(wrapper, 'DIALOG.APP_SECRET_PLACEHOLDER');
    expect(secretInput.attributes('type')).toBe('password');
    await secretInput.setValue(' app-secret ');
    await button(wrapper, 'DIALOG.REVIEW_MIGRATION').trigger('click');
    expect(wrapper.text()).not.toContain('app-secret');
    await button(wrapper, 'DIALOG.RECONNECT').trigger('click');

    expect(wrapper.emitted('reconnect')).toEqual([
      [
        {
          wabaId: '67890',
          phoneNumberId: '12345',
          accessToken: 'access-token',
          appSecret: 'app-secret',
        },
      ],
    ]);
  });
});
