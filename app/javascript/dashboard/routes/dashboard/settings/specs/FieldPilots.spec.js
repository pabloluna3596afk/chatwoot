import { mount } from '@vue/test-utils';
import TeamForm from '../teams/TeamForm.vue';
import UserBasicDetails from '../profile/UserBasicDetails.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

it('saves unit strings and boolean, and associates an invalid name', async () => {
  const onSubmit = vi.fn();
  const wrapper = mount(TeamForm, {
    props: {
      formData: {
        name: 'Support',
        description: 'Help',
        allow_auto_assign: false,
      },
      onSubmit,
    },
    global: { stubs: { Popover: true } },
  });
  expect(wrapper.get('label').element.control.tagName).toBe('INPUT');
  await wrapper.get('input[name="title"]').setValue('Sales');
  await wrapper.get('form').trigger('submit');
  expect(onSubmit).toHaveBeenCalledWith({
    name: 'Sales',
    description: 'Help',
    allow_auto_assign: false,
    icon: '',
    icon_color: '',
  });
  await wrapper.get('input[name="title"]').setValue('');
  await wrapper.get('input[name="title"]').trigger('blur');
  expect(wrapper.get('input[name="title"]').attributes('aria-invalid')).toBe(
    'true'
  );
  expect(wrapper.get('[role="alert"]').text()).toBeTruthy();
  await wrapper.get('form').trigger('submit');
  expect(onSubmit).toHaveBeenCalledTimes(1);
  wrapper.unmount();
});

it('saves profile strings and associates an invalid email', async () => {
  const wrapper = mount(UserBasicDetails, {
    props: {
      name: 'Agent',
      displayName: 'Support',
      email: 'agent@example.com',
      emailEnabled: true,
    },
  });
  expect(wrapper.get('label').element.control).toBe(
    wrapper.get('input').element
  );
  await wrapper.findAll('input')[0].setValue('Updated');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('updateUser')).toEqual([
    [{ name: 'Updated', displayName: 'Support', email: 'agent@example.com' }],
  ]);
  await wrapper.findAll('input')[2].setValue('invalid');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.findAll('input')[2].attributes('aria-invalid')).toBe('true');
  expect(wrapper.get('[role="alert"]').text()).toBe(
    'PROFILE_SETTINGS.FORM.EMAIL.ERROR'
  );
  expect(wrapper.emitted('updateUser')).toHaveLength(1);
  wrapper.unmount();
});
