import { mount } from '@vue/test-utils';
import InfoChip from './InfoChip.vue';

describe('InfoChip', () => {
  it.each([
    ['neutral', 'bg-n-alpha-2', 'text-n-slate-11'],
    ['success', 'bg-n-teal-3', 'text-n-teal-11'],
    ['warning', 'bg-n-amber-3', 'text-n-amber-11'],
    ['error', 'bg-n-ruby-3', 'text-n-ruby-11'],
  ])('renders the %s tone and its content', (tone, background, foreground) => {
    const wrapper = mount(InfoChip, {
      props: { tone },
      slots: { default: 'Role' },
    });
    expect(wrapper.classes()).toEqual(
      expect.arrayContaining([background, foreground])
    );
    expect(wrapper.text()).toBe('Role');
  });

  it('defaults to neutral', () => {
    expect(mount(InfoChip).classes()).toContain('bg-n-alpha-2');
  });
});
