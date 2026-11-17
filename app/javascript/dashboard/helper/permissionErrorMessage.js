export const permissionErrorMessage = (
  error,
  permissionMessage,
  fallbackMessage
) => {
  if ([401, 403].includes(error?.response?.status)) return permissionMessage;

  return error?.message || fallbackMessage;
};
