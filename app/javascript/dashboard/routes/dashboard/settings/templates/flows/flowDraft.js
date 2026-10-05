// A flow that has been started (name, categories, starting point) but not saved yet, handed from the start page to the
// builder page. It lives only while the page is open: a reload goes back to the start page.
let draft = null;

export const setFlowDraft = flow => {
  draft = flow;
};
export const getFlowDraft = () => draft;
export const clearFlowDraft = () => {
  draft = null;
};
