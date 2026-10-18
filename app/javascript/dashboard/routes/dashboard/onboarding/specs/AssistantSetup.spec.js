import authEn from 'dashboard/i18n/locale/en/auth.json';
import authEs from 'dashboard/i18n/locale/es/auth.json';
import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createMemoryHistory, createRouter } from 'vue-router';
import OnboardingAPI from 'dashboard/api/onboarding';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import CaptainInboxes from 'dashboard/api/captain/inboxes';
import AccountAPI from 'dashboard/api/account';
import accounts from 'dashboard/store/modules/accounts';
import en from 'dashboard/i18n/locale/en/onboarding.json';
import es from 'dashboard/i18n/locale/es/onboarding.json';
import integrationsEn from 'dashboard/i18n/locale/en/integrations.json';
import integrationsEs from 'dashboard/i18n/locale/es/integrations.json';
import AssistantSetup from '../AssistantSetup.vue';

vi.mock('dashboard/api/onboarding');
vi.mock('dashboard/api/captain/assistant');
vi.mock('dashboard/api/captain/inboxes');
vi.mock('dashboard/api/account');

const draft = {
  id: 42,
  name: 'Asistente de Acme',
  config: {
    onboarding: { goal: 'Explica mis servicios', tone: 'professional' },
  },
  paused_reason: null,
  inbox_ids: [],
};

