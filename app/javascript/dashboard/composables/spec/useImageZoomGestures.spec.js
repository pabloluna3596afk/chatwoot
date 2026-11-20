import { ref } from 'vue';
import { useImageZoom } from '../useImageZoom';

const pointer = (pointerId, clientX, clientY) => ({
  pointerId,
  clientX,
  clientY,
  button: 0,
  currentTarget: { setPointerCapture: vi.fn(), releasePointerCapture: vi.fn() },
});
const preventDefault = vi.fn();
let zoom;
beforeEach(() => {
  const viewport = ref({
    clientWidth: 400,
    clientHeight: 300,
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 400, height: 300 }),
  });
  const image = ref({ offsetWidth: 400, offsetHeight: 200 });
  zoom = useImageZoom(image, viewport);
});

it('keeps the cursor point stationary on consecutive wheel zooms at different positions', () => {
  zoom.onZoom(1, 250, 150);
  zoom.onZoom(1, 150, 150);
  // The image point at x=150 before the second zoom remains at x=150.
  expect(zoom.imageStyle.value.transform).toContain('translate(-50px, 0px)');
});

it('drags only while held, clamps edges, and keeps the position on release', () => {
  zoom.onZoom(1);
  zoom.onPointerMove(pointer(1, 250, 150));
  expect(zoom.imageStyle.value.transform).toContain('translate(0px, 0px)');
  zoom.onPointerDown(pointer(1, 200, 150));
  zoom.onPointerMove(pointer(1, 900, 900));
  expect(zoom.imageStyle.value.transform).toContain('translate(200px, 50px)');
  zoom.onPointerUp(pointer(1, 900, 900));
  zoom.onPointerMove(pointer(1, 0, 0));
  expect(zoom.imageStyle.value.transform).toContain('translate(200px, 50px)');
});

it('pinches around its midpoint and continues with one finger without jumping', () => {
  zoom.onPointerDown(pointer(1, 150, 150));
  zoom.onPointerDown(pointer(2, 250, 150));
  zoom.onPointerMove(pointer(2, 350, 150));
  expect(zoom.zoomScale.value).toBe(2);
  zoom.onPointerUp(pointer(2, 350, 150));
  const transform = zoom.imageStyle.value.transform;
  zoom.onPointerMove(pointer(1, 150, 150));
  expect(zoom.imageStyle.value.transform).toBe(transform);
});

it('ignores a stationary wheel and resets pan when double clicking out', () => {
  zoom.onWheelImageZoom({
    deltaY: 0,
    clientX: 250,
    clientY: 150,
    preventDefault,
  });
  expect(zoom.zoomScale.value).toBe(1);
  zoom.onDoubleClickZoomImage({ clientX: 250, clientY: 150, preventDefault });
  zoom.onDoubleClickZoomImage({ clientX: 100, clientY: 150, preventDefault });
  expect(zoom.zoomScale.value).toBe(1);
  expect(zoom.imageStyle.value.transform).toContain('translate(0px, 0px)');
});

it('reset and photo changes clear active gestures as well as transforms', () => {
  zoom.onZoom(1);
  zoom.onPointerDown(pointer(1, 200, 150));
  zoom.resetZoomAndRotation();
  zoom.onPointerMove(pointer(1, 300, 200));
  expect(zoom.zoomScale.value).toBe(1);
  expect(zoom.imageStyle.value.transform).toContain('translate(0px, 0px)');
});

it.each([
  [4000, 200, 400, 20],
  [200, 4000, 15, 300],
  [40, 20, 40, 20],
])(
  'fits natural size %sx%s, including panoramas and small images',
  (naturalWidth, naturalHeight, width, height) => {
    const image = ref({ naturalWidth, naturalHeight });
    const viewport = ref({ clientWidth: 400, clientHeight: 300 });
    const fitted = useImageZoom(image, viewport);
    fitted.updateImageBounds();
    expect(fitted.imageStyle.value).toMatchObject({
      width: `${width}px`,
      height: `${height}px`,
    });
    fitted.onRotate('clockwise');
    const style = fitted.imageStyle.value;
    expect(parseFloat(style.height)).toBeLessThanOrEqual(400);
    expect(parseFloat(style.width)).toBeLessThanOrEqual(300);
    fitted.onZoom(1);
    fitted.onPointerDown(pointer(1, 200, 150));
    fitted.onPointerMove(pointer(1, 300, 200));
    expect(fitted.imageStyle.value.transform).toContain(
      'rotate(90deg) scale(2)'
    );
    fitted.resetZoomAndRotation();
    expect(fitted.imageStyle.value.transform).toBe(
      'translate(0px, 0px) rotate(0deg) scale(1)'
    );
  }
);

it('ignores gestures after cancellation and centers the image on zoom out', () => {
  zoom.onZoom(2);
  zoom.onPointerDown(pointer(1, 200, 150));
  zoom.onPointerMove(pointer(1, 300, 200));
  zoom.onPointerUp(pointer(1, 300, 200));
  const last = zoom.imageStyle.value.transform;
  zoom.onPointerMove(pointer(1, 600, 600));
  expect(zoom.imageStyle.value.transform).toBe(last);
  zoom.onZoom(-2);
  expect(zoom.imageStyle.value.transform).toContain('translate(0px, 0px)');
});

it('fits and bounds a rotated image after resizing to a 390px phone viewport', () => {
  const image = ref({ naturalWidth: 1600, naturalHeight: 800 });
  const viewport = ref({ clientWidth: 1000, clientHeight: 600 });
  const resized = useImageZoom(image, viewport);
  resized.updateImageBounds();
  resized.onRotate('clockwise');
  resized.onZoom(1);
  resized.onPointerDown(pointer(1, 200, 150));
  resized.onPointerMove(pointer(1, 1200, 1150));
  viewport.value.clientWidth = 390;
  viewport.value.clientHeight = 300;
  resized.updateImageBounds();
  expect(resized.imageStyle.value.width).toBe('300px');
  expect(resized.imageStyle.value.height).toBe('150px');
  expect(resized.imageStyle.value.transform).toBe(
    'translate(0px, 150px) rotate(90deg) scale(2)'
  );
});
