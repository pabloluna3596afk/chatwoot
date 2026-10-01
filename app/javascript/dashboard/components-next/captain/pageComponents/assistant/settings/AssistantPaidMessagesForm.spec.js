import { mount } from '@vue/test-utils';
import AssistantPaidMessagesForm from './AssistantPaidMessagesForm.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mountForm = (config = {}) =>
  mount(AssistantPaidMessagesForm, {
    props: { assistant: { config: { product_name: 'Acme', ...config } } },
  });

const toggle = wrapper => wrapper.get('button[role="switch"]');
const save = wrapper =>
  wrapper.get('[data-testid="paid-messages-save"]').trigger('click');

describe('AssistantPaidMessagesForm', () => {
  it('is off by default and always shows that WhatsApp charges outside the 24 h window', () => {
    const wrapper = mountForm();

    expect(toggle(wrapper).attributes('aria-checked')).toBe('false');
    expect(wrapper.get('[data-testid="paid-messages-note"]').text()).toBe(
      'CAPTAIN.ASSISTANTS.FORM.PAID_MESSAGES.NOTE'
    );
  });

  it('saves it on, keeping the rest of the config', async () => {
    const wrapper = mountForm();
    await toggle(wrapper).trigger('click');

    await save(wrapper);

    expect(wrapper.emitted('submit')[0][0]).toEqual({
      config: { product_name: 'Acme', allow_paid_templates: true },
    });
  });

  it('shows the saved value and saves it off', async () => {
    const wrapper = mountForm({ allow_paid_templates: true });
    expect(toggle(wrapper).attributes('aria-checked')).toBe('true');

    await toggle(wrapper).trigger('click');
    await save(wrapper);

    expect(wrapper.emitted('submit')[0][0].config.allow_paid_templates).toBe(
      false
    );
  });
});
