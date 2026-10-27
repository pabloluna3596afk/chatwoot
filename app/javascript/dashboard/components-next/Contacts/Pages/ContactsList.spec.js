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

const contacts = [
  { id: 9, name: 'Ana Contacto' },
  { id: 10, name: 'Luis Contacto' },
];

const mountList = selectedContactIds =>
  mount(ContactsList, {
    props: { contacts, selectedContactIds },
    global: {
      stubs: {
        ContactsTable: true,
        ContactsCard: {
          props: ['id', 'selectable', 'isSelected'],
          emits: ['select', 'avatarHover', 'toggle'],
          template: `<div data-test="card" :data-id="id"
            :data-selectable="selectable" :data-is-selected="isSelected">
            <button data-test="avatar" @click="$emit('select', !isSelected)"
              @mouseenter="$emit('avatarHover', true)"
              @mouseleave="$emit('avatarHover', false)">avatar</button>
            <button data-test="outside" @click="$emit('toggle')">outside</button>
          </div>`,
        },
      },
    },
  });

describe('ContactsList mobile selection', () => {
  it('shows checkboxes on every card while any contact is selected', () => {
    const wrapper = mountList([9]);

    expect(
      wrapper
        .findAll('[data-test="card"]')
        .map(card => card.attributes('data-selectable'))
    ).toEqual(['true', 'true']);
  });

  it('shows a checkbox on hover and hides it after leaving without selection', async () => {
    const wrapper = mountList([]);
    const firstAvatar = wrapper.findAll('[data-test="avatar"]')[0];

    expect(
      wrapper.findAll('[data-test="card"]')[0].attributes('data-selectable')
    ).toBe('false');

    await firstAvatar.trigger('mouseenter');
    expect(
      wrapper
        .findAll('[data-test="card"]')
        .map(card => card.attributes('data-selectable'))
    ).toEqual(['true', 'false']);

    await firstAvatar.trigger('mouseleave');
    expect(
      wrapper
        .findAll('[data-test="card"]')
        .map(card => card.attributes('data-selectable'))
    ).toEqual(['false', 'false']);
  });

  it('emits the contact id and checked state from the avatar selector', async () => {
    const wrapper = mountList([]);

    await wrapper.findAll('[data-test="avatar"]')[0].trigger('click');

    expect(wrapper.emitted('toggleContact')).toEqual([
      [{ id: 9, value: true }],
    ]);
  });

  it('keeps the desktop table selection event contract', async () => {
    const wrapper = mount(ContactsList, {
      props: { contacts, selectedContactIds: [] },
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
