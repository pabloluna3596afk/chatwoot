export const PDF_PREVIEW_MAX_BYTES = 25 * 1024 * 1024;

export function attachmentName(attachment) {
  return (
    attachment.fileName ||
    decodeURIComponent(
      (attachment.dataUrl || '').split('?')[0].split('/').pop() || ''
    )
  );
}

export function attachmentExtension(attachment) {
  return (
    attachment.extension ||
    attachmentName(attachment).split('.').pop() ||
    ''
  ).toLowerCase();
}

export function isPdfAttachment(attachment) {
  return (
    attachment.fileType === 'file' &&
    attachmentExtension(attachment) === 'pdf' &&
    attachment.contentType === 'application/pdf'
  );
}

export function middleEllipsis(name, limit = 48) {
  if (name.length <= limit) return name;
  const endLength = Math.floor((limit - 1) / 2);
  return `${name.slice(0, limit - endLength - 1)}…${name.slice(-endLength)}`;
}

export async function downloadAttachment(attachment, downloadFile) {
  try {
    await downloadFile({
      url: attachment.dataUrl,
      type: attachment.fileType,
      extension: attachment.extension,
    });
    return true;
  } catch {
    window.open(attachment.dataUrl, '_blank', 'noopener,noreferrer');
    return false;
  }
}
