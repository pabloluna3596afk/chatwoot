import { mount, flushPromises } from '@vue/test-utils';
import Avatar from '../Avatar.vue';

const LIGHT_URL =
  'https://chat.example.com/assets/images/dashboard/captain/avatar-light.svg';
const DARK_URL =
  'https://chat.example.com/assets/images/dashboard/captain/avatar-dark.svg';

const global = { stubs: { ChannelIcon: true } };

describe('Avatar with the default Captain assistant image', () => {
  afterEach(() => document.body.classList.remove('dark'));

  it('shows the light image in light mode', () => {
    const wrapper = mount(Avatar, {
      props: { name: 'Acme', src: LIGHT_URL, roundedFull: true },
      global,
    });

    expect(wrapper.find('img').attributes('src')).toBe(LIGHT_URL);
  });

  it('switches to the dark image when the page goes dark and back', async () => {
    const wrapper = mount(Avatar, {
      props: { name: 'Acme', src: LIGHT_URL, roundedFull: true },
      global,
    });

    document.body.classList.add('dark');
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });
    await flushPromises();
    expect(wrapper.find('img').attributes('src')).toBe(DARK_URL);

    document.body.classList.remove('dark');
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });
    await flushPromises();
    expect(wrapper.find('img').attributes('src')).toBe(LIGHT_URL);
  });

  it('keeps an uploaded photo in dark mode', async () => {
    document.body.classList.add('dark');
    const photo = 'https://chat.example.com/rails/active_storage/photo.png';
    const wrapper = mount(Avatar, {
      props: { name: 'Acme', src: photo },
      global,
    });
    await flushPromises();

    expect(wrapper.find('img').attributes('src')).toBe(photo);
  });
});
