import { computed, defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Message from '../Message.vue';
import TextBubble from '../bubbles/Text/Index.vue';
import EmailBubble from '../bubbles/Email/Index.vue';
import AttachmentChips from '../chips/AttachmentChips.vue';
import { provideMessageContext } from '../provider';
import settings from 'dashboard/i18n/locale/en/settings.json';
import conversation from 'dashboard/i18n/locale/en/conversation.json';

let channel = 'Channel::Api';
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: key =>
    computed(() => {
      if (key === 'inboxes/getInbox') return () => ({ channel_type: channel });
      if (key === 'getSelectedChatAttachments') return [];
      return () => false;
    }),
}));
vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
  useAlert: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 }, query: {} }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: ref({ id: 1 }) }),
}));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: value => value }),
}));

vi.mock('dashboard/composables/useTranslations', () => ({
  useTranslations: () => ({
    hasTranslations: ref(false),
    translationContent: ref(''),
  }),
}));

const image = {
  id: 1,
  fileType: 'image',
  dataUrl: '/receipt.png',
  thumbUrl: '/thumb.png',
  width: 600,
  height: 800,
};
const pdf = {
  id: 2,
  fileType: 'file',
  dataUrl: '/quotation.pdf',
  contentType: 'application/pdf',
  extension: 'pdf',
  fileSize: 1000,
};
const stubs = {
  ContextMenu: true,
  MessageMeta: true,
  EmailMeta: true,
  GalleryView: true,
  Letter: { props: ['html'], template: '<div data-letter v-html="html" />' },
};
const globalOptions = () => ({
  plugins: [
    createI18n({
      legacy: false,
      locale: 'en',
      messages: { en: { ...settings, ...conversation } },
    }),
  ],
  stubs,
  directives: {
    dompurifyHtml: (el, binding) => {
      el.innerHTML = binding.value;
    },
  },
});
const channels = [
  'Api',
  'Whatsapp',
  'Email',
  'WebWidget',
  'Telegram',
  'Instagram',
  'FacebookPage',
  'TwilioSms',
];
const contexts = [
  ['single image', { attachments: [image] }, 'image'],
  [
    'three images with text',
    {
      content: 'Receipt',
      attachments: [image, { ...image, id: 3 }, { ...image, id: 4 }],
    },
    'text',
  ],
  ['PDF', { attachments: [pdf] }, 'file'],
  [
    'reply to image',
    { content: 'Thanks', inReplyTo: { id: 9, attachments: [image] } },
    'text',
  ],
  [
    'private note',
    { private: true, content: 'Internal', attachments: [image, pdf] },
    'text',
  ],
];

describe('attachments across seed channels', () => {
  it.each(
    channels.flatMap(type =>
      contexts.map(([name, props, bubble]) => [type, name, props, bubble])
    )
  )('%s: %s', (type, name, props, bubble) => {
    channel = `Channel::${type}`;
    const wrapper = mount(Message, {
      props: {
        id: 20,
        messageType: 0,
        status: 'sent',
        conversationId: 1,
        createdAt: 1732195656,
        currentUserId: 1,
        inboxId: 1,
        isEmailInbox: type === 'Email',
        sender: { id: 7, type: 'Contact', name: 'Demo' },
        ...props,
      },
      global: globalOptions(),
    });
    if (type === 'Email' && !props.private) {
      expect(wrapper.findComponent(EmailBubble).exists()).toBe(true);
    } else {
      expect(wrapper.get(`[data-bubble-name="${bubble}"]`).exists()).toBe(true);
    }
    if (props.attachments?.some(item => item.fileType === 'image'))
      expect(wrapper.findComponent({ name: 'MediaGrid' }).exists()).toBe(true);
    if (props.attachments?.some(item => item.fileType === 'file'))
      expect(wrapper.findComponent({ name: 'FileCard' }).exists()).toBe(true);
    if (props.inReplyTo)
      expect(wrapper.findComponent({ name: 'ReplyPreview' }).exists()).toBe(
        true
      );
    wrapper.unmount();
  });
});

