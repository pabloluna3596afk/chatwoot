import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { describe, expect, it, vi } from 'vitest';
import VueDOMPurifyHTML from 'vue-dompurify-html';
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
    global: { mocks: { $t: key => key }, plugins: [VueDOMPurifyHTML] },
    ...options,
  });

describe('ToolCards', () => {
  it('renders the markdown of a response: bold, line breaks and lists', () => {
    const wrapper = mountCards({
      items: [
        {
          ...canned,
          content:
            '**5X MATRIX**\n\n- Fuerza\n- Recuperación\n\nHola {{contact.name}}',
        },
      ],
      variableLabels: { 'contact.name': 'Nombre del contacto' },
    });

    expect(wrapper.find('strong').text()).toBe('5X MATRIX');
    expect(wrapper.findAll('li').map(item => item.text())).toEqual([
      'Fuerza',
      'Recuperación',
    ]);
    expect(wrapper.text()).not.toContain('**');
    expect(wrapper.find('.text-n-blue-12').text()).toBe('Nombre del contacto');
  });

  it('does not render scripts or event handlers typed in a response', () => {
    const wrapper = mountCards({
      items: [
        {
          ...canned,
          content: '<img src=x onerror="alert(1)"><script>alert(2)</script>ok',
        },
      ],
    });

    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.find('script').exists()).toBe(false);
    expect(wrapper.text()).toContain('ok');
  });

  // jsdom has no layout: fake the measured heights (scrollHeight / clientHeight).
  const stubHeights = (scroll, client) => {
    vi.spyOn(HTMLElement.prototype, 'scrollHeight', 'get').mockReturnValue(
      scroll
    );
    vi.spyOn(HTMLElement.prototype, 'clientHeight', 'get').mockReturnValue(
      client
    );
  };
  const mountMeasured = async (props, heights) => {
    stubHeights(...heights);
    const wrapper = mountCards(props);
    await nextTick();
    await nextTick();
    return wrapper;
  };

  it('does not expand a short note whose text fits (160/160), even with many line breaks', async () => {
    const wrapper = await mountMeasured(
      {
        items: [
          { ...canned, content: 'hola\n\nfr\n\nfr\n\nfr\n\nfr\n\nfr\n\nfr' },
        ],
      },
      [160, 160]
    );
    const textButton = wrapper.find('[data-card-content] button');

    expect(textButton.classes().join(' ')).not.toContain(
      'group-hover/content:invisible'
    );
    expect(wrapper.find('[data-card-content] .absolute').exists()).toBe(false);
    expect(wrapper.find('[aria-expanded]').exists()).toBe(false);
    vi.restoreAllMocks();
  });

  it('expands a card whose text is really cut (200/120): overlay on hover and a «show more» button', async () => {
    const wrapper = await mountMeasured(
      { items: [{ ...canned, content: 'Respuesta larga. '.repeat(40) }] },
      [200, 120]
    );
    const textButton = wrapper.find('[data-card-content] button');

    expect(textButton.classes().join(' ')).toContain(
      'group-hover/content:invisible'
    );
    expect(wrapper.find('[data-card-content] .absolute').exists()).toBe(true);
    expect(wrapper.find('[aria-expanded]').exists()).toBe(true);
    vi.restoreAllMocks();
  });

  it('keeps the action menu above the hover overlay of the card', async () => {
    const wrapper = await mountMeasured(
      {
        actions: [{ key: 'edit', label: 'Edit' }],
        items: [{ ...canned, content: 'Respuesta larga. '.repeat(40) }],
      },
      [200, 120]
    );

    expect(wrapper.find('details').classes()).toContain('z-30');
    expect(wrapper.find('[data-card-content] .absolute').classes()).toContain(
      'z-20'
    );
    vi.restoreAllMocks();
  });

  it('keeps an expanded card expanded after it is measured again', async () => {
    const wrapper = await mountMeasured(
      { items: [{ ...canned, content: 'Respuesta larga. '.repeat(40) }] },
      [200, 120]
    );
    const toggle = wrapper.find('[aria-expanded]');

    await toggle.trigger('click');
    stubHeights(200, 200);
    wrapper.vm.$forceUpdate();
    await nextTick();
    await nextTick();

    expect(wrapper.find('[aria-expanded]').exists()).toBe(true);
    expect(wrapper.find('[aria-expanded]').attributes('aria-expanded')).toBe(
      'true'
    );
    vi.restoreAllMocks();
  });

  it('renders no footer for a card without creator or approver', async () => {
    const wrapper = await mountMeasured(
      { items: [{ ...canned, created_by: null }] },
      [100, 100]
    );

    expect(wrapper.find('footer').exists()).toBe(false);
    vi.restoreAllMocks();
  });

  it('hangs the footer of a short card below it on hover devices, without taking space', async () => {
    const wrapper = await mountMeasured({ items: [canned] }, [100, 100]);
    const classes = wrapper.find('footer').classes().join(' ');

    expect(classes).toContain('[@media(hover:hover)]:absolute');
    expect(classes).toContain('[@media(hover:hover)]:top-full');
    expect(classes).toContain('[@media(hover:hover)]:opacity-0');
    vi.restoreAllMocks();
  });

  it('shows the trace once on a truncated card (overlay) and keeps the footer for screen readers', async () => {
    const wrapper = await mountMeasured(
      { items: [{ ...canned, content: 'Respuesta larga. '.repeat(40) }] },
      [200, 120]
    );

    expect(wrapper.find('footer').classes().join(' ')).toContain(
      '[@media(hover:hover)]:sr-only'
    );
    vi.restoreAllMocks();
  });
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

  it('closes the action menu when the user clicks outside of it', async () => {
    const wrapper = mountCards(
      { actions: [{ key: 'edit', label: 'Edit' }] },
      { attachTo: document.body }
    );
    const menu = wrapper.find('details');
    menu.element.open = true;
    document.body.click();
    await wrapper.vm.$nextTick();
    expect(menu.element.open).toBe(false);
    wrapper.unmount();
  });
  it('keeps the action menu open when clicking inside it', async () => {
    const wrapper = mountCards(
      { actions: [{ key: 'edit', label: 'Edit' }] },
      { attachTo: document.body }
    );
    const menu = wrapper.find('details');
    menu.element.open = true;
    menu.find('summary').element.click();
    await wrapper.vm.$nextTick();
    expect(wrapper.find('details').exists()).toBe(true);
    wrapper.unmount();
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
    const wrapper = await mountMeasured({ items: [longResponse] }, [200, 120]);
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

  it('keeps a hovered card, and a card with its menu open, above the neighbor menus', async () => {
    const wrapper = await mountMeasured({ items: [canned] }, [100, 100]);
    const classes = wrapper.find('article').classes().join(' ');

    expect(classes).toContain('hover:z-40');
    expect(classes).toContain('focus-within:z-40');
    expect(classes).toContain('has-[details[open]]:z-50');
    // neighbor action menus sit at z-30, below a hovered card (z-40)
    expect(wrapper.find('details').classes()).toContain('z-30');
    vi.restoreAllMocks();
  });
});
