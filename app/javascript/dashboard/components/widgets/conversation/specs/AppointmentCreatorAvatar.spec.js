import { shallowMount } from '@vue/test-utils';
import AppointmentCreatorAvatar from '../AppointmentCreatorAvatar.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => `${key} ${params?.name ?? ''}`.trim(),
  }),
}));

const mountAvatar = creator =>
  shallowMount(AppointmentCreatorAvatar, {
    props: { creator },
    global: { directives: { tooltip: {} } },
  });

describe('AppointmentCreatorAvatar', () => {
  it('shows the assistant with its photo inside the Captain ring', () => {
    const wrapper = mountAvatar({
      type: 'captain',
      name: 'Aurora',
      thumbnail: 'https://example.com/aurora.png',
    });

    expect(wrapper.find('[data-testid="creator-captain"]').exists()).toBe(true);
    const avatar = wrapper.findComponent({ name: 'Avatar' });
    expect(avatar.props('src')).toBe('https://example.com/aurora.png');
    expect(avatar.props('name')).toBe('Aurora');
  });

  it('shows the person without the ring', () => {
    const wrapper = mountAvatar({
      type: 'user',
      name: 'Pablo',
      thumbnail: 'https://example.com/pablo.png',
    });

    expect(wrapper.find('[data-testid="creator-user"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="creator-captain"]').exists()).toBe(
      false
    );
  });

  it('shows nothing when nobody is known', () => {
    expect(mountAvatar(null).find('span').exists()).toBe(false);
  });
});