describe('attachment composition', () => {
  it.each([0, 1])(
    'keeps photo, mosaic and video metadata readable for message type %s',
    messageType => {
      channel = 'Channel::Api';
      [
        [image],
        [image, { ...image, id: 2 }],
        [{ ...image, fileType: 'video', dataUrl: '/clip.mp4' }],
      ].forEach(attachments => {
        const wrapper = mount(Message, {
          props: {
            id: 20,
            messageType,
            status: 'read',
            conversationId: 1,
            createdAt: 1732195656,
            currentUserId: 1,
            inboxId: 1,
            attachments,
          },
          global: globalOptions(),
        });
        const meta = wrapper.getComponent({ name: 'MessageMeta' });
        if (attachments.length === 1 && attachments[0].fileType === 'image') {
          expect(meta.classes()).toContain('bg-black/80');
          expect(meta.attributes('overlay')).toBe('true');
        } else {
          // Mosaics and native video controls already place metadata below the media.
          expect(meta.classes()).not.toContain('absolute');
          expect(meta.classes()).toContain('text-n-slate-11');
        }
        wrapper.unmount();
      });
    }
  );

  it('keeps unavailable story and reel messages visible with their channel', async () => {
    channel = 'Channel::Instagram';
    const props = {
      id: 1,
      messageType: 0,
      status: 'sent',
      conversationId: 1,
      createdAt: 1732195656,
      currentUserId: 1,
      inboxId: 1,
    };
    const story = mount(Message, {
      props: {
        ...props,
        contentAttributes: { imageType: 'story_mention' },
        attachments: [{ ...image, fileType: 'story_mention' }],
      },
      global: globalOptions(),
    });
    await story.get('img').trigger('error');
    await story.get('video').trigger('error');
    expect(story.text()).toContain(
      'This file is no longer available on Instagram.'
    );
    story.unmount();
    const reel = mount(Message, {
      props: {
        ...props,
        attachments: [
          { ...image, fileType: 'ig_reel', dataUrl: '/expired.mp4' },
        ],
      },
      global: globalOptions(),
    });
    await reel.get('video').trigger('error');
    reel.unmount();
  });

  it('keeps the failed-send error alongside attachment content', () => {
    const wrapper = mount(Message, {
      props: {
        id: 1,
        messageType: 1,
        status: 'failed',
        conversationId: 1,
        createdAt: 1732195656,
        currentUserId: 1,
        inboxId: 1,
        attachments: [image],
        contentAttributes: { externalError: 'Simulated upload failure' },
      },
      global: { ...globalOptions(), stubs: { ...stubs, MessageError: true } },
    });
    expect(wrapper.findComponent({ name: 'MessageError' }).exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'MediaGrid' }).exists()).toBe(true);
  });

  it('renders media and documents before the text, with part defaulting to all', () => {
    const wrapper = mount(Message, {
      props: {
        id: 1,
        messageType: 0,
        status: 'sent',
        conversationId: 1,
        createdAt: 1732195656,
        currentUserId: 1,
        inboxId: 1,
        content: 'Caption',
        attachments: [image, pdf],
      },
      global: globalOptions(),
    });
    const text = wrapper.getComponent(TextBubble);
    const html = text.html();
    expect(html.indexOf('<figure')).toBeLessThan(html.indexOf('quotation.pdf'));
    expect(html.indexOf('quotation.pdf')).toBeLessThan(
      html.indexOf('Caption</p>')
    );
    expect(
      text.findAllComponents(AttachmentChips).map(item => item.props('part'))
    ).toEqual(['media', 'files']);
  });

  it('lists exactly three email files while leaving the CID image in the letter body', () => {
    const wrapper = mount(Message, {
      props: {
        id: 1,
        messageType: 0,
        status: 'sent',
        conversationId: 1,
        createdAt: 1732195656,
        currentUserId: 1,
        inboxId: 1,
        isEmailInbox: true,
        contentType: 'incoming_email',
        contentAttributes: {
          email: {
            htmlContent: {
              full: '<p>Inline receipt</p><img src="/rails/active_storage/blobs/receipt.png">',
            },
            textContent: { full: 'Inline receipt' },
          },
        },
        attachments: [
          pdf,
          {
            ...pdf,
            id: 3,
            dataUrl: '/contract.docx',
            extension: 'docx',
            contentType: 'application/octet-stream',
          },
          {
            ...pdf,
            id: 4,
            dataUrl: '/prices.xlsx',
            extension: 'xlsx',
            contentType: 'application/octet-stream',
          },
        ],
      },
      global: globalOptions(),
    });
    expect(wrapper.findAllComponents({ name: 'FileCard' })).toHaveLength(3);
    expect(wrapper.findAll('[data-letter] img')).toHaveLength(1);
    expect(wrapper.findComponent({ name: 'MediaGrid' }).exists()).toBe(false);
    expect(wrapper.getComponent(AttachmentChips).props('part')).toBe('all');
  });

  it('keeps part=all as the public default', () => {
    const Host = defineComponent({
      components: { AttachmentChips },
      setup() {
        provideMessageContext({
          attachments: ref([image, pdf]),
          content: ref(''),
          orientation: ref('left'),
        });
        return { attachments: [image, pdf] };
      },
      template: '<AttachmentChips :attachments="attachments" />',
    });
    const wrapper = mount(Host, { global: globalOptions() });
    expect(wrapper.getComponent(AttachmentChips).props('part')).toBe('all');
    expect(wrapper.findComponent({ name: 'MediaGrid' }).exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'FileCard' }).exists()).toBe(true);
  });
});
