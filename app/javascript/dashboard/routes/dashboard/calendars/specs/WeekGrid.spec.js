import { vi } from 'vitest';
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: {} } }),
}));

import { mount } from '@vue/test-utils';
import WeekGrid from '../WeekGrid.vue';
import EventBlock from '../EventBlock.vue';

const events = ['a', 'b', 'c'].map(id => ({
  id,
  summary: `Cita · Patient ${id}`,
  start: '2030-01-15T10:00:00-05:00',
  end: '2030-01-15T10:30:00-05:00',
}));
const mountGrid = props =>
  mount(WeekGrid, {
    props: { weekStartKey: '2030-01-14', ...props },
    global: { mocks: { $t: key => key } },
  });

it.each([2, 3])(
  'renders %i equal lanes with names, full tooltips and minute geometry',
  async count => {
    const wrapper = mountGrid({ events: events.slice(0, count) });
    const blocks = wrapper.findAllComponents(EventBlock);
    expect(blocks).toHaveLength(count);
    expect(blocks[0].element.parentElement).not.toBe(
      blocks[1].element.parentElement
    );
    blocks.forEach(block => {
      expect(block.element.parentElement.classList.contains('flex-1')).toBe(
        true
      );
      expect(block.element.style.gridRow).toBe('1 / span 30');
      expect(block.props('compact')).toBe(true);
      expect(block.text()).toBe(`Patient ${block.props('event').id}`);
      expect(block.attributes('title')).toContain('10:00 – 10:30');
      expect(block.attributes('title')).toContain('Cita · Patient');
    });
    await blocks[0].trigger('click');
    await blocks[1].trigger('click');
    expect(wrapper.emitted('event-click').map(([event]) => event.id)).toEqual([
      'a',
      'b',
    ]);
    expect(wrapper.emitted('slotClick')).toBeUndefined();
    wrapper.unmount();
  }
);

it('renders midnight labels without substituting the default opening hour', () => {
  const wrapper = mountGrid({ hourStart: 0, hourEnd: 2 });
  expect(wrapper.text()).toContain('00:00');
  expect(wrapper.text()).toContain('00:30');
  expect(wrapper.text()).not.toContain('08:00');
  wrapper.unmount();
});

it('recalculates lanes when cancelled events are hidden', async () => {
  const wrapper = mountGrid({
    events: [events[0], { ...events[1], appointment_status: 'cancelled' }],
  });
  expect(wrapper.findAllComponents(EventBlock)).toHaveLength(2);
  await wrapper.setProps({ events: [events[0]] });
  const block = wrapper.getComponent(EventBlock);
  expect(block.element.parentElement.parentElement.children).toHaveLength(1);
  expect(block.props('compact')).toBe(false);
  expect(block.text()).toContain('10:00');
  expect(block.text()).toContain('Cita · Patient a');
  wrapper.unmount();
});

it('uses a uniform surface with subtle hour lines confined to the timed grid', () => {
  const wrapper = mountGrid({ events: [] });
  const columns = wrapper.findAll('[style*="grid-template-rows"]');
  expect(columns).toHaveLength(7);
  columns.forEach(column => {
    expect(column.element.style.gridTemplateRows.replace(/\s/g, '')).toBe(
      'repeat(720,minmax(0,calc(1rem/15)))'
    );
    expect(column.findAll('.border-b')).toHaveLength(12);
    expect(column.classes()).toContain('border-n-weak');
  });
  expect(wrapper.html()).not.toContain('even:bg');
  expect(wrapper.html()).not.toContain('row-start-[');
  expect(wrapper.html()).not.toContain('row-end-[');
  wrapper.unmount();
});

it('includes full title, all-day label and status on all-day blocks', () => {
  const wrapper = mountGrid({
    events: [{ ...events[0], all_day: true, appointment_status: 'confirmed' }],
  });
  expect(wrapper.get('button').attributes('title')).toBe(
    'Cita · Patient a\nSIDEBAR.CALENDAR_PAGE.ALL_DAY\nSIDEBAR.CALENDAR_PAGE.STATUS.CONFIRMED'
  );
  wrapper.unmount();
});
