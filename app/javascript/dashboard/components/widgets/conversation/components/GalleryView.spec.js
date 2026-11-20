import { mount, flushPromises } from '@vue/test-utils';
import { ref, nextTick } from 'vue';
import { createI18n } from 'vue-i18n';
import settings from 'dashboard/i18n/locale/en/settings.json';
import conversation from 'dashboard/i18n/locale/en/conversation.json';
import GalleryView from './GalleryView.vue';

vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ getCurrentUser: ref({ id: 1 }) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useDetectKeyboardLayout', () => ({
  useDetectKeyboardLayout: () => Promise.resolve('QWERTY'),
}));
const pdf = {
  id: 1,
  message_id: 10,
  file_type: 'file',
  content_type: 'application/pdf',
  extension: 'pdf',
  file_size: 1024,
  data_url: '/document.pdf',
};
const options = () => ({
  global: {
    plugins: [
      createI18n({
        legacy: false,
        locale: 'en',
        messages: { en: { ...conversation, ...settings } },
      }),
    ],
    stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
    directives: {
      dompurifyHtml: (el, binding) => {
        el.textContent = binding.value;
      },
    },
  },
});

describe('gallery PDF preview', () => {
  it('allows retrying a failed video without treating it as an image', async () => {
    const video = { ...pdf, file_type: 'video', data_url: '/clip.mp4' };
    const wrapper = mount(GalleryView, {
      ...options(),
      props: { attachment: video, allAttachments: [video], show: true },
    });
    await nextTick();
    await wrapper.get('video').trigger('error');
    expect(wrapper.get('[role="status"]').text()).toContain('Could not load');
    await wrapper.get('[role="status"] button').trigger('click');
    expect(wrapper.get('video').attributes('src')).toBe('/clip.mp4');
    await wrapper.get('video').trigger('loadeddata');
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
  });

  it('embeds only a small application/pdf without sandbox and links to the original', async () => {
    const wrapper = mount(GalleryView, {
      ...options(),
      props: { attachment: pdf, allAttachments: [pdf], show: true },
    });
    await nextTick();
    const iframe = wrapper.get('iframe');
    expect(iframe.attributes('src')).toBe(pdf.data_url);
    expect(iframe.attributes('title')).toBe('document.pdf');
    expect(iframe.attributes('sandbox')).toBeUndefined();
    expect(iframe.attributes('referrerpolicy')).toBe('no-referrer');
    expect(wrapper.text()).toContain('1 of 1');
    const link = wrapper.get('a');
    expect(link.text()).toBe('Open original');
    expect(link.attributes()).toMatchObject({
      href: pdf.data_url,
      target: '_blank',
      rel: 'noopener noreferrer',
    });
    expect(wrapper.find('[icon="i-lucide-zoom-in"]').exists()).toBe(false);
  });

  it('shows the download explanation for a 30 MB PDF', async () => {
    const wrapper = mount(GalleryView, {
      ...options(),
      props: {
        attachment: { ...pdf, file_size: 30 * 1024 * 1024 },
        allAttachments: [pdf],
        show: true,
      },
    });
    await nextTick();
    expect(wrapper.find('iframe').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'This PDF is large. Download it to view it.'
    );
  });

  it.each([
    ['html', 'text/html'],
    ['svg', 'image/svg+xml'],
    ['txt', 'text/plain'],
    ['pdf', 'text/html'],
  ])('never embeds %s with MIME %s', async (extension, content_type) => {
    const wrapper = mount(GalleryView, {
      ...options(),
      props: {
        attachment: { ...pdf, extension, content_type },
        allAttachments: [pdf],
        show: true,
      },
    });
    await nextTick();
    expect(wrapper.find('iframe').exists()).toBe(false);
  });

  it('selects by attachment id when several photos share a message, and returns focus on close', async () => {
    const trigger = document.createElement('button');
    document.body.appendChild(trigger);
    trigger.focus();
    const second = { ...pdf, id: 2, data_url: '/second.pdf' };
    const wrapper = mount(GalleryView, {
      ...options(),
      props: { attachment: second, allAttachments: [pdf, second], show: true },
    });
    await nextTick();
    expect(wrapper.text()).toContain('2 of 2');
    expect(wrapper.get('iframe').attributes('src')).toBe('/second.pdf');
    await wrapper.get('[icon="i-lucide-x"]').trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(document.activeElement).toBe(trigger);
    trigger.remove();
  });
});

