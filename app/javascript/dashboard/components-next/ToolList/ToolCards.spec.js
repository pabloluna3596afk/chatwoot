import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import ToolCards from './ToolCards.vue';
import en from 'dashboard/i18n/locale/en/cannedMgmt.json';
import es from 'dashboard/i18n/locale/es/cannedMgmt.json';

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

const mountCards = (props, options = {}) =>
  mount(ToolCards, {
    props: { items: [canned], titleKey: 'short_code', ...props },
    global: { mocks: { $t: key => key } },
    ...options,
  });

describe('ToolCards', () => {
  it('shows readable variable labels while preserving source text in the tooltip', () => {
    const wrapper = mountCards({
      variableLabels: { 'contact.name': 'Nombre del contacto' },
    });

    expect(wrapper.find('.text-n-blue-12').text()).toBe('Nombre del contacto');
    expect(wrapper.find('.text-n-blue-12').attributes('title')).toBe(
      '{{contact.name}}'
    );
  });

  it.each([
    ['{{contact.email}}', 'Correo del contacto'],
    ['{{agent.name}}', 'Nombre del agente'],
    ['{{conversation.id}}', 'Número de conversación'],
    ['{{inbox.name}}', 'Nombre de la bandeja'],
    ['{{account.name}}', 'Nombre de la cuenta'],
    ['{{assistant.name}}', 'Nombre del asistente'],
    ['{{appointment.datetime}}', 'Fecha y hora de la cita'],
  ])(
    'renders localized labels for standard variable family %s',
    (token, label) => {
      const wrapper = mountCards({
        items: [{ ...canned, content: token }],
        variableLabels: {
          'contact.email': 'Correo del contacto',
          'agent.name': 'Nombre del agente',
          'conversation.id': 'Número de conversación',
          'inbox.name': 'Nombre de la bandeja',
          'account.name': 'Nombre de la cuenta',
          'assistant.name': 'Nombre del asistente',
          'appointment.datetime': 'Fecha y hora de la cita',
        },
      });

      expect(wrapper.find('.text-n-blue-12').text()).toBe(label);
      expect(wrapper.find('.text-n-blue-12').attributes('title')).toBe(token);
    }
  );

  it('labels an unknown custom attribute without changing its key or source', () => {
    const token = '{{ conversation.custom_attribute.monto }}';
    const wrapper = mountCards({
      items: [{ ...canned, content: token }],
      variableLabels: { 'contact.custom_attribute': 'Atributo' },
    });

    expect(wrapper.find('.text-n-blue-12').text()).toBe('Atributo: monto');
    expect(wrapper.find('.text-n-blue-12').attributes('title')).toBe(token);
  });

  it('keeps English and Spanish variable label keys in parity', () => {
    expect(Object.keys(es.CANNED_MGMT.VARIABLES).sort()).toEqual(
      Object.keys(en.CANNED_MGMT.VARIABLES).sort()
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

  it('closes the action menu on Escape and returns focus to its trigger', async () => {
    const wrapper = mountCards(
      {
        actions: [{ key: 'edit', label: 'Edit' }],
      },
      { attachTo: document.body }
    );
    const menu = wrapper.find('details');
    const trigger = menu.find('summary');
    menu.element.open = true;

    await trigger.trigger('keydown', { key: 'Escape' });

    expect(menu.element.open).toBe(false);
    expect(document.activeElement).toBe(trigger.element);
    wrapper.unmount();
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
