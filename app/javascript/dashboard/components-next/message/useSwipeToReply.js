import { computed, shallowRef, unref } from 'vue';

export const REPLY_INTERACTIVE_SELECTOR = [
  'a',
  'button',
  'input',
  'textarea',
  'select',
  'label',
  'summary',
  'img',
  'picture',
  'audio',
  'video',
  'iframe',
  'embed',
  'object',
  'pre',
  'code',
  '[role="button"]',
  '[role="link"]',
  '[contenteditable]:not([contenteditable="false"])',
  '[tabindex]',
  '.skip-context-menu',
].join(',');

const SWIPE_THRESHOLD = 56;
const SWIPE_MAX = 72;
const DIRECTION_RATIO = 1.5;
const DIRECTION_SLOP = 8;
// Static classes keep Tailwind's scanner aware of every possible displacement.
const SWIPE_CLASSES = [
  'translate-x-0',
  'translate-x-1',
  'translate-x-2',
  'translate-x-3',
  'translate-x-4',
  'translate-x-5',
  'translate-x-6',
  'translate-x-7',
  'translate-x-8',
  'translate-x-9',
  'translate-x-10',
  'translate-x-11',
  'translate-x-12',
  'translate-x-[3.25rem]',
  'translate-x-14',
  'translate-x-[3.75rem]',
  'translate-x-16',
  'translate-x-[4.25rem]',
  'translate-x-[4.5rem]',
];

export function useSwipeToReply({ enabled, onReply }) {
  const distance = shallowRef(0);
  const isSwiping = shallowRef(false);
  let start = null;

  const reset = () => {
    start = null;
    distance.value = 0;
    isSwiping.value = false;
  };

  const onTouchStart = event => {
    reset();
    if (
      !unref(enabled) ||
      event.touches.length !== 1 ||
      event.target.closest(REPLY_INTERACTIVE_SELECTOR)
    )
      return;
    // Preserve horizontal scrolling in tables, code and other nested scrollers.
    let node = event.target;
    while (node && node !== event.currentTarget) {
      if (
        node.scrollWidth > node.clientWidth &&
        ['auto', 'scroll'].includes(getComputedStyle(node).overflowX)
      )
        return;
      node = node.parentElement;
    }
    const touch = event.touches[0];
    start = { x: touch.clientX, y: touch.clientY };
  };

  const onTouchMove = event => {
    if (!start) return;
    if (!unref(enabled) || event.touches.length !== 1) {
      reset();
      return;
    }
    const dx = event.touches[0].clientX - start.x;
    const dy = Math.abs(event.touches[0].clientY - start.y);
    if (!isSwiping.value) {
      if (Math.max(Math.abs(dx), dy) < DIRECTION_SLOP) return;
      if (dx <= DIRECTION_RATIO * dy) {
        reset();
        return;
      }
      isSwiping.value = true;
    }
    event.preventDefault();
    distance.value = dx > DIRECTION_RATIO * dy ? Math.min(SWIPE_MAX, dx) : 0;
  };

  const onTouchEnd = () => {
    const shouldReply = unref(enabled) && distance.value >= SWIPE_THRESHOLD;
    reset();
    if (shouldReply) onReply();
  };

  return {
    isSwiping,
    swipeClass: computed(() => SWIPE_CLASSES[Math.round(distance.value / 4)]),
    onTouchStart,
    onTouchMove,
    onTouchEnd,
    onTouchCancel: reset,
  };
}
