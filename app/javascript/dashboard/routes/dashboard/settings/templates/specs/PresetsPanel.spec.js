import { mount } from '@vue/test-utils';
import PresetsPanel from '../PresetsPanel.vue';
import { PRESETS } from '../presets';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false }),
}));

const mountPanel = () =>
  mount(PresetsPanel, {
    props: { inboxes: [{ id: 1, name: 'Soporte' }] },
    global: {
      mocks: { $t: key => key },
      stubs: { LibraryPanel: true },
    },
  });

describe('PresetsPanel', () => {
  it('shows a card per preset, with its category and the variables it uses', () => {
    const wrapper = mountPanel();

    PRESETS.forEach(preset => {
      expect(wrapper.find(`[data-testid="preset-${preset.id}"]`).exists()).toBe(
        true
      );
    });
    expect(wrapper.text()).toContain(
      '{{nombre}}'.replace(/[{}]/g, '') || 'nombre'
    );
  });

  it('opens the form with the preset the admin picked', async () => {
    const wrapper = mountPanel();

    await wrapper.get('[data-testid="use-recordatorio_cita"]').trigger('click');

    expect(wrapper.emitted('use')[0][0]).toMatchObject({
      id: 'recordatorio_cita',
    });
  });

  it('does not let the customer data preset be used yet', async () => {
    const wrapper = mountPanel();
    const button = wrapper.get('[data-testid="use-datos_cliente"]');

    expect(button.attributes('disabled')).toBeDefined();
    await button.trigger('click');
    expect(wrapper.emitted('use')).toBeUndefined();
  });
});
