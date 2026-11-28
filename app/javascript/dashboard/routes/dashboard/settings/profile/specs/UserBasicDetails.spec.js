import { mount } from '@vue/test-utils';
import UserBasicDetails from '../UserBasicDetails.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const mountForm = () =>
  mount(UserBasicDetails, {
    props: { name: 'Agent', email: 'agent@example.com', emailEnabled: true },
    global: { mocks: { $t: key => key } },
  });

describe('UserBasicDetails email verification', () => {
  it('allows ordinary profile edits without asking for a password', async () => {
    const wrapper = mountForm();
    expect(wrapper.find('input[type="password"]').exists()).toBe(false);
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('updateUser')[0][0]).toMatchObject({
      email: 'agent@example.com',
      currentPassword: undefined,
    });
  });

  it('requires the current password for a changed email and sends it', async () => {
    const wrapper = mountForm();
    await wrapper.findAll('input')[2].setValue('new@example.com');
    expect(wrapper.find('input[type="password"]').exists()).toBe(true);
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('updateUser')).toBeUndefined();
    await wrapper.find('input[type="password"]').setValue('CurrentPassword1!');
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('updateUser')[0][0]).toMatchObject({
      email: 'new@example.com',
      currentPassword: 'CurrentPassword1!',
    });
  });

  it('clears the password when the original email is restored', async () => {
    const wrapper = mountForm();
    await wrapper.findAll('input')[2].setValue('new@example.com');
    await wrapper.find('input[type="password"]').setValue('CurrentPassword1!');
    await wrapper.findAll('input')[2].setValue('agent@example.com');
    expect(wrapper.find('input[type="password"]').exists()).toBe(false);
    await wrapper.findAll('input')[2].setValue('other@example.com');
    expect(wrapper.find('input[type="password"]').element.value).toBe('');
  });
});
