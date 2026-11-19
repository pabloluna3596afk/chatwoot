import { computed } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/integrations.json';
import es from 'dashboard/i18n/locale/es/integrations.json';
import assistantStore from 'dashboard/store/captain/assistant';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import DurationSelect from 'dashboard/components-next/captain/pageComponents/assistant/settings/DurationSelect.vue';
import Followup from './Followup.vue';

const mocks = vi.hoisted(() => ({ assistant: null, dispatch: vi.fn() }));
vi.mock(
  'dashboard/components-next/captain/pageComponents/assistant/settings/SettingsPageLayout.vue',
  () => ({ default: { template: '<div><slot /></div>' } })
);
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1', assistantId: '7' } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
  useMapGetter: () => computed(() => []),
  useFunctionGetter: () => computed(() => mocks.assistant),
}));
vi.mock('dashboard/api/variables', () => ({
  default: { catalog: async () => ({ data: { variables: [] } }) },
}));
vi.mock('dashboard/api/captain/inboxes', () => ({
  default: { get: async () => ({ data: { payload: [] } }) },
}));

describe.each(['en', 'es'])(
  'Closing and follow-up persistence (%s)',
  locale => {
    it('sends one PATCH with both edited clocks and the complete followup, without handoff or messaging', async () => {
      const followup = {
        inactivity_enabled: true,
        inactivity_after_minutes: 30,
        max_nudges: 1,
        close_after_minutes: 240,
        reengagement_enabled: true,
        reengagement_template: {
          name: 'volver',
          language: 'es',
          processed_params: { body: { 1: '{{ contact.name }}' } },
        },
      };
      mocks.assistant = {
        id: 7,
        name: 'Ada',
        config: {
          auto_resolve_after: 120,
          followup,
          messaging: { version: 2, revision: 4 },
          handoff_routing: { new: { mode: 'inbox', team_id: null } },
          handoff_priority: 'always',
          handoff_message: 'Transfer',
        },
      };
      window.history.replaceState(
        {},
        '',
        '/app/accounts/1/captain/assistants/7/settings/followup'
      );
      const patch = vi.fn(async () => ({ data: mocks.assistant }));
      vi.stubGlobal('axios', { patch });
      mocks.dispatch.mockImplementation((action, payload) => {
        if (action === 'captainAssistants/update') {
          return assistantStore.actions.update({ commit: vi.fn() }, payload);
        }
        return Promise.resolve();
      });
      const i18n = createI18n({ legacy: false, locale, messages: { en, es } });
      const wrapper = mount(Followup, {
        global: {
          plugins: [i18n],
          stubs: {
            SettingsPageLayout: { template: '<div><slot /></div>' },
            Editor: true,
          },
        },
      });
      await flushPromises();
      const duration = wrapper.findComponent(DurationSelect);
      expect(duration.props('modelValue')).toBe(120);
      expect(wrapper.text()).not.toContain('CAPTAIN.');
      expect(wrapper.text()).not.toContain('Howly');
      const mode = wrapper
        .findAllComponents(ComboBox)
        .find(item => item.attributes('data-testid') === 'closure-mode');
      expect(mode.props('options')[0].label).toContain('Ada');

      duration.vm.$emit('update:modelValue', 10);
      await flushPromises();
      const error = wrapper.get('[data-testid="closure-timing-error"]').text();
      expect(error).toBe(
        i18n.global.t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.AFTER_ERROR', {
          interval: 30,
          minutes: 10,
        })
      );
      await wrapper.get('[data-testid="followup-save"]').trigger('click');
      expect(patch).not.toHaveBeenCalled();
      const interval = wrapper
        .findAllComponents(ComboBox)
        .find(item => item.attributes('data-testid') === 'followup-after');
      expect(interval.props('options').some(option => option.value === 5)).toBe(
        true
      );
      interval.vm.$emit('update:modelValue', 5);
      await flushPromises();
      expect(
        wrapper.find('[data-testid="closure-timing-error"]').exists()
      ).toBe(false);
      await wrapper.get('[data-testid="followup-save"]').trigger('click');
      await flushPromises();

      expect(patch).toHaveBeenCalledTimes(1);
      const [url, payload] = patch.mock.calls[0];
      expect(url).toBe('/api/v1/accounts/1/captain/assistants/7');
      expect(payload).toEqual({
        config: {
          auto_resolve_mode: 'evaluated',
          auto_resolve_after: 10,
          completion_signal_enabled: false,
          completion_grace_minutes: 5,
          send_inactivity_resolution_message: true,
          resolution_message: undefined,
          followup: { ...followup, inactivity_after_minutes: 5 },
        },
      });
      wrapper.unmount();
      vi.unstubAllGlobals();
    });
  }
);
