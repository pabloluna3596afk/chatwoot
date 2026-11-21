import { ref } from 'vue';
import DraftsAPI from 'dashboard/api/whatsappTemplateDrafts';

// Owns the server revision; the drawer owns the user's unsaved form. On a conflict
// only the server record is refreshed, until the user chooses how to resolve it.
export const useTemplateDraft = () => {
  const draft = ref(null);
  const conflict = ref(false);
  const conflictLoaded = ref(false);

  const load = async id => {
    const { data } = await DraftsAPI.show(id);
    draft.value = data;
    return data;
  };
  const reset = () => {
    draft.value = null;
    conflict.value = false;
    conflictLoaded.value = false;
  };
  const acceptRevision = () => {
    conflict.value = false;
  };
  const handleConflict = async error => {
    if (
      error?.response?.status !== 409 ||
      error.response.data?.error !== 'stale_revision'
    )
      return false;
    conflict.value = true;
    conflictLoaded.value = false;
    await load(draft.value.id);
    conflictLoaded.value = true;
    return true;
  };
  const save = async attributes => {
    const { data } = draft.value
      ? await DraftsAPI.update(draft.value.id, {
          ...attributes,
          lock_version: draft.value.lock_version,
        })
      : await DraftsAPI.create(attributes);
    draft.value = data;
    return data;
  };
  const upload = async file => {
    const { data } = await DraftsAPI.uploadMedia(
      draft.value.id,
      draft.value.lock_version,
      file
    );
    draft.value = data;
  };
  const removeMedia = async () => {
    const { data } = await DraftsAPI.removeMedia(
      draft.value.id,
      draft.value.lock_version
    );
    draft.value = data;
  };
  const submit = async () => {
    const { data } = await DraftsAPI.submit(
      draft.value.id,
      draft.value.lock_version
    );
    draft.value = {
      ...draft.value,
      status: data.status,
      submissions: [
        data,
        ...draft.value.submissions.filter(
          item => item.revision !== data.revision
        ),
      ],
    };
    await load(draft.value.id);
  };
  return {
    draft,
    conflict,
    conflictLoaded,
    load,
    reset,
    acceptRevision,
    handleConflict,
    save,
    upload,
    removeMedia,
    submit,
  };
};
