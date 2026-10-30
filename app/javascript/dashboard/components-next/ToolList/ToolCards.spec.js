import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import ToolCards from './ToolCards.vue';

const canned = {
  id: 7,
  short_code: 'saludo',
  content: 'Hola {{contact.name}}, gracias por escribir.',
  category: 'Saludo',
  approval_status: 'pending',
  visibility: 'personal',
  created_by: { available_name: 'Ana' },
  created_at: '2026-10-24T12:00:00Z',
};

const mountCards = props =>
  mount(ToolCards, {
    props: { items: [canned], titleKey: 'short_code', ...props },
    global: { mocks: { $t: key => key } },
  });

describe('ToolCards', () => {
  it('shows readable variable labels while preserving source text in the tooltip', () => {
    const wrapper = mountCards({
      variableLabels: { 'contact.name': 'Nombre del contacto' },
    });

    expect(wrapper.find('.text-n-brand').text()).toBe('Nombre del contacto');
    expect(wrapper.find('.text-n-brand').attributes('title')).toBe(
      '{{contact.name}}'
    );
  });

  it('shows the card actions with icons and emits the selected action', async () => {
    const wrapper = mountCards({
      actions: [{ key: 'duplicate', label: 'Duplicar', icon: 'i-lucide-copy' }],
    });

    expect(wrapper.find('[role="menuitem"] .i-lucide-copy').exists()).toBe(
      true
    );
    await wrapper.find('[role="menuitem"]').trigger('click');
    expect(wrapper.emitted('action')[0][0]).toEqual({
      action: 'duplicate',
      item: canned,
    });
  });

  it('expands a long response in place for touch screens', async () => {
    const longResponse = { ...canned, content: 'Respuesta larga. '.repeat(40) };
    const wrapper = mountCards({ items: [longResponse] });
    const toggle = wrapper.find('[aria-expanded]');

    expect(toggle.attributes('aria-expanded')).toBe('false');
    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('true');
    expect(wrapper.find('.line-clamp-none').exists()).toBe(true);
  });

  it('provides icon labels, short trace text and the copy confirmation live region', async () => {
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: vi.fn().mockResolvedValue() },
    });
    const wrapper = mountCards({
      statusKey: 'approval_status',
      statusLabel: () => 'Pendiente',
      visibilityLabel: () => 'Personal',
      createdAt: () => '24 oct 2026',
      creatorLabel: 'Creó',
      copiedLabel: 'Copiado',
    });

    expect(wrapper.find('[aria-label="Pendiente"]').exists()).toBe(true);
    expect(wrapper.find('[aria-label="Personal"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Creó Ana · 24 oct 2026');
    await wrapper.find('button[title="Copy"]').trigger('click');
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(canned.content);
    expect(wrapper.find('[aria-live="polite"]').text()).toBe('Copiado');
  });
});