describe('gallery image interactions', () => {
  let wrapper;
  const photo = { ...pdf, file_type: 'image', data_url: '/photo.jpg' };
  beforeEach(async () => {
    const second = { ...photo, id: 2, data_url: '/second.jpg' };
    wrapper = mount(GalleryView, {
      ...options(),
      props: { attachment: photo, allAttachments: [photo, second], show: true },
    });
    await flushPromises();
    const image = wrapper.get('img').element;
    const viewport = image.parentElement.parentElement;
    Object.defineProperties(viewport, {
      clientWidth: { configurable: true, value: 400 },
      clientHeight: { configurable: true, value: 300 },
    });
    Object.defineProperties(image, {
      naturalWidth: { configurable: true, value: 800 },
      naturalHeight: { configurable: true, value: 400 },
    });
    await wrapper.get('img').trigger('load');
  });
  afterEach(() => wrapper.unmount());

  it('wires image gestures and prevents native dragging without delayed transforms', async () => {
    const image = wrapper.get('img');
    expect(image.attributes('draggable')).toBe('false');
    expect(image.classes()).toContain('touch-none');
    expect(image.classes()).not.toContain('duration-100');
    await image.trigger('dblclick', { clientX: 0, clientY: 0 });
    expect(image.element.style.transform).toContain('scale(3)');
    await image.trigger('dblclick', { clientX: 0, clientY: 0 });
    expect(image.element.style.transform).toContain('scale(1)');
  });

  it('wires wheel, pointer capture, drag and cancellation without closing the gallery', async () => {
    const image = wrapper.get('img');
    expect(image.element.style.width).toBe('400px');
    image.element.setPointerCapture = vi.fn();
    const viewport = image.element.parentElement.parentElement;
    viewport.getBoundingClientRect = () => ({
      left: 0,
      top: 0,
      width: 400,
      height: 300,
    });
    image.element.dispatchEvent(
      new WheelEvent('wheel', {
        deltaY: -10,
        clientX: 250,
        clientY: 150,
        bubbles: true,
        cancelable: true,
      })
    );
    await nextTick();
    expect(image.element.style.transform).toContain('scale(1.2)');
    image.element.dispatchEvent(
      new WheelEvent('wheel', {
        deltaY: 10,
        clientX: 250,
        clientY: 150,
        bubbles: true,
      })
    );
    await nextTick();
    await wrapper.get('[aria-label="Zoom in"]').trigger('click');
    image.element.dispatchEvent(
      new PointerEvent('pointerdown', {
        pointerId: 1,
        button: 0,
        clientX: 200,
        clientY: 150,
      })
    );
    image.element.dispatchEvent(
      new PointerEvent('pointermove', {
        pointerId: 1,
        clientX: 210,
        clientY: 150,
      })
    );
    await nextTick();
    expect(image.element.setPointerCapture).toHaveBeenCalledWith(1);
    expect(image.element.style.transform).toContain('translate(10px, 0px)');
    image.element.dispatchEvent(
      new PointerEvent('pointercancel', { pointerId: 1 })
    );
    await nextTick();
    const transform = image.element.style.transform;
    image.element.dispatchEvent(
      new PointerEvent('pointermove', {
        pointerId: 1,
        clientX: 300,
        clientY: 150,
      })
    );
    await nextTick();
    expect(image.element.style.transform).toBe(transform);
    await image.trigger('click');
    expect(wrapper.emitted('close')).toBeUndefined();
  });

  it.each([
    { key: '+', code: 'BracketRight' },
    { key: '+', code: 'NumpadAdd' },
    { key: '=', code: 'Equal' },
  ])('zooms once with a layout-independent $code key', async key => {
    document.dispatchEvent(new KeyboardEvent('keydown', key));
    await nextTick();
    expect(wrapper.get('img').element.style.transform).toContain('scale(1.1)');
  });

  it('zooms with buttons and keyboard, resets, navigates, and closes with Escape', async () => {
    await wrapper.get('[aria-label="Zoom in"]').trigger('click');
    expect(wrapper.get('img').element.style.transform).toContain('scale(1.1)');
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: '+', code: 'Equal', shiftKey: true })
    );
    await nextTick();
    expect(wrapper.get('img').element.style.transform).toContain('scale(1.2');
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: '-', code: 'Minus' })
    );
    await nextTick();
    expect(wrapper.get('img').element.style.transform).toContain('scale(1.1');
    await wrapper.get('[aria-label="Rotate right"]').trigger('click');
    expect(wrapper.get('img').element.style.transform).toContain(
      'rotate(90deg)'
    );
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: '0', code: 'Digit0' })
    );
    await nextTick();
    expect(wrapper.get('img').element.style.transform).toBe(
      'translate(0px, 0px) rotate(0deg) scale(1)'
    );
    await wrapper.get('[aria-label="Zoom in"]').trigger('click');
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight' }));
    await nextTick();
    expect(wrapper.get('img').attributes('src')).toBe('/second.jpg');
    expect(wrapper.get('img').element.style.transform).toContain('scale(1)');
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft' }));
    await nextTick();
    expect(wrapper.get('img').attributes('src')).toBe('/photo.jpg');
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    expect(wrapper.emitted('close')).toHaveLength(1);
  });
});
