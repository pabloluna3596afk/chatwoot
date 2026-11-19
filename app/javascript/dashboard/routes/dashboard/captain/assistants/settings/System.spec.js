import { computed } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import AssistantSystemSettingsForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantSystemSettingsForm.vue';
import System from './System.vue';

const mocks = vi.hoisted(() => ({ dispatch: vi.fn() }));
vi.mock(
  'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue',
  () => ({ default: { template: '<div><slot /></div>' } })
);
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { assistantId: '7' } }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
  useMapGetter: () => computed(() => []),
  useFunctionGetter: () =>
    computed(() => ({
      id: 7,
      config: { messaging: { version: 2, revision: 4 } },
    })),
}));

describe('Handoff settings persistence', () => {
  it.each([403, 409])(
    'preserves the draft after a %s response',
    async status => {
      mocks.dispatch.mockImplementation(action =>
        action === 'teams/get'
          ? Promise.resolve()
          : Promise.reject(
              Object.assign(new Error('Save rejected'), {
                response: { status },
              })
            )
      );
      const wrapper = shallowMount(System, {
        global: {
          stubs: {
            SettingsPageLayout: { template: '<div><slot /></div>' },
            AssistantSystemSettingsForm: false,
            SettingsToggleSection: false,
          },
        },
      });
      await flushPromises();
      const form = wrapper.findComponent(AssistantSystemSettingsForm);
      await form.find('input[value="on_signal"]').setValue();
      form.findComponent(Button).vm.$emit('click');
      await flushPromises();
      expect(mocks.dispatch).toHaveBeenCalledWith('captainAssistants/update', {
        id: 7,
        config: {
          handoff_message: undefined,
          max_replies_per_conversation: 20,
          handoff_routing: {
            new: { mode: 'inbox', team_id: null },
            reopened: { mode: 'inbox', team_id: null },
          },
          handoff_priority: 'on_signal',
        },
      });
      expect(form.find('input[value="on_signal"]').element.checked).toBe(true);
      expect(useAlert).toHaveBeenCalledWith(
        status === 403
          ? 'CAPTAIN.ASSISTANTS.EDIT.NO_PERMISSION'
          : 'Save rejected'
      );
      wrapper.unmount();
    }
  );
});
