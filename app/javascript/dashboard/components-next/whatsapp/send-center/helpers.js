import { isSendableTemplate } from '@chatwoot/utils';

export const TEMPLATE_CATEGORIES = ['UTILITY', 'MARKETING', 'AUTHENTICATION'];
export const TEMPLATE_STATUSES = [
  'APPROVED',
  'PENDING',
  'REJECTED',
  'PAUSED',
  'DISABLED',
  'IN_APPEAL',
  'FLAGGED',
  'LIMIT_EXCEEDED',
  'UNKNOWN',
];
export const FLOW_STATUSES = [
  'published',
  'changes',
  'none',
  'draft',
  'deprecated',
  'blocked',
  'throttled',
];

export const supportsFlows = inbox =>
  inbox.channel_type === 'Channel::Whatsapp' &&
  inbox.provider === 'whatsapp_cloud';

export const usesContentTemplates = inbox =>
  inbox.channel_type === 'Channel::TwilioSms' && inbox.medium === 'whatsapp';

export const sendCenterIcon = inbox =>
  inbox.channel_type === 'Channel::Whatsapp' || usesContentTemplates(inbox)
    ? 'i-ph-whatsapp-logo'
    : 'i-lucide-layout-template';

export const templateReason = (template, content = false) => {
  const status = template.status?.toUpperCase();
  if (status !== 'APPROVED')
    return `template_${TEMPLATE_STATUSES.includes(status) ? status : 'UNKNOWN'}`;
  if (content) return '';
  if (template.category === 'AUTHENTICATION') return 'authentication';
  if (template.name?.startsWith('customer_satisfaction_survey')) return 'csat';
  return isSendableTemplate(template) ? '' : 'unsupported';
};

export const flowState = flow =>
  flow.unpublished_changes ? 'changes' : flow.status;

export const flowReason = (flow, canReply) => {
  if (flow.status === 'none') return 'no_publication';
  if (flow.unpublished_changes) return 'changes';
  if (flow.status !== 'published') return `flow_${flow.status}`;
  if (!canReply) return 'outside_window';
  return flow.can_send ? '' : 'unavailable';
};
