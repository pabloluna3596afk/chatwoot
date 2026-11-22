import { mount } from '@vue/test-utils';
import Snackbar from './Snackbar.vue';

describe('Snackbar actions', () => {
  it('runs a callback only when its action is clicked', async () => {
    const onClick = vi.fn();
    const wrapper = mount(Snackbar, {
      props: {
        message: 'Saved locally',
        action: { type: 'callback', message: 'View in Templates', onClick },
      },
      global: { stubs: { RouterLink: true } },
    });
    expect(onClick).not.toHaveBeenCalled();
    expect(wrapper.get('button').text()).toBe('View in Templates');
    await wrapper.get('button').trigger('click');
    expect(onClick).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it('preserves existing link actions', () => {
    const wrapper = mount(Snackbar, {
      props: {
        message: 'Saved',
        action: { type: 'link', message: 'Open', to: '/app/accounts/1' },
      },
      global: {
        stubs: {
          RouterLink: { props: ['to'], template: '<a :href="to"><slot /></a>' },
        },
      },
    });
    expect(wrapper.get('a').attributes('href')).toBe('/app/accounts/1');
    expect(wrapper.get('a').text()).toBe('Open');
    expect(wrapper.find('button').exists()).toBe(false);
    wrapper.unmount();
  });
});
