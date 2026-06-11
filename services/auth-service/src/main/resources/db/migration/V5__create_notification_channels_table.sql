CREATE TABLE notification_channels (
    id        UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id   UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type      VARCHAR(50) NOT NULL,
    config    JSONB     NOT NULL,
    is_active BOOLEAN   NOT NULL DEFAULT TRUE,

    CONSTRAINT chk_channel_type CHECK (type IN ('EMAIL', 'SLACK', 'WEBHOOK'))
);

CREATE INDEX idx_notification_channels_user ON notification_channels(user_id);

COMMENT ON COLUMN notification_channels.config IS
  'EMAIL: {"address":"x@y.com"}, SLACK: {"webhookUrl":"..."}, WEBHOOK: {"url":"...","secret":"..."}';
