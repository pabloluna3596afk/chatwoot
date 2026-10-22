import { mount } from '@vue/test-utils';
import AccordionItem from '../AccordionItem.vue';

const mountItem = props =>
  mount(AccordionItem, {
    props: { title: 'Atributos', ...props },
    global: { stubs: { 'fluent-icon': true, EmojiOrIcon: true } },
  });

describe('AccordionItem', () => {
  it('shows the count next to the title when provided', () => {
    const wrapper = mountItem({ count: 3 });
    expect(wrapper.get('[data-testid="accordion-count"]').text()).toBe('3');
  });

  it('shows a zero count', () => {
    const wrapper = mountItem({ count: 0 });
    expect(wrapper.get('[data-testid="accordion-count"]').text()).toBe('0');
  });

  it('hides the count when not provided', () => {
    const wrapper = mountItem();
    expect(wrapper.find('[data-testid="accordion-count"]').exists()).toBe(
      false
    );
  });
});
