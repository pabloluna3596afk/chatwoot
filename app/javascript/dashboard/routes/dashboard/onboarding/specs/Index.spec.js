import authEn from 'dashboard/i18n/locale/en/auth.json';
import authEs from 'dashboard/i18n/locale/es/auth.json';
import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createMemoryHistory, createRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import OnboardingAPI from 'dashboard/api/onboarding';
import accounts from 'dashboard/store/modules/accounts';
import en from 'dashboard/i18n/locale/en/onboarding.json';
import es from 'dashboard/i18n/locale/es/onboarding.json';
import OnboardingShell from '../shared/OnboardingShell.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import ComboBoxDropdown from 'dashboard/components-next/combobox/ComboBoxDropdown.vue';
import Index from '../Index.vue';

vi.mock('dashboard/api/onboarding');
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));

describe('Business onboarding', () => {
  let wrapper;
  let account;
  let router;
  let setUser;
  let i18n;
  let mountOptions;

  beforeEach(async () => {
    account = reactive({
      id: 1,
      name: 'Acme',
      locale: 'es',
      custom_attributes: { onboarding_step: 'account_details' },
    });
    setUser = vi.fn();
    const store = createStore({
      getters: {
        'accounts/getAccount': () => () => account,
        'globalConfig/get': () => ({
          installationName: 'ChatHub',
          logo: '/logo.svg',
        }),
      },
      actions: {
        'accounts/finishOnboarding': accounts.actions.finishOnboarding,
        setUser,
      },
      mutations: {
        SET_ACCOUNT_UI_FLAG: vi.fn(),
        EDIT_ACCOUNT: (_, updated) => Object.assign(account, updated),
      },
    });
    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        'onboarding_account_details',
        'onboarding_inbox_setup',
        'home',
      ].map(name => ({
        path: `/accounts/:accountId/${name}`,
        name,
        component: { template: '<div />' },
      })),
    });
    await router.push({
      name: 'onboarding_account_details',
      params: { accountId: 1 },
    });
    await router.isReady();
    i18n = createI18n({
      legacy: false,
      locale: 'es',
      messages: { en: { ...en, ...authEn }, es: { ...es, ...authEs } },
    });
    mountOptions = {
      attachTo: document.body,
      global: { plugins: [store, router, i18n] },
    };
    OnboardingAPI.update.mockResolvedValue({
      data: { ...account, custom_attributes: {} },
    });
  });

  afterEach(() => {
    wrapper?.unmount();
    vi.restoreAllMocks();
  });

  it('updates the live preview when the business name and activity change', async () => {
    wrapper = mount(Index, mountOptions);
    await flushPromises();
    await wrapper.get('[name="name"]').setValue('Librería Sol');
    await wrapper.get('[value="commerce"]').setValue();
    expect(wrapper.get('[data-testid="business-preview"]').text()).toContain(
      'Librería Sol'
    );
    expect(wrapper.get('[data-testid="business-preview"]').text()).toContain(
      es.ONBOARDING_LAYOUT.PREVIEW_REPLIES.commerce
    );
    expect(OnboardingAPI.update).not.toHaveBeenCalled();
  });

  it('reviews saved business details without replaying the completed backend step', async () => {
    account.custom_attributes.onboarding_step = 'inbox_setup';
    wrapper = mount(Index, mountOptions);
    await flushPromises();
    expect(wrapper.get('[name="name"]').element.disabled).toBe(true);
    expect(wrapper.find('[aria-controls="location-fields"]').exists()).toBe(
      false
    );
    await wrapper.get('button[type="submit"]').trigger('click');
    await flushPromises();
    expect(OnboardingAPI.update).not.toHaveBeenCalled();
    expect(router.currentRoute.value.name).toBe('onboarding_inbox_setup');
  });

  it.each(['en', 'es'])(
    'renders the business fields and shared layout in %s',
    async lang => {
      i18n.global.locale.value = lang;
      wrapper = mount(Index, mountOptions);
      await flushPromises();
      const strings = { en, es }[lang].ONBOARDING_NEXT;

      expect(wrapper.getComponent(OnboardingShell).exists()).toBe(true);
      expect(wrapper.get('h1').text()).toBe(strings.TITLE);
      expect(wrapper.text()).toContain(
        i18n.global.t('ONBOARDING_LAYOUT.STEP', { current: 1, total: 4 })
      );
      expect(
        wrapper.get('[role="progressbar"]').attributes('aria-valuenow')
      ).toBe('1');
      expect(
        wrapper.get('[role="progressbar"]').attributes('aria-valuemax')
      ).toBe('4');
      expect(wrapper.get('[name="name"]').element.value).toBe('Acme');
      expect(wrapper.findAll('[name="business_type"]')).toHaveLength(4);
      Object.values(strings.BUSINESS_TYPES).forEach(label => {
        expect(wrapper.text()).toContain(label);
      });
      const labels = wrapper
        .findAllComponents(ComboBox)
        .map(combo => combo.props('ariaLabel'));
      expect(labels).toEqual([
        strings.FIELDS.COUNTRY,
        strings.FIELDS.LANGUAGE,
        strings.FIELDS.TIMEZONE,
      ]);
      expect(wrapper.find('select').exists()).toBe(false);
      expect(wrapper.find('[name="user_role"]').exists()).toBe(false);
      expect(wrapper.find('[name="industry"]').exists()).toBe(false);
      expect(wrapper.find('[name="company_size"]').exists()).toBe(false);
      expect(wrapper.find('[name="referral_source"]').exists()).toBe(false);
      expect(wrapper.get('[name="website"]').element.required).toBe(false);
      expect(wrapper.get('[name="name"]').classes()).toEqual(
        expect.arrayContaining(['min-h-14', 'rounded-xl', 'border-solid'])
      );
      expect(wrapper.get('button[type="submit"]').text()).toBe(
        strings.CONTINUE
      );
      expect(wrapper.get('button[type="submit"]').classes()).toEqual(
        expect.arrayContaining(['min-h-12', 'rounded-xl', 'bg-n-brand'])
      );
    },
    20000
  );

  it('requires a business type before sending anything', async () => {
    wrapper = mount(Index, mountOptions);
    await wrapper.get('form').trigger('submit');

    expect(OnboardingAPI.update).not.toHaveBeenCalled();
    expect(wrapper.get('#business-type-error').text()).toBe(
      es.ONBOARDING_NEXT.BUSINESS_TYPE_REQUIRED
    );
  });

  it('keeps the form scrollable above its separate action footer and pairs country with language from sm', async () => {
    wrapper = mount(Index, mountOptions);
    await flushPromises();

    expect(wrapper.get('main').classes()).toContain('h-dvh');
    const scroller = wrapper.get('[data-testid="onboarding-scroll-content"]');
    expect(scroller.find('form').exists()).toBe(true);
    expect(scroller.find('button[type="submit"]').exists()).toBe(false);
    const submit = wrapper.get('button[type="submit"]');
    expect(submit.element.form).toBe(wrapper.get('form').element);
    expect(
      submit.element.closest('footer').classList.contains('shrink-0')
    ).toBe(true);

    const row = wrapper.get('.sm\\:grid-cols-2');
    expect(row.classes()).toContain('grid-cols-1');
    expect(
      row.findAllComponents(ComboBox).map(combo => combo.props('ariaLabel'))
    ).toEqual([
      es.ONBOARDING_NEXT.FIELDS.COUNTRY,
      es.ONBOARDING_NEXT.FIELDS.LANGUAGE,
    ]);
    expect(
      wrapper
        .findAllComponents(ComboBox)
        .every(combo => combo.props('teleport'))
    ).toBe(true);
  });

  it('opts all three pickers into the same 56px bordered field with light, dark and keyboard focus states', () => {
    wrapper = mount(Index, mountOptions);
    const pickers = wrapper.findAllComponents(ComboBox);
    expect(pickers).toHaveLength(3);
    pickers.forEach(picker => {
      expect(picker.get('button').classes()).toEqual(
        expect.arrayContaining([
          '!h-14',
          '!rounded-xl',
          '!border',
          '!border-solid',
          '!border-n-slate-9',
          'dark:!border-n-slate-10',
          '!bg-n-solid-1',
          'dark:!bg-n-solid-3',
          'focus-visible:!border-n-brand',
          'focus-visible:ring-2',
        ])
      );
    });
  });

  it('exposes a radio group with one tab stop, brand selection, icons and a check', async () => {
    wrapper = mount(Index, mountOptions);
    const group = wrapper.get('[role="radiogroup"]');
    expect(group.attributes('aria-labelledby')).toBe('business-type-label');
    const radios = group.findAll('[role="radio"]');
    expect(radios.map(radio => radio.attributes('tabindex'))).toEqual([
      '0',
      '-1',
      '-1',
      '-1',
    ]);
    ['calendar', 'store', 'briefcase', 'sparkles'].forEach((icon, index) => {
      const card = radios[index].element.parentElement;
      expect(
        card.querySelector(`.i-lucide-${icon}`).getAttribute('aria-hidden')
      ).toBe('true');
      expect(card.querySelector('.peer-checked\\:bg-n-blue-2')).not.toBeNull();
      expect(
        card.querySelector('.peer-checked\\:border-n-brand')
      ).not.toBeNull();
      expect(card.querySelector('.i-lucide-circle-check')).not.toBeNull();
    });
    await radios[2].setValue();
    expect(radios.map(radio => radio.element.checked)).toEqual([
      false,
      false,
      true,
      false,
    ]);
    expect(radios.map(radio => radio.attributes('tabindex'))).toEqual([
      '-1',
      '-1',
      '0',
      '-1',
    ]);
  });

  it.each([
    [0, 'ArrowRight', 1],
    [0, 'ArrowDown', 1],
    [0, 'ArrowLeft', 3],
    [0, 'ArrowUp', 3],
    [3, 'ArrowRight', 0],
  ])(
    'moves focus and selection from radio %i with %s to %i',
    async (from, key, to) => {
      wrapper = mount(Index, mountOptions);
      const radios = wrapper.findAll('[role="radio"]');
      await radios[from].setValue();
      radios[from].element.focus();
      await radios[from].trigger('keydown', { key });

      expect(document.activeElement).toBe(radios[to].element);
      expect(radios.filter(radio => radio.element.checked)).toHaveLength(1);
      expect(radios[to].element.checked).toBe(true);
      expect(radios[to].attributes('tabindex')).toBe('0');
      expect(OnboardingAPI.update).not.toHaveBeenCalled();
    }
  );

  it.each(['Guayaquil', 'Ecuador', 'America/Guayaquil'])(
    'finds a readable timezone by %s while preserving its IANA value',
    async search => {
      wrapper = mount(Index, mountOptions);
      const timezone = wrapper.findAllComponents(ComboBox)[2];
      const dropdown = timezone.getComponent(ComboBoxDropdown);
      await dropdown.vm.$emit('update:searchValue', search);
      await flushPromises();

      const option = dropdown
        .props('options')
        .find(o => o.value === 'America/Guayaquil');
      expect(option.label).toBe('Ecuador (GMT-5) · Guayaquil');
      await dropdown.vm.$emit('select', option);
      await flushPromises();
      expect(timezone.props('modelValue')).toBe('America/Guayaquil');
      expect(timezone.get('button').text()).toBe('Ecuador (GMT-5) · Guayaquil');
    }
  );

  it('requires an editable business name', async () => {
    wrapper = mount(Index, mountOptions);
    await flushPromises();
    await wrapper.get('[name="name"]').setValue('');
    await wrapper.get('[value="other"]').setValue();
    await wrapper.get('form').trigger('submit');

    expect(OnboardingAPI.update).not.toHaveBeenCalled();
    expect(wrapper.get('#business-name-error').text()).toBe(
      es.ONBOARDING_NEXT.NAME_REQUIRED
    );
  });

  it.each(['en', 'es'])(
    'saves a 60-character name without truncation in %s',
    async lang => {
      i18n.global.locale.value = lang;
      wrapper = mount(Index, mountOptions);
      await flushPromises();
      const businessName = 'N'.repeat(60);
      await wrapper.get('#business-name').setValue(businessName);
      await wrapper.get('[value="other"]').setValue();
      await wrapper.get('form').trigger('submit');
      await flushPromises();
      expect(OnboardingAPI.update).toHaveBeenCalledWith(
        expect.objectContaining({
          name: businessName,
          business_type: 'other',
          onboarding_step: 'account_details',
        })
      );
    }
  );

  it('prefills the account language and detected timezone, including zones omitted by supportedValuesOf', async () => {
    const detectedZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    vi.spyOn(Intl, 'supportedValuesOf').mockReturnValueOnce([
      'America/Guayaquil',
    ]);
    wrapper = mount(Index, mountOptions);
    await flushPromises();
    const [country, language, timezone] = wrapper.findAllComponents(ComboBox);

    expect(country.props('modelValue')).toBe('EC');
    expect(timezone.props('modelValue')).toBe(detectedZone);
    expect(timezone.props('options')).toContainEqual(
      expect.objectContaining({ value: detectedZone })
    );
    expect(
      timezone.props('options').find(o => o.value === detectedZone).label
    ).toContain('GMT');
    expect(language.props('modelValue')).toBe('es');
    expect(language.props('options').map(option => option.value)).toEqual([
      'es',
      'en',
    ]);
    expect(country.props('showSearch')).toBe(true);
    expect(timezone.props('showSearch')).toBe(true);
    expect(country.props('options')).toContainEqual({
      value: 'EC',
      label: 'Ecuador',
    });
  });

  it('sends the edited name through the real store action and API with account_details, without website or country', async () => {
    wrapper = mount(Index, mountOptions);
    await wrapper.get('[name="name"]').setValue('Mi tienda');
    await wrapper.get('[value="commerce"]').setValue();
    await wrapper.get('button[type="submit"]').trigger('click');
    await flushPromises();

    expect(OnboardingAPI.update).toHaveBeenCalledExactlyOnceWith({
      name: 'Mi tienda',
      business_type: 'commerce',
      country: 'EC',
      website: '',
      locale: 'es',
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      onboarding_step: 'account_details',
    });
    expect(setUser).toHaveBeenCalledOnce();
    expect(router.currentRoute.value.name).toBe('home');
  });

  it('saves confirmed selections and normalizes a supplied website before following the cloud cursor', async () => {
    OnboardingAPI.update.mockResolvedValueOnce({
      data: {
        ...account,
        custom_attributes: { onboarding_step: 'inbox_setup' },
      },
    });
    wrapper = mount(Index, mountOptions);
    await wrapper.get('[value="appointments"]').setValue();
    const [country, language, timezone] = wrapper.findAllComponents(ComboBox);
    country.vm.$emit('update:modelValue', 'EC');
    timezone.vm.$emit('update:modelValue', 'America/Guayaquil');
    language.vm.$emit('update:modelValue', 'en');
    await wrapper.get('[name="website"]').setValue(' acme.com ');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(OnboardingAPI.update).toHaveBeenCalledWith(
      expect.objectContaining({
        business_type: 'appointments',
        country: 'EC',
        timezone: 'America/Guayaquil',
        locale: 'en',
        website: 'https://acme.com',
        onboarding_step: 'account_details',
      })
    );
    expect(setUser).toHaveBeenCalledOnce();
    expect(router.currentRoute.value.name).toBe('onboarding_inbox_setup');
  });

  it('retains input on API failure and permits retry', async () => {
    OnboardingAPI.update.mockRejectedValueOnce(new Error('Network error'));
    wrapper = mount(Index, mountOptions);
    await wrapper.get('[name="name"]').setValue('Mi negocio');
    await wrapper.get('[value="services"]').setValue();
    await wrapper.get('[name="website"]').setValue('mi-negocio.com');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(es.ONBOARDING_NEXT.ERROR);
    expect(wrapper.get('[name="name"]').element.value).toBe('Mi negocio');
    expect(wrapper.get('[value="services"]').element.checked).toBe(true);
    expect(wrapper.get('[name="website"]').element.value).toBe(
      'mi-negocio.com'
    );
    expect(wrapper.get('button[type="submit"]').element.disabled).toBe(false);
    expect(router.currentRoute.value.name).toBe('onboarding_account_details');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(OnboardingAPI.update).toHaveBeenCalledTimes(2);
    expect(router.currentRoute.value.name).toBe('home');
  });

  it('shows loading and blocks duplicate requests', async () => {
    OnboardingAPI.update.mockReturnValueOnce(new Promise(() => {}));
    wrapper = mount(Index, mountOptions);
    await wrapper.get('[value="other"]').setValue();
    await wrapper.get('form').trigger('submit');
    await wrapper.get('form').trigger('submit');

    const button = wrapper.get('button[type="submit"]');
    expect(button.element.disabled).toBe(true);
    expect(button.attributes('aria-busy')).toBe('true');
    expect(button.find('svg.animate-spin').exists()).toBe(true);
    expect(OnboardingAPI.update).toHaveBeenCalledOnce();
  });

  it('waits for account enrichment before submitting', async () => {
    account.custom_attributes.onboarding_step = 'enrichment';
    wrapper = mount(Index, mountOptions);
    await wrapper.get('[value="other"]').setValue();
    await wrapper.get('form').trigger('submit');

    expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
    expect(OnboardingAPI.update).not.toHaveBeenCalled();
    account.custom_attributes.onboarding_step = 'account_details';
    await flushPromises();
    expect(wrapper.get('button[type="submit"]').element.disabled).toBe(false);
  });
});
