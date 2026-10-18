import authEn from 'dashboard/i18n/locale/en/auth.json';
import authEs from 'dashboard/i18n/locale/es/auth.json';
import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createMemoryHistory, createRouter } from 'vue-router';
import OnboardingAPI from 'dashboard/api/onboarding';
import accounts from 'dashboard/store/modules/accounts';
import en from 'dashboard/i18n/locale/en/onboarding.json';
import es from 'dashboard/i18n/locale/es/onboarding.json';
import AuthSplitLayout from 'v3/components/Auth/AuthSplitLayout.vue';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';
import { useAlert } from 'dashboard/composables';
import WhatsappGuideDialog from '../inbox-setup/WhatsappGuideDialog.vue';
import InboxSetup from '../InboxSetup.vue';

vi.mock('dashboard/api/onboarding');
vi.mock('dashboard/composables/useWhatsappEmbeddedSignup');
vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
  useAlert: vi.fn(),
}));

const openDialog = vi.fn();
const DialogStub = {
  setup(_, { expose }) {
    expose({ open: openDialog });
  },
  template: '<div />',
};
const credentials = {
  code: 'code',
  waba_id: 'waba',
  business_id: '',
  phone_number_id: '',
  is_coexistence: true,
};
const connected = {
  id: 7,
  name: 'Acme WhatsApp',
  phone_number: '+593999999999',
  channel_type: 'whatsapp',
};
const originalClipboard = Object.getOwnPropertyDescriptor(
  navigator,
  'clipboard'
);

