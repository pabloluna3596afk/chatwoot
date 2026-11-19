import { shallowMount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/integrations.json';
import es from 'dashboard/i18n/locale/es/integrations.json';
import ClosureSummary from './ClosureSummary.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1', assistantId: '2' } }),
}));

describe.each(['en', 'es'])('closure summary (%s)', locale => {
  it('derives the saved reminder and closing times, including a saved 120', async () => {
    const wrapper = shallowMount(ClosureSummary, {
      props: {
        config: {
          auto_resolve_after: 120,
          followup: { inactivity_after_minutes: 30, max_nudges: 2 },
        },
        linkToFollowup: true,
      },
      global: {
        plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
      },
    });
    expect(wrapper.text()).toContain('120');
    expect(wrapper.text()).toContain('30');
    expect(wrapper.text()).toContain('2');
    await wrapper.setProps({
      config: {
        auto_resolve_after: 30,
        followup: { inactivity_enabled: false },
      },
    });
    expect(wrapper.text()).not.toContain('120');
    expect(wrapper.text()).toContain('30');
    expect(wrapper.text()).not.toContain('CAPTAIN.');
  });

  it('explains that reminders still run with automatic closing disabled', () => {
    const i18n = createI18n({ legacy: false, locale, messages: { en, es } });
    const wrapper = shallowMount(ClosureSummary, {
      props: { config: { auto_resolve_mode: 'disabled' } },
      global: { plugins: [i18n] },
    });
    expect(wrapper.text()).toContain(
      i18n.global.t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.DISABLED_NUDGES')
    );
  });
});
