// Chromium can initially focus a scroll container before its form controls.
// Leave containment, background isolation, Escape and restoration to <dialog>.
export const showModal = dialog => {
  dialog.showModal();
  const controls = dialog.querySelectorAll(
    '[autofocus], input:not([type="hidden"]):enabled, select:enabled, textarea:enabled, button:enabled, [contenteditable="true"], [tabindex="0"]'
  );
  const visible = [...controls].filter(
    control => control.getClientRects().length
  );
  const target =
    visible.find(control => control.hasAttribute('autofocus')) ||
    visible[0] ||
    dialog;
  target.focus({ preventScroll: true });
};
