import { createI18n } from 'vue-i18n';
import { shallowMount } from '@vue/test-utils';
import en from 'dashboard/i18n/locale/en/integrations.json';
import es from 'dashboard/i18n/locale/es/integrations.json';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import AssistantSystemSettingsForm from './AssistantSystemSettingsForm.vue';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));

it.each([
  ['en', en, 'When the customer stops replying', 'Close the conversation'],
  ['es', es, 'Cuando el cliente no responde', 'Cerrar la conversación'],
])(
  'renders the unanswered policy in %s with interpolated assistant name',
  (locale, messages, label, close) => {
    const i18n = createI18n({
      legacy: false,
      locale,
      messages: { [locale]: messages },
      missingWarn: false,
      fallbackWarn: false,
    });
    const wrapper = shallowMount(AssistantSystemSettingsForm, {
      props: {
        assistant: {
          name: 'Sofía',
          config: {
            unanswered_action: 'close',
            followup: { inactivity_enabled: true },
          },
        },
      },
      global: { plugins: [i18n], stubs: { SettingsToggleSection: false } },
    });
    expect(wrapper.text()).toContain(label);
    expect(wrapper.findComponent('#unanswered-close').props('label')).toBe(
      close
    );
    expect(
      wrapper.get('[data-testid="unanswered-followup-notice"]').text()
    ).toContain('Sofía');
    expect(
      wrapper
        .findAllComponents(RadioCard)
        .filter(card => card.props('name') === 'unanswered-action')
    ).toHaveLength(3);
    wrapper.unmount();
  }
);

it('keeps exact en/es key parity for the new strings', () => {
  expect(
    Object.keys(en.CAPTAIN.ASSISTANTS.AUTO_RESOLVE.UNANSWERED_ACTION)
  ).toEqual(Object.keys(es.CAPTAIN.ASSISTANTS.AUTO_RESOLVE.UNANSWERED_ACTION));
  expect(
    Object.keys(en.CAPTAIN.ASSISTANTS.AUTO_RESOLVE.UNANSWERED_ACTION.OPTIONS)
  ).toEqual(
    Object.keys(es.CAPTAIN.ASSISTANTS.AUTO_RESOLVE.UNANSWERED_ACTION.OPTIONS)
  );
  [en, es].forEach(messages => {
    expect(messages.CAPTAIN.ASSISTANTS.FOLLOWUP.WINDOW_CLOSED_NOTICE).toContain(
      '{assistantName}'
    );
  });
});