describe('Assistant onboarding', () => {
  let wrapper;
  let account;
  let inboxes;
  let serverAssistant;
  let router;
  let options;
  let i18n;
  let setUser;
  let getInboxes;

  beforeEach(async () => {
    CaptainAssistant.playgroundUsage.mockResolvedValue({
      data: { test_usage: null },
    });
    account = reactive({
      id: 1,
      name: 'Acme',
      custom_attributes: {
        onboarding_version: 2,
        onboarding_step: 'assistant',
        business_type: 'appointments',
      },
    });
    inboxes = reactive([]);
    serverAssistant = null;
    setUser = vi.fn();
    getInboxes = vi.fn().mockResolvedValue(true);
    AccountAPI.get.mockImplementation(async () => ({ data: account }));
    OnboardingAPI.getAssistant.mockImplementation(async () => ({
      data: { assistant: structuredClone(serverAssistant) },
    }));
    OnboardingAPI.saveAssistant.mockImplementation(async () => {
      serverAssistant = structuredClone(draft);
      return { data: { assistant: serverAssistant } };
    });
    OnboardingAPI.update.mockResolvedValue({
      data: {
        id: 1,
        custom_attributes: {
          onboarding_version: 2,
          onboarding_assistant_id: 42,
        },
      },
    });
    CaptainAssistant.playground.mockResolvedValue({
      data: {
        response: 'Hola, ¿en qué puedo ayudarte?',
        agent_name: 'Assistant',
      },
    });
    CaptainInboxes.create.mockResolvedValue({ data: {} });
    const store = createStore({
      getters: {
        'accounts/getAccount': () => () => account,
        'inboxes/getInboxes': () => inboxes,
      },
      actions: {
        'accounts/get': accounts.actions.get,
        'inboxes/get': getInboxes,
        'accounts/finishOnboarding': accounts.actions.finishOnboarding,
        setUser,
      },
      mutations: {
        SET_ACCOUNT_UI_FLAG: vi.fn(),
        ADD_ACCOUNT: (_, updated) => Object.assign(account, updated),
        EDIT_ACCOUNT: (_, updated) => Object.assign(account, updated),
      },
    });
    router = createRouter({
      history: createMemoryHistory(),
      routes: ['onboarding_assistant', 'onboarding_inbox_setup', 'home'].map(
        name => ({
          path: `/accounts/:accountId/${name}`,
          name,
          component: { template: '<div />' },
        })
      ),
    });
    await router.push({
      name: 'onboarding_assistant',
      params: { accountId: 1 },
    });
    i18n = createI18n({
      legacy: false,
      locale: 'es',
      messages: {
        en: { ...en, ...authEn, ...integrationsEn },
        es: { ...es, ...authEs, ...integrationsEs },
      },
    });
    options = {
      global: {
        plugins: [store, router, i18n],
        stubs: {
          AuthSplitLayout: {
            template:
              '<main><slot /><footer><slot name="footer" /></footer></main>',
          },
        },
      },
    };
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  it.each(['en', 'es'])(
    'shows the Captain brand icon and assistant setup title in %s',
    async lang => {
      i18n.global.locale.value = lang;
      wrapper = mount(AssistantSetup, options);
      await flushPromises();
      const strings = { en, es }[lang].ONBOARDING_ASSISTANT;
      expect(wrapper.get('h1').text()).toBe(strings.TITLE);
      expect(wrapper.get('header .i-woot-captain').classes()).toEqual(
        expect.arrayContaining(['size-7', 'sm:size-10', 'text-n-slate-12'])
      );
      expect(
        wrapper.get('header .i-woot-captain').attributes('aria-hidden')
      ).toBe('true');
      expect(wrapper.find('input[type="file"]').exists()).toBe(false);

      await wrapper.get('#assistant-name').setValue('Asistente de Acme');
      await wrapper.get('#assistant-goal').setValue('Ayuda a tus clientes');
      await wrapper.get('#assistant-form').trigger('submit');
      await flushPromises();
      await wrapper.get('#assistant-question').setValue('Hola');
      await wrapper.get('section form').trigger('submit');
      await flushPromises();

      expect(wrapper.get('section [role="status"]').text()).toContain(
        draft.name
      );
      expect(wrapper.get('[data-message-role="assistant"]').text()).toContain(
        draft.name
      );
      expect(wrapper.find('img').exists()).toBe(false);
    }
  );

  it.each(['en', 'es'])(
    'shows the paid daily allowance before testing in %s',
    async lang => {
      serverAssistant = structuredClone(draft);
      i18n.global.locale.value = lang;
      CaptainAssistant.playgroundUsage.mockResolvedValueOnce({
        data: {
          test_usage: {
            plan_kind: 'paid',
            daily_total: 10,
            daily_used: 3,
            daily_remaining: 7,
            uses_plan_pool: false,
            plan_remaining: 50,
          },
        },
      });
      wrapper = mount(AssistantSetup, options);
      await flushPromises();
      const strings = { en: integrationsEn, es: integrationsEs }[lang].CAPTAIN
        .PLAYGROUND.USAGE;
      expect(wrapper.text()).toContain(
        strings.DAILY.replace('{used}', '3').replace('{total}', '10')
      );
      expect(CaptainAssistant.playgroundUsage).toHaveBeenCalledWith(42);
      expect(CaptainAssistant.playground).not.toHaveBeenCalled();
    }
  );

  it.each(['en', 'es'])('renders API remaining values in %s', async lang => {
    serverAssistant = structuredClone(draft);
    i18n.global.locale.value = lang;
    const strings = { en: integrationsEn, es: integrationsEs }[lang].CAPTAIN
      .PLAYGROUND.USAGE;
    CaptainAssistant.playground.mockResolvedValueOnce({
      data: {
        response: 'Hello',
        test_usage: {
          plan_kind: 'free',
          daily_total: 0,
          daily_used: 0,
          daily_remaining: 0,
          uses_plan_pool: true,
          plan_remaining: 50,
        },
      },
    });
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    await wrapper.get('#assistant-question').setValue('Hello');
    await wrapper
      .get('#assistant-question')
      .trigger('keydown', { key: 'Enter' });
    await flushPromises();
    expect(wrapper.text()).toContain(strings.FREE.replace('{count}', '50'));
    CaptainAssistant.playground.mockResolvedValueOnce({
      data: {
        response: 'Hello again',
        test_usage: {
          plan_kind: 'paid',
          daily_total: 10,
          daily_used: 10,
          daily_remaining: 0,
          uses_plan_pool: true,
          plan_remaining: 50,
        },
      },
    });
    await wrapper.get('#assistant-question').setValue('Again');
    await wrapper
      .get('#assistant-question')
      .trigger('keydown', { key: 'Enter' });
    await flushPromises();
    expect(wrapper.text()).toContain(
      strings.PLAN.replace('{count}', '50').replace('{total}', '10')
    );
  });

  it.each(['responses_limit_reached', 'playground_rate_limit'])(
    'keeps the chat open on %s and supports retry without duplicating the question',
    async code => {
      serverAssistant = structuredClone(draft);
      CaptainAssistant.playground.mockRejectedValueOnce({
        response: {
          status: code === 'responses_limit_reached' ? 422 : 429,
          data: {
            error_code: code,
            test_usage: {
              plan_kind: 'free',
              daily_total: 0,
              daily_used: 0,
              daily_remaining: 0,
              uses_plan_pool: true,
              plan_remaining: 0,
            },
          },
          headers: { 'retry-after': '60' },
        },
      });
      wrapper = mount(AssistantSetup, options);
      await flushPromises();
      await wrapper.get('#assistant-question').setValue('Hello');
      await wrapper
        .get('#assistant-question')
        .trigger('keydown', { key: 'Enter' });
      await flushPromises();
      expect(wrapper.get('#assistant-chat-error').text()).toContain(
        integrationsEs.CAPTAIN.PLAYGROUND.USAGE[code].replace('{seconds}', '60')
      );
      expect(router.currentRoute.value.name).toBe('onboarding_assistant');
      expect(OnboardingAPI.update).not.toHaveBeenCalled();
      expect(wrapper.find('[data-message-role="assistant"]').exists()).toBe(
        false
      );
      if (code === 'responses_limit_reached') {
        expect(wrapper.get('#assistant-chat-error a').attributes('href')).toBe(
          '/app/accounts/1/settings/billing'
        );
      }
      await wrapper.get('#assistant-chat-error button').trigger('click');
      await flushPromises();
      expect(wrapper.findAll('[data-message-role="user"]')).toHaveLength(1);
      expect(wrapper.findAll('[data-message-role="assistant"]')).toHaveLength(
        1
      );
    }
  );

  it.each(['en', 'es'])(
    'preserves a 60-character business name and makes example selection editable in %s',
    async lang => {
      account.name = 'N'.repeat(60);
      i18n.global.locale.value = lang;
      wrapper = mount(AssistantSetup, options);
      await flushPromises();
      const strings = { en, es }[lang].ONBOARDING_ASSISTANT;
      expect(wrapper.get('#assistant-name').element.value).toBe(
        strings.DEFAULT_NAME.replace('{business}', account.name)
      );
      const chip = wrapper.get('[data-testid="example"]');
      expect(chip.text()).toBe(strings.EXAMPLE_LABELS.appointments['1']);
      expect(chip.attributes('aria-label')).toContain(chip.text());
      await chip.trigger('click');
      expect(wrapper.get('#assistant-goal').element.value).toBe(
        strings.EXAMPLES.appointments['1']
      );
      expect(chip.attributes('aria-pressed')).toBe('true');
      expect(chip.classes()).toEqual(
        expect.arrayContaining([
          'border-solid',
          'border-n-brand',
          'bg-n-blue-2',
        ])
      );
      expect(wrapper.get('#goal-count').text()).toBe(
        strings.CHARACTERS.replace(
          '{count}',
          strings.EXAMPLES.appointments['1'].length
        ).replace('{max}', '2000')
      );
      await wrapper.get('#assistant-goal').setValue('Edited goal');
      expect(chip.attributes('aria-pressed')).toBe('false');
    }
  );

  it('supports tone selection with arrows and keeps one tab stop', async () => {
    options.attachTo = document.body;
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    const radios = wrapper.findAll('[name="assistant-tone"]');
    await radios[0].trigger('keydown', { key: 'ArrowRight' });
    expect(radios[1].element.checked).toBe(true);
    expect(document.activeElement).toBe(radios[1].element);
    expect(radios.map(radio => radio.attributes('tabindex'))).toEqual([
      '-1',
      '0',
      '-1',
    ]);
    expect(wrapper.text()).toContain(
      es.ONBOARDING_ASSISTANT.TONE_DESCRIPTIONS.professional
    );
    expect(radios[1].element.nextElementSibling.classList).toEqual(
      expect.objectContaining({
        value: expect.stringContaining('peer-checked:border-n-brand'),
      })
    );
  });

  it.each(['en', 'es'])(
    'shows step 4 and translated copy in %s',
    async lang => {
      i18n.global.locale.value = lang;
      wrapper = mount(AssistantSetup, options);
      await flushPromises();
      const strings = { en, es }[lang].ONBOARDING_ASSISTANT;
      expect(wrapper.get('h1').text()).toBe(strings.TITLE);
      expect(
        wrapper.get('[role="progressbar"]').attributes('aria-valuenow')
      ).toBe('4');
      expect(wrapper.get('#assistant-name').element.value).toBe(
        strings.DEFAULT_NAME.replace('{business}', 'Acme')
      );
      expect(
        wrapper.get('[data-testid="create"]').attributes('disabled')
      ).toBeDefined();
      expect(wrapper.find('select').exists()).toBe(false);
      expect(OnboardingAPI.saveAssistant).not.toHaveBeenCalled();
    }
  );

  it.each(['appointments', 'commerce', 'services', 'other'])(
    'offers three editable examples for %s',
    async businessType => {
      account.custom_attributes.business_type = businessType;
      wrapper = mount(AssistantSetup, options);
      await flushPromises();
      const examples = wrapper.findAll('[data-testid="example"]');
      expect(examples).toHaveLength(3);
      expect(examples.map(item => item.attributes('title'))).toEqual(
        Object.values(es.ONBOARDING_ASSISTANT.EXAMPLES[businessType])
      );
      await examples[1].trigger('click');
      expect(wrapper.get('#assistant-goal').element.value).toBe(
        examples[1].attributes('title')
      );
      await wrapper.get('#assistant-goal').setValue('Mi objetivo');
      await wrapper.get('input[value="brief"]').setValue();
      await wrapper.get('#assistant-form').trigger('submit');
      await flushPromises();
      expect(OnboardingAPI.saveAssistant).toHaveBeenCalledExactlyOnceWith({
        name: 'Asistente de Acme',
        goal: 'Mi objetivo',
        tone: 'brief',
      });
      expect(wrapper.text()).toContain(es.ONBOARDING_ASSISTANT.DRAFT);
      expect(CaptainInboxes.create).not.toHaveBeenCalled();
      expect(CaptainAssistant.playground).not.toHaveBeenCalled();
      expect(OnboardingAPI.update).not.toHaveBeenCalled();
    }
  );

  it('keeps the form during creation and prevents a duplicate submission', async () => {
    OnboardingAPI.saveAssistant.mockReturnValue(new Promise(() => {}));
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    await wrapper.get('#assistant-goal').setValue('Mi objetivo');
    await wrapper.get('#assistant-form').trigger('submit');
    await wrapper.get('#assistant-form').trigger('submit');
    expect(OnboardingAPI.saveAssistant).toHaveBeenCalledOnce();
    expect(wrapper.get('[data-testid="create"]').attributes('aria-busy')).toBe(
      'true'
    );
    expect(wrapper.text()).toContain(es.ONBOARDING_ASSISTANT.CREATING);
    expect(CaptainInboxes.create).not.toHaveBeenCalled();
  });

  it.each(['limit', 'network'])(
    'keeps entered data and shows the %s error without reporting success',
    async failure => {
      OnboardingAPI.saveAssistant.mockRejectedValue({
        response: {
          data:
            failure === 'limit'
              ? {
                  error_code: 'assistant_limit',
                  limit: 1,
                  error: 'English server error',
                }
              : {},
        },
      });
      wrapper = mount(AssistantSetup, options);
      await flushPromises();
      await wrapper.get('#assistant-goal').setValue('Mi objetivo');
      await wrapper.get('#assistant-form').trigger('submit');
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).toBe(
        failure === 'limit'
          ? es.ONBOARDING_ASSISTANT.LIMIT_ERROR.replace('{limit}', '1')
          : es.ONBOARDING_ASSISTANT.CREATE_ERROR
      );
      expect(wrapper.get('#assistant-goal').element.value).toBe('Mi objetivo');
      expect(wrapper.find('[data-testid="activate"]').exists()).toBe(false);
      expect(router.currentRoute.value.name).toBe('onboarding_assistant');
    }
  );

  it('resumes a draft without creating one and restores its editable inputs', async () => {
    serverAssistant = structuredClone(draft);
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    expect(wrapper.text()).toContain(draft.name);
    expect(OnboardingAPI.saveAssistant).not.toHaveBeenCalled();
    await wrapper.get('[data-testid="edit"]').trigger('click');
    expect(wrapper.get('#assistant-name').element.value).toBe(draft.name);
    expect(wrapper.get('#assistant-goal').element.value).toBe(
      draft.config.onboarding.goal
    );
    expect(wrapper.get('input[value="professional"]').element.checked).toBe(
      true
    );
    await wrapper.get('#assistant-form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[data-testid="activate"]').exists()).toBe(true);
    expect(CaptainInboxes.create).not.toHaveBeenCalled();
  });

  it('sends a test question, shows the reply and does not activate', async () => {
    serverAssistant = structuredClone(draft);
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    expect(wrapper.get('#assistant-question').attributes('placeholder')).toBe(
      es.ONBOARDING_ASSISTANT.QUESTION_PLACEHOLDER
    );
    const composer = wrapper.get('#assistant-question');
    expect(composer.attributes('aria-label')).toBe(
      es.ONBOARDING_ASSISTANT.QUESTION
    );
    expect(wrapper.find('label[for="assistant-question"]').exists()).toBe(
      false
    );
    expect(composer.classes()).toEqual(
      expect.arrayContaining(['border', 'border-solid', 'min-h-14', 'pe-16'])
    );
    expect(
      composer.element.parentElement.querySelector('button[type="submit"]')
    ).not.toBeNull();
    expect(
      wrapper
        .get('[data-testid="chat-empty"]')
        .find('[aria-hidden="true"]')
        .exists()
    ).toBe(true);
    expect(wrapper.get('[data-testid="chat-empty"]').text()).toBe(
      es.ONBOARDING_ASSISTANT.CHAT_EMPTY
    );
    await wrapper.get('#assistant-question').setValue('Hola');
    await wrapper
      .get('#assistant-question')
      .element.form.dispatchEvent(
        new Event('submit', { bubbles: true, cancelable: true })
      );
    await flushPromises();
    expect(CaptainAssistant.playground).toHaveBeenCalledExactlyOnceWith({
      assistantId: 42,
      messageContent: 'Hola',
      messageHistory: [{ role: 'user', content: 'Hola' }],
    });
    expect(wrapper.get('[data-message-role="user"]').classes()).toContain(
      'self-end'
    );
    expect(wrapper.get('[data-message-role="assistant"]').classes()).toContain(
      'self-start'
    );
    expect(wrapper.find('[data-testid="chat-empty"]').exists()).toBe(false);
    expect(wrapper.get('[role="log"]').text()).toContain(
      'Hola, ¿en qué puedo ayudarte?'
    );
    expect(CaptainInboxes.create).not.toHaveBeenCalled();
  });

  it.each(['missing_key', 'quota_exhausted', 'network', 'response_error'])(
    'supports retry after %s without duplicating the question',
    async reason => {
      serverAssistant = {
        ...structuredClone(draft),
        paused_reason: ['missing_key', 'quota_exhausted'].includes(reason)
          ? reason
          : null,
      };
      if (reason === 'network')
        CaptainAssistant.playground.mockRejectedValueOnce(new Error('network'));
      if (reason === 'response_error')
        CaptainAssistant.playground.mockResolvedValueOnce({
          data: { error: 'Unavailable' },
        });
      wrapper = mount(AssistantSetup, options);
      await flushPromises();
      await wrapper.get('#assistant-question').setValue('Hola');
      await wrapper
        .get('#assistant-question')
        .element.form.dispatchEvent(
          new Event('submit', { bubbles: true, cancelable: true })
        );
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).toContain(
        serverAssistant.paused_reason
          ? es.ONBOARDING_ASSISTANT.AI_UNAVAILABLE
          : es.ONBOARDING_ASSISTANT.CHAT_ERROR
      );
      if (serverAssistant.paused_reason)
        expect(CaptainAssistant.playground).not.toHaveBeenCalled();
      serverAssistant.paused_reason = null;
      await wrapper.get('[role="alert"] button').trigger('click');
      await flushPromises();
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
      expect(wrapper.get('[role="log"]').text()).toContain(
        'Hola, ¿en qué puedo ayudarte?'
      );
      expect(
        CaptainAssistant.playground.mock.lastCall[0].messageHistory.filter(
          message => message.role === 'user'
        )
      ).toHaveLength(1);
    }
  );

  it('disables activation without WhatsApp and links back to step 3', async () => {
    inboxes.push({ id: 5, channel_type: 'Channel::WebWidget' });
    serverAssistant = structuredClone(draft);
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    expect(
      wrapper.get('[data-testid="activate"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.text()).toContain(es.ONBOARDING_ASSISTANT.CONNECT_REQUIRED);
    await wrapper.get('a').trigger('click');
    await flushPromises();
    expect(router.currentRoute.value.name).toBe('onboarding_inbox_setup');
    expect(CaptainInboxes.create).not.toHaveBeenCalled();
  });

  it('lets the owner recheck AI availability before sending a question', async () => {
    serverAssistant = {
      ...structuredClone(draft),
      paused_reason: 'missing_key',
    };
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    expect(wrapper.text()).toContain(es.ONBOARDING_ASSISTANT.AI_UNAVAILABLE);
    serverAssistant.paused_reason = null;
    await wrapper.get('[data-testid="ai-retry"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      es.ONBOARDING_ASSISTANT.AI_UNAVAILABLE
    );
    expect(CaptainAssistant.playground).not.toHaveBeenCalled();
    expect(OnboardingAPI.saveAssistant).not.toHaveBeenCalled();
  });

  it('shows that the test is running and prevents another send or activation', async () => {
    serverAssistant = structuredClone(draft);
    inboxes.push({ id: 7, channel_type: 'Channel::Whatsapp' });
    CaptainAssistant.playground.mockReturnValue(new Promise(() => {}));
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    await wrapper.get('#assistant-question').setValue('Hola');
    await wrapper.get('section form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[role="log"]').text()).toContain(
      es.ONBOARDING_ASSISTANT.THINKING
    );
    expect(
      wrapper.get('[data-testid="activate"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.get('#assistant-question').attributes('disabled')
    ).toBeDefined();
    expect(CaptainAssistant.playground).toHaveBeenCalledOnce();
  });

  it('links only on explicit activation and then finishes onboarding', async () => {
    inboxes.push({ id: 7, channel_type: 'Channel::Whatsapp' });
    serverAssistant = structuredClone(draft);
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    expect(CaptainInboxes.create).not.toHaveBeenCalled();
    await wrapper.get('[data-testid="activate"]').trigger('click');
    await flushPromises();
    expect(CaptainInboxes.create).toHaveBeenCalledExactlyOnceWith({
      assistantId: 42,
      inboxId: 7,
    });
    expect(OnboardingAPI.update).toHaveBeenCalledExactlyOnceWith({
      onboarding_step: 'assistant',
    });
    expect(setUser).toHaveBeenCalledOnce();
    expect(router.currentRoute.value.name).toBe('home');
  });

  it('keeps the draft on activation failure and reconciles a lost response on retry', async () => {
    inboxes.push({ id: 7, channel_type: 'Channel::Whatsapp' });
    serverAssistant = structuredClone(draft);
    CaptainInboxes.create.mockImplementationOnce(async () => {
      serverAssistant.inbox_ids = [7];
      throw new Error('lost response');
    });
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    await wrapper.get('[data-testid="activate"]').trigger('click');
    await flushPromises();
    expect(OnboardingAPI.update).not.toHaveBeenCalled();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      es.ONBOARDING_ASSISTANT.ACTIVATE_ERROR
    );
    await wrapper.get('[data-testid="activate"]').trigger('click');
    await flushPromises();
    expect(CaptainInboxes.create).toHaveBeenCalledOnce();
    expect(router.currentRoute.value.name).toBe('home');
  });

  it.each([false, true])(
    'can skip with draft=%s without activating',
    async hasDraft => {
      if (hasDraft) serverAssistant = structuredClone(draft);
      wrapper = mount(AssistantSetup, options);
      await flushPromises();
      await wrapper.get('[data-testid="skip"]').trigger('click');
      await flushPromises();
      expect(OnboardingAPI.update).toHaveBeenCalledExactlyOnceWith({
        onboarding_step: 'assistant',
      });
      expect(CaptainInboxes.create).not.toHaveBeenCalled();
      expect(OnboardingAPI.saveAssistant).not.toHaveBeenCalled();
      expect(router.currentRoute.value.name).toBe('home');
    }
  );

  it('offers retry if loading the saved draft fails', async () => {
    OnboardingAPI.getAssistant.mockRejectedValueOnce(new Error('network'));
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      es.ONBOARDING_ASSISTANT.LOAD_ERROR
    );
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('#assistant-form').exists()).toBe(true);
    expect(OnboardingAPI.saveAssistant).not.toHaveBeenCalled();
  });

  it('waits for the account payload before choosing the name and business examples', async () => {
    let resolveAccount;
    AccountAPI.get.mockReturnValueOnce(
      new Promise(resolve => {
        resolveAccount = resolve;
      })
    );
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    expect(wrapper.find('#assistant-form').exists()).toBe(false);
    resolveAccount({
      data: {
        ...account,
        name: 'Tienda',
        custom_attributes: {
          ...account.custom_attributes,
          business_type: 'commerce',
        },
      },
    });
    await flushPromises();
    expect(wrapper.get('#assistant-name').element.value).toBe(
      'Asistente de Tienda'
    );
    expect(
      wrapper
        .findAll('[data-testid="example"]')
        .map(item => item.attributes('title'))
    ).toEqual(Object.values(es.ONBOARDING_ASSISTANT.EXAMPLES.commerce));
  });

  it.each(['account', 'inboxes'])(
    'offers retry when the %s store action absorbs an HTTP failure',
    async resource => {
      if (resource === 'account') {
        AccountAPI.get.mockRejectedValueOnce({ response: { status: 503 } });
      } else {
        getInboxes.mockResolvedValueOnce(false);
      }
      wrapper = mount(AssistantSetup, options);
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).toBe(
        es.ONBOARDING_ASSISTANT.LOAD_ERROR
      );
      expect(wrapper.find('#assistant-form').exists()).toBe(false);
      await wrapper.get('button').trigger('click');
      await flushPromises();
      expect(wrapper.find('#assistant-form').exists()).toBe(true);
      expect(OnboardingAPI.saveAssistant).not.toHaveBeenCalled();
    }
  );

  it('keeps the draft and step when activation returns 5xx', async () => {
    serverAssistant = structuredClone(draft);
    inboxes.push({ id: 7, channel_type: 'Channel::Whatsapp' });
    CaptainInboxes.create.mockRejectedValueOnce({ response: { status: 503 } });
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    await wrapper.get('[data-testid="activate"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      es.ONBOARDING_ASSISTANT.ACTIVATE_ERROR
    );
    expect(OnboardingAPI.update).not.toHaveBeenCalled();
    expect(router.currentRoute.value.name).toBe('onboarding_assistant');
    expect(wrapper.text()).toContain(es.ONBOARDING_ASSISTANT.DRAFT);
  });

  it('prevents a double activation while the inbox request is pending', async () => {
    serverAssistant = structuredClone(draft);
    inboxes.push({ id: 7, channel_type: 'Channel::Whatsapp' });
    CaptainInboxes.create.mockReturnValueOnce(new Promise(() => {}));
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    await wrapper.get('[data-testid="activate"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-testid="activate"]').trigger('click');
    expect(CaptainInboxes.create).toHaveBeenCalledOnce();
    expect(OnboardingAPI.update).not.toHaveBeenCalled();
  });

  it('retries completion after 5xx without linking an already activated draft again', async () => {
    serverAssistant = structuredClone(draft);
    inboxes.push({ id: 7, channel_type: 'Channel::Whatsapp' });
    OnboardingAPI.update.mockRejectedValueOnce({ response: { status: 503 } });
    wrapper = mount(AssistantSetup, options);
    await flushPromises();
    await wrapper.get('[data-testid="activate"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      es.ONBOARDING_ASSISTANT.ACTIVATE_ERROR
    );
    expect(wrapper.text()).toContain(es.ONBOARDING_ASSISTANT.ACTIVE);
    expect(router.currentRoute.value.name).toBe('onboarding_assistant');
    expect(setUser).not.toHaveBeenCalled();
    await wrapper.get('[data-testid="activate"]').trigger('click');
    await flushPromises();
    expect(CaptainInboxes.create).toHaveBeenCalledOnce();
    expect(OnboardingAPI.update).toHaveBeenCalledTimes(2);
    expect(router.currentRoute.value.name).toBe('home');
  });
});
