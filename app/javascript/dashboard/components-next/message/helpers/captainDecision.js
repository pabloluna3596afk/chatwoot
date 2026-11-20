export function hasCaptainDetails({
  sender,
  senderType,
  contentAttributes = {},
}) {
  return (
    (sender?.type ?? senderType) === 'captain_assistant' ||
    Boolean(contentAttributes.captainHandoff) ||
    Boolean(contentAttributes.captainFollowup) ||
    contentAttributes.activity?.source?.type === 'captain'
  );
}
