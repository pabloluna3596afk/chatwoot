import { shallowRef, watch } from 'vue';

// Keep selection on click so scrolling/cancelled pointers never execute an item.
export const useTouchPreview = ({ selectedItem, onPreview, onSelect }) => {
  const isTouch = shallowRef(false);
  let previewedItem = null;
  watch(
    selectedItem,
    item => {
      if (item !== previewedItem) previewedItem = null;
    },
    { flush: 'sync' }
  );

  const onPointerDown = event => {
    isTouch.value = event.pointerType === 'touch';
    if (!isTouch.value) previewedItem = null;
  };
  const onHover = item => {
    if (!isTouch.value) onPreview(item);
  };
  const onPointerMove = (event, item) => {
    if (event.pointerType !== 'mouse') return;
    onPointerDown(event);
    onHover(item);
  };
  const onClick = item => {
    if (isTouch.value && previewedItem !== item) {
      onPreview(item);
      previewedItem = item;
      return;
    }
    onSelect(item);
  };

  return { isTouch, onPointerDown, onHover, onPointerMove, onClick };
};
