import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import ToolList from './ToolList.vue';
import InfoChip from 'dashboard/components-next/ListCard/InfoChip.vue';

describe('ToolList', () => {
  it('renders mobile cards and desktop table from the same items', () => {
    const wrapper = mount(ToolList, {
      props: {
        items: [{ id: 1, name: 'Horario' }],
        columns: [{ key: 'name', label: 'Nombre' }],
      },
    });
    expect(wrapper.find('article').text()).toContain('Horario');
    expect(wrapper.find('table').text()).toContain('Horario');
  });

  it('emits declarative actions and applies success and danger variants', async () => {
    const actions = [
      { key: 'approve', label: 'Aprobar', variant: 'success' },
      { key: 'reject', label: 'Rechazar', variant: 'danger' },
    ];
    const wrapper = mount(ToolList, {
      props: { items: [{ id: 1, name: 'Horario' }], actions },
    });
    const buttons = wrapper.findAll('[role="menuitem"]');
    expect(buttons[0].classes()).toContain('text-n-teal-11');
    expect(buttons[1].classes()).toContain('text-n-ruby-9');
    await buttons[0].trigger('click');
    expect(wrapper.emitted('action')[0][0]).toEqual({
      action: 'approve',
      item: { id: 1, name: 'Horario' },
    });
  });

  it('omits actions hidden for a given item without disabling other actions', () => {
    const wrapper = mount(ToolList, {
      props: {
        items: [{ id: 1 }, { id: 2 }],
        actions: [
          { key: 'edit', label: 'Edit' },
          {
            key: 'approve',
            label: 'Approve',
            visible: item => item.id === 1,
          },
        ],
      },
    });

    const menus = wrapper.findAll('[role="menu"]');
    expect(menus[0].text()).toContain('Approve');
    expect(menus[1].text()).not.toContain('Approve');
    expect(menus[1].text()).toContain('Edit');
  });

  it('renders reusable chips with neutral and status tones', () => {
    const wrapper = mount({
      components: { InfoChip },
      template: `
        <div>
          <InfoChip>Cuenta</InfoChip>
          <InfoChip tone="warning">Pendiente</InfoChip>
          <InfoChip tone="success">Aprobada</InfoChip>
          <InfoChip tone="error">Rechazada</InfoChip>
        </div>
      `,
    });
    const chips = wrapper.findAll('span');
    expect(chips[0].classes()).toContain('bg-n-alpha-2');
    expect(chips[1].classes()).toContain('bg-n-amber-3');
    expect(chips[1].classes()).toContain('text-n-amber-11');
    expect(chips[2].classes()).toContain('bg-n-teal-3');
    expect(chips[2].classes()).toContain('text-n-teal-11');
    expect(chips[3].classes()).toContain('bg-n-ruby-3');
    expect(chips[3].classes()).toContain('text-n-ruby-11');
  });

  it('announces loading, error and empty states and supports selection', async () => {
    const loading = mount(ToolList, { props: { loading: true } });
    expect(loading.find('[role="status"]').exists()).toBe(true);
    const failed = mount(ToolList, { props: { error: 'No se pudo cargar' } });
    expect(failed.find('[role="alert"]').text()).toBe('No se pudo cargar');
    const empty = mount(ToolList, {
      props: { emptyMessage: 'Sin respuestas' },
    });
    expect(empty.text()).toContain('Sin respuestas');
    const wrapper = mount(ToolList, {
      props: { selectable: true, items: [{ id: 9, name: 'X' }] },
    });
    await wrapper.find('input').setValue(true);
    expect(wrapper.emitted('select')[0][0].selected).toBe(true);
  });
});
