import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ContactInfo from '../ContactInfo.vue';

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: { value: true } }),
}));
vi.mock('dashboard/composables/useFeaturedAttributes', () => ({
  useFeaturedAttributes: () => ({ featuredBadges: { value: [] } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const contact = {
  id: 9,
  name: 'Ana',
  phone_number: '+593999111222',
  created_at: 1700000000,
};

const mountInfo = () =>
  mount(ContactInfo, {
    props: { contact },
    global: {
      plugins: [
        createStore({
          getters: {
            getSelectedChat: () => ({ id: 1, meta: { sender: {} } }),
            'contacts/getUIFlags': () => ({}),
          },
          actions: { 'contacts/fetchContactableInbox': () => {} },
        }),
      ],
      mocks: { $t: key => key, $route: { params: { accountId: 1 } } },
      directives: { tooltip: () => {} },
      stubs: {
        ContactInfoRow: true,
        ViewAllConversations: true,
        Avatar: true,
        SocialIcons: true,
        EditContact: true,
        ContactMergeModal: true,
        ContactDeleteModal: true,
        ComposeConversation: true,
        VoiceCallButton: true,
        ContactAssigneeSelector: true,
        FeaturedAttributeBadges: true,
        NextButton: { template: '<button />' },
      },
    },
  });

describe('ContactInfo header menu', () => {
  it('lists profile, edit and creation date only after opening', async () => {
    const wrapper = mountInfo();
    expect(wrapper.vm.showHeaderMenu).toBe(false);
    await wrapper.get('[data-testid="contact-header-menu"]').trigger('click');
    const actions = wrapper.vm.headerMenuItems.map(item => item.action);
    expect(wrapper.vm.showHeaderMenu).toBe(true);
    expect(actions).toEqual(['profile', 'edit', 'created']);
  });

  it('opens the edit modal from the menu and closes it', () => {
    const wrapper = mountInfo();
    wrapper.vm.showHeaderMenu = true;
    wrapper.vm.onHeaderMenuAction({ action: 'edit' });
    expect(wrapper.vm.showEditModal).toBe(true);
    expect(wrapper.vm.showHeaderMenu).toBe(false);
  });

  it('opens the full profile in a new tab', () => {
    const open = vi.spyOn(window, 'open').mockImplementation(() => null);
    const wrapper = mountInfo();
    wrapper.vm.onHeaderMenuAction({ action: 'profile' });
    expect(open).toHaveBeenCalledWith(
      '/app/accounts/1/contacts/9',
      '_blank',
      'noopener,noreferrer'
    );
    open.mockRestore();
  });
});
