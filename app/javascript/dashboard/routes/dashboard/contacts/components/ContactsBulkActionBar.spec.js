import { mount } from '@vue/test-utils';
import ContactsBulkActionBar from './ContactsBulkActionBar.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const mountBar = () =>
  mount(ContactsBulkActionBar, {
    props: {
      visibleContactIds: [1, 2, 3],
      selectedContactIds: [1, 2],
      totalMatchingCount: 3,
    },
    global: {
      stubs: {
        BulkSelectBar: {
          props: [
            'selectedCountLabel',
            'mobileSelectedCount',
            'compactSelection',
          ],
          template:
            '<div data-test="bulk-select" :data-count="selectedCountLabel" :data-mobile-count="mobileSelectedCount" :data-compact="compactSelection"><slot name="primaryActions"/><slot name="actions"/></div>',
        },
        Button: {
          props: ['label', 'icon', 'ariaLabel', 'title'],
          emits: ['click'],
          template:
            '<button :aria-label="ariaLabel" :title="title" :data-label="label" :data-icon="icon" @click="$emit(\'click\')">{{ label }}</button>',
        },
        BulkLabelActions: {
          props: ['action'],
          emits: ['assign', 'remove'],
          template:
            "<button :data-action=\"action || 'assign'\" @click=\"$emit(action === 'remove' ? 'remove' : 'assign', ['vip'])\">labels</button>",
        },
        Policy: { template: '<div><slot /></div>' },
      },
    },
  });

describe('ContactsBulkActionBar', () => {
  it('shows the selected count and uses a compact mobile selection action', () => {
    const wrapper = mountBar();

    expect(wrapper.get('[data-test="bulk-select"]').attributes()).toMatchObject(
      {
        'data-count': 'CONTACTS_BULK_ACTIONS.SELECTED_COUNT',
        'data-mobile-count': '2',
      }
    );
    expect(
      wrapper.get('[data-test="bulk-select"]').attributes('data-compact')
    ).toBeDefined();
    expect(wrapper.get('[data-test="bulk-select"]').classes()).toContain(
      'max-md:fixed'
    );
    expect(wrapper.get('[data-test="bulk-select"]').classes()).toContain(
      'max-md:bottom-[calc(env(safe-area-inset-bottom)+4.5rem)]'
    );
  });

  it('uses an accessible icon for selecting every matching contact', () => {
    const wrapper = mountBar();
    const selectMatching = wrapper.get(
      '[data-label="CONTACTS_BULK_ACTIONS.SELECT_ALL_MATCHING"]'
    );

    expect(selectMatching.attributes('data-icon')).toBe('i-lucide-check-check');
    expect(selectMatching.attributes('title')).toBe(
      'CONTACTS_BULK_ACTIONS.SELECT_ALL_MATCHING_ACCESSIBILITY'
    );
    expect(selectMatching.attributes('aria-label')).toBe(
      'CONTACTS_BULK_ACTIONS.SELECT_ALL_MATCHING_ACCESSIBILITY'
    );
  });

  it('emits clear, label, and delete actions', async () => {
    const wrapper = mountBar();
    await wrapper
      .get('[data-label="CONTACTS_BULK_ACTIONS.CLEAR_SELECTION"]')
      .trigger('click');
    await wrapper.get('[data-action="assign"]').trigger('click');
    await wrapper.get('[data-action="remove"]').trigger('click');
    await wrapper
      .get('[data-label="CONTACTS_BULK_ACTIONS.DELETE_CONTACTS"]')
      .trigger('click');

    expect(wrapper.emitted('clearSelection')).toHaveLength(1);
    expect(wrapper.emitted('assignLabels')).toEqual([[['vip']]]);
    expect(wrapper.emitted('removeLabels')).toEqual([[['vip']]]);
    expect(wrapper.emitted('deleteSelected')).toHaveLength(1);
  });
});
