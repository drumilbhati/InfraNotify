CREATE TABLE alert_rules (
    id               UUID             PRIMARY KEY DEFAULT gen_random_uuid(),
    service_id       UUID             NOT NULL REFERENCES monitored_services(id) ON DELETE CASCADE,
    metric_name      VARCHAR(100)     NOT NULL,
    operator         VARCHAR(10)      NOT NULL,
    threshold        DOUBLE PRECISION NOT NULL,
    duration_seconds INT              NOT NULL DEFAULT 60,
    severity         VARCHAR(20)      NOT NULL DEFAULT 'WARNING',
    is_active        BOOLEAN          NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP        NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_operator CHECK (operator IN ('>', '<', '>=', '<=', '==')),
    CONSTRAINT chk_severity CHECK (severity IN ('INFO', 'WARNING', 'CRITICAL'))
);

CREATE INDEX idx_alert_rules_service ON alert_rules(service_id);
CREATE INDEX idx_alert_rules_active ON alert_rules(is_active);
