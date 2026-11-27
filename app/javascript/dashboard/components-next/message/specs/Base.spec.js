import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import Base from '../bubbles/Base.vue';
import { MESSAGE_VARIANTS } from '../constants';

const context = {};
vi.mock('../provider.js', () => ({ useMessageContext: () => context }));

const render = (props = {}) =>
  mount(Base, {
    props,
    global: {
      stubs: {
        MessageMeta: {
          props: ['showTimestamp'],
          template:
            '<div data-meta :data-time="showTimestamp"><slot name="captain" /></div>',
        },
        CaptainGenerationDetails: {
          template: '<div data-captain><slot name="meta" /></div>',
        },
        ReplyPreview: true,
      },
    },
  });

describe('bubble metadata composition', () => {
  beforeEach(() =>
    Object.assign(context, {
      id: ref(9),
      variant: ref('agent'),
      orientation: ref('right'),
      inReplyTo: ref(null),
      shouldGroupWithNext: ref(false),
      contentAttributes: ref({}),
      contentType: ref('text'),
      sender: ref({ type: 'User' }),
    })
  );

  it('hides repeated time for ordinary intermediate messages', () => {
    context.shouldGroupWithNext.value = true;
    expect(render().find('[data-meta]').exists()).toBe(false);
  });

  it.each(['agent', 'user', 'private', 'template'])(
    'preserves bottom padding when the %s text has no metadata',
    variant => {
      context.variant.value = variant;
      context.shouldGroupWithNext.value = true;
      const wrapper = render({ contentClass: 'px-3 pt-2' });
      expect(wrapper.find('[data-meta]').exists()).toBe(false);
      expect(wrapper.get('[data-bubble-content]').classes()).toContain('pb-2');
    }
  );

  it('does not add padding to full-bleed media or explicitly hidden metadata', () => {
    context.shouldGroupWithNext.value = true;
    expect(render().get('[data-bubble-content]').classes()).not.toContain(
      'pb-2'
    );
    expect(
      render({ hideMeta: true, contentClass: 'p-2' })
        .get('[data-bubble-content]')
        .classes()
    ).not.toContain('pb-2');
  });

  it.each(['macro', 'automation', 'flow'])(
    'preserves %s on grouped messages',
    type => {
      context.shouldGroupWithNext.value = true;
      context.contentAttributes.value = { messageSource: { type, id: 2 } };
      const wrapper = render();
      expect(wrapper.get('[data-meta]').attributes('data-time')).toBe('false');
    }
  );

  it('mounts the existing Captain component with metadata on grouped replies', () => {
    context.shouldGroupWithNext.value = true;
    context.sender.value = { type: 'captain_assistant' };
    const wrapper = render();
    expect(wrapper.find('[data-captain] [data-meta]').exists()).toBe(true);
    expect(wrapper.get('[data-meta]').attributes('data-time')).toBe('false');
  });

  it('preserves the private handoff note and its details', () => {
    context.variant.value = 'private';
    context.contentAttributes.value = { captainHandoff: {} };
    const wrapper = render();
    expect(wrapper.classes()).toContain('bg-n-solid-amber');
    expect(wrapper.find('[data-captain]').exists()).toBe(true);
  });

  it('uses the shared metadata spacing for every message variant', () => {
    context.variant.value = 'email';
    const wrapper = render();
    const meta = wrapper.get('[data-meta]');
    expect(meta.classes()).toEqual(
      expect.arrayContaining([
        'mt-1',
        'px-2.5',
        'pb-1.5',
        'justify-end',
        'text-n-slate-11',
      ])
    );
    expect(meta.classes()).not.toContain('absolute');
  });

  it.each(Object.values(MESSAGE_VARIANTS))(
    'provides an explicit background for the %s variant',
    variant => {
      context.variant.value = variant;
      const classes = render().classes();
      expect(classes.some(className => className.startsWith('bg-'))).toBe(true);
    }
  );

  it('keeps the sticker variant transparent by design', () => {
    context.contentType.value = 'sticker';
    const wrapper = render();
    expect(wrapper.classes()).toContain('bg-transparent');
    expect(wrapper.classes()).toContain('shadow-none');
    expect(wrapper.get('[data-meta]').classes()).toContain('text-n-slate-1');
    expect(wrapper.get('[data-meta]').classes()).toContain(
      'dark:text-n-slate-12'
    );
  });

  it.each([
    ['left', 'rounded-es-none'],
    ['right', 'rounded-ee-none'],
  ])('keeps the %s tail on its logical side in RTL', (orientation, corner) => {
    context.orientation.value = orientation;
    expect(render().classes()).toContain(corner);
  });

  it('does not create a meta row for activities or an explicit hideMeta', async () => {
    const wrapper = render({ hideMeta: true });
    expect(wrapper.find('[data-meta]').exists()).toBe(false);
    context.variant.value = 'activity';
    await wrapper.setProps({ hideMeta: false });
    expect(wrapper.find('[data-meta]').exists()).toBe(false);
  });
});
