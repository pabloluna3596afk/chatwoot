import { nextTick } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import AssistantSystemSettingsForm from './AssistantSystemSettingsForm.vue';
import DurationSelect from './DurationSelect.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));

const assistant = {
  config: {
    product_name: 'Chatwoot',
    handoff_message: 'I will connect you with the team.',
    resolution_message: 'I will close this conversation for now.',
    auto_resolve_mode: 'evaluated',
    auto_resolve_after: 75,
    send_inactivity_resolution_message: true,
  },
};

const mountComponent = () =>
  shallowMount(AssistantSystemSettingsForm, {
    props: { assistant },
    global: { stubs: { Banner: false, SettingsToggleSection: false } },
  });

const submitForm = async wrapper => {
  wrapper.findComponent(Button).vm.$emit('click');
  await flushPromises();
};

describe('AssistantSystemSettingsForm', () => {
  it('explains which message is sent outside business hours', () => {
    expect(mountComponent().text()).toContain(
      'CAPTAIN.ASSISTANTS.FORM.HANDOFF_MESSAGE.OUTSIDE_HOURS_HELP'
    );
  });

  it('keeps only the goodbye message control in system settings', () => {
    const wrapper = mountComponent();
    expect(wrapper.findAllComponents(RadioCard)).toHaveLength(0);
    expect(wrapper.findAllComponents(DurationSelect)).toHaveLength(0);
    expect(wrapper.findAllComponents(Switch)).toHaveLength(1);
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.FORM.INACTIVITY_RESOLUTION.RESOLUTION_MESSAGE.TITLE'
    );
  });

  it('saves system messages without changing the mode or the inactivity timer', async () => {
    const wrapper = mountComponent();
    await submitForm(wrapper);

    expect(wrapper.emitted('submit')[0][0]).toEqual({
      config: {
        ...assistant.config,
        max_replies_per_conversation: 20,
      },
    });
  });

  it('saves the reply limit, 20 by default and 0 for no limit', async () => {
    const wrapper = mountComponent();
    expect(wrapper.findComponent(Input).props('modelValue')).toBe(20);

    wrapper.findComponent(Input).vm.$emit('update:modelValue', '0');
    await nextTick();
    await submitForm(wrapper);

    expect(
      wrapper.emitted('submit')[0][0].config.max_replies_per_conversation
    ).toBe(0);
  });

  it('does not save a negative reply limit', async () => {
    const wrapper = mountComponent();

    wrapper.findComponent(Input).vm.$emit('update:modelValue', '-3');
    await nextTick();
    await submitForm(wrapper);

    expect(wrapper.emitted('submit')).toBeUndefined();
  });
  it('does not render inactivity mode controls', () => {
    const wrapper = mountComponent();
    expect(wrapper.find('[role="radiogroup"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="followup-notice"]').exists()).toBe(
      false
    );
  });
});
