// Shared presentation for structured validation errors and unavailable servers.
function formatAgentError(error) {
  const lines = [`${error?.code || 'request_failed'}: ${error?.message || 'Request failed.'}`];
  for (const violation of error?.details?.violations || []) {
    lines.push(`${violation.path || '(root)'}: ${violation.message}`);
    if (violation.expected !== undefined) lines.push(`Expected: ${JSON.stringify(violation.expected)}; actual: ${violation.actual}.`);
  }
  if (error?.details?.truncated) lines.push('Additional validation errors were omitted. Correct these fields and retry.');
  return lines.join('\n');
}
async function serverFetch(path, options) {
  try {
    return await fetch(path, options);
  } catch {
    const error = new Error(`Server is unreachable at ${location.origin}. Start AgentServer and retry.`);
    error.code = 'server_unreachable';
    throw error;
  }
}
