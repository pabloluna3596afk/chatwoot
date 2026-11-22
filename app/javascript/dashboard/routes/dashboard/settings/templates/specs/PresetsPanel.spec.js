import { mount } from '@vue/test-utils';
import PresetsPanel from '../PresetsPanel.vue';
import { PRESETS, presetToForm } from '../presets';

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

  it('uses one external search and one category help, retaining accessible action names and internal title', async () => {
    const wrapper = mountPanel();
    await wrapper.setProps({ search: 'ITEMS.recordatorio_cita.TITLE' });
    expect(wrapper.findAll('[data-testid^="preset-"]')).toHaveLength(1);
    expect(wrapper.find('input').exists()).toBe(false);
    expect(wrapper.text().split('PRESETS.CATEGORY_NOTE.UTILITY')).toHaveLength(
      2
    );
    const button = wrapper.get('[data-testid="use-recordatorio_cita"]');
    expect(button.attributes('aria-label')).toContain(
      'ITEMS.recordatorio_cita.TITLE'
    );
    await button.trigger('click');
    const preset = wrapper.emitted('use')[0][0];
    expect(presetToForm(preset).title).toBe(preset.title);
    await wrapper.setProps({ search: 'no-matching-preset' });
    expect(wrapper.findAll('[data-testid^="preset-"]')).toHaveLength(0);
    expect(wrapper.get('[role="status"]').text()).not.toBe('');
    wrapper.unmount();
  });

  it('keeps category chips directly under the subtitle with wrapping and theme tokens', () => {
    const wrapper = mountPanel();
    const help = wrapper.get('[data-testid="category-help"]');
    expect(help.element.previousElementSibling.textContent).toContain(
      'PRESETS.DESCRIPTION'
    );
    expect(help.classes()).toContain('flex-wrap');
    expect(help.findAll('p')).toHaveLength(0);
    expect(help.findAll('[data-testid="category-chip"]')).toHaveLength(2);
    expect(help.find('.bg-n-teal-3.text-n-teal-11').exists()).toBe(true);
    expect(help.find('.bg-n-amber-3.text-n-amber-11').exists()).toBe(true);
    wrapper.unmount();
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
