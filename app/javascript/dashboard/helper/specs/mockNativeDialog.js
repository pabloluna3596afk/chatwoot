// JSDOM does not implement the native dialog methods. Browser checks cover
// top-layer focus containment and inertness; this stub supplies lifecycle only.
export const mockNativeDialog = () => {
  const openers = new WeakMap();
  HTMLDialogElement.prototype.showModal = vi.fn(function showModal() {
    openers.set(this, document.activeElement);
    this.setAttribute('open', '');
  });
  HTMLDialogElement.prototype.close = vi.fn(function close() {
    this.removeAttribute('open');
    const opener = openers.get(this);
    if (opener?.isConnected) opener.focus();
  });
};
