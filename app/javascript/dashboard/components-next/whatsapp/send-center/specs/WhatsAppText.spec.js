import { h } from 'vue';
import { mount } from '@vue/test-utils';
import WhatsAppText from '../WhatsAppText';
import ChatPreview from '../ChatPreview.vue';
import { withFullI18n } from 'test-i18n';

withFullI18n('en');

describe('WhatsApp source formatting', () => {
  it('renders compact rich snippets with inline blocks, plain links and muted variables', () => {
    const wrapper = mount(WhatsAppText, {
      props: {
        compact: true,
        text: '*Hello {{1}}* _italic_ ~removed~ `inline`\n- item\n1. first\n> quote\n\nhttps://example.com',
      },
    });
    expect(wrapper.get('strong').text()).toBe('Hello {{1}}');
    expect(wrapper.get('em').text()).toBe('italic');
    expect(wrapper.get('s').text()).toBe('removed');
    expect(wrapper.get('code').text()).toBe('inline');
    expect(wrapper.get('strong span').classes()).toContain('text-n-slate-10');
    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.find('[role=list]').exists()).toBe(false);
    expect(wrapper.find('.border-s-2').exists()).toBe(false);
    expect(wrapper.element.textContent).toBe(
      'Hello {{1}} italic removed inline item first quote  https://example.com'
    );
    expect(wrapper.classes()).toContain('whitespace-normal');
  });

  it.each([
    '<script>alert(1)</script>',
    '<img src=x onerror=alert(1)>',
    '&lt;img src=x onerror=alert(1)&gt;',
    ['javascript', 'alert(1)'].join(':'),
  ])('escapes compact source as Vue text: %s', text => {
    const wrapper = mount(WhatsAppText, {
      props: { compact: true, text: `*${text}* {{1}}` },
    });
    expect(wrapper.find('script, img, a').exists()).toBe(false);
    expect(wrapper.get('strong').text()).toBe(text);
    expect(wrapper.text()).toContain('{{1}}');
  });

  it('renders rich source, exact newlines, lists, quotes, links and nested fields', () => {
    const text =
      '*Hello {{1}}*\n*_nested_* _italic_ ~removed~ `inline`\n```mono\n*literal* {{2}}```\n\n- item\n* bullet\n1. first\n2. second\n> quote\nhttps://example.com';
    const wrapper = mount(WhatsAppText, {
      props: { text },
      slots: {
        field: ({ key }) =>
          h('textarea', { value: key === '1' ? '*literal*' : '_literal_' }),
      },
    });
    expect(wrapper.get('strong textarea').element.value).toBe('*literal*');
    expect(wrapper.get('strong em').text()).toBe('nested');
    expect(wrapper.get('s').text()).toBe('removed');
    expect(wrapper.findAll('code').map(code => code.text())).toEqual([
      'inline',
      'mono\n*literal*',
    ]);
    expect(wrapper.get('code textarea').element.value).toBe('_literal_');
    expect(wrapper.findAll('[role=listitem]').map(item => item.text())).toEqual(
      ['•item', '•bullet', '1.first', '2.second']
    );
    expect(wrapper.get('a').attributes('href')).toBe('https://example.com');
    expect(wrapper.element.textContent).toContain('\n\n');
    expect(wrapper.element.textContent.match(/\n/g)).toHaveLength(
      text.match(/\n/g).length
    );
  });

  it('keeps code literal inside emphasis and link punctuation outside URLs', () => {
    const wrapper = mount(WhatsAppText, {
      props: {
        text: '*before `*literal*` after* https://example.com/a_b?q=one_two.',
      },
    });
    expect(wrapper.get('strong code').text()).toBe('*literal*');
    expect(wrapper.get('strong').text()).toBe('before *literal* after');
    expect(wrapper.get('a').attributes('href')).toBe(
      'https://example.com/a_b?q=one_two'
    );
    expect(wrapper.element.textContent.endsWith('.')).toBe(true);
  });

  it('obeys marker whitespace rules and leaves code literal', () => {
    const wrapper = mount(WhatsAppText, {
      props: { text: '* no* _no _ ~ no ~ `*x*` *yes*' },
    });
    expect(wrapper.findAll('strong')).toHaveLength(1);
    expect(wrapper.get('strong').text()).toBe('yes');
    expect(wrapper.find('em').exists()).toBe(false);
    expect(wrapper.find('s').exists()).toBe(false);
    expect(wrapper.get('code').text()).toBe('*x*');
  });

  it('formats header, body and small muted footer through the same renderer', () => {
    const wrapper = mount(ChatPreview, {
      props: { header: '*Header*', body: '_Body_', footer: '~Footer~' },
    });
    expect(wrapper.get('strong').text()).toBe('Header');
    expect(wrapper.get('em').text()).toBe('Body');
    expect(wrapper.get('s').text()).toBe('Footer');
    expect(
      wrapper.get('s').element.parentElement.classList.contains('text-xs')
    ).toBe(true);
  });
});
