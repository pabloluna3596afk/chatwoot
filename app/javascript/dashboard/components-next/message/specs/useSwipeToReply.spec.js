import { ref } from 'vue';
import { useSwipeToReply } from '../useSwipeToReply';

const touch = (x, y, target = document.createElement('div')) => ({
  touches: [{ clientX: x, clientY: y }],
  target,
  currentTarget: target,
  preventDefault: vi.fn(),
});

describe('swipe to reply', () => {
  it.each([
    [55, 0, false],
    [56, 0, true],
    [80, 10, true],
    [56, 40, false],
    [0, 80, false],
    [-80, 0, false],
    [60, 40, false],
  ])('checks threshold and direction (%s, %s)', (dx, dy, expected) => {
    const onReply = vi.fn();
    const swipe = useSwipeToReply({ enabled: ref(true), onReply });
    swipe.onTouchStart(touch(0, 0));
    const move = touch(dx, dy);
    swipe.onTouchMove(move);
    if (dy >= Math.abs(dx)) expect(move.preventDefault).not.toHaveBeenCalled();
    swipe.onTouchEnd();
    swipe.onTouchEnd();
    expect(onReply).toHaveBeenCalledTimes(expected ? 1 : 0);
    expect(swipe.swipeClass.value).toBe('translate-x-0');
    expect(swipe.isSwiping.value).toBe(false);
  });

  it('tracks the finger, caps displacement and cancels without replying', () => {
    const onReply = vi.fn();
    const swipe = useSwipeToReply({ enabled: ref(true), onReply });
    swipe.onTouchStart(touch(0, 0));
    swipe.onTouchMove(touch(32, 0));
    expect(swipe.swipeClass.value).toBe('translate-x-8');
    swipe.onTouchMove(touch(200, 0));
    expect(swipe.swipeClass.value).toBe('translate-x-[4.5rem]');
    swipe.onTouchCancel();
    swipe.onTouchEnd();
    expect(onReply).not.toHaveBeenCalled();
  });

  it('never captures a vertical gesture after direction was decided', () => {
    const onReply = vi.fn();
    const swipe = useSwipeToReply({ enabled: ref(true), onReply });
    swipe.onTouchStart(touch(0, 0));
    swipe.onTouchMove(touch(4, 20));
    swipe.onTouchMove(touch(80, 20));
    swipe.onTouchEnd();
    expect(onReply).not.toHaveBeenCalled();
  });

  it.each(['a', 'button', 'img', 'pre', 'code', 'audio', 'video'])(
    'preserves %s interactions',
    tag => {
      const onReply = vi.fn();
      const swipe = useSwipeToReply({ enabled: ref(true), onReply });
      swipe.onTouchStart(touch(0, 0, document.createElement(tag)));
      swipe.onTouchMove(touch(80, 0));
      swipe.onTouchEnd();
      expect(onReply).not.toHaveBeenCalled();
    }
  );

  it('preserves nested horizontal scrolling', () => {
    const onReply = vi.fn();
    const swipe = useSwipeToReply({ enabled: ref(true), onReply });
    const target = document.createElement('div');
    target.style.overflowX = 'auto';
    Object.defineProperties(target, {
      scrollWidth: { value: 500 },
      clientWidth: { value: 100 },
    });
    swipe.onTouchStart({
      ...touch(0, 0, target),
      currentTarget: document.createElement('div'),
    });
    swipe.onTouchMove(touch(80, 0));
    swipe.onTouchEnd();
    expect(onReply).not.toHaveBeenCalled();
  });

  it('checks eligibility at start and release and cancels multi-touch', () => {
    const onReply = vi.fn();
    const enabled = ref(false);
    const swipe = useSwipeToReply({ enabled, onReply });
    swipe.onTouchStart(touch(0, 0));
    swipe.onTouchMove(touch(80, 0));
    swipe.onTouchEnd();
    enabled.value = true;
    swipe.onTouchStart(touch(0, 0));
    swipe.onTouchMove(touch(80, 0));
    enabled.value = false;
    swipe.onTouchEnd();
    enabled.value = true;
    swipe.onTouchStart(touch(0, 0));
    swipe.onTouchMove({ ...touch(80, 0), touches: [{}, {}] });
    swipe.onTouchEnd();
    expect(onReply).not.toHaveBeenCalled();
  });
});
