# LLM content in traces

Langfuse and OpenTelemetry traces omit prompt and response text by default. They
retain redaction markers and content lengths for troubleshooting. To capture
content during an explicitly approved debugging session, set
`LANGFUSE_CAPTURE_CONTENT=true` in the application environment and restart the
application. The setting applies to LLM prompt, completion, transcription, and
Captain tool trace attributes. Logs never include message, response, query, or
transcription text, regardless of this setting.

Return the variable to `false` or remove it after debugging. Treat captured
traces as customer data and apply the same access and retention controls as
conversation records.
