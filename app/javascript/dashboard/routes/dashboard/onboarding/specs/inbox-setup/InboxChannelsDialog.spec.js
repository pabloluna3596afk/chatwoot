import { flushPromises, mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import InboxChannelsDialog from '../../inbox-setup/InboxChannelsDialog.vue';

const { connectWhatsapp, closeDialog } = vi.hoisted(() => ({
  connectWhatsapp: vi.fn(),
  closeDialog: vi.fn(),
}));

const { isOnChatwootCloud, isMetaInboxCreationDisabled, isTiktokEnabled } =
  vi.hoisted(() => ({
    isOnChatwootCloud: { value: false },
    isMetaInboxCreationDisabled: { value: false },
    isTiktokEnabled: { value: true },
  }));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter =>
    getter === 'globalConfig/isOnChatwootCloud'
      ? isOnChatwootCloud
      : { value: {} },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: feature =>
      feature !== 'channel_tiktok' || isTiktokEnabled.value,
    isOnChatwootCloud,
    isMetaInboxCreationDisabled,
  }),
}));
vi.mock('../../inbox-setup/useChannelConnect', () => ({
  useChannelConnect: () => ({
    connectViaOAuth: vi.fn(),
    connectWhatsapp,
  }),
}));

const mountDialog = (onboardingV2 = false) =>
  mount(InboxChannelsDialog, {
    props: { inboxes: [], onboardingV2 },
    global: {
      stubs: {
        Dialog: {
          template: '<div><slot /></div>',
          methods: { open() {}, close: closeDialog },
        },
        InboxFacebookForm: { template: '<div data-test="fb-form" />' },
        InboxChannelForm: { template: '<div data-test="channel-form" />' },
        ChannelIcon: true,
        Icon: true,
      },
    },
  });

describe('InboxChannelsDialog channel availability', () => {
  afterEach(() => {
    delete window.chatwootConfig;
    isOnChatwootCloud.value = false;
    isMetaInboxCreationDisabled.value = false;
    isTiktokEnabled.value = true;
  });

  it('opens the Facebook page picker when fbAppId is configured', async () => {
    window.chatwootConfig = { fbAppId: 'fb-app' };
    const wrapper = mountDialog();

    wrapper.vm.open('facebook');
    await nextTick();

    expect(wrapper.find('[data-test="fb-form"]').exists()).toBe(true);
  });

  it('closes WhatsApp signup and returns to the onboarding success screen', async () => {
    window.chatwootConfig = {
      whatsappAppId: 'app',
      whatsappConfigurationId: 'config',
    };
    connectWhatsapp.mockResolvedValue({ id: 7 });
    const wrapper = mountDialog(true);

    await wrapper
      .findAll('button')
      .find(button => button.text().includes('WHATSAPP.TITLE'))
      .trigger('click');
    await flushPromises();

    expect(connectWhatsapp).toHaveBeenCalledOnce();
    expect(closeDialog).toHaveBeenCalledOnce();
    expect(wrapper.emitted('connected')).toHaveLength(1);
  });

  it('keeps the dialog open when WhatsApp signup is cancelled', async () => {
    window.chatwootConfig = {
      whatsappAppId: 'app',
      whatsappConfigurationId: 'config',
    };
    connectWhatsapp.mockResolvedValue(null);
    const wrapper = mountDialog(true);

    await wrapper
      .findAll('button')
      .find(button => button.text().includes('WHATSAPP.TITLE'))
      .trigger('click');
    await flushPromises();

    expect(closeDialog).not.toHaveBeenCalled();
    expect(wrapper.emitted('connected')).toBeUndefined();
  });

  it('preserves the legacy dialog after WhatsApp signup', async () => {
    window.chatwootConfig = {
      whatsappAppId: 'app',
      whatsappConfigurationId: 'config',
    };
    connectWhatsapp.mockResolvedValue({ id: 7 });
    const wrapper = mountDialog();

    await wrapper
      .findAll('button')
      .find(button => button.text().includes('WHATSAPP.TITLE'))
      .trigger('click');
    await flushPromises();

    expect(closeDialog).not.toHaveBeenCalled();
    expect(wrapper.emitted('connected')).toBeUndefined();
  });

  it('shows the grid (not the picker) when fbAppId is missing', async () => {
    window.chatwootConfig = {};
    const wrapper = mountDialog();

    wrapper.vm.open('facebook');
    await nextTick();

    expect(wrapper.find('[data-test="fb-form"]').exists()).toBe(false);
    // The channel grid renders its cards instead.
    expect(wrapper.find('button').exists()).toBe(true);
  });

  it('shows the grid when Meta inbox creation is disabled on Chatwoot Cloud', async () => {
    isOnChatwootCloud.value = true;
    isMetaInboxCreationDisabled.value = true;
    window.chatwootConfig = { fbAppId: 'fb-app' };
    const wrapper = mountDialog();

    wrapper.vm.open('facebook');
    await nextTick();

    expect(wrapper.find('[data-test="fb-form"]').exists()).toBe(false);
    expect(wrapper.find('button').exists()).toBe(true);
  });

  it('shows TikTok as disabled when account access is disabled on Chatwoot Cloud', () => {
    isOnChatwootCloud.value = true;
    isTiktokEnabled.value = false;
    window.chatwootConfig = { tiktokAppId: 'tiktok-app' };
    const wrapper = mountDialog();

    const tiktokButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('TIKTOK.TITLE'));

    expect(tiktokButton.attributes('disabled')).toBeDefined();
    expect(tiktokButton.text()).toContain('SETUP_LATER');
  });
});
