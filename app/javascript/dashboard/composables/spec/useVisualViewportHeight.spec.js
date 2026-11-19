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
    vi.stubGlobal('visualViewport', viewport);
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
  });

  it.each(['Android', 'Windows', 'Macintosh'])('does nothing on %s', ua => {
    vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(ua);
    Object.defineProperty(navigator, 'maxTouchPoints', {
      configurable: true,
      get: () => 0,
    });
    const addListener = vi.spyOn(viewport, 'addEventListener');
    wrapper = mount({ setup: useVisualViewportHeight, template: '<div />' });
    viewport.dispatchEvent(new Event('resize'));
    expect(addListener).not.toHaveBeenCalled();
    expect(
      document.documentElement.style.getPropertyValue('--app-height')
    ).toBe('');
  });

  it('does nothing without visualViewport', () => {
    vi.stubGlobal('visualViewport', undefined);
    wrapper = mount({ setup: useVisualViewportHeight, template: '<div />' });
    expect(
      document.documentElement.style.getPropertyValue('--app-height')
    ).toBe('');
  });
});
