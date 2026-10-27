import { mount } from '@vue/test-utils';
import SaveStateButton from './SaveStateButton.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('./Button.vue', () => ({
  default: {
    inheritAttrs: false,
    props: ['label', 'icon', 'size', 'variant', 'color', 'isLoading'],
    emits: ['click'],
    template:
      '<button :disabled="$attrs.disabled" :aria-disabled="$attrs[\'aria-disabled\']" :title="$attrs.title" @click="$emit(\'click\')"><i :class="icon" /><span>{{ label }}</span><span v-if="isLoading">spinner</span></button>',
  },
}));

describe('SaveStateButton', () => {
  it('shows the clean disabled state and does not emit save', async () => {
    const wrapper = mount(SaveStateButton);
    expect(wrapper.text()).toContain('GENERAL.SAVE_STATE.CLEAN');
    expect(wrapper.attributes('aria-disabled')).toBe('true');
    await wrapper.trigger('click');
    expect(wrapper.emitted('save')).toBeUndefined();
  });

  it('allows a compact save action to keep the Save label when clean', () => {
    const wrapper = mount(SaveStateButton, {
      props: { labelClean: 'GENERAL.SAVE_STATE.SAVE' },
    });
    expect(wrapper.text()).toContain('GENERAL.SAVE_STATE.SAVE');
  });

  it('emits save when dirty and valid', async () => {
    const wrapper = mount(SaveStateButton, { props: { dirty: true } });
    expect(wrapper.text()).toContain('GENERAL.SAVE_STATE.SAVE');
    expect(wrapper.find('i').classes()).toContain('i-lucide-save');
    await wrapper.trigger('click');
    expect(wrapper.emitted('save')).toHaveLength(1);
  });

  it('shows a disabled saving state with spinner', () => {
    const wrapper = mount(SaveStateButton, {
      props: { dirty: true, loading: true },
    });
    expect(wrapper.text()).toContain('GENERAL.SAVE_STATE.SAVING');
    expect(wrapper.text()).toContain('spinner');
    expect(wrapper.attributes('disabled')).toBeDefined();
  });

  it('disables invalid changes and exposes the reason as title', () => {
    const wrapper = mount(SaveStateButton, {
      props: { dirty: true, invalid: true, invalidReason: 'Invalid email' },
    });
    expect(wrapper.text()).toContain('GENERAL.SAVE_STATE.SAVE');
    expect(wrapper.attributes('disabled')).toBeDefined();
    expect(wrapper.attributes('title')).toBe('Invalid email');
  });
});