describe('WhatsApp onboarding', () => {
  let wrapper;
  let account;
  let inboxes;
  let router;
  let i18n;
  let options;
  let runEmbeddedSignup;
  let createWhatsapp;
  let fetchInboxes;
  let setUser;
  let restricted;
  let cloud;
  let featureEnabled;

  beforeEach(async () => {
    vi.stubGlobal('innerWidth', 1280);
    vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue('Desktop');
    window.chatwootConfig = {
      whatsappAppId: 'app',
      whatsappConfigurationId: 'config',
    };
    account = reactive({
      id: 1,
      custom_attributes: {
        onboarding_version: 2,
        onboarding_step: 'inbox_setup',
      },
    });
    inboxes = reactive([]);
    restricted = false;
    cloud = false;
    featureEnabled = true;
    runEmbeddedSignup = vi.fn().mockResolvedValue(credentials);
    useWhatsappEmbeddedSignup.mockReturnValue({ runEmbeddedSignup });
    createWhatsapp = vi.fn().mockResolvedValue(connected);
    fetchInboxes = vi.fn();
    setUser = vi.fn();
    const store = createStore({
      getters: {
        'accounts/getAccount': () => () => account,
        'accounts/isFeatureEnabledonAccount': () => () => featureEnabled,
        'globalConfig/get': () => ({
          installationName: 'ChatHub',
          logo: '/logo.svg',
        }),
        'globalConfig/isOnChatwootCloud': () => cloud,
        'globalConfig/isMetaInboxCreationDisabled': () => restricted,
        'inboxes/getInboxes': () => inboxes,
      },
      actions: {
        'accounts/finishOnboarding': accounts.actions.finishOnboarding,
        'inboxes/createWhatsAppEmbeddedSignup': (_, params) =>
          createWhatsapp(params),
        'inboxes/get': () => fetchInboxes(),
        setUser,
      },
      mutations: {
        SET_ACCOUNT_UI_FLAG: vi.fn(),
        EDIT_ACCOUNT: (_, updated) => Object.assign(account, updated),
      },
    });
    router = createRouter({
      history: createMemoryHistory(),
      routes: ['onboarding_inbox_setup', 'onboarding_assistant', 'home'].map(
        name => ({
          path: `/accounts/:accountId/${name}`,
          name,
          component: { template: '<div />' },
        })
      ),
    });
    await router.push({
      name: 'onboarding_inbox_setup',
      params: { accountId: 1 },
    });
    i18n = createI18n({
      legacy: false,
      locale: 'es',
      messages: { en: { ...en, ...authEn }, es: { ...es, ...authEs } },
    });
    options = {
      global: {
        plugins: [store, router, i18n],
        stubs: {
          InboxChannelsDialog: DialogStub,
          LegacyInboxSetup: { template: '<div data-testid="legacy" />' },
        },
      },
    };
    OnboardingAPI.update.mockResolvedValue({
      data: { id: 1, custom_attributes: { onboarding_version: 2 } },
    });
  });

  afterEach(() => {
    wrapper?.unmount();
    delete window.chatwootConfig;
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    if (originalClipboard)
      Object.defineProperty(navigator, 'clipboard', originalClipboard);
    else delete navigator.clipboard;
  });

  it.each(['en', 'es'])(
    'shows the three trust points in %s without the provider claim by default',
    lang => {
      i18n.global.locale.value = lang;
      wrapper = mount(InboxSetup, options);
      const strings = { en, es }[lang].ONBOARDING_WHATSAPP;
      const trust = wrapper.get('[data-testid="whatsapp-trust"]');
      expect(trust.element.tagName).toBe('DETAILS');
      expect(trust.element.open).toBe(false);
      expect(trust.get('summary').text()).toBe(strings.TRUST.SAFETY);
      expect(trust.get('h2').text()).toBe(strings.TRUST.TITLE);
      expect(trust.findAll('li').map(item => item.text())).toEqual([
        strings.TRUST.APP,
        strings.TRUST.OFFICIAL,
        strings.TRUST.BENEFITS,
      ]);
      expect(trust.text()).not.toContain(strings.TRUST.PROVIDER);
      expect(wrapper.get('[data-testid="connection-guide"]').text()).toBe(
        strings.GUIDE.OPEN
      );
      expect(
        wrapper
          .get('[data-testid="connection-guide"] .i-lucide-book-open')
          .exists()
      ).toBe(true);
      expect(wrapper.findComponent(WhatsappGuideDialog).exists()).toBe(false);
    }
  );

  it.each([false, 'false', 'true', true])(
    'only shows the provider claim for a boolean true flag: %s',
    flag => {
      window.chatwootConfig.metaTechProviderLive = flag;
      wrapper = mount(InboxSetup, options);
      expect(
        wrapper
          .get('[data-testid="whatsapp-trust"]')
          .text()
          .includes(es.ONBOARDING_WHATSAPP.TRUST.PROVIDER)
      ).toBe(flag === true);
    }
  );

  it.each(
    ['initial', 'unavailable', 'connected'].flatMap(screen =>
      [undefined, false, 'false', 'true', true].map(flag => [screen, flag])
    )
  )(
    'shows the header badge in %s only for boolean true: %s',
    (screen, flag) => {
      window.chatwootConfig.metaTechProviderLive = flag;
      if (screen === 'unavailable') delete window.chatwootConfig.whatsappAppId;
      if (screen === 'connected') inboxes.push(connected);
      wrapper = mount(InboxSetup, options);

      const header = wrapper.get('header');
      const badge = header.find('[data-testid="header-meta-tech-provider"]');
      expect(badge.exists()).toBe(flag === true);
      const logo = header.get('[data-testid="header-whatsapp-business"]');
      expect(logo.attributes('alt')).toBe('WhatsApp Business');
      expect(logo.attributes('src')).toContain('whatsapp_business_temporal');
      const row = logo.element.parentElement;
      expect(row.classList).toContain('justify-between');
      expect(row.classList).toContain('items-center');
      if (flag !== true) return;

      expect(badge.element.parentElement).toBe(row);
      expect(row.firstElementChild).toBe(logo.element);
      expect(logo.classes()).toEqual(
        expect.arrayContaining(['h-7', 'sm:h-10', 'min-w-0', 'object-contain'])
      );
      expect(logo.classes()).not.toContain('shrink-0');
      expect(badge.classes()).toEqual(
        expect.arrayContaining(['shrink-0', 'p-3', 'sm:p-5'])
      );
      const images = badge.findAll('img');
      expect(images).toHaveLength(2);
      ['black', 'white'].forEach((color, index) => {
        expect(images[index].attributes('src')).toContain(
          `meta_tech_provider_${color}.svg`
        );
        expect(images[index].attributes('alt')).toBe('Meta Tech Provider');
        expect(images[index].classes()).toEqual(
          expect.arrayContaining([
            'h-auto',
            'w-20',
            'sm:w-28',
            ...(color === 'black' ? ['dark:hidden'] : ['hidden', 'dark:block']),
          ])
        );
      });
    }
  );

  it('loads the connection guide on demand and allows closing and reopening it', async () => {
    options.global.stubs.Dialog = {
      template: '<div><slot /></div>',
      methods: { open: vi.fn() },
    };
    wrapper = mount(InboxSetup, options);
    expect(wrapper.findComponent(WhatsappGuideDialog).exists()).toBe(false);
    await wrapper.get('[data-testid="connection-guide"]').trigger('click');
    await vi.dynamicImportSettled();
    await flushPromises();
    expect(wrapper.getComponent(WhatsappGuideDialog).text()).toContain(
      es.ONBOARDING_WHATSAPP.GUIDE.STEPS.VERIFY
    );
    wrapper.getComponent(WhatsappGuideDialog).vm.$emit('close');
    await flushPromises();
    expect(wrapper.findComponent(WhatsappGuideDialog).exists()).toBe(false);
    await wrapper.get('[data-testid="connection-guide"]').trigger('click');
    await flushPromises();
    expect(wrapper.findComponent(WhatsappGuideDialog).exists()).toBe(true);
  });

  it('keeps the guide and expanded mobile content above a separate footer while loading', async () => {
    vi.stubGlobal('innerWidth', 360);
    window.chatwootConfig.metaTechProviderLive = true;
    fetchInboxes.mockReturnValue(new Promise(() => {}));
    wrapper = mount(InboxSetup, options);
    await flushPromises();
    const scroller = wrapper.get('[data-testid="onboarding-scroll-content"]');
    expect(scroller.get('[data-testid="connection-guide"]').exists()).toBe(
      true
    );
    expect(scroller.classes()).toContain('pb-4');
    const notice = scroller.get('[data-testid="mobile-notice"]');
    notice.element.open = true;
    expect(notice.get('[data-testid="copy-link"]').exists()).toBe(true);
    expect(scroller.element.nextElementSibling).toBe(
      wrapper.get('footer').element
    );
    const logo = wrapper.get('[data-testid="header-whatsapp-business"]');
    expect(
      logo.element.parentElement.querySelector('[role="status"]')
    ).toBeNull();
    expect(wrapper.get('header [role="status"]').text()).toBe(
      authEs.ONBOARDING_AUTH.LOADING
    );
  });

  it.each([
    [767, 'Desktop', true],
    [768, 'Desktop', false],
    [1280, 'Desktop', false],
    [1280, 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)', true],
    [1280, 'Mozilla/5.0 (Linux; Android 14)', true],
    [1280, 'Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)', true],
  ])(
    'detects mobile at width %s and user agent %s',
    (width, userAgent, visible) => {
      vi.stubGlobal('innerWidth', width);
      vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(userAgent);
      wrapper = mount(InboxSetup, options);
      expect(wrapper.find('[data-testid="mobile-notice"]').exists()).toBe(
        visible
      );
    }
  );

  it('updates the mobile notice when the viewport resizes', async () => {
    wrapper = mount(InboxSetup, options);
    await flushPromises();
    expect(wrapper.find('[data-testid="mobile-notice"]').exists()).toBe(false);
    vi.stubGlobal('innerWidth', 375);
    window.dispatchEvent(new Event('resize'));
    await flushPromises();
    expect(wrapper.find('[data-testid="mobile-notice"]').exists()).toBe(true);
    vi.stubGlobal('innerWidth', 1024);
    window.dispatchEvent(new Event('resize'));
    await flushPromises();
    expect(wrapper.find('[data-testid="mobile-notice"]').exists()).toBe(false);
  });

  it.each(['en', 'es'])(
    'translates the mobile note and emphasizes Enter code in %s',
    lang => {
      vi.stubGlobal('innerWidth', 375);
      i18n.global.locale.value = lang;
      wrapper = mount(InboxSetup, options);
      const strings = { en, es }[lang].ONBOARDING_WHATSAPP.MOBILE;
      const notice = wrapper.get('[data-testid="mobile-notice"]');
      expect(notice.get('p').text()).toBe(
        strings.NOTICE.replace('{code}', strings.ENTER_CODE)
      );
      expect(notice.get('strong').text()).toBe(strings.ENTER_CODE);
      expect(notice.get('button').text()).toBe(strings.COPY);
    }
  );

  it.each(['success', 'denied', 'unavailable'])(
    'copies the current URL and handles clipboard %s',
    async result => {
      vi.stubGlobal('innerWidth', 375);
      const writeText = vi.fn().mockResolvedValue(undefined);
      if (result === 'denied')
        writeText.mockRejectedValue(new Error('Permission denied'));
      Object.defineProperty(navigator, 'clipboard', {
        configurable: true,
        value: result === 'unavailable' ? undefined : { writeText },
      });
      wrapper = mount(InboxSetup, options);
      await wrapper.get('[data-testid="copy-link"]').trigger('click');
      await flushPromises();
      if (result !== 'unavailable')
        expect(writeText).toHaveBeenCalledExactlyOnceWith(window.location.href);
      expect(useAlert).toHaveBeenCalledExactlyOnceWith(
        es.ONBOARDING_WHATSAPP.MOBILE[
          result === 'success' ? 'COPIED' : 'COPY_ERROR'
        ]
      );
    }
  );

  it.each(['loading', 'cancelled', 'error', 'connected', 'unavailable'])(
    'hides initial help in state %s',
    async nextState => {
      vi.stubGlobal('innerWidth', 375);
      if (nextState === 'loading')
        runEmbeddedSignup.mockReturnValue(new Promise(() => {}));
      if (nextState === 'cancelled') runEmbeddedSignup.mockResolvedValue(null);
      if (nextState === 'error')
        runEmbeddedSignup.mockRejectedValue(new Error('Internal error'));
      if (nextState === 'unavailable')
        delete window.chatwootConfig.whatsappAppId;
      wrapper = mount(InboxSetup, options);
      if (nextState !== 'unavailable') {
        await wrapper.get('[data-testid="primary"]').trigger('click');
        await flushPromises();
      }
      expect(wrapper.find('[data-testid="whatsapp-trust"]').exists()).toBe(
        false
      );
      expect(wrapper.find('[data-testid="mobile-notice"]').exists()).toBe(
        false
      );
    }
  );

  it.each(['en', 'es'])(
    'renders the shared layout, step 3 of 5 and idle action in %s',
    async lang => {
      i18n.global.locale.value = lang;
      wrapper = mount(InboxSetup, options);
      await flushPromises();
      const strings = { en, es }[lang];
      expect(wrapper.getComponent(AuthSplitLayout).props('scrollable')).toBe(
        true
      );
      expect(wrapper.get('h1').text()).toBe(strings.ONBOARDING_WHATSAPP.TITLE);
      expect(wrapper.text()).toContain(strings.ONBOARDING_WHATSAPP.SUBTITLE);
      expect(
        wrapper
          .get('[data-testid="connection-steps"]')
          .findAll('li')
          .map(step => step.text())
      ).toEqual(Object.values(strings.ONBOARDING_WHATSAPP.STEPS));
      expect(
        wrapper.get('[role="progressbar"]').attributes('aria-valuenow')
      ).toBe('3');
      expect(
        wrapper.get('[role="progressbar"]').attributes('aria-valuemax')
      ).toBe('5');
      expect(wrapper.get('[data-testid="primary"]').text()).toBe(
        strings.ONBOARDING_WHATSAPP.CONNECT
      );
      expect(fetchInboxes).toHaveBeenCalledOnce();
      expect(runEmbeddedSignup).not.toHaveBeenCalled();
    }
  );

  it('shows loading, prevents duplicate signup and leaves skip available', async () => {
    runEmbeddedSignup.mockReturnValue(new Promise(() => {}));
    wrapper = mount(InboxSetup, options);
    await wrapper.get('[data-testid="primary"]').trigger('click');
    expect(wrapper.get('[data-testid="primary"]').attributes('aria-busy')).toBe(
      'true'
    );
    expect(wrapper.get('[data-testid="primary"]').element.disabled).toBe(true);
    expect(wrapper.get('[role="status"]').text()).toBe(
      es.ONBOARDING_WHATSAPP.CONNECTING
    );
    await wrapper.get('[data-testid="primary"]').trigger('click');
    expect(runEmbeddedSignup).toHaveBeenCalledOnce();
    expect(wrapper.get('[data-testid="skip"]').element.disabled).toBe(false);
  });

  it('exchanges coexistence credentials and displays the API name and number before continuing', async () => {
    wrapper = mount(InboxSetup, options);
    const push = vi.spyOn(router, 'push');
    const replace = vi.spyOn(router, 'replace');
    await wrapper.get('[data-testid="primary"]').trigger('click');
    await flushPromises();
    expect(createWhatsapp).toHaveBeenCalledExactlyOnceWith(credentials);
    expect(wrapper.get('[role="status"]').text()).toContain(
      es.ONBOARDING_WHATSAPP.CONNECTED
    );
    expect(wrapper.text()).toContain(connected.name);
    expect(wrapper.text()).toContain(connected.phone_number);
    expect(
      wrapper.get('.i-lucide-circle-check').element.parentElement.classList
    ).toContain('bg-n-teal-3');
    expect(wrapper.find('[data-testid="connection-steps"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain(es.ONBOARDING_WHATSAPP.AGENT_ASSIGNED);
    expect(wrapper.get('[data-testid="primary"]').text()).toBe(
      es.ONBOARDING_WHATSAPP.CONTINUE
    );
    expect(wrapper.findAll('button.bg-n-slate-12')).toHaveLength(1);
    expect(
      wrapper.get('[data-testid="other-channel"]').classes()
    ).not.toContain('border');
    expect(router.currentRoute.value.name).toBe('onboarding_inbox_setup');
    expect(push).not.toHaveBeenCalled();
    expect(replace).not.toHaveBeenCalled();
    expect(OnboardingAPI.update).not.toHaveBeenCalled();
    await wrapper.get('[data-testid="primary"]').trigger('click');
    await flushPromises();
    expect(OnboardingAPI.update).toHaveBeenCalledExactlyOnceWith({
      onboarding_step: 'inbox_setup',
      inbox_setup_result: 'whatsapp_connected',
    });
    expect(setUser).toHaveBeenCalledOnce();
    expect(router.currentRoute.value.name).toBe('onboarding_assistant');
  });

  it('shows cancellation separately and allows another attempt', async () => {
    runEmbeddedSignup.mockResolvedValueOnce(null);
    wrapper = mount(InboxSetup, options);
    await wrapper.get('[data-testid="primary"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="status"]').text()).toBe(
      es.ONBOARDING_WHATSAPP.CANCELLED
    );
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(createWhatsapp).not.toHaveBeenCalled();
    await wrapper.get('[data-testid="primary"]').trigger('click');
    await flushPromises();
    expect(createWhatsapp).toHaveBeenCalledOnce();
  });

  it.each(['sdk', 'api'])(
    'shows a translated %s error and allows retry without raw messages',
    async source => {
      const error = new Error('Internal secret SQL error');
      if (source === 'sdk') runEmbeddedSignup.mockRejectedValueOnce(error);
      else createWhatsapp.mockRejectedValueOnce(error);
      wrapper = mount(InboxSetup, options);
      await wrapper.get('[data-testid="primary"]').trigger('click');
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).toBe(
        es.ONBOARDING_WHATSAPP.ERROR
      );
      expect(wrapper.text()).not.toContain(error.message);
      expect(wrapper.get('[data-testid="primary"]').text()).toBe(
        es.ONBOARDING_WHATSAPP.RETRY
      );
      await wrapper.get('[data-testid="primary"]').trigger('click');
      await flushPromises();
      expect(wrapper.text()).toContain(connected.phone_number);
    }
  );

  it('skips without connecting and records skipped through the real store action', async () => {
    wrapper = mount(InboxSetup, options);
    await wrapper.get('[data-testid="skip"]').trigger('click');
    await flushPromises();
    expect(OnboardingAPI.update).toHaveBeenCalledExactlyOnceWith({
      onboarding_step: 'inbox_setup',
      inbox_setup_result: 'skipped',
    });
    expect(runEmbeddedSignup).not.toHaveBeenCalled();
    expect(setUser).toHaveBeenCalledOnce();
    expect(router.currentRoute.value.name).toBe('onboarding_assistant');
  });

  it('opens the existing dialog and continues after another channel connects', async () => {
    wrapper = mount(InboxSetup, options);
    const push = vi.spyOn(router, 'push');
    const replace = vi.spyOn(router, 'replace');
    await wrapper.get('[data-testid="other-channel"]').trigger('click');
    expect(openDialog).toHaveBeenCalledOnce();
    inboxes.push({
      id: 8,
      name: 'Telegram',
      channel_type: 'Channel::Telegram',
    });
    wrapper.getComponent(DialogStub).vm.$emit('connected');
    await flushPromises();
    expect(wrapper.text()).toContain('Telegram');
    expect(fetchInboxes).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).toContain(es.ONBOARDING_WHATSAPP.AGENT_ASSIGNED);
    expect(router.currentRoute.value.name).toBe('onboarding_inbox_setup');
    expect(push).not.toHaveBeenCalled();
    expect(replace).not.toHaveBeenCalled();
    await wrapper.get('[data-testid="primary"]').trigger('click');
    await flushPromises();
    expect(OnboardingAPI.update).toHaveBeenCalledWith({
      onboarding_step: 'inbox_setup',
      inbox_setup_result: 'skipped',
    });
  });

  it.each([
    'whatsappAppId',
    'whatsappConfigurationId',
    'sentinel',
    'restriction',
    'cloud-feature',
  ])('offers other channel and skip when unavailable: %s', async reason => {
    if (reason === 'sentinel') window.chatwootConfig.whatsappAppId = 'none';
    else if (reason === 'restriction') restricted = true;
    else if (reason === 'cloud-feature') {
      cloud = true;
      featureEnabled = false;
    } else delete window.chatwootConfig[reason];
    wrapper = mount(InboxSetup, options);
    await flushPromises();
    expect(wrapper.get('[role="status"]').text()).toBe(
      es.ONBOARDING_WHATSAPP.UNAVAILABLE
    );
    expect(wrapper.find('[data-testid="primary"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="connection-steps"]').exists()).toBe(
      false
    );
    expect(wrapper.get('[role="status"]').find('.i-lucide-info').exists()).toBe(
      true
    );
    expect(wrapper.get('[role="status"]').classes()).toContain('bg-n-slate-3');
    expect(wrapper.get('[data-testid="other-channel"]').classes()).toEqual(
      expect.arrayContaining([
        'min-h-12',
        'rounded-xl',
        'border',
        'border-n-slate-9',
        'w-full',
      ])
    );
    expect(wrapper.get('[data-testid="skip"]').classes()).not.toContain(
      'border'
    );
    await wrapper.get('[data-testid="other-channel"]').trigger('click');
    expect(openDialog).toHaveBeenCalledOnce();
    await wrapper.get('[data-testid="skip"]').trigger('click');
    await flushPromises();
    expect(router.currentRoute.value.name).toBe('onboarding_assistant');
  });

  it('resumes a connection from the inbox API after reload', async () => {
    fetchInboxes.mockImplementationOnce(() =>
      inboxes.push({ ...connected, channel_type: 'Channel::Whatsapp' })
    );
    wrapper = mount(InboxSetup, options);
    await flushPromises();
    expect(wrapper.text()).toContain(connected.phone_number);
    expect(wrapper.get('[data-testid="primary"]').text()).toBe(
      es.ONBOARDING_WHATSAPP.CONTINUE
    );
    expect(runEmbeddedSignup).not.toHaveBeenCalled();
  });

  it.each(['en', 'es'])(
    'translates the unavailable note and footer, then offers Continue after another channel connects in %s',
    async lang => {
      i18n.global.locale.value = lang;
      delete window.chatwootConfig.whatsappAppId;
      wrapper = mount(InboxSetup, options);
      await flushPromises();
      const strings = { en, es }[lang].ONBOARDING_WHATSAPP;

      expect(wrapper.get('[role="status"]').text()).toBe(strings.UNAVAILABLE);
      expect(wrapper.get('[data-testid="other-channel"]').text()).toBe(
        strings.OTHER_CHANNEL
      );
      expect(wrapper.get('[data-testid="skip"]').text()).toBe(strings.SKIP);
      await wrapper.get('[data-testid="other-channel"]').trigger('click');
      expect(openDialog).toHaveBeenCalledOnce();

      inboxes.push({
        id: 8,
        name: 'Telegram',
        channel_type: 'Channel::Telegram',
      });
      wrapper.getComponent(DialogStub).vm.$emit('connected');
      await flushPromises();

      expect(wrapper.get('[role="status"]').text()).toContain(
        strings.OTHER_CONNECTED
      );
      expect(wrapper.find('.i-lucide-info').exists()).toBe(false);
      expect(wrapper.get('[data-testid="primary"]').text()).toBe(
        strings.CONTINUE
      );
      expect(
        wrapper.get('[data-testid="other-channel"]').classes()
      ).not.toContain('border');
    }
  );

  it.each(['en', 'es'])(
    'shows the agent assignment message in %s',
    async lang => {
      i18n.global.locale.value = lang;
      wrapper = mount(InboxSetup, options);
      await wrapper.get('[data-testid="primary"]').trigger('click');
      await flushPromises();

      expect(wrapper.get('[role="status"]').text()).toContain(
        { en, es }[lang].ONBOARDING_WHATSAPP.AGENT_ASSIGNED
      );
      expect(router.currentRoute.value.name).toBe('onboarding_inbox_setup');
    }
  );

  it('waits for the account after a reload before choosing the flow or fetching inboxes', async () => {
    delete account.id;
    account.custom_attributes = {};
    wrapper = mount(InboxSetup, options);
    expect(wrapper.find('[data-testid="legacy"]').exists()).toBe(false);
    expect(fetchInboxes).not.toHaveBeenCalled();

    Object.assign(account, {
      id: 1,
      custom_attributes: {
        onboarding_version: 2,
        onboarding_step: 'inbox_setup',
      },
    });
    await flushPromises();
    expect(fetchInboxes).toHaveBeenCalledOnce();
    expect(wrapper.get('h1').text()).toBe(es.ONBOARDING_WHATSAPP.TITLE);
  });

  it('keeps a successful connection on completion failure and permits retry', async () => {
    inboxes.push({ ...connected, channel_type: 'Channel::Whatsapp' });
    OnboardingAPI.update.mockRejectedValueOnce(new Error('internal'));
    wrapper = mount(InboxSetup, options);
    await wrapper.get('[data-testid="primary"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      es.ONBOARDING_WHATSAPP.COMPLETION_ERROR
    );
    expect(wrapper.text()).toContain(connected.phone_number);
    expect(router.currentRoute.value.name).toBe('onboarding_inbox_setup');
    await wrapper.get('[data-testid="primary"]').trigger('click');
    await flushPromises();
    expect(router.currentRoute.value.name).toBe('onboarding_assistant');
  });

  it('prevents duplicate completion requests', async () => {
    OnboardingAPI.update.mockReturnValue(new Promise(() => {}));
    wrapper = mount(InboxSetup, options);
    await wrapper.get('[data-testid="skip"]').trigger('click');
    await wrapper.get('[data-testid="skip"]').trigger('click');
    expect(OnboardingAPI.update).toHaveBeenCalledOnce();
  });

  it('keeps the legacy screen for accounts without a version', () => {
    delete account.custom_attributes.onboarding_version;
    wrapper = mount(InboxSetup, options);
    expect(wrapper.find('[data-testid="legacy"]').exists()).toBe(true);
    expect(wrapper.findComponent(AuthSplitLayout).exists()).toBe(false);
    expect(fetchInboxes).not.toHaveBeenCalled();
  });
});
