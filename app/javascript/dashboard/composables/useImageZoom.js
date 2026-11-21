import { ref, computed } from 'vue';

const MIN_ZOOM = 1;
const MAX_ZOOM = 3;
const WHEEL_STEP = 0.2;
const CLICK_ZOOM = 2;
const DRAG_THRESHOLD = 5;
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

// Translations use viewport coordinates; rotation never rotates the drag axes.
export const useImageZoom = (imageRef, viewportRef = null) => {
  const zoomScale = ref(MIN_ZOOM);
  const activeImageRotation = ref(0);
  const position = ref({ x: 0, y: 0 });
  const dimensions = ref(null);
  const pointers = new Map();
  const isDragging = ref(false);
  let pointerStart = null;
  let suppressClick = false;

  const bounds = () => {
    const viewport = viewportRef?.value;
    const image = imageRef.value;
    return {
      width: viewport?.clientWidth || image?.offsetWidth || 0,
      height: viewport?.clientHeight || image?.offsetHeight || 0,
      imageWidth: dimensions.value?.width || image?.offsetWidth || 0,
      imageHeight: dimensions.value?.height || image?.offsetHeight || 0,
    };
  };
  const constrainPosition = () => {
    const { width, height, imageWidth, imageHeight } = bounds();
    const rotated = activeImageRotation.value % 180 !== 0;
    const limitX = Math.max(
      0,
      ((rotated ? imageHeight : imageWidth) * zoomScale.value - width) / 2
    );
    const limitY = Math.max(
      0,
      ((rotated ? imageWidth : imageHeight) * zoomScale.value - height) / 2
    );
    position.value = {
      x: clamp(position.value.x, -limitX, limitX),
      y: clamp(position.value.y, -limitY, limitY),
    };
  };
  const updateImageBounds = () => {
    const image = imageRef.value;
    const viewport = viewportRef?.value;
    if (
      image?.naturalWidth &&
      viewport?.clientWidth &&
      viewport?.clientHeight
    ) {
      const rotated = activeImageRotation.value % 180 !== 0;
      const fit = Math.min(
        1,
        (rotated ? viewport.clientHeight : viewport.clientWidth) /
          image.naturalWidth,
        (rotated ? viewport.clientWidth : viewport.clientHeight) /
          image.naturalHeight
      );
      dimensions.value = {
        width: image.naturalWidth * fit,
        height: image.naturalHeight * fit,
      };
    }
    constrainPosition();
  };
  const cursor = computed(() => {
    if (isDragging.value) return 'grabbing';
    return zoomScale.value > MIN_ZOOM ? 'zoom-out' : 'zoom-in';
  });
  const imageStyle = computed(() => ({
    ...(dimensions.value
      ? {
          width: `${dimensions.value.width}px`,
          height: `${dimensions.value.height}px`,
        }
      : {}),
    transform: `translate(${position.value.x}px, ${position.value.y}px) rotate(${activeImageRotation.value}deg) scale(${zoomScale.value})`,
    cursor: cursor.value,
    transformOrigin: 'center center',
  }));
  const centerOffset = (x, y) => {
    const rect = (viewportRef?.value || imageRef.value).getBoundingClientRect();
    return {
      x: x - rect.left - rect.width / 2,
      y: y - rect.top - rect.height / 2,
    };
  };
  const onZoom = (delta, x, y) => {
    if (!imageRef.value) return;
    const next = clamp(zoomScale.value + delta, MIN_ZOOM, MAX_ZOOM);
    if (next === zoomScale.value) return;
    const ratio = next / zoomScale.value;
    const point = x != null && y != null ? centerOffset(x, y) : { x: 0, y: 0 };
    position.value = {
      x: point.x - (point.x - position.value.x) * ratio,
      y: point.y - (point.y - position.value.y) * ratio,
    };
    zoomScale.value = next;
    constrainPosition();
  };
  const resetZoomAndRotation = () => {
    pointers.clear();
    isDragging.value = false;
    activeImageRotation.value = 0;
    zoomScale.value = MIN_ZOOM;
    position.value = { x: 0, y: 0 };
    dimensions.value = null;
    updateImageBounds();
  };
  const onRotate = direction => {
    if (!imageRef.value) return;
    activeImageRotation.value =
      (activeImageRotation.value + (direction === 'clockwise' ? 90 : -90)) %
      360;
    zoomScale.value = MIN_ZOOM;
    position.value = { x: 0, y: 0 };
    pointers.clear();
    isDragging.value = false;
    updateImageBounds();
  };
  const onClickZoomImage = event => {
    event.preventDefault();
    // The second click of a double click must not undo the first one.
    if (suppressClick || event.detail > 1) return;
    onZoom(
      (zoomScale.value > MIN_ZOOM ? MIN_ZOOM : CLICK_ZOOM) - zoomScale.value,
      event.clientX,
      event.clientY
    );
  };
  const onWheelImageZoom = event => {
    event.preventDefault();
    if (!event.deltaY) return;
    onZoom(
      event.deltaY > 0 ? -WHEEL_STEP : WHEEL_STEP,
      event.clientX,
      event.clientY
    );
  };
  const onPointerDown = event => {
    if (event.button !== 0) return;
    if (!pointers.size) {
      pointerStart = { x: event.clientX, y: event.clientY };
      suppressClick = false;
    } else {
      suppressClick = true;
    }
    event.currentTarget.setPointerCapture(event.pointerId);
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    isDragging.value = true;
  };
  const onPointerMove = event => {
    if (!pointers.has(event.pointerId)) return;
    if (
      pointerStart &&
      Math.hypot(
        event.clientX - pointerStart.x,
        event.clientY - pointerStart.y
      ) > DRAG_THRESHOLD
    )
      suppressClick = true;
    const before = [...pointers.values()];
    const previous = pointers.get(event.pointerId);
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    const after = [...pointers.values()];
    if (before.length === 2) {
      const distance = points =>
        Math.hypot(points[0].x - points[1].x, points[0].y - points[1].y);
      const midpoint = points => ({
        x: (points[0].x + points[1].x) / 2,
        y: (points[0].y + points[1].y) / 2,
      });
      const start = midpoint(before);
      const end = midpoint(after);
      if (distance(before))
        onZoom(
          zoomScale.value * (distance(after) / distance(before) - 1),
          start.x,
          start.y
        );
      position.value = {
        x: position.value.x + end.x - start.x,
        y: position.value.y + end.y - start.y,
      };
    } else if (before.length === 1 && zoomScale.value > MIN_ZOOM) {
      position.value = {
        x: position.value.x + event.clientX - previous.x,
        y: position.value.y + event.clientY - previous.y,
      };
    }
    constrainPosition();
  };
  const onPointerUp = event => {
    pointers.delete(event.pointerId);
    isDragging.value = pointers.size > 0;
  };
  return {
    zoomScale,
    activeImageRotation,
    imageStyle,
    onRotate,
    onZoom,
    onClickZoomImage,
    onWheelImageZoom,
    onPointerDown,
    onPointerMove,
    onPointerUp,
    updateImageBounds,
    resetZoomAndRotation,
  };
};
