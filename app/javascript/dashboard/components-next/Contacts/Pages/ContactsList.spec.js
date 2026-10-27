import { mount } from '@vue/test-utils';
import ContactsList from './ContactsList.vue';

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ({ value: { isUpdating: false } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
  useRoute: () => ({ name: 'contacts_dashboard_index', params: {}, query: {} }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const contact = { id: 9, name: 'Ana Contacto' };

describe('ContactsList mobile selection', () => {
  it('always exposes card selection and emits the id with checked state', async () => {
    const wrapper = mount(ContactsList, {
      props: { contacts: [contact], selectedContactIds: [] },
      global: {
        stubs: {
          ContactsTable: true,
          ContactsCard: {
            inheritAttrs: false,
            emits: ['select'],
            template:
              '<button data-test="select" :data-selectable="$attrs.selectable" @click="$emit(\'select\', true)">select</button>',
          },
        },
      },
    });

    expect(
      wrapper.get('[data-test="select"]').attributes('data-selectable')
    ).toBeDefined();
    await wrapper.get('[data-test="select"]').trigger('click');
    expect(wrapper.emitted('toggleContact')).toEqual([
      [{ id: 9, value: true }],
    ]);
  });

  it('passes selected state back to the card for unchecking', () => {
    const wrapper = mount(ContactsList, {
      props: { contacts: [contact], selectedContactIds: [9] },
      global: {
        stubs: {
          ContactsTable: true,
          ContactsCard: {
            inheritAttrs: false,
            template:
              '<div data-test="selection" :data-selectable="$attrs.selectable" :data-is-selected="$attrs[\'is-selected\']" />',
          },
        },
      },
    });

    expect(wrapper.get('[data-test="selection"]').attributes()).toMatchObject({
      'data-selectable': '',
      'data-is-selected': 'true',
    });
  });

  it('preserves the desktop table selection event contract', async () => {
    const wrapper = mount(ContactsList, {
      props: { contacts: [contact], selectedContactIds: [] },
      global: {
        stubs: {
          ContactsTable: {
            emits: ['toggleContact'],
            template:
              '<button data-test="table-select" @click="$emit(\'toggleContact\', { id: 9, value: true })">select</button>',
          },
          ContactsCard: true,
        },
      },
    });

    await wrapper.get('[data-test="table-select"]').trigger('click');
    expect(wrapper.emitted('toggleContact')).toEqual([
      [{ id: 9, value: true }],
    ]);
  });
});
