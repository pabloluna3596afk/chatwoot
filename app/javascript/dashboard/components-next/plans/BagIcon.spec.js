import { mount } from '@vue/test-utils';
import BagIcon from './BagIcon.vue';

describe('BagIcon', () => {
  it.each([
    ['internal', 'i-lucide-sparkles'],
    ['captain_responses', 'i-woot-captain'],
    ['copilot', 'i-fluent-pen-sparkle-24-regular'],
  ])('uses the shared %s icon', (bag, icon) => {
    const wrapper = mount(BagIcon, { props: { bag } });

    expect(wrapper.classes()).toContain(icon);
    expect(wrapper.attributes('aria-hidden')).toBe('true');
  });
});
