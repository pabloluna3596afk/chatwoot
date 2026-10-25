import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import Switch from './Switch.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('Switch', () => {
  it('has a 44 px touch target on small screens while keeping its desktop size', () => {
    const wrapper = mount(Switch);

    expect(wrapper.classes()).toContain('max-sm:!h-11');
    expect(wrapper.classes()).toContain('max-sm:!w-11');
    expect(wrapper.classes()).toContain('h-4');
    expect(wrapper.classes()).toContain('w-7');
  });
});
