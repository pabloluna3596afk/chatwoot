import { mount } from '@vue/test-utils';
import PageLayout from './PageLayout.vue';

describe('PageLayout', () => {
  it.each([
    ['settings', 'max-w-5xl'],
    ['wide', 'max-w-[90rem]'],
    ['full', 'max-w-none'],
  ])('applies the %s width to header and body', (width, className) => {
    const wrapper = mount(PageLayout, {
      props: { width },
      slots: { title: '<h1>Title</h1>', default: '<p>Body</p>' },
    });

    expect(wrapper.find('header').element.parentElement.classList).toContain(
      className
    );
    expect(wrapper.get('main > div').classes()).toContain(className);
  });

  it('keeps one scrollable body and supports banner and footer slots', () => {
    const wrapper = mount(PageLayout, {
      slots: {
        banner: '<aside>Notice</aside>',
        default: '<p>Body</p>',
        footer: '<nav>Pagination</nav>',
      },
    });

    expect(wrapper.findAll('[class*="overflow-y-auto"]')).toHaveLength(1);
    expect(wrapper.get('main').text()).toContain('Notice');
    expect(wrapper.get('main').text()).toContain('Body');
    expect(wrapper.get('footer').text()).toContain('Pagination');
  });
});
