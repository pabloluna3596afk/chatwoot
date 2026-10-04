// Files a WhatsApp template header (image, video, document) accepts, as Meta sets them.
// Keep in sync with Whatsapp::TemplateHeaderMedia::FORMATS.
const MB = 1024 * 1024;

export const HEADER_MEDIA_RULES = {
  IMAGE: { types: ['image/jpeg', 'image/png'], maxBytes: 5 * MB },
  VIDEO: { types: ['video/mp4', 'video/3gpp'], maxBytes: 16 * MB },
  DOCUMENT: { types: ['application/pdf'], maxBytes: 100 * MB },
};

// What the header params keep about an uploaded file (media_url stays: it is the link the file is also reachable by).
export const UPLOADED_MEDIA_KEYS = [
  'media_id',
  'media_blob',
  'media_uploaded_at',
  'media_phone_number_id',
];

export const headerMediaAccept = format =>
  (HEADER_MEDIA_RULES[format?.toUpperCase()]?.types || []).join(',');

export const headerMediaMaxMegabytes = format =>
  (HEADER_MEDIA_RULES[format?.toUpperCase()]?.maxBytes || 0) / MB;

// null when the file fits the header, otherwise EMPTY | INVALID_TYPE | TOO_LARGE.
export const validateHeaderMediaFile = (format, file) => {
  const rules = HEADER_MEDIA_RULES[format?.toUpperCase()];
  if (!rules || !file || !file.size) return 'EMPTY';
  if (!rules.types.includes(file.type)) return 'INVALID_TYPE';
  if (file.size > rules.maxBytes) return 'TOO_LARGE';
  return null;
};

export const isUploadedHeaderMedia = header => Boolean(header?.media_id);

// The header without the uploaded file (kept: media_type and any text variables).
export const withoutUploadedMedia = header => {
  const rest = { ...header };
  UPLOADED_MEDIA_KEYS.forEach(key => delete rest[key]);
  return rest;
};
