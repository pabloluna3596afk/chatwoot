/* eslint-disable @intlify/vue-i18n/no-dynamic-keys -- Validation cases share parameterized message keys. */
import { computed, nextTick } from 'vue';
import { createI18n } from 'vue-i18n';
import { config, flushPromises, shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import en from 'dashboard/i18n/locale/en';
import es from 'dashboard/i18n/locale/es';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TeamForm from 'dashboard/routes/dashboard/settings/teams/TeamForm.vue';
import AssistantBasicSettingsForm from './AssistantBasicSettingsForm.vue';
import AssistantFollowupForm from './AssistantFollowupForm.vue';
import AssistantSystemSettingsForm from './AssistantSystemSettingsForm.vue';
import DurationSelect from './DurationSelect.vue';

vi.mock('@amplitude/analytics-browser', () => ({
  init: vi.fn(),
  track: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1', assistantId: '2' } }),
}));

vi.mock('dashboard/api/variables', () => ({
  default: { catalog: vi.fn(async () => ({ data: { variables: [] } })) },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn().mockResolvedValue() }),
  useMapGetter: name =>
    computed(() => (name === 'getCurrentAccountId' ? 1 : [])),
}));

const features = vi.hoisted(() => ({ captainV2: true }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => features.captainV2 }),
}));

const assistant = {
  name: 'Sofia',
  description: 'Support assistant',
  config: { product_name: 'ChatHub', auto_resolve_after: 60 },
};
const originalPlugins = config.global.plugins;

afterEach(() => {
  config.global.plugins = originalPlugins;
});

