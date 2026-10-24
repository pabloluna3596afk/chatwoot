import { showModal } from '../overlayFocus';

it('focuses the first visible useful control rather than the native scroll container', () => {
  const dialog = document.createElement('dialog');
  dialog.innerHTML =
    '<input disabled><input type="hidden"><input id="first"><button>Save</button>';
  dialog.showModal = vi.fn();
  const first = dialog.querySelector('#first');
  first.getClientRects = () => [{}];
  first.focus = vi.fn();
  showModal(dialog);
  expect(dialog.showModal).toHaveBeenCalledOnce();
  expect(first.focus).toHaveBeenCalledWith({ preventScroll: true });
});

it('honors visible autofocus and focuses a read-only container when there are no controls', () => {
  const dialog = document.createElement('dialog');
  dialog.innerHTML = '<button>Cancel</button><input autofocus>';
  dialog.showModal = vi.fn();
  [...dialog.children].forEach(control => {
    control.getClientRects = () => [{}];
  });
  const autofocus = dialog.querySelector('[autofocus]');
  autofocus.focus = vi.fn();
  showModal(dialog);
  expect(autofocus.focus).toHaveBeenCalledOnce();
  dialog.innerHTML = '<p>Read only</p>';
  dialog.focus = vi.fn();
  showModal(dialog);
  expect(dialog.focus).toHaveBeenCalledOnce();
});
