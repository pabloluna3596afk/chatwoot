import { mount } from '@vue/test-utils';
import ContactToolsBar from '../ContactToolsBar.vue';

const tools = [
  {
    key: 'captain',
    icon: 'i-woot-captain',
    tone: 'teal',
    label: 'Captain',
    legend: 'Responde: Aurora',
  },
  {
    key: 'calendar',
    icon: 'i-lucide-calendar',
    tone: 'blue',
    label: 'Citas',
    legend: 'Mañana 10:00 · Consulta',
  },
  {
    key: 'payment',
    icon: 'i-lucide-credit-card',
    tone: 'ruby',
    label: 'Pago pendiente',
    legend: 'Pendiente $25',
  },
  {
    key: 'cart',
    icon: 'i-lucide-shopping-cart',
    tone: 'iris',
    label: 'Carrito activo',
    legend: '3 productos',
  },
];

describe('ContactToolsBar', () => {
  it('renders each tool once, active rows first and idle icons together in one pill', async () => {
    const onClick = vi.fn();
    const wrapper = mount(ContactToolsBar, {
      props: {
        tools: tools.map((tool, i) => ({
          ...tool,
          state: i < 2 ? 'active' : 'idle',
          onClick,
        })),
      },
    });
    expect(
      wrapper.findAll('[data-tool]').map(item => item.attributes('data-tool'))
    ).toEqual(['captain', 'calendar', 'payment', 'cart']);
    expect(wrapper.find('[data-tool="captain"]').text()).toBe(
      'Responde: Aurora'
    );
    expect(wrapper.find('[data-tool="calendar"]').text()).toContain('Consulta');
    expect(wrapper.find('[data-tool="payment"]').text()).toBe('');
    expect(wrapper.find('[data-tool="payment"]').element.parentElement).toBe(
      wrapper.find('[data-tool="cart"]').element.parentElement
    );
    expect(wrapper.findAll('[data-testid="idle-tools"]')).toHaveLength(1);
    await wrapper.find('[data-tool="calendar"] .truncate').trigger('click');
    await wrapper.find('[data-tool="calendar"] .size-4').trigger('click');
    await wrapper.find('[data-tool="cart"]').trigger('click');
    expect(onClick).toHaveBeenCalledTimes(3);
  });

  it.each(['idle', 'active'])(
    'groups idle tools only when all tools are %s',
    state => {
      const wrapper = mount(ContactToolsBar, {
        props: { tools: tools.map(tool => ({ ...tool, state })) },
      });
      expect(wrapper.find('[data-testid="idle-tools"]').exists()).toBe(
        state === 'idle'
      );
      expect(wrapper.findAll('[data-tool]')).toHaveLength(4);
      expect(wrapper.text().includes('3 productos')).toBe(state === 'active');
    }
  );

  it('hides unavailable tools and uses amber for escalation', () => {
    const wrapper = mount(ContactToolsBar, {
      props: {
        tools: [
          { ...tools[0], state: 'warning' },
          { ...tools[1], state: 'hidden' },
        ],
      },
    });
    expect(wrapper.findAll('[data-tool]')).toHaveLength(1);
    expect(wrapper.find('.text-n-amber-11').exists()).toBe(true);
    expect(wrapper.find('button').attributes('title')).toBe('Captain');
  });

  it('renders nothing when all tools are hidden', () => {
    expect(
      mount(ContactToolsBar, {
        props: { tools: tools.map(tool => ({ ...tool, state: 'hidden' })) },
      })
        .find('[data-testid="contact-tools"]')
        .exists()
    ).toBe(false);
  });
});
