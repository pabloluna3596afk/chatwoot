import { mount } from '@vue/test-utils';
import { useVisualViewportHeight } from '../useVisualViewportHeight';

const touchPointsDescriptor = Object.getOwnPropertyDescriptor(
  navigator,
  'maxTouchPoints'
);

describe('useVisualViewportHeight', () => {
  let wrapper;
  let viewport;

  beforeEach(() => {
    viewport = new EventTarget();
    viewport.height = 844;
    viewport.offsetTop = 0;
    vi.stubGlobal('visualViewport', viewport);
    vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
    vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue('iPhone');
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = undefined;
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    if (touchPointsDescriptor) {
      Object.defineProperty(navigator, 'maxTouchPoints', touchPointsDescriptor);
    } else {
      delete navigator.maxTouchPoints;
    }
    document.documentElement.style.removeProperty('--app-height');
    document.documentElement.style.removeProperty('--app-offset-top');
  });

  it.each(['iPhone', 'iPad', 'Macintosh'])(
    '%s tracks resize and scroll',
    ua => {
      vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(ua);
      Object.defineProperty(navigator, 'maxTouchPoints', {
        configurable: true,
        get: () => 5,
      });
      wrapper = mount({ setup: useVisualViewportHeight, template: '<div />' });
      expect(
        document.documentElement.style.getPropertyValue('--app-height')
      ).toBe('844px');
      viewport.height = 500;
      viewport.dispatchEvent(new Event('resize'));
      expect(
        document.documentElement.style.getPropertyValue('--app-height')
      ).toBe('500px');
      viewport.height = 844;
      viewport.dispatchEvent(new Event('scroll'));
      expect(
        document.documentElement.style.getPropertyValue('--app-height')
      ).toBe('844px');
    }
  );

  it.each(['resize', 'scroll'])(
    'compensates visual viewport panning on %s',
    event => {
      wrapper = mount({ setup: useVisualViewportHeight, template: '<div />' });
      viewport.height = 500;
      viewport.offsetTop = 180;
      viewport.dispatchEvent(new Event(event));
      expect(wrapper.vm.isIOSViewport).toBe(true);
      expect(
        document.documentElement.style.getPropertyValue('--app-height')
      ).toBe('500px');
      expect(
        document.documentElement.style.getPropertyValue('--app-offset-top')
      ).toBe('180px');
    }
  );

  it('restores height, offset and document scroll when the keyboard closes', () => {
    wrapper = mount({ setup: useVisualViewportHeight, template: '<div />' });
    viewport.height = 500;
    viewport.offsetTop = 180;
    viewport.dispatchEvent(new Event('resize'));

    vi.stubGlobal('scrollY', 180);
    viewport.height = 844;
    viewport.offsetTop = 0;
    viewport.dispatchEvent(new Event('resize'));
    expect(window.scrollTo).toHaveBeenCalledWith(0, 0);
    expect(
      document.documentElement.style.getPropertyValue('--app-height')
    ).toBe('844px');
    expect(
      document.documentElement.style.getPropertyValue('--app-offset-top')
    ).toBe('0px');
  });

  it('resets document scrolling while the visual viewport is panned', () => {
    vi.stubGlobal('scrollX', 12);
    vi.stubGlobal('scrollY', 100);
    viewport.offsetTop = 80;
    wrapper = mount({ setup: useVisualViewportHeight, template: '<div />' });
    expect(window.scrollTo).toHaveBeenCalledWith(0, 0);

    window.scrollTo.mockClear();
    viewport.dispatchEvent(new Event('scroll'));
    expect(window.scrollTo).toHaveBeenCalledWith(0, 0);
    expect(
      document.documentElement.style.getPropertyValue('--app-offset-top')
    ).toBe('80px');
  });

  it('tracks rotation and Safari toolbar changes without caching the height', () => {
    wrapper = mount({ setup: useVisualViewportHeight, template: '<div />' });
    viewport.height = 320;
    viewport.offsetTop = 60;
    viewport.dispatchEvent(new Event('resize'));
    expect(
      document.documentElement.style.getPropertyValue('--app-height')
    ).toBe('320px');
    expect(
      document.documentElement.style.getPropertyValue('--app-offset-top')
    ).toBe('60px');

    viewport.height = 390;
    viewport.offsetTop = 0;
    viewport.dispatchEvent(new Event('resize'));
    viewport.height = 430;
    viewport.dispatchEvent(new Event('scroll'));
    expect(
      document.documentElement.style.getPropertyValue('--app-height')
    ).toBe('430px');
    expect(
      document.documentElement.style.getPropertyValue('--app-offset-top')
    ).toBe('0px');
    expect(window.scrollTo).not.toHaveBeenCalled();
  });

  it('removes both listeners and the variable on unmount', () => {
    const removeListener = vi.spyOn(viewport, 'removeEventListener');
    wrapper = mount({ setup: useVisualViewportHeight, template: '<div />' });
    wrapper.unmount();
    wrapper = undefined;
    expect(removeListener).toHaveBeenCalledWith('resize', expect.any(Function));
    expect(removeListener).toHaveBeenCalledWith('scroll', expect.any(Function));
    viewport.height = 500;
    viewport.dispatchEvent(new Event('resize'));
    viewport.dispatchEvent(new Event('scroll'));
    expect(
      document.documentElement.style.getPropertyValue('--app-height')
    ).toBe('');
    expect(
      document.documentElement.style.getPropertyValue('--app-offset-top')
    ).toBe('');
    expect(window.scrollTo).not.toHaveBeenCalled();
  });

  it.each(['Android', 'Windows', 'Macintosh'])('does nothing on %s', ua => {
    vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(ua);
    Object.defineProperty(navigator, 'maxTouchPoints', {
      configurable: true,
      get: () => 0,
    });
    const addListener = vi.spyOn(viewport, 'addEventListener');
    vi.stubGlobal('scrollY', 180);
    viewport.offsetTop = 180;
    wrapper = mount({ setup: useVisualViewportHeight, template: '<div />' });
    viewport.dispatchEvent(new Event('resize'));
    viewport.dispatchEvent(new Event('scroll'));
    expect(wrapper.vm.isIOSViewport).toBe(false);
    expect(addListener).not.toHaveBeenCalled();
    expect(
      document.documentElement.style.getPropertyValue('--app-height')
    ).toBe('');
    expect(
      document.documentElement.style.getPropertyValue('--app-offset-top')
    ).toBe('');
    expect(window.scrollTo).not.toHaveBeenCalled();
  });

  it('does nothing without visualViewport', () => {
    vi.stubGlobal('visualViewport', undefined);
    wrapper = mount({ setup: useVisualViewportHeight, template: '<div />' });
    expect(wrapper.vm.isIOSViewport).toBe(false);
    expect(
      document.documentElement.style.getPropertyValue('--app-height')
    ).toBe('');
    expect(
      document.documentElement.style.getPropertyValue('--app-offset-top')
    ).toBe('');
    expect(window.scrollTo).not.toHaveBeenCalled();
  });
});