describe.each(['en', 'es'])('localized validation (%s)', locale => {
  let i18n;

  beforeEach(() => {
    features.captainV2 = true;
    i18n = createI18n({
      legacy: false,
      locale,
      fallbackLocale: false,
      messages: { en, es },
    });
    config.global.plugins = [i18n];
  });

  it('renders the goodbye link in the current locale with one inactivity timer', () => {
    const wrapper = shallowMount(AssistantFollowupForm, {
      props: {
        assistant: {
          ...assistant,
        },
      },
      global: {
        stubs: {
          I18nT: { template: '<p><slot name="link" /></p>' },
          SettingsToggleSection: false,
          RouterLink: { template: '<a><slot /></a>' },
        },
        mocks: { $t: key => i18n.global.t(key) },
      },
    });
    const expectedLink =
      locale === 'es' ? 'Traspaso y cierre' : 'Handoff and closing';

    expect(wrapper.text()).toContain(expectedLink);
    expect(wrapper.findAllComponents(DurationSelect)).toHaveLength(0);
    wrapper.unmount();
  });

  it.each(['name', 'description', 'productName'])(
    'requires the basic %s field and preserves the draft',
    async field => {
      const wrapper = shallowMount(AssistantBasicSettingsForm, {
        props: { assistant },
      });
      wrapper.vm.state[field] = '';
      wrapper.findComponent(Button).vm.$emit('click');
      await flushPromises();

      expect(wrapper.emitted('submit')).toBeUndefined();
      expect(wrapper.vm.formErrors[field]).toBe(
        i18n.global.t('GENERAL.VALIDATION.REQUIRED')
      );
      expect(wrapper.vm.state[field]).toBe('');
      expect(wrapper.vm.v$[field].minLength.$params.min).toBe(1);
      expect(wrapper.vm.v$[field].minLength.$message).toBe(
        i18n.global.t('GENERAL.VALIDATION.MIN_LENGTH', { min: 1 })
      );
      wrapper.unmount();
    }
  );

  it('saves basic fields with one character and the unchanged config', async () => {
    const wrapper = shallowMount(AssistantBasicSettingsForm, {
      props: { assistant },
    });
    Object.assign(wrapper.vm.state, {
      name: 'A',
      description: 'B',
      productName: 'C',
    });
    wrapper.findComponent(Button).vm.$emit('click');
    await flushPromises();
    expect(wrapper.emitted('submit')[0][0]).toMatchObject({
      name: 'A',
      description: 'B',
      config: { ...assistant.config, product_name: 'C' },
    });
    wrapper.unmount();
  });

  it.each([
    ['', 'REQUIRED', {}],
    ['-1', 'MIN_VALUE', { min: 0 }],
    ['1001', 'MAX_VALUE', { max: 1000 }],
    ['1.5', 'INTEGER', {}],
  ])(
    'shows the reply limit error for %j and blocks submission',
    async (value, key, params) => {
      const wrapper = shallowMount(AssistantSystemSettingsForm, {
        props: { assistant },
        global: { stubs: { SettingsToggleSection: false } },
      });
      wrapper.findComponent(Input).vm.$emit('update:modelValue', value);
      wrapper.findComponent(Button).vm.$emit('click');
      await flushPromises();
      expect(wrapper.findComponent(Input).props('message')).toBe(
        i18n.global.t(`GENERAL.VALIDATION.${key}`, params)
      );
      expect(wrapper.findComponent(Input).props('messageType')).toBe('error');
      expect(wrapper.emitted('submit')).toBeUndefined();
      wrapper.unmount();
    }
  );

  it.each([
    [4, 'MIN_VALUE', { min: 5 }],
    [1441, 'MAX_VALUE', { max: 1440 }],
    [null, 'REQUIRED', {}],
  ])('shows the inactivity error for %j', async (value, key, params) => {
    const wrapper = shallowMount(AssistantSystemSettingsForm, {
      props: {
        assistant: { config: { auto_resolve_after: 60 } },
      },
      global: { stubs: { SettingsToggleSection: false } },
    });
    wrapper.findComponent(DurationSelect).vm.$emit('update:modelValue', value);
    wrapper.findComponent(Button).vm.$emit('click');
    await flushPromises();
    expect(wrapper.findComponent(DurationSelect).props('error')).toBe(
      i18n.global.t(`GENERAL.VALIDATION.${key}`, params)
    );
    expect(wrapper.emitted('submit')).toBeUndefined();
    wrapper.unmount();
  });

  it('shows the localized follow-up timing error and blocks submission', async () => {
    const wrapper = shallowMount(AssistantFollowupForm, {
      props: { assistant: { config: { auto_resolve_after: 30 } } },
      global: { stubs: { SettingsToggleSection: false } },
    });
    await wrapper.get('[data-testid="followup-save"]').trigger('click');
    await flushPromises();

    expect(wrapper.get('[data-testid="followup-after-error"]').text()).toBe(
      i18n.global.t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.AFTER_ERROR')
    );
    expect(wrapper.emitted('submit')).toBeUndefined();
    wrapper.unmount();
  });

  it.each(['0', '1000', '20'])(
    'preserves accepted reply limit %s',
    async replies => {
      const wrapper = shallowMount(AssistantSystemSettingsForm, {
        props: {
          assistant: { config: { max_replies_per_conversation: replies } },
        },
      });
      wrapper.findComponent(Button).vm.$emit('click');
      await flushPromises();
      expect(wrapper.emitted('submit')[0][0].config).toMatchObject({
        max_replies_per_conversation: Number(replies),
      });
      wrapper.unmount();
    }
  );

  it.each([5, 1440, 60])(
    'preserves accepted inactivity timer boundary %s',
    async minutes => {
      const wrapper = shallowMount(AssistantSystemSettingsForm, {
        props: {
          assistant: {
            config: {
              auto_resolve_after: minutes,
              followup: { inactivity_enabled: false },
            },
          },
        },
      });
      wrapper.findComponent(Button).vm.$emit('click');
      await flushPromises();
      expect(wrapper.emitted('submit')[0][0].config.auto_resolve_after).toBe(
        minutes
      );
      wrapper.unmount();
    }
  );

  it.each([
    ['', 'REQUIRED', {}],
    ['A', 'MIN_LENGTH', { min: 2 }],
  ])('shows the team name error for %j on blur', async (value, key, params) => {
    const onSubmit = vi.fn();
    const wrapper = shallowMount(TeamForm, {
      props: { onSubmit, formData: { name: value } },
    });
    const title = wrapper.findAllComponents(Input)[0];
    title.vm.$emit('blur');
    await nextTick();
    expect(title.props('message')).toBe(
      i18n.global.t(`GENERAL.VALIDATION.${key}`, params)
    );
    await wrapper.find('form').trigger('submit');
    expect(onSubmit).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('saves a two-character team name with an optional description', async () => {
    const onSubmit = vi.fn();
    const wrapper = shallowMount(TeamForm, {
      props: { onSubmit, formData: { name: 'AB' } },
    });
    await wrapper.find('form').trigger('submit');
    expect(onSubmit).toHaveBeenCalledWith({
      name: 'AB',
      description: '',
      allow_auto_assign: true,
      icon: '',
      icon_color: '',
    });
    wrapper.unmount();
  });

  it.each([true, false])(
    'keeps optional system text empty in Captain V2=%s',
    async captainV2 => {
      features.captainV2 = captainV2;
      const wrapper = shallowMount(AssistantSystemSettingsForm, {
        props: {
          assistant: {
            config: {
              handoff_message: '',
              resolution_message: '',
              instructions: '',
            },
          },
        },
      });
      wrapper.findComponent(Button).vm.$emit('click');
      await flushPromises();
      expect(wrapper.emitted('submit')).toHaveLength(1);
      ['handoffMessage', 'resolutionMessage', 'instructions'].forEach(field => {
        expect(wrapper.vm.v$[field].minLength.$params.min).toBe(1);
        expect(wrapper.vm.v$[field].minLength.$message).toBe(
          i18n.global.t('GENERAL.VALIDATION.MIN_LENGTH', { min: 1 })
        );
      });
      wrapper.unmount();
    }
  );

  it('does not validate the hidden inactivity timer when disabled', async () => {
    const wrapper = shallowMount(AssistantFollowupForm, {
      props: {
        assistant: {
          config: { auto_resolve_mode: 'disabled', auto_resolve_after: 1441 },
        },
      },
    });
    await wrapper.get('[data-testid="followup-save"]').trigger('click');
    await flushPromises();
    expect(wrapper.emitted('submit')).toHaveLength(1);
    expect(wrapper.emitted('submit')[0][0].config).not.toHaveProperty(
      'auto_resolve_after'
    );
    wrapper.unmount();
  });

  it('updates an already visible error when the locale changes', async () => {
    const wrapper = shallowMount(AssistantBasicSettingsForm, {
      props: { assistant: { ...assistant, name: '' } },
    });
    wrapper.findComponent(Button).vm.$emit('click');
    await flushPromises();
    const input = wrapper.findComponent(Input);
    const firstMessage = input.props('message');
    i18n.global.locale.value = locale === 'en' ? 'es' : 'en';
    await nextTick();
    expect(input.props('message')).toBe(
      i18n.global.t('GENERAL.VALIDATION.REQUIRED')
    );
    expect(input.props('message')).not.toBe(firstMessage);
    wrapper.unmount();
  });
});
