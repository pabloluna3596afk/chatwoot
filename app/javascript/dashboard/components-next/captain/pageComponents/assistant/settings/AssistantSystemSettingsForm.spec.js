import { computed, nextTick } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import AssistantSystemSettingsForm from './AssistantSystemSettingsForm.vue';
import DurationSelect from './DurationSelect.vue';
import HandoffRoutingRow from './HandoffRoutingRow.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const teamsState = vi.hoisted(() => ({ teams: [], dispatch: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: teamsState.dispatch }),
  useMapGetter: () => computed(() => teamsState.teams),
}));
beforeEach(() => {
  teamsState.teams = [{ id: 7, name: 'Support' }];
  teamsState.dispatch.mockReset().mockResolvedValue();
});

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

const mountComponent = (props = {}) =>
  shallowMount(AssistantSystemSettingsForm, {
    props: { assistant, ...props },
    global: {
      stubs: {
        Banner: false,
        SettingsToggleSection: false,
        HandoffRoutingRow: false,
      },
    },
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
        handoff_message: assistant.config.handoff_message,
        resolution_message: assistant.config.resolution_message,
        send_inactivity_resolution_message: true,
        handoff_routing: {
          new: { mode: 'inbox', team_id: null },
          reopened: { mode: 'inbox', team_id: null },
        },
        handoff_priority: 'off',
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
  it('renders only the three handoff priority radios and no native selects', () => {
    const wrapper = mountComponent();
    expect(
      wrapper.findAll('input[type="radio"]').map(input => input.element.value)
    ).toEqual(['off', 'on_signal', 'always']);
    expect(wrapper.find('input[value="off"]').element.checked).toBe(true);
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('shows the fixed team picker and blocks a missing team on save', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    const row = wrapper.findComponent(HandoffRoutingRow);
    expect(row.findAllComponents(ComboBox)).toHaveLength(1);
    row.findComponent(ComboBox).vm.$emit('update:modelValue', 'team');
    await nextTick();
    expect(row.findAllComponents(ComboBox)).toHaveLength(2);
    await submitForm(wrapper);
    expect(wrapper.emitted('submit')).toBeUndefined();
    expect(row.findAllComponents(ComboBox)[1].props('message')).toBe(
      'CAPTAIN.ASSISTANTS.FORM.HANDOFF_ROUTING.TEAM_REQUIRED'
    );
    row.findAllComponents(ComboBox)[1].vm.$emit('update:modelValue', 7);
    await nextTick();
    await wrapper.find('input[value="always"]').setValue();
    await submitForm(wrapper);
    expect(wrapper.emitted('submit')[0][0].config).toMatchObject({
      handoff_routing: { new: { mode: 'team', team_id: 7 } },
      handoff_priority: 'always',
    });
    row.findComponent(ComboBox).vm.$emit('update:modelValue', 'inbox');
    await nextTick();
    expect(row.findAllComponents(ComboBox)).toHaveLength(1);
  });

  it('preserves a deleted team draft and blocks save until it is replaced', async () => {
    const wrapper = mountComponent({
      assistant: {
        config: { handoff_routing: { new: { mode: 'team', team_id: 99 } } },
      },
    });
    await flushPromises();
    const picker = wrapper
      .findComponent(HandoffRoutingRow)
      .findAllComponents(ComboBox)[1];
    expect(picker.props('displayLabel')).toBe(
      'CAPTAIN.ASSISTANTS.FORM.HANDOFF_ROUTING.TEAM_DELETED'
    );
    await submitForm(wrapper);
    expect(wrapper.emitted('submit')).toBeUndefined();
    expect(picker.props('modelValue')).toBe(99);
    picker.vm.$emit('update:modelValue', 7);
    await nextTick();
    await submitForm(wrapper);
    expect(wrapper.emitted('submit')).toHaveLength(1);
  });

  it('shows a disabled team picker while loading and on error but saves inbox modes', async () => {
    let reject;
    teamsState.dispatch.mockImplementation(
      () =>
        new Promise((resolve, rejectPromise) => {
          reject = rejectPromise;
        })
    );
    const wrapper = mountComponent({
      assistant: {
        config: { handoff_routing: { new: { mode: 'team', team_id: 7 } } },
      },
    });
    const row = wrapper.findComponent(HandoffRoutingRow);
    const picker = row.findAllComponents(ComboBox)[1];
    expect(picker.props()).toMatchObject({
      disabled: true,
      placeholder: 'CAPTAIN.ASSISTANTS.FORM.HANDOFF_ROUTING.TEAMS_LOADING',
    });
    reject(new Error('Unavailable'));
    await flushPromises();
    expect(picker.props()).toMatchObject({
      disabled: true,
      placeholder: 'CAPTAIN.ASSISTANTS.FORM.HANDOFF_ROUTING.TEAMS_ERROR',
    });
    row.findComponent(ComboBox).vm.$emit('update:modelValue', 'inbox');
    await nextTick();
    await submitForm(wrapper);
    expect(wrapper.emitted('submit')).toHaveLength(1);
  });

  it('disables team modes in an empty account and explains how to create teams', async () => {
    teamsState.teams = [];
    const wrapper = mountComponent();
    await flushPromises();
    const row = wrapper.findComponent(HandoffRoutingRow);
    expect(
      row
        .findComponent(ComboBox)
        .props('options')
        .filter(option => option.disabled)
        .map(option => option.value)
    ).toEqual(['team', 'ai_team']);
    expect(row.text()).toContain(
      'CAPTAIN.ASSISTANTS.FORM.HANDOFF_ROUTING.NO_TEAMS'
    );
  });

  it.each(['team', 'ai_team'])(
    'warns about %s without eligible members and allows saving',
    async mode => {
      const wrapper = mountComponent({
        assistant: {
          config: {
            handoff_routing: {
              new: { mode, team_id: mode === 'team' ? 7 : null },
            },
          },
          eligible_team_ids: [],
        },
      });
      await flushPromises();
      expect(wrapper.findComponent(HandoffRoutingRow).text()).toContain(
        `CAPTAIN.ASSISTANTS.FORM.HANDOFF_ROUTING.${mode === 'team' ? 'TEAM_NO_MEMBERS' : 'AI_TEAM_NONE'}`
      );
      await submitForm(wrapper);
      expect(wrapper.emitted('submit')).toHaveLength(1);
    }
  );
});
