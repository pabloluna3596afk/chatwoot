import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import conversation from 'dashboard/i18n/locale/en/conversation.json';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import ReplyPreview from './ReplyPreview.vue';
import { activeJumpMessageId } from './useJumpToMessage';

const inReplyTo = ref({});
const currentUserId = ref(7);
vi.mock('./provider', () => ({
  useMessageContext: () => ({
    inReplyTo,
    channelType: ref('Channel::Instagram'),
    currentUserId,
    conversationId: ref(3),
  }),
}));
const options = () => ({
  global: {
    plugins: [
      createI18n({
        legacy: false,
        locale: 'en',
        messages: { en: conversation },
      }),
    ],
    directives: {
      dompurifyHtml: (el, binding) => {
        el.innerHTML = binding.value;
      },
    },
  },
});

describe('reply attachment preview', () => {
  beforeEach(() => {
    activeJumpMessageId.value = null;
  });

  it('shows the image thumbnail, type, caption and scrolls to its message', async () => {
    const emit = vi.spyOn(emitter, 'emit');
    inReplyTo.value = {
      id: 14,
      conversation_id: 3,
      content: 'Payment receipt',
      attachments: [
        {
          file_type: 'image',
          data_url: '/original.png',
          thumb_url: '/thumb.png',
        },
      ],
    };
    const wrapper = mount(ReplyPreview, options());
    expect(wrapper.get('img').attributes('src')).toBe('/thumb.png');
    expect(wrapper.text()).toContain('Photo');
    expect(wrapper.text()).toContain('Payment receipt');
    await wrapper.get('button').trigger('click');
    expect(emit).toHaveBeenCalledWith(BUS_EVENTS.SCROLL_TO_MESSAGE, {
      messageId: 14,
      source: 'reply',
      conversationId: 3,
    });
    emit.mockRestore();
  });

  it('shows PDF type, filename and file icon', () => {
    inReplyTo.value = {
      id: 1,
      attachments: [
        { fileType: 'file', dataUrl: '/final.pdf', extension: 'pdf' },
      ],
    };
    const wrapper = mount(ReplyPreview, options());
    expect(wrapper.text()).toContain('PDF');
    expect(wrapper.text()).toContain('final.pdf');
    expect(wrapper.findComponent({ name: 'FileIcon' }).exists()).toBe(true);
    expect(wrapper.find('img').exists()).toBe(false);
  });

  it('shows the sender name and a plain-text excerpt without markup', () => {
    inReplyTo.value = {
      id: 1,
      content: '**Confirmed**',
      sender: { name: 'Ana' },
    };
    const wrapper = mount(ReplyPreview, options());
    expect(wrapper.text()).toContain('Ana');
    expect(wrapper.text()).toContain('Confirmed');
    expect(wrapper.find('strong').exists()).toBe(false);
  });

  it('flattens paragraphs and lists into one clamped excerpt', () => {
    inReplyTo.value = {
      id: 1,
      content: 'First paragraph\n\nSecond paragraph\n\n- one\n- two',
      sender: { name: 'Ana' },
    };
    const wrapper = mount(ReplyPreview, options());
    const excerpt = wrapper.get('[class*="line-clamp-1"][class*="leading-4"]');
    expect(excerpt.text()).toBe('First paragraph Second paragraph one two');
    expect(excerpt.classes()).not.toContain('sm:line-clamp-2');
    expect(excerpt.element.parentElement.classList).toContain('flex-1');
    expect(wrapper.get('button').classes()).toContain('box-border');
    expect(wrapper.findAll('p, ul, li, br')).toHaveLength(0);
  });

  it('caps the excerpt length for a very long message', () => {
    const paragraph = 'Hello, I need to check my order number 24. ';
    inReplyTo.value = {
      id: 1,
      content: Array.from({ length: 40 }, () => paragraph).join('\n\n'),
      sender: { name: 'Ana' },
    };
    const wrapper = mount(ReplyPreview, options());
    const excerpt = wrapper.get('[class*="line-clamp-1"][class*="leading-4"]');
    expect(excerpt.text().length).toBeLessThanOrEqual(240);
    expect(excerpt.text()).not.toContain('\n');
  });

  it('keeps the missing-message text', () => {
    inReplyTo.value = { id: 1 };
    expect(mount(ReplyPreview, options()).text()).toContain(
      'Message not available'
    );
  });

  it('falls back to an icon and unavailable label when an external thumbnail fails', async () => {
    inReplyTo.value = {
      id: 1,
      attachments: [{ fileType: 'image', dataUrl: '/expired.png' }],
    };
    const wrapper = mount(ReplyPreview, options());
    await wrapper.get('img').trigger('error');
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.text()).toContain('Photo unavailable');
  });

  it.each([
    [
      { messageType: 0, sender: { name: 'Ana' } },
      'text-n-iris-11',
      'bg-n-iris-9/70',
    ],
    [
      { messageType: 1, senderId: 7, sender: { name: 'Agent' } },
      'text-n-teal-11',
      'bg-n-teal-9/70',
    ],
    [
      { messageType: 1, senderId: 8, sender: { name: 'Luis' } },
      'text-n-teal-11',
      'bg-n-teal-9/70',
    ],
    [
      { messageType: 0, private: true, sender: { name: 'Ana' } },
      'text-n-amber-11',
      'bg-n-amber-9/70',
    ],
  ])(
    'uses the author tone and always shows the author',
    (message, authorClass, barClass) => {
      inReplyTo.value = { id: 1, content: 'Quoted text', ...message };
      const wrapper = mount(ReplyPreview, options());
      const author = wrapper.get('span:nth-child(2) > span:first-child');
      expect(author.classes()).toContain(authorClass);
      expect(
        wrapper.get('button').find('span:first-child').classes()
      ).toContain(barClass);
      expect(author.text()).not.toBe('');
    }
  );

  it('keeps the thumbnail at the trailing edge and uses logical spacing for RTL', () => {
    inReplyTo.value = {
      id: 2,
      messageType: 0,
      sender: { name: 'Ana' },
      attachments: [{ fileType: 'image', dataUrl: '/photo.png' }],
    };
    const wrapper = mount(ReplyPreview, options());
    const button = wrapper.get('button');
    expect(button.element.lastElementChild.classList).toContain('size-10');
    expect(button.classes()).toContain('text-start');
    expect(
      button.classes().some(className => /(^|:)(left|right)-/.test(className))
    ).toBe(false);
  });

  it('does not expose a deleted or unavailable quote as a clickable button', () => {
    inReplyTo.value = { content: 'Deleted', sender: { name: 'Ana' } };
    const wrapper = mount(ReplyPreview, options());
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    expect(wrapper.get('button').classes()).toContain('cursor-default');
  });

  it('labels the current agent as You and shows a spinner while fetching', () => {
    inReplyTo.value = {
      id: 8,
      conversationId: 3,
      messageType: 1,
      senderId: 7,
      sender: { name: 'Agent' },
      content: 'Earlier reply',
    };
    activeJumpMessageId.value = 8;
    const wrapper = mount(ReplyPreview, options());
    expect(wrapper.text()).toContain('You');
    expect(wrapper.find('.i-lucide-loader-circle').exists()).toBe(true);
    activeJumpMessageId.value = null;
  });

  it.each([
    { id: 9, content: 'Deleted', contentAttributes: { deleted: true } },
    { id: 10, conversationId: 4, content: 'Other conversation' },
  ])('disables a quote that cannot be opened', message => {
    inReplyTo.value = message;
    const wrapper = mount(ReplyPreview, options());
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    expect(wrapper.get('button').classes()).toContain('cursor-default');
    expect(wrapper.get('button').attributes('aria-label')).toBeUndefined();
  });
});
