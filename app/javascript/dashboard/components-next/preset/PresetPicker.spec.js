import { mount } from '@vue/test-utils';
import PresetPicker from './PresetPicker.vue';

const items = [
  {
    id: 'welcome',
    group: 'messages',
    title: 'Welcome',
    description: 'Greet customers',
    tags: [{ label: 'UTILITY' }],
    actionLabel: 'Use',
  },
  {
    id: 'followup',
    group: 'messages',
    title: 'Follow up',
    description: 'Check in later',
    tags: [{ label: 'MARKETING' }],
    actionLabel: 'Use',
  },
  {
    id: 'rule',
    group: 'rules',
    title: 'Assign a team',
    description: 'Route conversations',
    tags: [{ label: 'AUTOMATION' }],
    actionLabel: 'Apply',
  },
];

const mountPicker = (props = {}, slots = {}) =>
  mount(PresetPicker, {
    props: { items, ...props },
    slots,
    global: { mocks: { $t: key => key } },
  });

describe('PresetPicker', () => {
  it('renders cards in their groups and uses one list when groups are omitted', () => {
    const wrapper = mountPicker({
      groups: [
        { id: 'messages', label: 'Messages' },
        { id: 'rules', label: 'Rules' },
      ],
    });

    expect(wrapper.findAll('section')).toHaveLength(2);
    expect(wrapper.text()).toContain('Messages');
    expect(wrapper.text()).toContain('Assign a team');
    expect(mountPicker().findAll('section')).toHaveLength(1);
  });

  it('filters by title, description and tag label', async () => {
    const wrapper = mountPicker({ searchable: true });
    const input = wrapper.get('input[type="search"]');

    await input.setValue('marketing');
    expect(wrapper.text()).toContain('Follow up');
    expect(wrapper.text()).not.toContain('Welcome');

    await input.setValue('route conversations');
    expect(wrapper.text()).toContain('Assign a team');
    expect(wrapper.text()).not.toContain('Follow up');
  });

  it('emits the full item when a card is applied', async () => {
    const wrapper = mountPicker();

    await wrapper.get('[data-testid="preset-welcome"] button').trigger('click');

    expect(wrapper.emitted('apply')).toEqual([[items[0]]]);
  });

  it('forwards preview and meta slots and supports a custom card slot', () => {
    const wrapper = mountPicker(
      {},
      {
        preview: '<p class="preview-slot">Preview</p>',
        meta: '<p class="meta-slot">Requirements</p>',
      }
    );

    expect(wrapper.findAll('.preview-slot')).toHaveLength(items.length);
    expect(wrapper.findAll('.meta-slot')).toHaveLength(items.length);

    const customCard = mountPicker(
      {},
      {
        card: '<div class="custom-card">{{ item.title }}</div>',
      }
    );
    expect(customCard.findAll('.custom-card')).toHaveLength(items.length);
    expect(customCard.text()).toContain('Welcome');
  });

  it('shows the empty state when the search has no matches', async () => {
    const wrapper = mountPicker({
      searchable: true,
      emptyText: 'Nothing here',
    });

    await wrapper.get('input[type="search"]').setValue('missing preset');

    expect(wrapper.text()).toContain('Nothing here');
    expect(wrapper.get('[role="status"]').exists()).toBe(true);
  });
});
