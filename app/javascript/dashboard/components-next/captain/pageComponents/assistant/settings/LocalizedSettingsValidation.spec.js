/* eslint-disable @intlify/vue-i18n/no-dynamic-keys -- Validation cases share parameterized message keys. */
import { nextTick } from 'vue';
import { createI18n } from 'vue-i18n';
import { config, flushPromises, shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import en from 'dashboard/i18n/locale/en';
import es from 'dashboard/i18n/locale/es';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TeamForm from 'dashboard/routes/dashboard/settings/teams/TeamForm.vue';
import AssistantBasicSettingsForm from './AssistantBasicSettingsForm.vue';
import AssistantSystemSettingsForm from './AssistantSystemSettingsForm.vue';
import DurationSelect from './DurationSelect.vue';

vi.mock('@amplitude/analytics-browser', () => ({
  init: vi.fn(),
  track: vi.fn(),
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
        assistant: { config: { auto_resolve_after: value } },
      },
      global: { stubs: { SettingsToggleSection: false } },
    });
    // Null is initialized to 60 by the existing loader; exercise the rule directly.
    wrapper.vm.state.inactivityThresholdMinutes = value;
    wrapper.findComponent(Button).vm.$emit('click');
    await flushPromises();
    expect(wrapper.findComponent(DurationSelect).props('error')).toBe(
      i18n.global.t(`GENERAL.VALIDATION.${key}`, params)
    );
    expect(wrapper.emitted('submit')).toBeUndefined();
    wrapper.unmount();
  });

  it.each([
    ['0', 5],
    ['1000', 1440],
    ['20', 60],
  ])(
    'preserves accepted reply %s and inactivity %s boundaries',
    async (replies, minutes) => {
      const wrapper = shallowMount(AssistantSystemSettingsForm, {
        props: {
          assistant: {
            config: {
              max_replies_per_conversation: replies,
              auto_resolve_after: minutes,
            },
          },
        },
      });
      wrapper.findComponent(Button).vm.$emit('click');
      await flushPromises();
      expect(wrapper.emitted('submit')[0][0].config).toMatchObject({
        max_replies_per_conversation: Number(replies),
        auto_resolve_after: minutes,
      });
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
    const wrapper = shallowMount(AssistantSystemSettingsForm, {
      props: {
        assistant: {
          config: { auto_resolve_mode: 'disabled', auto_resolve_after: 1441 },
        },
      },
    });
    wrapper.findComponent(Button).vm.$emit('click');
    await flushPromises();
    expect(wrapper.emitted('submit')[0][0].config.auto_resolve_after).toBe(
      1441
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
