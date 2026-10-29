import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import ToolCards from './ToolCards.vue';

const canned = {
  id: 7,
  short_code: 'saludo',
  content: 'Hola {{contact.name}}, gracias por escribir.',
  category: 'Saludo',
  approval_status: 'pending',
  visibility: 'personal',
  created_by: { available_name: 'Ana' },
  created_at: '28 oct',
};

const mountCards = props =>
  mount(ToolCards, {
    props: { items: [canned], titleKey: 'short_code', ...props },
    global: { mocks: { $t: key => key } },
  });

describe('ToolCards', () => {
  it('highlights template variables and displays trace details', () => {
    const wrapper = mountCards({ variant: 'keep' });

    expect(wrapper.find('.text-n-brand').text()).toBe('{{contact.name}}');
    expect(wrapper.text()).toContain('Created Ana · 28 oct');
    expect(wrapper.attributes('data-variant')).toBe('keep');
  });

  it('uses an accessible accordion and expands the complete response', async () => {
    const wrapper = mountCards({ variant: 'accordion' });
    const toggle = wrapper.find('[aria-expanded]');

    expect(toggle.attributes('aria-expanded')).toBe('false');
    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('true');
    expect(wrapper.text()).toContain('{{contact.name}}');
  });

  it('emits actions from the overflow menu', async () => {
    const wrapper = mountCards({
      actions: [{ key: 'duplicate', label: 'Duplicate' }],
    });

    await wrapper.find('[role="menuitem"]').trigger('click');
    expect(wrapper.emitted('action')[0][0]).toEqual({
      action: 'duplicate',
      item: canned,
    });
  });

  it('renders a selectable preview panel with the response metadata', () => {
    const wrapper = mountCards({
      variant: 'panel',
      statusKey: 'approval_status',
      statusLabel: item => item.approval_status,
    });

    expect(wrapper.find('[data-variant="panel"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Saludo');
    expect(wrapper.text()).toContain('pending');
    expect(wrapper.text()).toContain('personal');
    expect(wrapper.text()).toContain('{{contact.name}}');
  });
});
